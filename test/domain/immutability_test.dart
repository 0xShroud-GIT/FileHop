import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('state-machine configuration is frozen', () {
    test('ScreenSession tables reject add/replace/noop mutation', () {
      final FiniteStateMachine<ScreenSessionState, ScreenSessionEvent> machine =
          ScreenSession.machine;

      expect(
        () => machine.allowed[ScreenSessionState.connected] =
            <ScreenSessionEvent, ScreenSessionState>{
              ScreenSessionEvent.becomeLive: ScreenSessionState.live,
            },
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () =>
            machine.allowed[ScreenSessionState.connected]![ScreenSessionEvent
                    .becomeLive] =
                ScreenSessionState.live,
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => machine.allowed.remove(ScreenSessionState.firstFrame),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => machine.noop.add((
          ScreenSessionState.connected,
          ScreenSessionEvent.becomeLive,
        )),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => machine.noop.remove((
          ScreenSessionState.closed,
          ScreenSessionEvent.close,
        )),
        throwsA(isA<UnsupportedError>()),
      );

      final ScreenSession connected =
          ScreenSession.idle(
                screenSessionId: idA(),
                peerFingerprint: fixtureFingerprint(),
              )
              .apply(
                ScreenSessionEvent.request,
                authority: TransitionAuthority.localCommand,
              )
              .apply(
                ScreenSessionEvent.accept,
                authority: TransitionAuthority.localCommand,
              )
              .apply(
                ScreenSessionEvent.awaitOsConsent,
                authority: TransitionAuthority.localCommand,
              )
              .apply(
                ScreenSessionEvent.captureStarting,
                authority: TransitionAuthority.localCommand,
              )
              .apply(
                ScreenSessionEvent.negotiate,
                authority: TransitionAuthority.localCommand,
              )
              .apply(
                ScreenSessionEvent.mediaConnected,
                authority: TransitionAuthority.localCommand,
              );
      expect(connected.state, ScreenSessionState.connected);
      expect(
        () => connected.apply(
          ScreenSessionEvent.becomeLive,
          authority: TransitionAuthority.localCommand,
        ),
        throwsA(isA<InvalidStateTransition>()),
      );
      expect(connected.state, ScreenSessionState.connected);
      expect(connected.isLive, isFalse);
    });

    test('caller-owned source maps cannot alter a constructed machine', () {
      final Map<TrustState, Map<TrustEvent, TrustState>> allowed =
          <TrustState, Map<TrustEvent, TrustState>>{
            TrustState.none: <TrustEvent, TrustState>{
              TrustEvent.verifyQr: TrustState.trusted,
            },
          };
      final Set<(Object, Object)> noop = <(Object, Object)>{};
      final FiniteStateMachine<TrustState, TrustEvent> machine =
          FiniteStateMachine<TrustState, TrustEvent>(
            machine: 'TrustRecord',
            allowed: allowed,
            noop: noop,
          );
      allowed[TrustState.none]![TrustEvent.block] = TrustState.blocked;
      allowed[TrustState.trusted] = <TrustEvent, TrustState>{
        TrustEvent.forget: TrustState.none,
      };
      noop.add((TrustState.none, TrustEvent.unblock));

      expect(machine.isLegal(TrustState.none, TrustEvent.block), isFalse);
      expect(machine.isLegal(TrustState.trusted, TrustEvent.forget), isFalse);
      expect(machine.isLegal(TrustState.none, TrustEvent.unblock), isFalse);
      expect(
        () => machine.reduce(
          from: TrustState.none,
          event: TrustEvent.block,
          authority: TransitionAuthority.localCommand,
        ),
        throwsA(isA<InvalidStateTransition>()),
      );
    });
  });

  group('domain collections are deeply immutable', () {
    test('Peer.lastCapabilities is isolated from caller lists', () {
      final List<String> input = <String>['share.files'];
      final Peer peer = Peer(
        fingerprint: fixtureFingerprint(),
        lastCapabilities: input,
      );
      input.add('share.folders');
      expect(peer.lastCapabilities, <String>['share.files']);
      expect(
        () => peer.lastCapabilities.add('screen.send'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(peer.lastCapabilities, <String>['share.files']);

      final List<String> next = <String>['share.text'];
      final Peer copied = peer.copyWith(lastCapabilities: next);
      next.add('share.links');
      expect(copied.lastCapabilities, <String>['share.text']);
      expect(peer.lastCapabilities, <String>['share.files']);
    });

    test('ShareSession.itemIds is isolated from caller lists', () {
      final List<LogicalId> input = <LogicalId>[idA()];
      final ShareSession share = ShareSession(
        shareSessionId: idB(),
        transferId: idC(),
        peerFingerprint: fixtureFingerprint(),
        direction: ShareDirection.outgoing,
        itemIds: input,
      );
      input.add(idB());
      expect(share.itemIds, <LogicalId>[idA()]);
      expect(() => share.itemIds.add(idC()), throwsA(isA<UnsupportedError>()));
      expect(share.itemIds, <LogicalId>[idA()]);
    });
  });
}
