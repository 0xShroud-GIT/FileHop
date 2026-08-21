import 'package:sqflite_common/sqlite_api.dart';

import '../errors.dart';

/// One explicit forward step. Must be exactly N → N+1.
class SchemaMigration {
  const SchemaMigration({
    required this.fromVersion,
    required this.toVersion,
    required this.apply,
  });

  final int fromVersion;
  final int toVersion;
  final Future<void> Function(DatabaseExecutor executor) apply;
}

/// Ordered forward-only migrator. Never deletes/recreates the user database.
class MigrationHarness {
  MigrationHarness(List<SchemaMigration> steps)
    : _steps = List<SchemaMigration>.unmodifiable(_validate(steps));

  final List<SchemaMigration> _steps;

  List<SchemaMigration> get steps => _steps;

  static List<SchemaMigration> _validate(List<SchemaMigration> steps) {
    final Set<int> froms = <int>{};
    final Set<int> tos = <int>{};
    for (final SchemaMigration step in steps) {
      if (step.toVersion != step.fromVersion + 1) {
        throw PersistenceException(
          kind: PersistenceFailureKind.migrationFailure,
          message:
              'migration must be contiguous ${step.fromVersion} → ${step.fromVersion + 1}, '
              'not ${step.fromVersion} → ${step.toVersion}',
        );
      }
      if (!froms.add(step.fromVersion)) {
        throw PersistenceException(
          kind: PersistenceFailureKind.migrationFailure,
          message: 'duplicate migration fromVersion ${step.fromVersion}',
        );
      }
      if (!tos.add(step.toVersion)) {
        throw PersistenceException(
          kind: PersistenceFailureKind.migrationFailure,
          message: 'duplicate migration toVersion ${step.toVersion}',
        );
      }
    }
    return List<SchemaMigration>.of(steps);
  }

  List<SchemaMigration> plan({required int from, required int to}) {
    if (to < from) {
      throw PersistenceException(
        kind: PersistenceFailureKind.schemaMismatch,
        message: 'downgrade $from → $to is unsupported',
      );
    }
    if (to == from) {
      return const <SchemaMigration>[];
    }
    final List<SchemaMigration> out = <SchemaMigration>[];
    int cursor = from;
    while (cursor < to) {
      SchemaMigration? next;
      for (final SchemaMigration step in _steps) {
        if (step.fromVersion == cursor && step.toVersion == cursor + 1) {
          next = step;
          break;
        }
      }
      if (next == null) {
        throw PersistenceException(
          kind: PersistenceFailureKind.migrationFailure,
          message: 'missing migration step from $cursor toward $to',
        );
      }
      out.add(next);
      cursor = next.toVersion;
    }
    return out;
  }

  Future<void> apply(
    DatabaseExecutor executor, {
    required int from,
    required int to,
  }) async {
    final List<SchemaMigration> planned = plan(from: from, to: to);
    for (final SchemaMigration step in planned) {
      try {
        await step.apply(executor);
      } on PersistenceException {
        rethrow;
      } catch (error) {
        throw PersistenceException(
          kind: PersistenceFailureKind.migrationFailure,
          message:
              'SQLite failure during migration ${step.fromVersion} → ${step.toVersion}',
          cause: error,
        );
      }
    }
  }
}
