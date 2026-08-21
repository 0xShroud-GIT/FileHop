import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  PeerSession discovered() =>
      PeerSession.discovered(displayName: fixtureName());

  PeerSession apply(PeerSession session, PeerSessionEvent event) {
    return session.apply(event, authority: TransitionAuthority.localCommand);
  }

  PeerSession toAuthenticating() {
    return discovered()
        .apply(
          PeerSessionEvent.connectRequested,
          authority: TransitionAuthority.localCommand,
        )
        .apply(
          PeerSessionEvent.pathEstablished,
          authority: TransitionAuthority.transportEvent,
        );
  }

  test('DISCOVERED to CONNECTING does not bind peerSessionId', () {
    final PeerSession connecting = apply(
      discovered(),
      PeerSessionEvent.connectRequested,
    );
    expect(connecting.state, PeerSessionState.connecting);
    expect(connecting.peerSessionId, isNull);
    expect(connecting.authenticatedFingerprint, isNull);
  });

  test('CONNECTING to AUTHENTICATING does not bind peerSessionId', () {
    final PeerSession authenticating = toAuthenticating();
    expect(authenticating.state, PeerSessionState.authenticating);
    expect(authenticating.peerSessionId, isNull);
    expect(authenticating.authenticatedFingerprint, isNull);
  });

  test('authentication success binds fingerprint and peerSessionId', () {
    final PeerSession connected = toAuthenticating().applyAuthentication(
      trustedHandshake(),
    );
    expect(connected.state, PeerSessionState.connected);
    expect(connected.authenticatedFingerprint, fixtureFingerprint());
    expect(connected.peerSessionId, fixturePeerSessionId());
    expect(connected.lastTransition?.authority, TransitionAuthority.peerEvent);
  });

  test('generic apply cannot inject peerSessionId or fingerprint', () {
    final PeerSession connecting = apply(
      discovered(),
      PeerSessionEvent.connectRequested,
    );
    expect(
      () => connecting.apply(
        PeerSessionEvent.handshakeAuthenticatedTrusted,
        authority: TransitionAuthority.peerEvent,
      ),
      throwsA(isA<DomainFormatException>()),
    );
    expect(connecting.peerSessionId, isNull);
    expect(connecting.authenticatedFingerprint, isNull);
  });

  test('transport event after authentication leaves identity unchanged', () {
    final PeerSession connected = toAuthenticating().applyAuthentication(
      trustedHandshake(),
    );
    final PeerSession reconnecting = connected.apply(
      PeerSessionEvent.transportLost,
      authority: TransitionAuthority.transportEvent,
    );
    expect(reconnecting.state, PeerSessionState.reconnecting);
    expect(reconnecting.authenticatedFingerprint, fixtureFingerprint());
    expect(reconnecting.peerSessionId, fixturePeerSessionId());
  });

  test('first-contact path enters VERIFYING_FIRST_CONTACT then CONNECTED', () {
    PeerSession session = toAuthenticating().applyAuthentication(
      firstContactHandshake(),
    );
    expect(session.state, PeerSessionState.verifyingFirstContact);
    expect(session.authenticatedFingerprint, fixtureFingerprint());
    expect(session.peerSessionId, fixturePeerSessionId());
    session = apply(session, PeerSessionEvent.firstContactResolved);
    expect(session.state, PeerSessionState.connected);
    expect(session.authenticatedFingerprint, fixtureFingerprint());
    expect(session.peerSessionId, fixturePeerSessionId());
  });

  test('DISCOVERED cannot skip to CONNECTED', () {
    final PeerSession session = discovered();
    expect(
      () => session.applyAuthentication(trustedHandshake()),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(session.state, PeerSessionState.discovered);
    expect(session.peerSessionId, isNull);
  });

  test('CONNECTED without authentication is illegal', () {
    final PeerSession session = apply(
      discovered(),
      PeerSessionEvent.connectRequested,
    );
    expect(
      () => apply(session, PeerSessionEvent.firstContactResolved),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(session.state, PeerSessionState.connecting);
    expect(session.peerSessionId, isNull);
  });

  test('side exits from connecting authenticating verifying', () {
    final PeerSession connecting = apply(
      discovered(),
      PeerSessionEvent.connectRequested,
    );
    expect(
      apply(connecting, PeerSessionEvent.fail).state,
      PeerSessionState.failed,
    );
    expect(
      apply(connecting, PeerSessionEvent.block).state,
      PeerSessionState.blocked,
    );
    expect(
      apply(connecting, PeerSessionEvent.disconnect).state,
      PeerSessionState.disconnected,
    );
    expect(apply(connecting, PeerSessionEvent.fail).peerSessionId, isNull);

    final PeerSession authenticating = toAuthenticating();
    expect(
      apply(authenticating, PeerSessionEvent.fail).state,
      PeerSessionState.failed,
    );

    final PeerSession verifying = authenticating.applyAuthentication(
      firstContactHandshake(),
    );
    expect(
      apply(verifying, PeerSessionEvent.block).state,
      PeerSessionState.blocked,
    );
  });

  test('reconnect with the same fingerprint is allowed', () {
    PeerSession session = toAuthenticating().applyAuthentication(
      trustedHandshake(),
    );
    session = session.apply(
      PeerSessionEvent.transportLost,
      authority: TransitionAuthority.transportEvent,
    );
    session = session.apply(
      PeerSessionEvent.pathEstablished,
      authority: TransitionAuthority.transportEvent,
    );
    expect(session.state, PeerSessionState.authenticating);
    expect(session.authenticatedFingerprint, fixtureFingerprint());
    final PeerSession reauthed = session.applyAuthentication(
      trustedHandshake(peerSessionId: fixturePeerSessionIdOther()),
    );
    expect(reauthed.state, PeerSessionState.connected);
    expect(reauthed.authenticatedFingerprint, fixtureFingerprint());
    expect(reauthed.peerSessionId, fixturePeerSessionIdOther());
  });

  test('reconnect fingerprint mismatch fails without mutation', () {
    PeerSession session = toAuthenticating().applyAuthentication(
      trustedHandshake(),
    );
    session = session
        .apply(
          PeerSessionEvent.transportLost,
          authority: TransitionAuthority.transportEvent,
        )
        .apply(
          PeerSessionEvent.pathEstablished,
          authority: TransitionAuthority.transportEvent,
        );
    expect(
      () => session.applyAuthentication(
        trustedHandshake(fingerprint: fixtureFingerprintOther()),
      ),
      throwsA(isA<PeerIdentityMismatch>()),
    );
    expect(session.state, PeerSessionState.authenticating);
    expect(session.authenticatedFingerprint, fixtureFingerprint());
    expect(session.peerSessionId, fixturePeerSessionId());
  });

  test('terminal sessions cannot be resurrected', () {
    final PeerSession failed = apply(
      apply(discovered(), PeerSessionEvent.connectRequested),
      PeerSessionEvent.fail,
    );
    expect(failed.isTerminal, isTrue);
    expect(
      () => apply(failed, PeerSessionEvent.connectRequested),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(failed.state, PeerSessionState.failed);
  });
}
