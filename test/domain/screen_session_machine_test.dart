import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  ScreenSession idle() {
    return ScreenSession.idle(
      screenSessionId: idA(),
      peerFingerprint: fixtureFingerprint(),
    );
  }

  ScreenSession apply(ScreenSession session, ScreenSessionEvent event) {
    return session.apply(event, authority: TransitionAuthority.localCommand);
  }

  ScreenSession walkTo(ScreenSessionEvent last) {
    final List<ScreenSessionEvent> path = <ScreenSessionEvent>[
      ScreenSessionEvent.request,
      ScreenSessionEvent.accept,
      ScreenSessionEvent.awaitOsConsent,
      ScreenSessionEvent.captureStarting,
      ScreenSessionEvent.negotiate,
      ScreenSessionEvent.mediaConnected,
      ScreenSessionEvent.firstFrameRendered,
      ScreenSessionEvent.becomeLive,
    ];
    ScreenSession current = idle();
    for (final ScreenSessionEvent event in path) {
      current = apply(current, event);
      if (event == last) {
        return current;
      }
    }
    return current;
  }

  test('complete path FIRST_FRAME then LIVE', () {
    final ScreenSession live = walkTo(ScreenSessionEvent.becomeLive);
    expect(live.state, ScreenSessionState.live);
    expect(live.isLive, isTrue);
    expect(live.lastTransition?.from, ScreenSessionState.firstFrame);
  });

  test('LIVE before FIRST_FRAME is impossible', () {
    final ScreenSession connected = walkTo(ScreenSessionEvent.mediaConnected);
    expect(connected.state, ScreenSessionState.connected);
    expect(
      () => apply(connected, ScreenSessionEvent.becomeLive),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(connected.state, ScreenSessionState.connected);
    expect(connected.isLive, isFalse);

    final ScreenSession negotiating = walkTo(ScreenSessionEvent.negotiate);
    expect(
      () => apply(negotiating, ScreenSessionEvent.becomeLive),
      throwsA(isA<InvalidStateTransition>()),
    );
  });

  test('pre-LIVE reject cancel fail close', () {
    final ScreenSession requesting = walkTo(ScreenSessionEvent.request);
    expect(
      apply(requesting, ScreenSessionEvent.reject).state,
      ScreenSessionState.rejected,
    );
    expect(
      apply(requesting, ScreenSessionEvent.cancel).state,
      ScreenSessionState.cancelled,
    );
    expect(
      apply(requesting, ScreenSessionEvent.fail).state,
      ScreenSessionState.failed,
    );
    expect(
      apply(requesting, ScreenSessionEvent.close).state,
      ScreenSessionState.closed,
    );
  });

  test('stop and close after LIVE', () {
    ScreenSession session = walkTo(ScreenSessionEvent.becomeLive);
    session = apply(session, ScreenSessionEvent.stop);
    expect(session.state, ScreenSessionState.stopping);
    session = apply(session, ScreenSessionEvent.close);
    expect(session.state, ScreenSessionState.closed);
    expect(
      apply(session, ScreenSessionEvent.close).state,
      ScreenSessionState.closed,
    );
  });

  test('restart never restores LIVE', () {
    final ScreenSession live = walkTo(ScreenSessionEvent.becomeLive);
    final ScreenSession recovered = live.apply(
      ScreenSessionEvent.processInterrupted,
      authority: TransitionAuthority.recovery,
    );
    expect(recovered.state, ScreenSessionState.closed);
    expect(recovered.isLive, isFalse);
    expect(
      () => apply(recovered, ScreenSessionEvent.becomeLive),
      throwsA(isA<InvalidStateTransition>()),
    );

    for (final ScreenSessionEvent step in <ScreenSessionEvent>[
      ScreenSessionEvent.request,
      ScreenSessionEvent.accept,
      ScreenSessionEvent.mediaConnected,
      ScreenSessionEvent.firstFrameRendered,
    ]) {
      final ScreenSession interrupted = walkTo(step).apply(
        ScreenSessionEvent.processInterrupted,
        authority: TransitionAuthority.recovery,
      );
      expect(interrupted.state, isNot(ScreenSessionState.live));
      expect(interrupted.state, ScreenSessionState.closed);
    }
  });
}
