/// Bounded transport-layer failures. Never raw platform exceptions.
enum TransportFailureKind {
  noEligibleTransport,
  adapterUnavailable,
  permissionRequired,
  candidateLost,
  connectionFailed,
  endpointFailed,
  cancelled,
  adapterContractViolation,
  interopUnverified,
  allFallbacksFailed,
  noCandidates,
  cleanupFailed,
  attemptCleanupUnavailable,
  invalidArgument,
}

class TransportException implements Exception {
  const TransportException({
    required this.kind,
    required this.message,
    this.causeKind,
  });

  final TransportFailureKind kind;
  final String message;
  final TransportFailureKind? causeKind;

  @override
  String toString() => 'TransportException(${kind.name}: $message)';
}
