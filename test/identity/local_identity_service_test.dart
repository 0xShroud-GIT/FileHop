import 'dart:typed_data';

import 'package:filehop/identity/constants.dart';
import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/fake/fake_protected_identity_key_store.dart';
import 'package:filehop/identity/generated_identity_material.dart';
import 'package:filehop/identity/local_identity_load.dart';
import 'package:filehop/identity/local_identity_service.dart';
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

  test('first run is identityAbsent', () async {
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityAbsent>());
  });

  test(
    'persist generated material then reload after metadata reopen',
    () async {
      final identity = await service.persistNewIdentity(testMaterialA());
      expect(identity.fingerprint.value, kVectorAFingerprint);
      expect(identity.staticPublicKeyBytes, hexToBytes(kVectorAPublicKeyHex));
      expect(identity.keyStorageVersion, kFileHopKeyStorageVersion);
      expect(identity.protectedKeyReference.value, startsWith('fhik1.'));
      expect(metadata.row?.wrappedKeyRef, identity.protectedKeyReference.value);
      expect(metadata.row?.identityFingerprint, kVectorAFingerprint);

      await secrets.withPrivateKey(identity.protectedKeyReference, (
        Uint8List bytes,
      ) async {
        expect(bytes, testPrivateA());
      });

      final LocalIdentityService reopened = LocalIdentityService(
        metadata: metadata,
        secrets: secrets,
        nowUtcMs: () => 1_700_000_000_000,
      );
      final LocalIdentityLoad load = await reopened.loadLocalIdentity();
      expect(load, isA<IdentityAvailable>());
      expect(
        (load as IdentityAvailable).identity.fingerprint.value,
        kVectorAFingerprint,
      );
    },
  );

  test('second persist cannot silently replace the first identity', () async {
    final first = await service.persistNewIdentity(testMaterialA());
    await expectLater(
      service.persistNewIdentity(testMaterialB()),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityAlreadyExists,
        ),
      ),
    );
    expect(metadata.row?.identityFingerprint, first.fingerprint.value);
    expect(metadata.row?.wrappedKeyRef, first.protectedKeyReference.value);
    expect(secrets.secretCount, 1);
  });

  test('metadata write failure after store cleans up the new secret', () async {
    metadata.failWrite = true;
    await expectLater(
      service.persistNewIdentity(testMaterialA()),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.operationFailure,
        ),
      ),
    );
    expect(secrets.isEmpty, isTrue);
    expect(metadata.row, isNull);
    expect(await service.loadLocalIdentity(), isA<IdentityAbsent>());
  });

  test('cleanup failure is reported as inconsistent cleanup', () async {
    metadata.failWrite = true;
    secrets.failDelete = true;
    await expectLater(
      service.persistNewIdentity(testMaterialA()),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityCleanupFailed,
        ),
      ),
    );
    expect(secrets.isEmpty, isFalse);
    expect(await service.loadLocalIdentity(), isA<IdentityUnavailable>());
  });

  test('metadata present and secret missing is identityKeyMissing', () async {
    final identity = await service.persistNewIdentity(testMaterialA());
    await secrets.delete(identity.protectedKeyReference);
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.identityKeyMissing,
    );
    expect(metadata.row?.identityFingerprint, kVectorAFingerprint);
  });

  test('orphaned secret without metadata is inconsistent', () async {
    secrets.injectOrphan(testPrivateA());
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.identityStorageInconsistent,
    );
  });

  test('stored fingerprint mismatch is identityCorrupt', () async {
    await service.persistNewIdentity(testMaterialA());
    metadata.row = LocalIdentityRecord(
      publicIdentityKey: hexToBytes(kVectorAPublicKeyHex),
      identityFingerprint: kVectorBFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: 1,
      createdAtUtcMs: 1,
    );
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.identityCorrupt,
    );
  });

  test('unknown key-storage version fails closed', () async {
    await service.persistNewIdentity(testMaterialA());
    metadata.row = LocalIdentityRecord(
      publicIdentityKey: metadata.row!.publicIdentityKey,
      identityFingerprint: metadata.row!.identityFingerprint,
      wrappedKeyRef: metadata.row!.wrappedKeyRef,
      keyStorageVersion: 99,
      createdAtUtcMs: metadata.row!.createdAtUtcMs,
    );
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.unsupportedKeyStorageVersion,
    );
  });

  test('corrupt protected secret fails closed', () async {
    final identity = await service.persistNewIdentity(testMaterialA());
    secrets.corruptReferences.add(identity.protectedKeyReference.value);
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.identityStoreCorrupt,
    );
  });

  test('explicit reset returns to identityAbsent', () async {
    await service.persistNewIdentity(testMaterialA());
    await service.resetLocalIdentity();
    expect(await service.loadLocalIdentity(), isA<IdentityAbsent>());
    expect(secrets.isEmpty, isTrue);
    expect(metadata.row, isNull);
  });

  test('reset cleanup failure is not reported as success', () async {
    await service.persistNewIdentity(testMaterialA());
    secrets.failDeleteAll = true;
    await expectLater(
      service.resetLocalIdentity(),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityCleanupFailed,
        ),
      ),
    );
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.identityStorageInconsistent,
    );
  });

  test('private bytes never appear on GeneratedIdentityMaterial toString', () {
    final GeneratedIdentityMaterial material = testMaterialA();
    expect(material.toString().contains('11'), isFalse);
    expect(material.toString(), contains('publicKeyBytes'));
  });

  test('unavailable store is distinct from missing identity', () async {
    secrets.unavailable = true;
    final LocalIdentityLoad load = await service.loadLocalIdentity();
    expect(load, isA<IdentityUnavailable>());
    expect(
      (load as IdentityUnavailable).kind,
      IdentityFailureKind.identityStoreUnavailable,
    );
  });
}
