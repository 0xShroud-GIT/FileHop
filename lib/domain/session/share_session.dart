import '../identity/peer_fingerprint.dart';
import '../ids/logical_id.dart';
import '../transport/transport_kind.dart';

/// Offer/relationship aggregate. Transfer lifecycle lives on [Transfer].
///
/// `06_STATE_MACHINES.md` does not define a ShareSession machine. This type
/// must not grow a competing offer/accept/reject state machine.
class ShareSession {
  ShareSession({
    required this.shareSessionId,
    required this.transferId,
    required this.peerFingerprint,
    required this.direction,
    List<LogicalId> itemIds = const <LogicalId>[],
  }) : itemIds = List<LogicalId>.unmodifiable(List<LogicalId>.from(itemIds));

  final LogicalId shareSessionId;
  final LogicalId transferId;
  final PeerFingerprint peerFingerprint;
  final ShareDirection direction;

  /// Unmodifiable copy; never a caller-owned list.
  final List<LogicalId> itemIds;
}
