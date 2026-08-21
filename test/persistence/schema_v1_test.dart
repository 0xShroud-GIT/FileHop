import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh schema v1 creates required tables and enables FKs', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });

    expect(await opened.db.userVersion(), 1);
    expect(await opened.db.foreignKeysEnabled(), isTrue);
    final Set<String> tables = await opened.db.tableNames();
    for (final String table in kSchemaV1Tables) {
      expect(tables.contains(table), isTrue, reason: table);
    }

    final Set<String> columns = await opened.db.columnNames();
    expect(columns.contains('peers.fingerprint'), isTrue);
    expect(columns.contains('local_identity.wrapped_key_ref'), isTrue);
    expect(
      columns.contains('transfer_checkpoints.verified_local_byte_offset'),
      isTrue,
    );

    final List<Map<String, Object?>> fks = await opened.db.raw.rawQuery(
      'PRAGMA foreign_key_list(transfer_checkpoints)',
    );
    final Map<int, List<Map<String, Object?>>> byId =
        <int, List<Map<String, Object?>>>{};
    for (final Map<String, Object?> row in fks) {
      final int id = row['id']! as int;
      byId.putIfAbsent(id, () => <Map<String, Object?>>[]).add(row);
    }
    final bool hasComposite = byId.values.any((
      List<Map<String, Object?>> group,
    ) {
      if (group.length != 2) {
        return false;
      }
      final Set<String> from = group
          .map((Map<String, Object?> row) => row['from']! as String)
          .toSet();
      final Set<String> to = group
          .map((Map<String, Object?> row) => row['to']! as String)
          .toSet();
      final String table = group.first['table']! as String;
      return table == 'transfer_items' &&
          from.contains('item_id') &&
          from.contains('transfer_id') &&
          to.contains('item_id') &&
          to.contains('transfer_id');
    });
    expect(
      hasComposite,
      isTrue,
      reason: 'composite FK item_id+transfer_id → transfer_items',
    );

    for (final String name in PersistTokens.forbiddenSecretNames) {
      expect(
        tables.any((String table) => table.contains(name)),
        isFalse,
        reason: name,
      );
      expect(
        columns.any((String column) => column.contains(name)),
        isFalse,
        reason: name,
      );
    }
  });
}
