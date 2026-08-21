import '../identity/peer_fingerprint.dart';
import '../ids/logical_id.dart';
import '../state_machine/finite_state_machine.dart';
import '../state_machine/transition_authority.dart';

enum ScreenSessionState {
  idle,
  requesting,
  accepted,
  awaitingOsConsent,
  captureStarting,
  negotiating,
  connected,
  firstFrame,
  live,
  stopping,
  closed,
  rejected,
  cancelled,
  failed,
}

enum ScreenSessionEvent {
  request,
  accept,
  awaitOsConsent,
  captureStarting,
  negotiate,
  mediaConnected,
  firstFrameRendered,
  becomeLive,
  stop,
  close,
  reject,
  cancel,
  fail,
  processInterrupted,
}

/// Domain screen states only. No capture, WebRTC, or media.
class ScreenSession {
  ScreenSession._({
    required this.screenSessionId,
    required this.peerFingerprint,
    required this.state,
    this.lastTransition,
  });

  factory ScreenSession.idle({
    required LogicalId screenSessionId,
    required PeerFingerprint peerFingerprint,
  }) {
    return ScreenSession._(
      screenSessionId: screenSessionId,
      peerFingerprint: peerFingerprint,
      state: ScreenSessionState.idle,
    );
  }

  static const Set<ScreenSessionState> _preLive = <ScreenSessionState>{
    ScreenSessionState.requesting,
    ScreenSessionState.accepted,
    ScreenSessionState.awaitingOsConsent,
    ScreenSessionState.captureStarting,
    ScreenSessionState.negotiating,
    ScreenSessionState.connected,
    ScreenSessionState.firstFrame,
  };

  static const Map<ScreenSessionEvent, ScreenSessionState> _preLiveExits =
      <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.reject: ScreenSessionState.rejected,
        ScreenSessionEvent.cancel: ScreenSessionState.cancelled,
        ScreenSessionEvent.fail: ScreenSessionState.failed,
        ScreenSessionEvent.close: ScreenSessionState.closed,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
      };

  static final FiniteStateMachine<ScreenSessionState, ScreenSessionEvent>
  machine = FiniteStateMachine<ScreenSessionState, ScreenSessionEvent>(
    machine: 'ScreenSession',
    allowed: <ScreenSessionState, Map<ScreenSessionEvent, ScreenSessionState>>{
      ScreenSessionState.idle: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.request: ScreenSessionState.requesting,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.idle,
      },
      ScreenSessionState.requesting: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.accept: ScreenSessionState.accepted,
        ..._preLiveExits,
      },
      ScreenSessionState.accepted: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.awaitOsConsent: ScreenSessionState.awaitingOsConsent,
        ..._preLiveExits,
      },
      ScreenSessionState
          .awaitingOsConsent: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.captureStarting: ScreenSessionState.captureStarting,
        ..._preLiveExits,
      },
      ScreenSessionState.captureStarting:
          <ScreenSessionEvent, ScreenSessionState>{
            ScreenSessionEvent.negotiate: ScreenSessionState.negotiating,
            ..._preLiveExits,
          },
      ScreenSessionState.negotiating: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.mediaConnected: ScreenSessionState.connected,
        ..._preLiveExits,
      },
      ScreenSessionState.connected: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.firstFrameRendered: ScreenSessionState.firstFrame,
        ..._preLiveExits,
      },
      ScreenSessionState.firstFrame: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.becomeLive: ScreenSessionState.live,
        ..._preLiveExits,
      },
      ScreenSessionState.live: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.stop: ScreenSessionState.stopping,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
      },
      ScreenSessionState.stopping: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.close: ScreenSessionState.closed,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
      },
    },
    noop: <(Object, Object)>{
      (ScreenSessionState.closed, ScreenSessionEvent.close),
      (ScreenSessionState.closed, ScreenSessionEvent.stop),
      (ScreenSessionState.closed, ScreenSessionEvent.processInterrupted),
      (ScreenSessionState.idle, ScreenSessionEvent.processInterrupted),
    },
  );

  final LogicalId screenSessionId;
  final PeerFingerprint peerFingerprint;
  final ScreenSessionState state;
  final AppliedTransition<ScreenSessionState, ScreenSessionEvent>?
  lastTransition;

  bool get isLive => state == ScreenSessionState.live;

  bool get isPreLive => _preLive.contains(state);

  ScreenSession apply(
    ScreenSessionEvent event, {
    required TransitionAuthority authority,
  }) {
    final AppliedTransition<ScreenSessionState, ScreenSessionEvent> transition =
        machine.reduce(from: state, event: event, authority: authority);
    return ScreenSession._(
      screenSessionId: screenSessionId,
      peerFingerprint: peerFingerprint,
      state: transition.to,
      lastTransition: transition,
    );
  }
}
