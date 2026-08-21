/// Bounded identity/trust failures. Never raw platform/SQLite exceptions.
enum IdentityFailureKind {
  identityAbsent,
  identityAlreadyExists,
  identityCorrupt,
  identityKeyMissing,
  identityStoreUnavailable,
  identityStoreCorrupt,
  unsupportedKeyStorageVersion,
  identityCleanupFailed,
  identityStorageInconsistent,
  identityAllocationExhausted,
  invalidArgument,
  operationFailure,
}

enum TrustFailureKind {
  trustPersistenceFailure,
  invalidTrustTransition,
  invalidArgument,
}

class IdentityException implements Exception {
  const IdentityException({
    required this.kind,
    required this.message,
    this.causeKind,
  });

  final IdentityFailureKind kind;
  final String message;

  /// When [kind] is [IdentityFailureKind.identityCleanupFailed], the original
  /// failure that cleanup was attempting to recover from.
  final IdentityFailureKind? causeKind;

  @override
  String toString() => 'IdentityException(${kind.name}: $message)';
}

class TrustException implements Exception {
  const TrustException({required this.kind, required this.message});

  final TrustFailureKind kind;
  final String message;

  @override
  String toString() => 'TrustException(${kind.name}: $message)';
}
