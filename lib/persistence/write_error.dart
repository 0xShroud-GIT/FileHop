import 'errors.dart';

/// Classifies SQLite write failures without leaking raw database exceptions.
PersistenceException translateWriteError(String operation, Object error) {
  if (error is PersistenceException) {
    return error;
  }
  if (_isConstraintFailure(error)) {
    return PersistenceException(
      kind: PersistenceFailureKind.constraintViolation,
      message: 'constraint violation during $operation',
      cause: error,
    );
  }
  return PersistenceException(
    kind: PersistenceFailureKind.operationFailure,
    message: 'database write failed during $operation',
    cause: error,
  );
}

Future<T> persistWrite<T>(String operation, Future<T> Function() body) async {
  try {
    return await body();
  } on PersistenceException {
    rethrow;
  } catch (error) {
    throw translateWriteError(operation, error);
  }
}

bool _isConstraintFailure(Object error) {
  final String text = error.toString().toLowerCase();
  return text.contains('constraint') ||
      text.contains('unique') ||
      text.contains('foreign key') ||
      text.contains('primary key') ||
      text.contains('not null') ||
      text.contains('check constraint') ||
      text.contains('sqlite_error: 19') ||
      text.contains('sqlite_error: 275') ||
      text.contains('sqlite_error: 787') ||
      text.contains('sqlite_error: 1555') ||
      text.contains('sqlite_error: 2067');
}
