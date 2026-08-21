import '../identity/display_name.dart';
import '../identity/peer_fingerprint.dart';
import '../ids/logical_id.dart';
import '../state_machine/finite_state_machine.dart';
import '../state_machine/invalid_state_transition.dart';
import '../state_machine/transition_authority.dart';

enum PeerSessionState {
  discovered,
  connecting,
  authenticating,
  verifyingFirstContact,
  connected,
  reconnecting,
  disconnected,
  blocked,
  failed,
}

enum PeerSessionEvent {
  connectRequested,
  pathEstablished,
  handshakeAuthenticatedTrusted,
  handshakeAuthenticatedFirstContact,
  firstContactResolved,
  transportLost,
  disconnect,
  fail,
  block,
}

/// Successful Noise handshake result. The only way to bind security identity.
///
/// Mission 03 does not compute these values. Mission 11 supplies them.
class HandshakeAuthenticated {
  const HandshakeAuthenticated.trusted({
    required this.authenticatedFingerprint,
    required this.peerSessionId,
    this.authority = TransitionAuthority.peerEvent,
  }) : firstContact = false;

  const HandshakeAuthenticated.firstContact({
    required this.authenticatedFingerprint,
    required this.peerSessionId,
    this.authority = TransitionAuthority.peerEvent,
  }) : firstContact = true;

  final PeerFingerprint authenticatedFingerprint;
  final PeerSessionId peerSessionId;
  final TransitionAuthority authority;
  final bool firstContact;

  PeerSessionEvent get event => firstContact
      ? PeerSessionEvent.handshakeAuthenticatedFirstContact
      : PeerSessionEvent.handshakeAuthenticatedTrusted;
}

/// Authenticated live relationship to one peer identity. Engine-owned.
class PeerSession {
  PeerSession._({
    required this.state,
    required this.displayName,
    this.authenticatedFingerprint,
    this.peerSessionId,
    this.lastTransition,
  });

  factory PeerSession.discovered({required DisplayName displayName}) {
    return PeerSession._(
      state: PeerSessionState.discovered,
      displayName: displayName,
    );
  }

  static final FiniteStateMachine<PeerSessionState, PeerSessionEvent> machine =
      FiniteStateMachine<PeerSessionState, PeerSessionEvent>(
        machine: 'PeerSession',
        allowed: <PeerSessionState, Map<PeerSessionEvent, PeerSessionState>>{
          PeerSessionState.discovered: <PeerSessionEvent, PeerSessionState>{
            PeerSessionEvent.connectRequested: PeerSessionState.connecting,
          },
          PeerSessionState.connecting: <PeerSessionEvent, PeerSessionState>{
            PeerSessionEvent.pathEstablished: PeerSessionState.authenticating,
            PeerSessionEvent.disconnect: PeerSessionState.disconnected,
            PeerSessionEvent.fail: PeerSessionState.failed,
            PeerSessionEvent.block: PeerSessionState.blocked,
          },
          PeerSessionState.authenticating: <PeerSessionEvent, PeerSessionState>{
            PeerSessionEvent.handshakeAuthenticatedTrusted:
                PeerSessionState.connected,
            PeerSessionEvent.handshakeAuthenticatedFirstContact:
                PeerSessionState.verifyingFirstContact,
            PeerSessionEvent.disconnect: PeerSessionState.disconnected,
            PeerSessionEvent.fail: PeerSessionState.failed,
            PeerSessionEvent.block: PeerSessionState.blocked,
          },
          PeerSessionState
              .verifyingFirstContact: <PeerSessionEvent, PeerSessionState>{
            PeerSessionEvent.firstContactResolved: PeerSessionState.connected,
            PeerSessionEvent.disconnect: PeerSessionState.disconnected,
            PeerSessionEvent.fail: PeerSessionState.failed,
            PeerSessionEvent.block: PeerSessionState.blocked,
          },
          PeerSessionState.connected: <PeerSessionEvent, PeerSessionState>{
            PeerSessionEvent.transportLost: PeerSessionState.reconnecting,
            PeerSessionEvent.disconnect: PeerSessionState.disconnected,
          },
          PeerSessionState.reconnecting: <PeerSessionEvent, PeerSessionState>{
            PeerSessionEvent.pathEstablished: PeerSessionState.authenticating,
            PeerSessionEvent.disconnect: PeerSessionState.disconnected,
            PeerSessionEvent.fail: PeerSessionState.failed,
            PeerSessionEvent.block: PeerSessionState.blocked,
          },
        },
      );

  static const Set<PeerSessionEvent> _authenticationEvents = <PeerSessionEvent>{
    PeerSessionEvent.handshakeAuthenticatedTrusted,
    PeerSessionEvent.handshakeAuthenticatedFirstContact,
  };

  final PeerSessionState state;
  final DisplayName displayName;

  /// Bound only by [applyAuthentication]. Null before handshake success.
  final PeerFingerprint? authenticatedFingerprint;
  final PeerSessionId? peerSessionId;
  final AppliedTransition<PeerSessionState, PeerSessionEvent>? lastTransition;

  bool get isTerminal =>
      state == PeerSessionState.disconnected ||
      state == PeerSessionState.blocked ||
      state == PeerSessionState.failed;

  /// Non-authentication transitions. Cannot bind or replace identity.
  PeerSession apply(
    PeerSessionEvent event, {
    required TransitionAuthority authority,
  }) {
    if (_authenticationEvents.contains(event)) {
      throw const DomainFormatException(
        'authentication events require applyAuthentication',
      );
    }
    final AppliedTransition<PeerSessionState, PeerSessionEvent> transition =
        machine.reduce(from: state, event: event, authority: authority);
    return PeerSession._(
      state: transition.to,
      displayName: displayName,
      authenticatedFingerprint: authenticatedFingerprint,
      peerSessionId: peerSessionId,
      lastTransition: transition,
    );
  }

  /// Binds [HandshakeAuthenticated] values after a successful handshake event.
  ///
  /// Re-handshake may replace [peerSessionId]. A different fingerprint is a
  /// deterministic [PeerIdentityMismatch] and does not mutate this session.
  PeerSession applyAuthentication(HandshakeAuthenticated handshake) {
    if (authenticatedFingerprint != null &&
        authenticatedFingerprint != handshake.authenticatedFingerprint) {
      throw PeerIdentityMismatch(
        existing: authenticatedFingerprint!,
        attempted: handshake.authenticatedFingerprint,
      );
    }
    final AppliedTransition<PeerSessionState, PeerSessionEvent> transition =
        machine.reduce(
          from: state,
          event: handshake.event,
          authority: handshake.authority,
        );
    return PeerSession._(
      state: transition.to,
      displayName: displayName,
      authenticatedFingerprint: handshake.authenticatedFingerprint,
      peerSessionId: handshake.peerSessionId,
      lastTransition: transition,
    );
  }
}
