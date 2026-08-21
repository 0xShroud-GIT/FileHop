import 'dart:typed_data';

import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/fake/fake_protected_identity_key_store.dart';
import 'package:filehop/identity/protected_key_reference.dart';
import 'package:filehop/identity/protected_key_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_key_material.dart';

void main() {
  test('fake store returns exact bytes and delete is idempotent', () async {
    final FakeProtectedIdentityKeyStore store = FakeProtectedIdentityKeyStore();
    final ProtectedKeyReference reference = await store.store(testPrivateA());
    await store.withPrivateKey(reference, (Uint8List bytes) async {
      expect(bytes, testPrivateA());
    });
    expect(await store.status(reference), ProtectedKeyStatus.present);
    await store.delete(reference);
    await store.delete(reference);
    expect(await store.status(reference), ProtectedKeyStatus.absent);
    expect(await store.hasAnySecret(), isFalse);
  });

  test('missing, corrupt, and unavailable are typed separately', () async {
    final FakeProtectedIdentityKeyStore store = FakeProtectedIdentityKeyStore();
    final ProtectedKeyReference missing = ProtectedKeyReference.parse(
      'fhik1.00000000000000000000000000000001',
    );
    expect(await store.status(missing), ProtectedKeyStatus.absent);
    expect(
      () => store.withPrivateKey(missing, (_) async {}),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityKeyMissing,
        ),
      ),
    );

    final ProtectedKeyReference stored = await store.store(testPrivateA());
    store.corruptReferences.add(stored.value);
    expect(await store.status(stored), ProtectedKeyStatus.corrupt);
    expect(
      () => store.withPrivateKey(stored, (_) async {}),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityStoreCorrupt,
        ),
      ),
    );

    store.unavailable = true;
    expect(
      () => store.status(stored),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityStoreUnavailable,
        ),
      ),
    );
  });

  test('invalid private-key length is rejected', () async {
    final FakeProtectedIdentityKeyStore store = FakeProtectedIdentityKeyStore();
    expect(() => store.store(Uint8List(8)), throwsA(isA<IdentityException>()));
  });
}
