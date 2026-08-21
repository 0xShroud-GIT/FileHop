import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('WebShareSession', () {
    WebShareSession stopped() =>
        WebShareSession.stopped(webShareSessionId: idA());

    WebShareSession apply(WebShareSession session, WebShareSessionEvent event) {
      return session.apply(event, authority: TransitionAuthority.localCommand);
    }

    test('start active client stop lifecycle', () {
      WebShareSession session = apply(stopped(), WebShareSessionEvent.start);
      expect(session.state, WebShareSessionState.starting);
      session = apply(session, WebShareSessionEvent.becameActive);
      expect(session.state, WebShareSessionState.active);
      session = apply(session, WebShareSessionEvent.clientConnected);
      expect(session.state, WebShareSessionState.clientConnected);
      session = apply(session, WebShareSessionEvent.clientConnected);
      expect(session.state, WebShareSessionState.clientConnected);
      session = apply(session, WebShareSessionEvent.lastClientDisconnected);
      expect(session.state, WebShareSessionState.active);
      session = apply(session, WebShareSessionEvent.stop);
      expect(session.state, WebShareSessionState.stopping);
      session = apply(session, WebShareSessionEvent.stopped);
      expect(session.state, WebShareSessionState.stopped);
      expect(
        apply(session, WebShareSessionEvent.stop).state,
        WebShareSessionState.stopped,
      );
    });

    test('restart resolves to STOPPED from every live state', () {
      WebShareSession session = apply(stopped(), WebShareSessionEvent.start);
      for (final WebShareSessionState _ in WebShareSessionState.values) {
        final WebShareSession recovered = session.apply(
          WebShareSessionEvent.processInterrupted,
          authority: TransitionAuthority.recovery,
        );
        expect(recovered.state, WebShareSessionState.stopped);
        session = apply(recovered, WebShareSessionEvent.start);
        if (session.state == WebShareSessionState.starting) {
          session = apply(session, WebShareSessionEvent.becameActive);
        }
        if (session.state == WebShareSessionState.active) {
          session = apply(session, WebShareSessionEvent.clientConnected);
        }
        if (session.state == WebShareSessionState.clientConnected) {
          session = apply(session, WebShareSessionEvent.stop);
        }
      }
    });
  });

  group('TransportCandidate', () {
    TransportCandidate observed() {
      return TransportCandidate.observed(
        candidateId: 'lan-1',
        kind: TransportKind.lan,
        locatorHint: '192.0.2.10',
      );
    }

    TransportCandidate apply(
      TransportCandidate candidate,
      TransportCandidateEvent event,
    ) {
      return candidate.apply(
        event,
        authority: TransitionAuthority.transportEvent,
      );
    }

    test('legal master transitions', () {
      TransportCandidate candidate = apply(
        observed(),
        TransportCandidateEvent.becomeAvailable,
      );
      expect(candidate.state, TransportCandidateState.available);
      expect(
        apply(candidate, TransportCandidateEvent.unavailable).state,
        TransportCandidateState.unavailable,
      );
      candidate = apply(candidate, TransportCandidateEvent.startConnect);
      expect(candidate.state, TransportCandidateState.connecting);
      expect(
        apply(candidate, TransportCandidateEvent.connected).state,
        TransportCandidateState.connected,
      );
      expect(
        apply(candidate, TransportCandidateEvent.fail).state,
        TransportCandidateState.failed,
      );
      expect(
        apply(candidate, TransportCandidateEvent.lost).state,
        TransportCandidateState.lost,
      );
    });

    test('OBSERVED cannot skip to CONNECTED', () {
      final TransportCandidate candidate = observed();
      expect(
        () => apply(candidate, TransportCandidateEvent.connected),
        throwsA(isA<InvalidStateTransition>()),
      );
      expect(candidate.state, TransportCandidateState.observed);
    });

    test('locator hint is not identity', () {
      final TransportCandidate candidate = observed();
      expect(candidate.locatorHint, '192.0.2.10');
      expect(candidate.locatorHint, isNot(fixtureFingerprint().value));
      expect(candidate.kind, TransportKind.lan);
    });
  });
}
