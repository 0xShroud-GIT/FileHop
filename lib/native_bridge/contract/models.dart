import 'enums.dart';

/// Locator/session metadata only. No security identity, fingerprint, or key.
class NativeTransportCandidate {
  const NativeTransportCandidate({
    required this.candidateId,
    required this.kind,
    this.displayLabel,
    this.locatorHint,
  });

  final String candidateId;
  final NativeTransportKind kind;

  /// Human convenience label. Never treat as cryptographic identity.
  final String? displayLabel;

  /// Opaque locator hint (SSID/handle/service name). Not a peer identity.
  final String? locatorHint;
}

class NativeConnectionHandle {
  const NativeConnectionHandle({required this.handleId, required this.kind});

  final String handleId;
  final NativeTransportKind kind;
}

/// Socket-reachable or native-managed stream. Not a [PeerIdentity].
///
/// Codec validation is by [reachability] only:
/// - [NativeEndpointReachability.socket] requires usable [host] and [port] 1..65535
/// - [NativeEndpointReachability.nativeStream] requires [nativePathHandle]
/// Fields that belong to the other mode are ignored and are never identity.
class NativeEndpoint {
  const NativeEndpoint({
    required this.endpointId,
    required this.kind,
    required this.reachability,
    this.host,
    this.port,
    this.nativePathHandle,
  });

  final String endpointId;
  final NativeTransportKind kind;
  final NativeEndpointReachability reachability;
  final String? host;
  final int? port;

  /// Opaque native path/stream token when Dart cannot own a socket.
  final String? nativePathHandle;
}

class NativeCapabilitySnapshot {
  const NativeCapabilitySnapshot({
    required this.kind,
    required this.status,
    this.permission,
    this.detail,
  });

  final NativeTransportKind kind;
  final NativeCapabilityStatus status;
  final NativePermissionStatus? permission;
  final String? detail;
}

class NativeAdapterError {
  const NativeAdapterError({
    required this.errorClass,
    required this.message,
    this.nativeCode,
    this.kind,
  });

  final NativeErrorClass errorClass;
  final String message;
  final String? nativeCode;
  final NativeTransportKind? kind;
}

class NativeLifecycleEvent {
  const NativeLifecycleEvent({required this.kind, this.detail});

  final NativeLifecycleKind kind;
  final String? detail;
}

class NativePingResult {
  const NativePingResult({required this.bridgeVersion, required this.ok});

  final int bridgeVersion;
  final bool ok;
}

/// Native protected-secret resolution. Never includes key bytes.
enum NativeIdentitySecretStatus {
  present('present'),
  absent('absent'),
  missingCiphertext('missingCiphertext'),
  missingWrappingKey('missingWrappingKey'),
  corrupt('corrupt'),
  unavailable('unavailable'),
  unsupported('unsupported'),
  unknown('unknown');

  const NativeIdentitySecretStatus(this.wire);
  final String wire;

  static NativeIdentitySecretStatus fromWire(String value) {
    for (final NativeIdentitySecretStatus item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeIdentitySecretStatus.unknown;
  }
}

class NativeIdentitySecretReference {
  const NativeIdentitySecretReference({required this.reference});
  final String reference;
}

class NativeIdentitySecretPresence {
  const NativeIdentitySecretPresence({required this.any});
  final bool any;
}
