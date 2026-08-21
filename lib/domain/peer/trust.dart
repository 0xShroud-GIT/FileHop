import '../identity/peer_fingerprint.dart';
import '../state_machine/finite_state_machine.dart';
import '../state_machine/transition_authority.dart';

enum TrustState { none, trusted, blocked }

enum TrustEvent { verifyQr, verifySas, forget, block, unblock }

/// Persistent trust metadata rules only. No storage or fingerprint derivation.
class TrustRecord {
  TrustRecord._({
    required this.fingerprint,
    required this.state,
    this.lastTransition,
  });

  factory TrustRecord.none(PeerFingerprint fingerprint) {
    return TrustRecord._(fingerprint: fingerprint, state: TrustState.none);
  }

  /// Restore a previously persisted state. Not a transition.
  factory TrustRecord.rehydrate({
    required PeerFingerprint fingerprint,
    required TrustState state,
  }) {
    return TrustRecord._(fingerprint: fingerprint, state: state);
  }

  static final FiniteStateMachine<TrustState, TrustEvent> machine =
      FiniteStateMachine<TrustState, TrustEvent>(
        machine: 'TrustRecord',
        allowed: <TrustState, Map<TrustEvent, TrustState>>{
          TrustState.none: <TrustEvent, TrustState>{
            TrustEvent.verifyQr: TrustState.trusted,
            TrustEvent.verifySas: TrustState.trusted,
            TrustEvent.block: TrustState.blocked,
          },
          TrustState.trusted: <TrustEvent, TrustState>{
            TrustEvent.forget: TrustState.none,
            TrustEvent.block: TrustState.blocked,
          },
          TrustState.blocked: <TrustEvent, TrustState>{
            TrustEvent.unblock: TrustState.none,
          },
        },
        noop: <(Object, Object)>{
          (TrustState.none, TrustEvent.forget),
          (TrustState.blocked, TrustEvent.block),
        },
      );

  final PeerFingerprint fingerprint;
  final TrustState state;
  final AppliedTransition<TrustState, TrustEvent>? lastTransition;

  bool get isTrusted => state == TrustState.trusted;
  bool get isBlocked => state == TrustState.blocked;

  TrustRecord apply(
    TrustEvent event, {
    required TransitionAuthority authority,
  }) {
    final AppliedTransition<TrustState, TrustEvent> transition = machine.reduce(
      from: state,
      event: event,
      authority: authority,
    );
    return TrustRecord._(
      fingerprint: fingerprint,
      state: transition.to,
      lastTransition: transition,
    );
  }
}
