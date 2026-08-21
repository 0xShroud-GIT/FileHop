import '../identity/peer_fingerprint.dart';
import '../ids/logical_id.dart';
import '../state_machine/finite_state_machine.dart';
import '../state_machine/transition_authority.dart';
import '../transport/transport_kind.dart';

enum TransferState {
  created,
  offered,
  accepted,
  transferring,
  paused,
  verifying,
  recoveryPending,
  completed,
  rejected,
  cancelled,
  failed,
}

enum TransferEvent {
  offer,
  accept,
  startTransfer,
  pause,
  resume,
  beginVerify,
  verificationSucceeded,
  verificationFailed,
  reject,
  cancel,
  fail,
  processInterrupted,
  checkpointResumable,
  checkpointInvalid,
}

/// FileHop transfer lifecycle. Retry after terminal failure is a new [transferId].
class Transfer {
  Transfer._({
    required this.transferId,
    required this.shareSessionId,
    required this.peerFingerprint,
    required this.direction,
    required this.state,
    this.lastTransition,
  });

  factory Transfer.created({
    required LogicalId transferId,
    required LogicalId shareSessionId,
    required PeerFingerprint peerFingerprint,
    required ShareDirection direction,
  }) {
    return Transfer._(
      transferId: transferId,
      shareSessionId: shareSessionId,
      peerFingerprint: peerFingerprint,
      direction: direction,
      state: TransferState.created,
    );
  }

  static const Set<TransferState> terminal = <TransferState>{
    TransferState.completed,
    TransferState.rejected,
    TransferState.cancelled,
    TransferState.failed,
  };

  static final FiniteStateMachine<TransferState, TransferEvent> machine =
      FiniteStateMachine<TransferState, TransferEvent>(
        machine: 'Transfer',
        allowed: <TransferState, Map<TransferEvent, TransferState>>{
          TransferState.created: <TransferEvent, TransferState>{
            TransferEvent.offer: TransferState.offered,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
          },
          TransferState.offered: <TransferEvent, TransferState>{
            TransferEvent.accept: TransferState.accepted,
            TransferEvent.reject: TransferState.rejected,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
          },
          TransferState.accepted: <TransferEvent, TransferState>{
            TransferEvent.startTransfer: TransferState.transferring,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
          },
          TransferState.transferring: <TransferEvent, TransferState>{
            TransferEvent.pause: TransferState.paused,
            TransferEvent.beginVerify: TransferState.verifying,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
            TransferEvent.processInterrupted: TransferState.recoveryPending,
          },
          TransferState.paused: <TransferEvent, TransferState>{
            TransferEvent.resume: TransferState.transferring,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
            TransferEvent.processInterrupted: TransferState.recoveryPending,
          },
          TransferState.verifying: <TransferEvent, TransferState>{
            TransferEvent.verificationSucceeded: TransferState.completed,
            TransferEvent.verificationFailed: TransferState.failed,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
            TransferEvent.processInterrupted: TransferState.recoveryPending,
          },
          TransferState.recoveryPending: <TransferEvent, TransferState>{
            TransferEvent.checkpointResumable: TransferState.paused,
            TransferEvent.checkpointInvalid: TransferState.failed,
            TransferEvent.cancel: TransferState.cancelled,
            TransferEvent.fail: TransferState.failed,
          },
        },
      );

  final LogicalId transferId;
  final LogicalId shareSessionId;
  final PeerFingerprint peerFingerprint;
  final ShareDirection direction;
  final TransferState state;
  final AppliedTransition<TransferState, TransferEvent>? lastTransition;

  bool get isTerminal => terminal.contains(state);

  Transfer apply(
    TransferEvent event, {
    required TransitionAuthority authority,
  }) {
    final AppliedTransition<TransferState, TransferEvent> transition = machine
        .reduce(from: state, event: event, authority: authority);
    return Transfer._(
      transferId: transferId,
      shareSessionId: shareSessionId,
      peerFingerprint: peerFingerprint,
      direction: direction,
      state: transition.to,
      lastTransition: transition,
    );
  }
}
