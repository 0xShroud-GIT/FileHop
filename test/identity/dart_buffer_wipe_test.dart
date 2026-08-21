import 'dart:typed_data';

import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/local_identity_load.dart';
import 'package:filehop/identity/local_identity_service.dart';
import 'package:filehop/identity/protected_identity_key_store.dart';
import 'package:filehop/identity/protected_key_reference.dart';
import 'package:filehop/identity/protected_key_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controllable_metadata_store.dart';
import 'support/test_key_material.dart';

class _ObservingProtectedStore implements ProtectedIdentityKeyStore {
  Uint8List? observed;
  bool failStore = false;

  @override
  Future<ProtectedKeyReference> store(Uint8List privateKeyBytes) async {
    observed = privateKeyBytes;
    if (failStore) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'observing store refused store',
      );
    }
    return ProtectedKeyReference.parse(
      'fhik1.dddddddddddddddddddddddddddddddd',
    );
  }

  @override
  Future<T> withPrivateKey<T>(
    ProtectedKeyReference reference,
    Future<T> Function(Uint8List privateKeyBytes) action,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(ProtectedKeyReference reference) async {}

  @override
  Future<ProtectedKeyStatus> status(ProtectedKeyReference reference) async {
    return ProtectedKeyStatus.present;
  }

  @override
  Future<bool> hasAnySecret() async => observed != null && !failStore;

  @override
  Future<void> deleteAllFileHopIdentitySecrets() async {}
}

void main() {
  test(
    'temporary private-key buffer is wiped after a successful store',
    () async {
      final _ObservingProtectedStore secrets = _ObservingProtectedStore();
      final LocalIdentityService service = LocalIdentityService(
        metadata: ControllableLocalIdentityMetadataStore(),
        secrets: secrets,
        nowUtcMs: () => 1,
      );
      await service.persistNewIdentity(testMaterialA());
      expect(secrets.observed, isNotNull);
      expect(secrets.observed, everyElement(0));
    },
  );

  test('temporary private-key buffer is wiped after a failed store', () async {
    final _ObservingProtectedStore secrets = _ObservingProtectedStore()
      ..failStore = true;
    final LocalIdentityService service = LocalIdentityService(
      metadata: ControllableLocalIdentityMetadataStore(),
      secrets: secrets,
      nowUtcMs: () => 1,
    );
    await expectLater(
      service.persistNewIdentity(testMaterialA()),
      throwsA(isA<IdentityException>()),
    );
    expect(secrets.observed, isNotNull);
    expect(secrets.observed, everyElement(0));
    expect(await service.loadLocalIdentity(), isA<IdentityAbsent>());
  });
}
