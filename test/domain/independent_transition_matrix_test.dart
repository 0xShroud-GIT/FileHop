import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  group('independent expected matrices', () {
    test('PeerSession', () {
      final PeerSession discovered = PeerSession.discovered(
        displayName: fixtureName(),
      );
      final PeerSession connecting = discovered.apply(
        PeerSessionEvent.connectRequested,
        authority: TransitionAuthority.localCommand,
      );
      final PeerSession authenticating = connecting.apply(
        PeerSessionEvent.pathEstablished,
        authority: TransitionAuthority.transportEvent,
      );
      final PeerSession verifying = authenticating.applyAuthentication(
        firstContactHandshake(),
      );
      final PeerSession connected = authenticating.applyAuthentication(
        trustedHandshake(),
      );
      final PeerSession reconnecting = connected.apply(
        PeerSessionEvent.transportLost,
        authority: TransitionAuthority.transportEvent,
      );
      final PeerSession disconnected = connecting.apply(
        PeerSessionEvent.disconnect,
        authority: TransitionAuthority.localCommand,
      );
      final PeerSession blocked = connecting.apply(
        PeerSessionEvent.block,
        authority: TransitionAuthority.localCommand,
      );
      final PeerSession failed = connecting.apply(
        PeerSessionEvent.fail,
        authority: TransitionAuthority.localCommand,
      );

      expectIndependentMatrix<PeerSessionState, PeerSessionEvent, PeerSession>(
        specimens: <PeerSessionState, PeerSession>{
          PeerSessionState.discovered: discovered,
          PeerSessionState.connecting: connecting,
          PeerSessionState.authenticating: authenticating,
          PeerSessionState.verifyingFirstContact: verifying,
          PeerSessionState.connected: connected,
          PeerSessionState.reconnecting: reconnecting,
          PeerSessionState.disconnected: disconnected,
          PeerSessionState.blocked: blocked,
          PeerSessionState.failed: failed,
        },
        expected: _peerSessionExpected,
        states: PeerSessionState.values,
        events: PeerSessionEvent.values,
        apply: _applyPeerSession,
        stateOf: (PeerSession session) => session.state,
      );
    });

    test('Trust', () {
      final TrustRecord none = TrustRecord.none(fixtureFingerprint());
      final TrustRecord trusted = none.apply(
        TrustEvent.verifyQr,
        authority: TransitionAuthority.localCommand,
      );
      final TrustRecord blocked = none.apply(
        TrustEvent.block,
        authority: TransitionAuthority.localCommand,
      );
      expectIndependentMatrix<TrustState, TrustEvent, TrustRecord>(
        specimens: <TrustState, TrustRecord>{
          TrustState.none: none,
          TrustState.trusted: trusted,
          TrustState.blocked: blocked,
        },
        expected: _trustExpected,
        states: TrustState.values,
        events: TrustEvent.values,
        apply: (TrustRecord record, TrustEvent event) {
          return record.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        },
        stateOf: (TrustRecord record) => record.state,
      );
    });

    test('Transfer', () {
      Transfer walk(List<TransferEvent> events) {
        Transfer current = Transfer.created(
          transferId: idA(),
          shareSessionId: idB(),
          peerFingerprint: fixtureFingerprint(),
          direction: ShareDirection.outgoing,
        );
        for (final TransferEvent event in events) {
          current = current.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        }
        return current;
      }

      expectIndependentMatrix<TransferState, TransferEvent, Transfer>(
        specimens: <TransferState, Transfer>{
          TransferState.created: walk(const <TransferEvent>[]),
          TransferState.offered: walk(const <TransferEvent>[
            TransferEvent.offer,
          ]),
          TransferState.accepted: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.accept,
          ]),
          TransferState.transferring: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.accept,
            TransferEvent.startTransfer,
          ]),
          TransferState.paused: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.accept,
            TransferEvent.startTransfer,
            TransferEvent.pause,
          ]),
          TransferState.verifying: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.accept,
            TransferEvent.startTransfer,
            TransferEvent.beginVerify,
          ]),
          TransferState.recoveryPending: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.accept,
            TransferEvent.startTransfer,
            TransferEvent.processInterrupted,
          ]),
          TransferState.completed: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.accept,
            TransferEvent.startTransfer,
            TransferEvent.beginVerify,
            TransferEvent.verificationSucceeded,
          ]),
          TransferState.rejected: walk(const <TransferEvent>[
            TransferEvent.offer,
            TransferEvent.reject,
          ]),
          TransferState.cancelled: walk(const <TransferEvent>[
            TransferEvent.cancel,
          ]),
          TransferState.failed: walk(const <TransferEvent>[TransferEvent.fail]),
        },
        expected: _transferExpected,
        states: TransferState.values,
        events: TransferEvent.values,
        apply: (Transfer transfer, TransferEvent event) {
          return transfer.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        },
        stateOf: (Transfer transfer) => transfer.state,
      );
    });

    test('TransferItem', () {
      TransferItem walk(List<TransferItemEvent> events) {
        TransferItem current = TransferItem.pending(
          itemId: idC(),
          transferId: idA(),
          kind: TransferItemKind.file,
          name: 'notes.txt',
        );
        for (final TransferItemEvent event in events) {
          current = current.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        }
        return current;
      }

      expectIndependentMatrix<
        TransferItemState,
        TransferItemEvent,
        TransferItem
      >(
        specimens: <TransferItemState, TransferItem>{
          TransferItemState.pending: walk(const <TransferItemEvent>[]),
          TransferItemState.ready: walk(const <TransferItemEvent>[
            TransferItemEvent.markReady,
          ]),
          TransferItemState.transferring: walk(const <TransferItemEvent>[
            TransferItemEvent.markReady,
            TransferItemEvent.startTransfer,
          ]),
          TransferItemState.paused: walk(const <TransferItemEvent>[
            TransferItemEvent.markReady,
            TransferItemEvent.startTransfer,
            TransferItemEvent.pause,
          ]),
          TransferItemState.verifying: walk(const <TransferItemEvent>[
            TransferItemEvent.markReady,
            TransferItemEvent.startTransfer,
            TransferItemEvent.beginVerify,
          ]),
          TransferItemState.completed: walk(const <TransferItemEvent>[
            TransferItemEvent.markReady,
            TransferItemEvent.startTransfer,
            TransferItemEvent.beginVerify,
            TransferItemEvent.verificationSucceeded,
          ]),
          TransferItemState.skipped: walk(const <TransferItemEvent>[
            TransferItemEvent.skip,
          ]),
          TransferItemState.cancelled: walk(const <TransferItemEvent>[
            TransferItemEvent.cancel,
          ]),
          TransferItemState.failed: walk(const <TransferItemEvent>[
            TransferItemEvent.fail,
          ]),
        },
        expected: _transferItemExpected,
        states: TransferItemState.values,
        events: TransferItemEvent.values,
        apply: (TransferItem item, TransferItemEvent event) {
          return item.apply(event, authority: TransitionAuthority.localCommand);
        },
        stateOf: (TransferItem item) => item.state,
      );
    });

    test('ScreenSession', () {
      ScreenSession walk(List<ScreenSessionEvent> events) {
        ScreenSession current = ScreenSession.idle(
          screenSessionId: idA(),
          peerFingerprint: fixtureFingerprint(),
        );
        for (final ScreenSessionEvent event in events) {
          current = current.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        }
        return current;
      }

      expectIndependentMatrix<
        ScreenSessionState,
        ScreenSessionEvent,
        ScreenSession
      >(
        specimens: <ScreenSessionState, ScreenSession>{
          ScreenSessionState.idle: walk(const <ScreenSessionEvent>[]),
          ScreenSessionState.requesting: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
          ]),
          ScreenSessionState.accepted: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
          ]),
          ScreenSessionState.awaitingOsConsent: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
          ]),
          ScreenSessionState.captureStarting: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
            ScreenSessionEvent.captureStarting,
          ]),
          ScreenSessionState.negotiating: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
            ScreenSessionEvent.captureStarting,
            ScreenSessionEvent.negotiate,
          ]),
          ScreenSessionState.connected: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
            ScreenSessionEvent.captureStarting,
            ScreenSessionEvent.negotiate,
            ScreenSessionEvent.mediaConnected,
          ]),
          ScreenSessionState.firstFrame: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
            ScreenSessionEvent.captureStarting,
            ScreenSessionEvent.negotiate,
            ScreenSessionEvent.mediaConnected,
            ScreenSessionEvent.firstFrameRendered,
          ]),
          ScreenSessionState.live: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
            ScreenSessionEvent.captureStarting,
            ScreenSessionEvent.negotiate,
            ScreenSessionEvent.mediaConnected,
            ScreenSessionEvent.firstFrameRendered,
            ScreenSessionEvent.becomeLive,
          ]),
          ScreenSessionState.stopping: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.accept,
            ScreenSessionEvent.awaitOsConsent,
            ScreenSessionEvent.captureStarting,
            ScreenSessionEvent.negotiate,
            ScreenSessionEvent.mediaConnected,
            ScreenSessionEvent.firstFrameRendered,
            ScreenSessionEvent.becomeLive,
            ScreenSessionEvent.stop,
          ]),
          ScreenSessionState.closed: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.close,
          ]),
          ScreenSessionState.rejected: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.reject,
          ]),
          ScreenSessionState.cancelled: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.cancel,
          ]),
          ScreenSessionState.failed: walk(const <ScreenSessionEvent>[
            ScreenSessionEvent.request,
            ScreenSessionEvent.fail,
          ]),
        },
        expected: _screenExpected,
        states: ScreenSessionState.values,
        events: ScreenSessionEvent.values,
        apply: (ScreenSession session, ScreenSessionEvent event) {
          return session.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        },
        stateOf: (ScreenSession session) => session.state,
      );
    });

    test('WebShareSession', () {
      WebShareSession walk(List<WebShareSessionEvent> events) {
        WebShareSession current = WebShareSession.stopped(
          webShareSessionId: idA(),
        );
        for (final WebShareSessionEvent event in events) {
          current = current.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        }
        return current;
      }

      expectIndependentMatrix<
        WebShareSessionState,
        WebShareSessionEvent,
        WebShareSession
      >(
        specimens: <WebShareSessionState, WebShareSession>{
          WebShareSessionState.stopped: walk(const <WebShareSessionEvent>[]),
          WebShareSessionState.starting: walk(const <WebShareSessionEvent>[
            WebShareSessionEvent.start,
          ]),
          WebShareSessionState.active: walk(const <WebShareSessionEvent>[
            WebShareSessionEvent.start,
            WebShareSessionEvent.becameActive,
          ]),
          WebShareSessionState.clientConnected: walk(
            const <WebShareSessionEvent>[
              WebShareSessionEvent.start,
              WebShareSessionEvent.becameActive,
              WebShareSessionEvent.clientConnected,
            ],
          ),
          WebShareSessionState.stopping: walk(const <WebShareSessionEvent>[
            WebShareSessionEvent.start,
            WebShareSessionEvent.stop,
          ]),
        },
        expected: _webShareExpected,
        states: WebShareSessionState.values,
        events: WebShareSessionEvent.values,
        apply: (WebShareSession session, WebShareSessionEvent event) {
          return session.apply(
            event,
            authority: TransitionAuthority.localCommand,
          );
        },
        stateOf: (WebShareSession session) => session.state,
      );
    });

    test('TransportCandidate', () {
      TransportCandidate walk(List<TransportCandidateEvent> events) {
        TransportCandidate current = TransportCandidate.observed(
          candidateId: 'lan-1',
          kind: TransportKind.lan,
        );
        for (final TransportCandidateEvent event in events) {
          current = current.apply(
            event,
            authority: TransitionAuthority.transportEvent,
          );
        }
        return current;
      }

      expectIndependentMatrix<
        TransportCandidateState,
        TransportCandidateEvent,
        TransportCandidate
      >(
        specimens: <TransportCandidateState, TransportCandidate>{
          TransportCandidateState.observed: walk(
            const <TransportCandidateEvent>[],
          ),
          TransportCandidateState.available: walk(
            const <TransportCandidateEvent>[
              TransportCandidateEvent.becomeAvailable,
            ],
          ),
          TransportCandidateState.connecting: walk(
            const <TransportCandidateEvent>[
              TransportCandidateEvent.becomeAvailable,
              TransportCandidateEvent.startConnect,
            ],
          ),
          TransportCandidateState.connected: walk(
            const <TransportCandidateEvent>[
              TransportCandidateEvent.becomeAvailable,
              TransportCandidateEvent.startConnect,
              TransportCandidateEvent.connected,
            ],
          ),
          TransportCandidateState.unavailable: walk(
            const <TransportCandidateEvent>[
              TransportCandidateEvent.becomeAvailable,
              TransportCandidateEvent.unavailable,
            ],
          ),
          TransportCandidateState.failed: walk(const <TransportCandidateEvent>[
            TransportCandidateEvent.becomeAvailable,
            TransportCandidateEvent.startConnect,
            TransportCandidateEvent.fail,
          ]),
          TransportCandidateState.lost: walk(const <TransportCandidateEvent>[
            TransportCandidateEvent.becomeAvailable,
            TransportCandidateEvent.startConnect,
            TransportCandidateEvent.lost,
          ]),
        },
        expected: _transportExpected,
        states: TransportCandidateState.values,
        events: TransportCandidateEvent.values,
        apply: (TransportCandidate candidate, TransportCandidateEvent event) {
          return candidate.apply(
            event,
            authority: TransitionAuthority.transportEvent,
          );
        },
        stateOf: (TransportCandidate candidate) => candidate.state,
      );
    });
  });
}

PeerSession _applyPeerSession(PeerSession session, PeerSessionEvent event) {
  switch (event) {
    case PeerSessionEvent.handshakeAuthenticatedTrusted:
      return session.applyAuthentication(trustedHandshake());
    case PeerSessionEvent.handshakeAuthenticatedFirstContact:
      return session.applyAuthentication(firstContactHandshake());
    case PeerSessionEvent.pathEstablished:
    case PeerSessionEvent.transportLost:
      return session.apply(
        event,
        authority: TransitionAuthority.transportEvent,
      );
    case PeerSessionEvent.connectRequested:
    case PeerSessionEvent.firstContactResolved:
    case PeerSessionEvent.disconnect:
    case PeerSessionEvent.fail:
    case PeerSessionEvent.block:
      return session.apply(event, authority: TransitionAuthority.localCommand);
  }
}

const Map<PeerSessionState, Map<PeerSessionEvent, PeerSessionState>>
_peerSessionExpected =
    <PeerSessionState, Map<PeerSessionEvent, PeerSessionState>>{
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
      PeerSessionState.verifyingFirstContact:
          <PeerSessionEvent, PeerSessionState>{
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
    };

const Map<TrustState, Map<TrustEvent, TrustState>> _trustExpected =
    <TrustState, Map<TrustEvent, TrustState>>{
      TrustState.none: <TrustEvent, TrustState>{
        TrustEvent.verifyQr: TrustState.trusted,
        TrustEvent.verifySas: TrustState.trusted,
        TrustEvent.block: TrustState.blocked,
        TrustEvent.forget: TrustState.none,
      },
      TrustState.trusted: <TrustEvent, TrustState>{
        TrustEvent.forget: TrustState.none,
        TrustEvent.block: TrustState.blocked,
      },
      TrustState.blocked: <TrustEvent, TrustState>{
        TrustEvent.unblock: TrustState.none,
        TrustEvent.block: TrustState.blocked,
      },
    };

const Map<TransferState, Map<TransferEvent, TransferState>> _transferExpected =
    <TransferState, Map<TransferEvent, TransferState>>{
      TransferState.created: <TransferEvent, TransferState>{
        TransferEvent.offer: TransferState.offered,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
      },
      TransferState.offered: <TransferEvent, TransferState>{
        TransferEvent.accept: TransferState.accepted,
        TransferEvent.reject: TransferState.rejected,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
      },
      TransferState.accepted: <TransferEvent, TransferState>{
        TransferEvent.startTransfer: TransferState.transferring,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
      },
      TransferState.transferring: <TransferEvent, TransferState>{
        TransferEvent.pause: TransferState.paused,
        TransferEvent.beginVerify: TransferState.verifying,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
        TransferEvent.processInterrupted: TransferState.recoveryPending,
      },
      TransferState.paused: <TransferEvent, TransferState>{
        TransferEvent.resume: TransferState.transferring,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
        TransferEvent.processInterrupted: TransferState.recoveryPending,
      },
      TransferState.verifying: <TransferEvent, TransferState>{
        TransferEvent.verificationSucceeded: TransferState.completed,
        TransferEvent.verificationFailed: TransferState.failed,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
        TransferEvent.processInterrupted: TransferState.recoveryPending,
      },
      TransferState.recoveryPending: <TransferEvent, TransferState>{
        TransferEvent.checkpointResumable: TransferState.paused,
        TransferEvent.checkpointInvalid: TransferState.failed,
        TransferEvent.cancel: TransferState.cancelled,
        TransferEvent.fail: TransferState.failed,
      },
    };

const Map<TransferItemState, Map<TransferItemEvent, TransferItemState>>
_transferItemExpected =
    <TransferItemState, Map<TransferItemEvent, TransferItemState>>{
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
    };

const Map<ScreenSessionEvent, ScreenSessionState> _screenPreLiveExits =
    <ScreenSessionEvent, ScreenSessionState>{
      ScreenSessionEvent.reject: ScreenSessionState.rejected,
      ScreenSessionEvent.cancel: ScreenSessionState.cancelled,
      ScreenSessionEvent.fail: ScreenSessionState.failed,
      ScreenSessionEvent.close: ScreenSessionState.closed,
      ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
    };

final Map<ScreenSessionState, Map<ScreenSessionEvent, ScreenSessionState>>
_screenExpected =
    <ScreenSessionState, Map<ScreenSessionEvent, ScreenSessionState>>{
      ScreenSessionState.idle: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.request: ScreenSessionState.requesting,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.idle,
      },
      ScreenSessionState.requesting: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.accept: ScreenSessionState.accepted,
        ..._screenPreLiveExits,
      },
      ScreenSessionState.accepted: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.awaitOsConsent: ScreenSessionState.awaitingOsConsent,
        ..._screenPreLiveExits,
      },
      ScreenSessionState
          .awaitingOsConsent: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.captureStarting: ScreenSessionState.captureStarting,
        ..._screenPreLiveExits,
      },
      ScreenSessionState.captureStarting:
          <ScreenSessionEvent, ScreenSessionState>{
            ScreenSessionEvent.negotiate: ScreenSessionState.negotiating,
            ..._screenPreLiveExits,
          },
      ScreenSessionState.negotiating: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.mediaConnected: ScreenSessionState.connected,
        ..._screenPreLiveExits,
      },
      ScreenSessionState.connected: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.firstFrameRendered: ScreenSessionState.firstFrame,
        ..._screenPreLiveExits,
      },
      ScreenSessionState.firstFrame: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.becomeLive: ScreenSessionState.live,
        ..._screenPreLiveExits,
      },
      ScreenSessionState.live: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.stop: ScreenSessionState.stopping,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
      },
      ScreenSessionState.stopping: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.close: ScreenSessionState.closed,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
      },
      ScreenSessionState.closed: <ScreenSessionEvent, ScreenSessionState>{
        ScreenSessionEvent.close: ScreenSessionState.closed,
        ScreenSessionEvent.stop: ScreenSessionState.closed,
        ScreenSessionEvent.processInterrupted: ScreenSessionState.closed,
      },
    };

const Map<WebShareSessionState, Map<WebShareSessionEvent, WebShareSessionState>>
_webShareExpected =
    <WebShareSessionState, Map<WebShareSessionEvent, WebShareSessionState>>{
      WebShareSessionState
          .stopped: <WebShareSessionEvent, WebShareSessionState>{
        WebShareSessionEvent.start: WebShareSessionState.starting,
        WebShareSessionEvent.stop: WebShareSessionState.stopped,
        WebShareSessionEvent.stopped: WebShareSessionState.stopped,
        WebShareSessionEvent.processInterrupted: WebShareSessionState.stopped,
      },
      WebShareSessionState
          .starting: <WebShareSessionEvent, WebShareSessionState>{
        WebShareSessionEvent.becameActive: WebShareSessionState.active,
        WebShareSessionEvent.stop: WebShareSessionState.stopping,
        WebShareSessionEvent.processInterrupted: WebShareSessionState.stopped,
      },
      WebShareSessionState.active: <WebShareSessionEvent, WebShareSessionState>{
        WebShareSessionEvent.clientConnected:
            WebShareSessionState.clientConnected,
        WebShareSessionEvent.stop: WebShareSessionState.stopping,
        WebShareSessionEvent.processInterrupted: WebShareSessionState.stopped,
      },
      WebShareSessionState
          .clientConnected: <WebShareSessionEvent, WebShareSessionState>{
        WebShareSessionEvent.clientConnected:
            WebShareSessionState.clientConnected,
        WebShareSessionEvent.lastClientDisconnected:
            WebShareSessionState.active,
        WebShareSessionEvent.stop: WebShareSessionState.stopping,
        WebShareSessionEvent.processInterrupted: WebShareSessionState.stopped,
      },
      WebShareSessionState
          .stopping: <WebShareSessionEvent, WebShareSessionState>{
        WebShareSessionEvent.stopped: WebShareSessionState.stopped,
        WebShareSessionEvent.processInterrupted: WebShareSessionState.stopped,
      },
    };

const Map<
  TransportCandidateState,
  Map<TransportCandidateEvent, TransportCandidateState>
>
_transportExpected =
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
      TransportCandidateState
          .connecting: <TransportCandidateEvent, TransportCandidateState>{
        TransportCandidateEvent.connected: TransportCandidateState.connected,
        TransportCandidateEvent.fail: TransportCandidateState.failed,
        TransportCandidateEvent.lost: TransportCandidateState.lost,
      },
      TransportCandidateState.connected:
          <TransportCandidateEvent, TransportCandidateState>{
            TransportCandidateEvent.fail: TransportCandidateState.failed,
            TransportCandidateEvent.lost: TransportCandidateState.lost,
          },
    };
