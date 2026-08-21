import 'display_name.dart';
import 'peer_fingerprint.dart';

/// Cryptographic peer identity reference. Display name is not part of equality.
class PeerIdentity {
  const PeerIdentity({required this.fingerprint, this.displayName});

  final PeerFingerprint fingerprint;
  final DisplayName? displayName;

  PeerIdentity withDisplayName(DisplayName? name) {
    return PeerIdentity(fingerprint: fingerprint, displayName: name);
  }

  @override
  bool operator ==(Object other) =>
      other is PeerIdentity && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;
}
