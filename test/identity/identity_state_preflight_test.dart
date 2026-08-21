import 'package:filehop/identity/constants.dart';
import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/fake/fake_protected_identity_key_store.dart';
import 'package:filehop/identity/local_identity.dart';
import 'package:filehop/identity/local_identity_load.dart';
import 'package:filehop/identity/local_identity_service.dart';
import 'package:filehop/identity/protected_key_reference.dart';
import 'package:filehop/persistence/records/persistence_records.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controllable_metadata_store.dart';
import 'support/fingerprint_vector.dart';
import 'support/test_key_material.dart';

void main() {
  late ControllableLocalIdentityMetadataStore metadata;
  late FakeProtectedIdentityKeyStore secrets;
  late LocalIdentityService service;

  setUp(() {
    metadata = ControllableLocalIdentityMetadataStore();
    secrets = FakeProtectedIdentityKeyStore();
    service = LocalIdentityService(
      metadata: metadata,
      secrets: secrets,
      nowUtcMs: () => 1_700_000_000_000,
    );
  });

  test(
    'first-run IdentityAbsent creates exactly one secret and metadata row',
    () async {
      expect(await service.inspectIdentityState(), isA<IdentityAbsent>());
      expect(await service.loadLocalIdentity(), isA<IdentityAbsent>());

      final LocalIdentity identity = await service.persistNewIdentity(
        testMaterialA(),
      );

      expect(identity.fingerprint.value, kVectorAFingerprint);
      expect(identity.staticPublicKeyBytes, hexToBytes(kVectorAPublicKeyHex));
      expect(identity.protectedKeyReference.value, startsWith('fhik1.'));
      expect(
        secrets.storeCallCount,
        1,
        reason: 'first-run create must invoke store() exactly once',
      );
      expect(secrets.secretCount, 1, reason: 'exactly one protected secret');
      expect(secrets.activeReferences, <String>{
        identity.protectedKeyReference.value,
      });
      expect(metadata.insertCallCount, 1);
      expect(metadata.row, isNotNull);
      expect(metadata.row!.wrappedKeyRef, identity.protectedKeyReference.value);
      expect(metadata.row!.identityFingerprint, kVectorAFingerprint);
      expect(secrets.deleteCallCount, 0);
      expect(secrets.deleteAllCallCount, 0);
      expect(await service.loadLocalIdentity(), isA<IdentityAvailable>());
    },
  );

  test('IdentityAvailable second persist is identityAlreadyExists with no mutation', () async {
    final LocalIdentity first = await service.persistNewIdentity(
      testMaterialA(),
    );
    final _StorageSnapshot before = _snapshot(metadata, secrets);

    await expectLater(
      service.persistNewIdentity(testMaterialB()),
      throwsA(_kind(IdentityFailureKind.identityAlreadyExists)),
    );

    expect(await service.loadLocalIdentity(), isA<IdentityAvailable>());
    _expectUnchanged(metadata, secrets, before);
    expect(metadata.row!.identityFingerprint, first.fingerprint.value);
    expect(metadata.row!.wrappedKeyRef, first.protectedKeyReference.value);
  });

  test(
    'orphan secret blocks creation as identityStorageInconsistent',
    () async {
      final ProtectedKeyReference orphan = secrets.injectOrphan(testPrivateA());
      expect(
        await service.loadLocalIdentity(),
        _unavailable(IdentityFailureKind.identityStorageInconsistent),
      );
      expect(
        await service.inspectIdentityState(),
        _unavailable(IdentityFailureKind.identityStorageInconsistent),
      );
      final _StorageSnapshot before = _snapshot(metadata, secrets);

      await expectLater(
        service.persistNewIdentity(testMaterialB()),
        throwsA(_kind(IdentityFailureKind.identityStorageInconsistent)),
      );

      _expectUnchanged(metadata, secrets, before);
      expect(metadata.row, isNull);
      expect(secrets.activeReferences, <String>{orphan.value});
      expect(secrets.storeCallCount, 0);
    },
  );

  test(
    'metadata present and secret missing blocks creation as identityKeyMissing',
    () async {
      final LocalIdentity first = await service.persistNewIdentity(
        testMaterialA(),
      );
      await secrets.delete(first.protectedKeyReference);
      expect(
        await service.loadLocalIdentity(),
        _unavailable(IdentityFailureKind.identityKeyMissing),
      );
      final _StorageSnapshot before = _snapshot(metadata, secrets);

      await expectLater(
        service.persistNewIdentity(testMaterialB()),
        throwsA(_kind(IdentityFailureKind.identityKeyMissing)),
      );

      _expectUnchanged(metadata, secrets, before);
      expect(metadata.row!.identityFingerprint, first.fingerprint.value);
      expect(metadata.row!.wrappedKeyRef, first.protectedKeyReference.value);
      expect(secrets.isEmpty, isTrue);
    },
  );

  test('fingerprint mismatch blocks creation as identityCorrupt', () async {
    await service.persistNewIdentity(testMaterialA());
    metadata.row = LocalIdentityRecord(
      publicIdentityKey: hexToBytes(kVectorAPublicKeyHex),
      identityFingerprint: kVectorBFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: kFileHopKeyStorageVersion,
      createdAtUtcMs: metadata.row!.createdAtUtcMs,
    );
    expect(
      await service.loadLocalIdentity(),
      _unavailable(IdentityFailureKind.identityCorrupt),
    );
    final _StorageSnapshot before = _snapshot(metadata, secrets);

    await expectLater(
      service.persistNewIdentity(testMaterialB()),
      throwsA(_kind(IdentityFailureKind.identityCorrupt)),
    );

    _expectUnchanged(metadata, secrets, before);
    expect(metadata.row!.identityFingerprint, kVectorBFingerprint);
    expect(metadata.row!.publicIdentityKey, hexToBytes(kVectorAPublicKeyHex));
  });

  test('unsupported key-storage version blocks creation', () async {
    await service.persistNewIdentity(testMaterialA());
    metadata.row = LocalIdentityRecord(
      publicIdentityKey: metadata.row!.publicIdentityKey,
      identityFingerprint: metadata.row!.identityFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: 99,
      createdAtUtcMs: metadata.row!.createdAtUtcMs,
    );
    expect(
      await service.loadLocalIdentity(),
      _unavailable(IdentityFailureKind.unsupportedKeyStorageVersion),
    );
    final _StorageSnapshot before = _snapshot(metadata, secrets);

    await expectLater(
      service.persistNewIdentity(testMaterialB()),
      throwsA(_kind(IdentityFailureKind.unsupportedKeyStorageVersion)),
    );

    _expectUnchanged(metadata, secrets, before);
    expect(metadata.row!.keyStorageVersion, 99);
  });

  test(
    'protected store unavailable is never treated as IdentityAbsent',
    () async {
      secrets.unavailable = true;
      expect(
        await service.loadLocalIdentity(),
        _unavailable(IdentityFailureKind.identityStoreUnavailable),
      );
      expect(
        await service.inspectIdentityState(),
        _unavailable(IdentityFailureKind.identityStoreUnavailable),
      );
      final _StorageSnapshot before = _snapshot(metadata, secrets);

      await expectLater(
        service.persistNewIdentity(testMaterialA()),
        throwsA(_kind(IdentityFailureKind.identityStoreUnavailable)),
      );

      _expectUnchanged(metadata, secrets, before);
      expect(metadata.row, isNull);
      expect(secrets.isEmpty, isTrue);
      expect(secrets.storeCallCount, 0);
    },
  );

  test(
    'corrupt protected secret blocks creation as identityStoreCorrupt',
    () async {
      final LocalIdentity first = await service.persistNewIdentity(
        testMaterialA(),
      );
      secrets.corruptReferences.add(first.protectedKeyReference.value);
      expect(
        await service.loadLocalIdentity(),
        _unavailable(IdentityFailureKind.identityStoreCorrupt),
      );
      final _StorageSnapshot before = _snapshot(metadata, secrets);

      await expectLater(
        service.persistNewIdentity(testMaterialB()),
        throwsA(_kind(IdentityFailureKind.identityStoreCorrupt)),
      );

      _expectUnchanged(metadata, secrets, before);
      expect(secrets.activeReferences, <String>{
        first.protectedKeyReference.value,
      });
      expect(metadata.row!.wrappedKeyRef, first.protectedKeyReference.value);
    },
  );

  test('load and persist use the same identity-state classification', () async {
    Future<void> expectAgree(IdentityFailureKind expected) async {
      final LocalIdentityLoad loaded = await service.loadLocalIdentity();
      final LocalIdentityLoad inspected = await service.inspectIdentityState();
      expect(loaded, _unavailable(expected));
      expect(inspected, _unavailable(expected));
      await expectLater(
        service.persistNewIdentity(testMaterialB()),
        throwsA(_kind(expected)),
      );
    }

    secrets.injectOrphan(testPrivateA());
    await expectAgree(IdentityFailureKind.identityStorageInconsistent);

    await secrets.deleteAllFileHopIdentitySecrets();
    final LocalIdentity first = await service.persistNewIdentity(
      testMaterialA(),
    );
    await secrets.delete(first.protectedKeyReference);
    await expectAgree(IdentityFailureKind.identityKeyMissing);

    await service.resetLocalIdentity();
    await service.persistNewIdentity(testMaterialA());
    metadata.row = LocalIdentityRecord(
      publicIdentityKey: hexToBytes(kVectorAPublicKeyHex),
      identityFingerprint: kVectorBFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: kFileHopKeyStorageVersion,
      createdAtUtcMs: metadata.row!.createdAtUtcMs,
    );
    await expectAgree(IdentityFailureKind.identityCorrupt);

    metadata.row = LocalIdentityRecord(
      publicIdentityKey: hexToBytes(kVectorAPublicKeyHex),
      identityFingerprint: kVectorAFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: 99,
      createdAtUtcMs: metadata.row!.createdAtUtcMs,
    );
    await expectAgree(IdentityFailureKind.unsupportedKeyStorageVersion);

    metadata.row = LocalIdentityRecord(
      publicIdentityKey: hexToBytes(kVectorAPublicKeyHex),
      identityFingerprint: kVectorAFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: kFileHopKeyStorageVersion,
      createdAtUtcMs: metadata.row!.createdAtUtcMs,
    );
    secrets.corruptReferences.add(metadata.row!.wrappedKeyRef!);
    await expectAgree(IdentityFailureKind.identityStoreCorrupt);

    secrets.unavailable = true;
    await expectAgree(IdentityFailureKind.identityStoreUnavailable);
  });
}

Matcher _kind(IdentityFailureKind kind) {
  return isA<IdentityException>().having(
    (IdentityException error) => error.kind,
    'kind',
    kind,
  );
}

Matcher _unavailable(IdentityFailureKind kind) {
  return isA<IdentityUnavailable>().having(
    (IdentityUnavailable state) => state.kind,
    'kind',
    kind,
  );
}

class _StorageSnapshot {
  const _StorageSnapshot({
    required this.storeCallCount,
    required this.deleteCallCount,
    required this.deleteAllCallCount,
    required this.insertCallCount,
    required this.metadataDeleteCallCount,
    required this.secretCount,
    required this.references,
    required this.fingerprint,
    required this.wrappedKeyRef,
    required this.keyStorageVersion,
    required this.publicKey,
  });

  final int storeCallCount;
  final int deleteCallCount;
  final int deleteAllCallCount;
  final int insertCallCount;
  final int metadataDeleteCallCount;
  final int secretCount;
  final Set<String> references;
  final String? fingerprint;
  final String? wrappedKeyRef;
  final int? keyStorageVersion;
  final List<int>? publicKey;
}

_StorageSnapshot _snapshot(
  ControllableLocalIdentityMetadataStore metadata,
  FakeProtectedIdentityKeyStore secrets,
) {
  return _StorageSnapshot(
    storeCallCount: secrets.storeCallCount,
    deleteCallCount: secrets.deleteCallCount,
    deleteAllCallCount: secrets.deleteAllCallCount,
    insertCallCount: metadata.insertCallCount,
    metadataDeleteCallCount: metadata.deleteCallCount,
    secretCount: secrets.secretCount,
    references: Set<String>.from(secrets.activeReferences),
    fingerprint: metadata.row?.identityFingerprint,
    wrappedKeyRef: metadata.row?.wrappedKeyRef,
    keyStorageVersion: metadata.row?.keyStorageVersion,
    publicKey: metadata.row == null
        ? null
        : List<int>.from(metadata.row!.publicIdentityKey),
  );
}

void _expectUnchanged(
  ControllableLocalIdentityMetadataStore metadata,
  FakeProtectedIdentityKeyStore secrets,
  _StorageSnapshot before,
) {
  expect(secrets.storeCallCount, before.storeCallCount, reason: 'store()');
  expect(secrets.deleteCallCount, before.deleteCallCount, reason: 'delete()');
  expect(
    secrets.deleteAllCallCount,
    before.deleteAllCallCount,
    reason: 'deleteAll()',
  );
  expect(metadata.insertCallCount, before.insertCallCount, reason: 'insert');
  expect(
    metadata.deleteCallCount,
    before.metadataDeleteCallCount,
    reason: 'metadata delete',
  );
  expect(secrets.secretCount, before.secretCount);
  expect(secrets.activeReferences, before.references);
  expect(metadata.row?.identityFingerprint, before.fingerprint);
  expect(metadata.row?.wrappedKeyRef, before.wrappedKeyRef);
  expect(metadata.row?.keyStorageVersion, before.keyStorageVersion);
  expect(metadata.row?.publicIdentityKey, before.publicKey);
}
