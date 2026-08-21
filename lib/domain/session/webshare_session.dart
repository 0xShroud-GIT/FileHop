import '../ids/logical_id.dart';
import '../state_machine/finite_state_machine.dart';
import '../state_machine/transition_authority.dart';

enum WebShareSessionState {
  stopped,
  starting,
  active,
  clientConnected,
  stopping,
}

enum WebShareSessionEvent {
  start,
  becameActive,
  clientConnected,
  lastClientDisconnected,
  stop,
  stopped,
  processInterrupted,
}

/// Local browser-share session states only. No HTTP, tokens, or sockets.
///
/// `CLIENT_CONNECTED*` (D-03-01): ACTIVE may stop with zero clients.
/// The first client enters [clientConnected]. Further clients stay there.
/// [lastClientDisconnected] returns to ACTIVE. Restart always yields STOPPED.
class WebShareSession {
  WebShareSession._({
    required this.webShareSessionId,
    required this.state,
    this.lastTransition,
  });

  factory WebShareSession.stopped({required LogicalId webShareSessionId}) {
    return WebShareSession._(
      webShareSessionId: webShareSessionId,
      state: WebShareSessionState.stopped,
    );
  }

  static final FiniteStateMachine<WebShareSessionState, WebShareSessionEvent>
  machine = FiniteStateMachine<WebShareSessionState, WebShareSessionEvent>(
    machine: 'WebShareSession',
    allowed:
        <WebShareSessionState, Map<WebShareSessionEvent, WebShareSessionState>>{
          WebShareSessionState.stopped:
              <WebShareSessionEvent, WebShareSessionState>{
                WebShareSessionEvent.start: WebShareSessionState.starting,
              },
          WebShareSessionState.starting:
              <WebShareSessionEvent, WebShareSessionState>{
                WebShareSessionEvent.becameActive: WebShareSessionState.active,
                WebShareSessionEvent.stop: WebShareSessionState.stopping,
                WebShareSessionEvent.processInterrupted:
                    WebShareSessionState.stopped,
              },
          WebShareSessionState.active:
              <WebShareSessionEvent, WebShareSessionState>{
                WebShareSessionEvent.clientConnected:
                    WebShareSessionState.clientConnected,
                WebShareSessionEvent.stop: WebShareSessionState.stopping,
                WebShareSessionEvent.processInterrupted:
                    WebShareSessionState.stopped,
              },
          WebShareSessionState.clientConnected:
              <WebShareSessionEvent, WebShareSessionState>{
                WebShareSessionEvent.lastClientDisconnected:
                    WebShareSessionState.active,
                WebShareSessionEvent.stop: WebShareSessionState.stopping,
                WebShareSessionEvent.processInterrupted:
                    WebShareSessionState.stopped,
              },
          WebShareSessionState.stopping:
              <WebShareSessionEvent, WebShareSessionState>{
                WebShareSessionEvent.stopped: WebShareSessionState.stopped,
                WebShareSessionEvent.processInterrupted:
                    WebShareSessionState.stopped,
              },
        },
    noop: <(Object, Object)>{
      (WebShareSessionState.stopped, WebShareSessionEvent.stop),
      (WebShareSessionState.stopped, WebShareSessionEvent.stopped),
      (WebShareSessionState.stopped, WebShareSessionEvent.processInterrupted),
      (
        WebShareSessionState.clientConnected,
        WebShareSessionEvent.clientConnected,
      ),
    },
  );

  final LogicalId webShareSessionId;
  final WebShareSessionState state;
  final AppliedTransition<WebShareSessionState, WebShareSessionEvent>?
  lastTransition;

  WebShareSession apply(
    WebShareSessionEvent event, {
    required TransitionAuthority authority,
  }) {
    final AppliedTransition<WebShareSessionState, WebShareSessionEvent>
    transition = machine.reduce(
      from: state,
      event: event,
      authority: authority,
    );
    return WebShareSession._(
      webShareSessionId: webShareSessionId,
      state: transition.to,
      lastTransition: transition,
    );
  }
}
