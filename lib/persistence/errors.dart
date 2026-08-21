/// Bounded persistence failures. Never an empty/reset database.
enum PersistenceFailureKind {
  openFailure,
  schemaMismatch,
  migrationFailure,
  constraintViolation,
  operationFailure,
  decodeFailure,
  invalidArgument,
}

class PersistenceException implements Exception {
  const PersistenceException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final PersistenceFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'PersistenceException(${kind.name}: $message)';
}
