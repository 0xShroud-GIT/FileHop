import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final SchemaMigration addMarker = SchemaMigration(
    fromVersion: 1,
    toVersion: 2,
    apply: (executor) async {
      await executor.execute(
        'ALTER TABLE activity_records ADD COLUMN test_only_marker TEXT',
      );
    },
  );

  test('test-only forward migration 1→2 applies once and keeps data', () async {
    final opened = await openTempDb();
    await opened.stores.insertActivity(
      const ActivityRecord(
        activityId: kActivityId,
        kind: 'baseline',
        summary: 'keep-me',
        createdAtUtcMs: kTs,
      ),
    );
    final String path = opened.file.path;
    await opened.db.close();

    final FileHopDatabase upgraded = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      targetVersion: 2,
      migrations: <SchemaMigration>[addMarker],
    );
    expect(await upgraded.userVersion(), 2);
    final FileHopStores stores = FileHopStores(upgraded.raw);
    expect((await stores.getActivity(kActivityId))?.summary, 'keep-me');
    final Set<String> columns = await upgraded.columnNames();
    expect(columns.contains('activity_records.test_only_marker'), isTrue);
    await upgraded.close();

    final FileHopDatabase again = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      targetVersion: 2,
      migrations: <SchemaMigration>[addMarker],
    );
    addTearDown(() async {
      await again.close();
      await deleteTempDb(opened.file);
    });
    expect(await again.userVersion(), 2);
  });

  test('failed migration rolls back and does not advance version', () async {
    final opened = await openTempDb();
    await opened.stores.insertActivity(
      const ActivityRecord(
        activityId: kActivityId,
        kind: 'baseline',
        summary: 'stay',
        createdAtUtcMs: kTs,
      ),
    );
    final String path = opened.file.path;
    await opened.db.close();

    final SchemaMigration boom = SchemaMigration(
      fromVersion: 1,
      toVersion: 2,
      apply: (executor) async {
        await executor.execute(
          'ALTER TABLE activity_records ADD COLUMN test_only_marker TEXT',
        );
        throw const PersistenceException(
          kind: PersistenceFailureKind.migrationFailure,
          message: 'intentional test failure',
        );
      },
    );

    await expectLater(
      FileHopDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        targetVersion: 2,
        migrations: <SchemaMigration>[boom],
      ),
      throwsA(anything),
    );

    final FileHopDatabase reopened = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(() async {
      await reopened.close();
      await deleteTempDb(opened.file);
    });
    expect(await reopened.userVersion(), 1);
    expect(
      (await reopened.columnNames()).contains(
        'activity_records.test_only_marker',
      ),
      isFalse,
    );
    expect(
      (await FileHopStores(reopened.raw).getActivity(kActivityId))?.summary,
      'stay',
    );
  });

  test('missing migration step fails closed', () {
    final MigrationHarness harness = MigrationHarness(<SchemaMigration>[]);
    expect(
      () => harness.plan(from: 1, to: 2),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.migrationFailure,
        ),
      ),
    );
  });

  test('migration definitions must be contiguous N→N+1', () {
    expect(
      () => MigrationHarness(<SchemaMigration>[
        SchemaMigration(
          fromVersion: 1,
          toVersion: 3,
          apply: (executor) async {},
        ),
      ]),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.migrationFailure,
        ),
      ),
    );
    expect(
      () => MigrationHarness(<SchemaMigration>[
        addMarker,
        SchemaMigration(
          fromVersion: 1,
          toVersion: 2,
          apply: (executor) async {},
        ),
      ]),
      throwsA(isA<PersistenceException>()),
    );
  });

  test(
    'real SQLite migration failure rolls back as migrationFailure',
    () async {
      final opened = await openTempDb();
      await opened.stores.insertActivity(
        const ActivityRecord(
          activityId: kActivityId,
          kind: 'baseline',
          summary: 'keep-sql',
          createdAtUtcMs: kTs,
        ),
      );
      final String path = opened.file.path;
      await opened.db.close();

      final SchemaMigration sqlBoom = SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        apply: (executor) async {
          await executor.execute(
            'CREATE TABLE test_only_marker (id INTEGER PRIMARY KEY)',
          );
          await executor.insert('test_only_marker', <String, Object?>{'id': 1});
          await executor.insert('test_only_marker', <String, Object?>{'id': 1});
        },
      );

      await expectLater(
        FileHopDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
          targetVersion: 2,
          migrations: <SchemaMigration>[sqlBoom],
        ),
        throwsA(
          isA<PersistenceException>().having(
            (PersistenceException e) => e.kind,
            'kind',
            PersistenceFailureKind.migrationFailure,
          ),
        ),
      );

      final FileHopDatabase reopened = await FileHopDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(() async {
        await reopened.close();
        await deleteTempDb(opened.file);
      });
      expect(await reopened.userVersion(), 1);
      expect(
        (await reopened.tableNames()).contains('test_only_marker'),
        isFalse,
      );
      expect(
        (await FileHopStores(reopened.raw).getActivity(kActivityId))?.summary,
        'keep-sql',
      );
    },
  );

  test('downgrade is rejected without resetting user data', () async {
    final opened = await openTempDb(
      targetVersion: 2,
      migrations: <SchemaMigration>[addMarker],
    );
    await opened.stores.insertActivity(
      const ActivityRecord(
        activityId: kActivityId,
        kind: 'baseline',
        summary: 'v2-row',
        createdAtUtcMs: kTs,
      ),
    );
    final String path = opened.file.path;
    await opened.db.close();

    await expectLater(
      FileHopDatabase.open(factory: databaseFactoryFfi, path: path),
      throwsA(anything),
    );

    final FileHopDatabase stillThere = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      targetVersion: 2,
      migrations: <SchemaMigration>[addMarker],
    );
    addTearDown(() async {
      await stillThere.close();
      await deleteTempDb(opened.file);
    });
    expect(await stillThere.userVersion(), 2);
    expect(
      (await FileHopStores(stillThere.raw).getActivity(kActivityId))?.summary,
      'v2-row',
    );
  });
}
