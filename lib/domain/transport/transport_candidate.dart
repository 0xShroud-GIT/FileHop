import '../state_machine/finite_state_machine.dart';
import '../state_machine/transition_authority.dart';
import 'transport_kind.dart';

enum TransportCandidateState {
  observed,
  available,
  connecting,
  connected,
  unavailable,
  failed,
  lost,
}

enum TransportCandidateEvent {
  becomeAvailable,
  startConnect,
  connected,
  unavailable,
  fail,
  lost,
}

/// One way to reach a peer. Locator metadata only — never peer identity.
/// Distinct from Mission 02 `NativeTransportCandidate`.
class TransportCandidate {
  TransportCandidate._({
    required this.candidateId,
    required this.kind,
    required this.state,
    this.locatorHint,
    this.lastTransition,
  });

  factory TransportCandidate.observed({
    required String candidateId,
    required TransportKind kind,
    String? locatorHint,
  }) {
    return TransportCandidate._(
      candidateId: candidateId,
      kind: kind,
      state: TransportCandidateState.observed,
      locatorHint: locatorHint,
    );
  }

  static final FiniteStateMachine<
    TransportCandidateState,
    TransportCandidateEvent
  >
  machine =
      FiniteStateMachine<TransportCandidateState, TransportCandidateEvent>(
        machine: 'TransportCandidate',
        allowed:
            <
              TransportCandidateState,
              Map<TransportCandidateEvent, TransportCandidateState>
            >{
              TransportCandidateState.observed:
                  <TransportCandidateEvent, TransportCandidateState>{
                    TransportCandidateEvent.becomeAvailable:
                        TransportCandidateState.available,
                  },
              TransportCandidateState.available:
                  <TransportCandidateEvent, TransportCandidateState>{
                    TransportCandidateEvent.startConnect:
                        TransportCandidateState.connecting,
                    TransportCandidateEvent.unavailable:
                        TransportCandidateState.unavailable,
                  },
              TransportCandidateState.connecting:
                  <TransportCandidateEvent, TransportCandidateState>{
                    TransportCandidateEvent.connected:
                        TransportCandidateState.connected,
                    TransportCandidateEvent.fail:
                        TransportCandidateState.failed,
                    TransportCandidateEvent.lost: TransportCandidateState.lost,
                  },
              TransportCandidateState.connected:
                  <TransportCandidateEvent, TransportCandidateState>{
                    TransportCandidateEvent.fail:
                        TransportCandidateState.failed,
                    TransportCandidateEvent.lost: TransportCandidateState.lost,
                  },
            },
      );

  final String candidateId;
  final TransportKind kind;
  final TransportCandidateState state;

  /// SSID / handle / service name. Not a fingerprint.
  final String? locatorHint;
  final AppliedTransition<TransportCandidateState, TransportCandidateEvent>?
  lastTransition;

  /// Locator/display metadata only. Does not change [state].
  TransportCandidate withLocatorHint(String? nextLocatorHint) {
    return TransportCandidate._(
      candidateId: candidateId,
      kind: kind,
      state: state,
      locatorHint: nextLocatorHint,
      lastTransition: lastTransition,
    );
  }

  TransportCandidate apply(
    TransportCandidateEvent event, {
    required TransitionAuthority authority,
  }) {
    final AppliedTransition<TransportCandidateState, TransportCandidateEvent>
    transition = machine.reduce(
      from: state,
      event: event,
      authority: authority,
    );
    return TransportCandidate._(
      candidateId: candidateId,
      kind: kind,
      state: transition.to,
      locatorHint: locatorHint,
      lastTransition: transition,
    );
  }
}
