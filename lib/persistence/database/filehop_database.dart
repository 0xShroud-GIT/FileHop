import 'package:sqflite_common/sqlite_api.dart';

import '../errors.dart';
import 'migrations.dart';
import 'schema_v1.dart';

/// FileHop SQLite owner. Factory/path are injectable for Arena FFI tests.
class FileHopDatabase {
  FileHopDatabase._(this._db);

  final Database _db;
  bool _closed = false;

  Database get raw => _db;

  int get schemaVersion => kFileHopSchemaVersion;

  static Future<FileHopDatabase> open({
    required DatabaseFactory factory,
    required String path,
    int targetVersion = kFileHopSchemaVersion,
    List<SchemaMigration> migrations = const <SchemaMigration>[],
  }) async {
    try {
      final MigrationHarness harness = MigrationHarness(migrations);
      final Database db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: targetVersion,
          onConfigure: (Database database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (Database database, int version) async {
            if (version != kFileHopSchemaVersion && migrations.isEmpty) {
              throw PersistenceException(
                kind: PersistenceFailureKind.schemaMismatch,
                message: 'fresh databases must create schema v1, not $version',
              );
            }
            await _createV1(database);
            if (version > kFileHopSchemaVersion) {
              await _runMigrations(
                harness,
                database,
                from: kFileHopSchemaVersion,
                to: version,
              );
            }
          },
          onUpgrade: (Database database, int oldVersion, int newVersion) async {
            await _runMigrations(
              harness,
              database,
              from: oldVersion,
              to: newVersion,
            );
          },
          onDowngrade:
              (Database database, int oldVersion, int newVersion) async {
                throw PersistenceException(
                  kind: PersistenceFailureKind.schemaMismatch,
                  message: 'downgrade $oldVersion → $newVersion is unsupported',
                );
              },
        ),
      );
      return FileHopDatabase._(db);
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException(
        kind: PersistenceFailureKind.openFailure,
        message: 'failed to open FileHop database',
        cause: error,
      );
    }
  }

  static Future<void> _runMigrations(
    MigrationHarness harness,
    DatabaseExecutor executor, {
    required int from,
    required int to,
  }) async {
    try {
      await harness.apply(executor, from: from, to: to);
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException(
        kind: PersistenceFailureKind.migrationFailure,
        message: 'SQLite failure during migration $from → $to',
        cause: error,
      );
    }
  }

  static Future<void> _createV1(DatabaseExecutor executor) async {
    for (final String statement in kSchemaV1Statements) {
      await executor.execute(statement);
    }
  }

  Future<bool> foreignKeysEnabled() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      'PRAGMA foreign_keys',
    );
    return (rows.first.values.first as int) == 1;
  }

  Future<int> userVersion() => _db.getVersion();

  Future<Set<String>> tableNames() async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toSet();
  }

  Future<Set<String>> columnNames() async {
    final Set<String> names = <String>{};
    for (final String table in await tableNames()) {
      if (table.startsWith('sqlite_')) {
        continue;
      }
      final List<Map<String, Object?>> rows = await _db.rawQuery(
        'PRAGMA table_info($table)',
      );
      for (final Map<String, Object?> row in rows) {
        names.add('$table.${row['name']}');
      }
    }
    return names;
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) {
    return _db.transaction(action);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _db.close();
  }
}
