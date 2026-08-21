/// Bounded LAN discovery failures. Never raw platform exceptions.
enum LanDiscoveryFailureKind {
  malformedDiscoveryRecord,
  unsupportedDiscoveryVersion,
  discoveryStartFailed,
  discoveryStopped,
  candidateLimitExceeded,
  advertisementNotConfigured,
  staleGeneration,
  wrongServiceType,
}

class LanDiscoveryException implements Exception {
  const LanDiscoveryException({required this.kind, required this.message});

  final LanDiscoveryFailureKind kind;
  final String message;

  @override
  String toString() => 'LanDiscoveryException(${kind.name}: $message)';
}
