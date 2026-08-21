import 'dart:async';

import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('close disconnects the active path before teardown', () async {
    final FakeTransportAdapter lan = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    lan.emitCandidate(candidateId: 'l1');
    await _flush();

    final SelectedTransportPath path = await manager.acquire(
      const TransportAcquireRequest(localPlatform: TransportPlatform.android),
    );
    expect(path.kind, TransportKind.lan);
    expect(manager.currentPath, isNotNull);

    await manager.close();

    expect(lan.disconnectCallCount, 1);
    expect(manager.currentPath, isNull);
    await lan.close();
  });

  test('close waits for an in-flight acquisition then releases it', () async {
    final Completer<void> connectBarrier = Completer<void>();
    final FakeTransportAdapter lan = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    )..connectBarrier = connectBarrier;
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    lan.emitCandidate(candidateId: 'l1');
    await _flush();

    final Future<SelectedTransportPath> acquisition = manager.acquire(
      const TransportAcquireRequest(localPlatform: TransportPlatform.android),
    );
    await _flush();
    expect(lan.connectCallCount, 1);

    bool closeCompleted = false;
    final Future<void> closing = manager.close().then((_) {
      closeCompleted = true;
    });
    await _flush();
    expect(closeCompleted, isFalse);

    connectBarrier.complete();
    final SelectedTransportPath path = await acquisition;
    expect(path.kind, TransportKind.lan);
    await closing;

    expect(closeCompleted, isTrue);
    expect(lan.disconnectCallCount, 1);
    expect(manager.currentPath, isNull);
    await lan.close();
  });

  test('failed active disconnect keeps close retryable and blocks work', () async {
    final FakeTransportAdapter lan = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    )..failDisconnect = true;
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    lan.emitCandidate(candidateId: 'l1');
    await _flush();
    await manager.acquire(
      const TransportAcquireRequest(localPlatform: TransportPlatform.android),
    );

    await expectLater(
      manager.close(),
      throwsA(
        isA<TransportException>().having(
          (TransportException error) => error.kind,
          'kind',
          TransportFailureKind.cleanupFailed,
        ),
      ),
    );
    expect(lan.disconnectCallCount, 1);
    expect(manager.currentPath, isNotNull);

    await expectLater(
      manager.acquire(
        const TransportAcquireRequest(
          localPlatform: TransportPlatform.android,
        ),
      ),
      throwsA(
        isA<TransportException>().having(
          (TransportException error) => error.kind,
          'kind',
          TransportFailureKind.invalidArgument,
        ),
      ),
    );

    lan.failDisconnect = false;
    await manager.close();
    expect(lan.disconnectCallCount, 2);
    expect(manager.currentPath, isNull);
    await lan.close();
  });

  test('new work is rejected after shutdown begins', () async {
    final FakeTransportAdapter lan = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    await manager.close();

    await expectLater(
      manager.acquire(
        const TransportAcquireRequest(
          localPlatform: TransportPlatform.android,
        ),
      ),
      throwsA(
        isA<TransportException>().having(
          (TransportException error) => error.kind,
          'kind',
          TransportFailureKind.invalidArgument,
        ),
      ),
    );

    await lan.close();
  });
}
