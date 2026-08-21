import '../ids/logical_id.dart';
import '../state_machine/finite_state_machine.dart';
import '../state_machine/transition_authority.dart';
import '../transport/transport_kind.dart';

enum TransferItemState {
  pending,
  ready,
  transferring,
  paused,
  verifying,
  completed,
  skipped,
  cancelled,
  failed,
}

enum TransferItemEvent {
  markReady,
  startTransfer,
  pause,
  resume,
  beginVerify,
  verificationSucceeded,
  verificationFailed,
  skip,
  cancel,
  fail,
}

/// One offered item. [completed] is reachable only via [verificationSucceeded].
class TransferItem {
  TransferItem._({
    required this.itemId,
    required this.transferId,
    required this.kind,
    required this.name,
    required this.state,
    this.lastTransition,
  });

  factory TransferItem.pending({
    required LogicalId itemId,
    required LogicalId transferId,
    required TransferItemKind kind,
    required String name,
  }) {
    return TransferItem._(
      itemId: itemId,
      transferId: transferId,
      kind: kind,
      name: name,
      state: TransferItemState.pending,
    );
  }

  static final FiniteStateMachine<TransferItemState, TransferItemEvent>
  machine = FiniteStateMachine<TransferItemState, TransferItemEvent>(
    machine: 'TransferItem',
    allowed: <TransferItemState, Map<TransferItemEvent, TransferItemState>>{
      TransferItemState.pending: <TransferItemEvent, TransferItemState>{
        TransferItemEvent.markReady: TransferItemState.ready,
        TransferItemEvent.skip: TransferItemState.skipped,
        TransferItemEvent.cancel: TransferItemState.cancelled,
        TransferItemEvent.fail: TransferItemState.failed,
      },
      TransferItemState.ready: <TransferItemEvent, TransferItemState>{
        TransferItemEvent.startTransfer: TransferItemState.transferring,
        TransferItemEvent.skip: TransferItemState.skipped,
        TransferItemEvent.cancel: TransferItemState.cancelled,
        TransferItemEvent.fail: TransferItemState.failed,
      },
      TransferItemState.transferring: <TransferItemEvent, TransferItemState>{
        TransferItemEvent.pause: TransferItemState.paused,
        TransferItemEvent.beginVerify: TransferItemState.verifying,
        TransferItemEvent.skip: TransferItemState.skipped,
        TransferItemEvent.cancel: TransferItemState.cancelled,
        TransferItemEvent.fail: TransferItemState.failed,
      },
      TransferItemState.paused: <TransferItemEvent, TransferItemState>{
        TransferItemEvent.resume: TransferItemState.transferring,
        TransferItemEvent.skip: TransferItemState.skipped,
        TransferItemEvent.cancel: TransferItemState.cancelled,
        TransferItemEvent.fail: TransferItemState.failed,
      },
      TransferItemState.verifying: <TransferItemEvent, TransferItemState>{
        TransferItemEvent.verificationSucceeded: TransferItemState.completed,
        TransferItemEvent.verificationFailed: TransferItemState.failed,
        TransferItemEvent.cancel: TransferItemState.cancelled,
        TransferItemEvent.fail: TransferItemState.failed,
      },
    },
  );

  final LogicalId itemId;
  final LogicalId transferId;
  final TransferItemKind kind;
  final String name;
  final TransferItemState state;
  final AppliedTransition<TransferItemState, TransferItemEvent>? lastTransition;

  bool get isTerminal =>
      state == TransferItemState.completed ||
      state == TransferItemState.skipped ||
      state == TransferItemState.cancelled ||
      state == TransferItemState.failed;

  TransferItem apply(
    TransferItemEvent event, {
    required TransitionAuthority authority,
  }) {
    final AppliedTransition<TransferItemState, TransferItemEvent> transition =
        machine.reduce(from: state, event: event, authority: authority);
    return TransferItem._(
      itemId: itemId,
      transferId: transferId,
      kind: kind,
      name: name,
      state: transition.to,
      lastTransition: transition,
    );
  }
}
