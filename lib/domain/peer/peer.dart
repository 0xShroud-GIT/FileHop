import '../identity/display_name.dart';
import '../identity/peer_fingerprint.dart';

/// Advisory peer snapshot. [localRecordId] is never security identity.
class Peer {
  Peer({
    required this.fingerprint,
    this.localRecordId,
    this.displayName,
    List<String> lastCapabilities = const <String>[],
  }) : lastCapabilities = List<String>.unmodifiable(
         List<String>.from(lastCapabilities),
       );

  /// Local convenience key only. Not [fingerprint], not a transport locator.
  final String? localRecordId;
  final PeerFingerprint fingerprint;
  final DisplayName? displayName;

  /// Capability tokens are advisory. Unknown tokens are ignored later.
  /// Unmodifiable copy; never a caller-owned list.
  final List<String> lastCapabilities;

  Peer copyWith({DisplayName? displayName, List<String>? lastCapabilities}) {
    return Peer(
      fingerprint: fingerprint,
      localRecordId: localRecordId,
      displayName: displayName ?? this.displayName,
      lastCapabilities: lastCapabilities ?? this.lastCapabilities,
    );
  }
}
