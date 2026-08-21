import 'dart:async';

import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/fake/fake_protected_identity_key_store.dart';
import 'package:filehop/identity/generated_identity_material.dart';
import 'package:filehop/identity/local_identity.dart';
import 'package:filehop/identity/local_identity_metadata_store.dart';
import 'package:filehop/identity/local_identity_service.dart';
import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import '../persistence/support/ffi_harness.dart';
import 'support/fingerprint_vector.dart';
import 'support/test_key_material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two concurrent creators cannot both win the singleton row', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });
    final FakeProtectedIdentityKeyStore secrets =
        FakeProtectedIdentityKeyStore();
    final SqliteLocalIdentityMetadataStore metadata =
        SqliteLocalIdentityMetadataStore(opened.stores);
    final _CreateRaceGates gates = _CreateRaceGates();

    final LocalIdentityService serviceA = LocalIdentityService(
      metadata: metadata,
      secrets: secrets,
      nowUtcMs: () => kTs,
      synchronizeCreateAfterPreflight: gates.rendezvousPreflight,
      synchronizeCreateMetadataInsert: gates.rendezvousInsert,
    );
    final LocalIdentityService serviceB = LocalIdentityService(
      metadata: metadata,
      secrets: secrets,
      nowUtcMs: () => kTs + 1,
      synchronizeCreateAfterPreflight: gates.rendezvousPreflight,
      synchronizeCreateMetadataInsert: gates.rendezvousInsert,
    );

    final List<Object> outcomes = await Future.wait<Object>(<Future<Object>>[
      _runCreate(serviceA, testMaterialA()),
      _runCreate(serviceB, testMaterialB()),
    ]);

    final List<LocalIdentity> winners = outcomes
        .whereType<LocalIdentity>()
        .toList();
    final List<IdentityException> losers = outcomes
        .whereType<IdentityException>()
        .toList();
    expect(winners, hasLength(1), reason: 'exactly one creator must succeed');
    expect(losers, hasLength(1), reason: 'exactly one creator must fail');
    expect(losers.single.kind, IdentityFailureKind.identityAlreadyExists);

    final LocalIdentityRecord? row = await opened.stores.getLocalIdentity();
    expect(row, isNotNull);
    expect(row!.identityFingerprint, winners.single.fingerprint.value);
    expect(row.publicIdentityKey, winners.single.staticPublicKeyBytes);
    expect(row.wrappedKeyRef, winners.single.protectedKeyReference.value);

    expect(secrets.secretCount, 1);
    expect(secrets.activeReferences, <String>{
      winners.single.protectedKeyReference.value,
    });
  });

  test('losing-attempt cleanup failure leaves winner intact', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });
    final FakeProtectedIdentityKeyStore secrets =
        FakeProtectedIdentityKeyStore()..failDelete = true;
    final SqliteLocalIdentityMetadataStore metadata =
        SqliteLocalIdentityMetadataStore(opened.stores);
    final _CreateRaceGates gates = _CreateRaceGates();

    final LocalIdentityService serviceA = LocalIdentityService(
      metadata: metadata,
      secrets: secrets,
      nowUtcMs: () => kTs,
      synchronizeCreateAfterPreflight: gates.rendezvousPreflight,
      synchronizeCreateMetadataInsert: gates.rendezvousInsert,
    );
    final LocalIdentityService serviceB = LocalIdentityService(
      metadata: metadata,
      secrets: secrets,
      nowUtcMs: () => kTs + 1,
      synchronizeCreateAfterPreflight: gates.rendezvousPreflight,
      synchronizeCreateMetadataInsert: gates.rendezvousInsert,
    );

    final List<Object> outcomes = await Future.wait<Object>(<Future<Object>>[
      _runCreate(serviceA, testMaterialA()),
      _runCreate(serviceB, testMaterialB()),
    ]);

    final List<LocalIdentity> winners = outcomes
        .whereType<LocalIdentity>()
        .toList();
    final List<IdentityException> losers = outcomes
        .whereType<IdentityException>()
        .toList();
    expect(winners, hasLength(1));
    expect(losers, hasLength(1));
    expect(losers.single.kind, IdentityFailureKind.identityCleanupFailed);
    expect(
      losers.single.kind,
      isNot(IdentityFailureKind.identityAlreadyExists),
    );

    final LocalIdentityRecord? row = await opened.stores.getLocalIdentity();
    expect(row!.identityFingerprint, winners.single.fingerprint.value);
    expect(row.wrappedKeyRef, winners.single.protectedKeyReference.value);
    expect(
      secrets.activeReferences.contains(
        winners.single.protectedKeyReference.value,
      ),
      isTrue,
    );
    expect(secrets.secretCount, 2);
  });

  test('insertLocalIdentityIfAbsent never replaces an existing row', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });
    await opened.stores.insertLocalIdentityIfAbsent(
      LocalIdentityRecord(
        publicIdentityKey: hexToBytes(kVectorAPublicKeyHex),
        identityFingerprint: kVectorAFingerprint,
        wrappedKeyRef: 'fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        keyStorageVersion: 1,
        createdAtUtcMs: kTs,
      ),
    );
    await expectLater(
      opened.stores.insertLocalIdentityIfAbsent(
        LocalIdentityRecord(
          publicIdentityKey: hexToBytes(kVectorBPublicKeyHex),
          identityFingerprint: kVectorBFingerprint,
          wrappedKeyRef: 'fhik1.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          keyStorageVersion: 1,
          createdAtUtcMs: kTs + 1,
        ),
      ),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.constraintViolation,
        ),
      ),
    );
    final LocalIdentityRecord? row = await opened.stores.getLocalIdentity();
    expect(row!.identityFingerprint, kVectorAFingerprint);
    expect(row.wrappedKeyRef, 'fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
  });
}

class _CreateRaceGates {
  final Completer<void> preflight = Completer<void>();
  final Completer<void> insert = Completer<void>();
  int preflightArrived = 0;
  int insertArrived = 0;

  Future<void> rendezvousPreflight() async {
    preflightArrived += 1;
    if (preflightArrived == 2) {
      preflight.complete();
    }
    await preflight.future;
  }

  Future<void> rendezvousInsert() async {
    insertArrived += 1;
    if (insertArrived == 2) {
      insert.complete();
    }
    await insert.future;
  }
}

Future<Object> _runCreate(
  LocalIdentityService service,
  GeneratedIdentityMaterial material,
) async {
  try {
    return await service.persistNewIdentity(material);
  } catch (error) {
    return error;
  }
}
