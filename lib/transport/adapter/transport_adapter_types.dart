import '../../domain/transport/transport_kind.dart';
import 'transport_availability.dart';

/// Immutable capability snapshot for one transport family.
class TransportCapabilitySnapshot {
  const TransportCapabilitySnapshot({
    required this.kind,
    required this.availability,
    this.permission,
    this.detail,
  });

  final TransportKind kind;
  final TransportAvailability availability;
  final TransportPermissionStatus? permission;
  final String? detail;

  TransportCapabilitySnapshot withPermission(TransportPermissionStatus? next) {
    return TransportCapabilitySnapshot(
      kind: kind,
      availability: availability,
      permission: next,
      detail: detail,
    );
  }
}

/// Compound locator key. Not a peer security identity.
class TransportCandidateKey {
  const TransportCandidateKey({required this.kind, required this.candidateId});

  final TransportKind kind;
  final String candidateId;

  @override
  bool operator ==(Object other) {
    return other is TransportCandidateKey &&
        other.kind == kind &&
        other.candidateId == candidateId;
  }

  @override
  int get hashCode => Object.hash(kind, candidateId);

  @override
  String toString() => 'TransportCandidateKey(${kind.wire}, $candidateId)';
}

/// Adapter connection handle. Not an authenticated peer.
class TransportConnectionHandle {
  const TransportConnectionHandle({required this.handleId, required this.kind});

  final String handleId;
  final TransportKind kind;
}

/// Reachable endpoint metadata. Host/path are locators, never identity.
class TransportEndpoint {
  const TransportEndpoint({
    required this.endpointId,
    required this.kind,
    this.host,
    this.port,
    this.nativePathHandle,
  });

  final String endpointId;
  final TransportKind kind;
  final String? host;
  final int? port;
  final String? nativePathHandle;
}

/// Currently selected runtime path. No fingerprint / session / trust.
class SelectedTransportPath {
  const SelectedTransportPath({
    required this.key,
    required this.connection,
    required this.healthy,
    this.endpoint,
  });

  final TransportCandidateKey key;
  final TransportConnectionHandle connection;
  final TransportEndpoint? endpoint;
  final bool healthy;

  TransportKind get kind => key.kind;

  SelectedTransportPath markUnhealthy() {
    return SelectedTransportPath(
      key: key,
      connection: connection,
      endpoint: endpoint,
      healthy: false,
    );
  }
}
