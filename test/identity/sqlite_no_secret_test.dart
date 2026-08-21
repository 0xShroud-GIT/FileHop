import 'package:filehop/identity/fake/fake_protected_identity_key_store.dart';
import 'package:filehop/identity/local_identity_load.dart';
import 'package:filehop/identity/local_identity_metadata_store.dart';
import 'package:filehop/identity/local_identity_service.dart';
import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../persistence/support/ffi_harness.dart';
import 'support/fingerprint_vector.dart';
import 'support/test_key_material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local_identity row stores only public metadata and opaque reference',
    () async {
      final opened = await openTempDb();
      addTearDown(() async {
        await opened.db.close();
        await deleteTempDb(opened.file);
      });
      final FakeProtectedIdentityKeyStore secrets =
          FakeProtectedIdentityKeyStore();
      final LocalIdentityService service = LocalIdentityService(
        metadata: SqliteLocalIdentityMetadataStore(opened.stores),
        secrets: secrets,
        nowUtcMs: () => kTs,
      );
      final identity = await service.persistNewIdentity(testMaterialA());

      final List<Map<String, Object?>> rows = await opened.db.raw.query(
        'local_identity',
      );
      expect(rows, hasLength(1));
      final Map<String, Object?> row = rows.single;
      expect(row.keys.toSet(), <String>{
        'id',
        'public_identity_key',
        'identity_fingerprint',
        'wrapped_key_ref',
        'key_storage_version',
        'created_at_utc_ms',
      });
      expect(row['identity_fingerprint'], kVectorAFingerprint);
      expect(row['wrapped_key_ref'], identity.protectedKeyReference.value);
      expect(row['key_storage_version'], 1);
      expect(row['public_identity_key'], isA<List<int>>());
      expect(row['public_identity_key'], hexToBytes(kVectorAPublicKeyHex));

      final String encoded = row.values
          .map((Object? value) => '$value')
          .join('|');
      expect(encoded.contains('17, 17, 17'), isFalse);
      expect(
        row['wrapped_key_ref'],
        isNot(contains(kTestOnlyPrivateKeyA.first.toString())),
      );

      final Set<String> columns = await opened.db.columnNames();
      expect(columns.contains('local_identity.wrapped_key_ref'), isTrue);
      expect(
        columns.any((String name) => name.contains('private_key')),
        isFalse,
      );
      expect(
        columns.any((String name) => name.contains('wrapping_key')),
        isFalse,
      );
      for (final String forbidden in PersistTokens.forbiddenSecretNames) {
        expect(
          columns.any((String name) => name.contains(forbidden)),
          isFalse,
          reason: forbidden,
        );
      }

      final LocalIdentityLoad load = await service.loadLocalIdentity();
      expect(load, isA<IdentityAvailable>());
    },
  );

  test('file-backed identity metadata reloads after close', () async {
    final opened = await openTempDb();
    final FakeProtectedIdentityKeyStore secrets =
        FakeProtectedIdentityKeyStore();
    final LocalIdentityService service = LocalIdentityService(
      metadata: SqliteLocalIdentityMetadataStore(opened.stores),
      secrets: secrets,
      nowUtcMs: () => kTs,
    );
    await service.persistNewIdentity(testMaterialA());
    await opened.db.close();

    final FileHopDatabase reopened = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: opened.file.path,
    );
    addTearDown(() async {
      await reopened.close();
      await deleteTempDb(opened.file);
    });
    final LocalIdentityService again = LocalIdentityService(
      metadata: SqliteLocalIdentityMetadataStore(FileHopStores(reopened.raw)),
      secrets: secrets,
    );
    final LocalIdentityLoad load = await again.loadLocalIdentity();
    expect(load, isA<IdentityAvailable>());
    expect(
      (load as IdentityAvailable).identity.fingerprint.value,
      kVectorAFingerprint,
    );
  });
}
