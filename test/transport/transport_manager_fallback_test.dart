import 'dart:async';

import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeTransportAdapter aware;
  late FakeTransportAdapter direct;
  late FakeTransportAdapter lan;
  late TransportManager manager;
  late List<String> trace;

  setUp(() async {
    trace = <String>[];
    aware = FakeTransportAdapter(
      kind: TransportKind.wifiAware,
      availability: TransportAvailability.supportedAvailable,
      sharedTrace: trace,
    );
    direct = FakeTransportAdapter(
      kind: TransportKind.wifiDirect,
      availability: TransportAvailability.supportedAvailable,
      sharedTrace: trace,
    );
    lan = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
      sharedTrace: trace,
    );
    manager = TransportManager();
    await manager.registerAdapter(aware);
    await manager.registerAdapter(direct);
    await manager.registerAdapter(lan);
  });

  tearDown(() async {
    await manager.close();
    await aware.close();
    await direct.close();
    await lan.close();
  });

  Future<void> discoverAll() async {
    aware.emitCandidate(candidateId: 'a1', displayLabel: 'Phone');
    direct.emitCandidate(candidateId: 'd1', displayLabel: 'Phone');
    lan.emitCandidate(candidateId: 'l1', displayLabel: 'Phone');
    await _flush();
  }

  TransportAcquireRequest androidToAndroid() {
    return const TransportAcquireRequest(
      localPlatform: TransportPlatform.android,
      remotePlatform: TransportPlatform.android,
    );
  }

  test('Aware → Direct: cleanup completes before Direct.connect', () async {
    aware.failConnect = true;
    await discoverAll();
    final SelectedTransportPath path = await manager.acquire(
      androidToAndroid(),
    );
    expect(path.kind, TransportKind.wifiDirect);
    expect(lan.operations.where((String s) => s.contains('connect')), isEmpty);
    expect(trace, contains('wifiAware.connect.start'));
    expect(trace, contains('wifiAware.connect.fail'));
    expect(trace, contains('wifiAware.cleanup.complete'));
    expect(trace, contains('wifiDirect.connect.start'));
    expect(
      trace.indexOf('wifiAware.cleanup.complete'),
      lessThan(trace.indexOf('wifiDirect.connect.start')),
    );
  });

  test('Aware → Direct → LAN cleanup ordering', () async {
    aware.failConnect = true;
    direct.failConnect = true;
    await discoverAll();
    final SelectedTransportPath path = await manager.acquire(
      androidToAndroid(),
    );
    expect(path.kind, TransportKind.lan);
    expect(
      trace.indexOf('wifiAware.cleanup.complete'),
      lessThan(trace.indexOf('wifiDirect.connect.start')),
    );
    expect(
      trace.indexOf('wifiDirect.cleanup.complete'),
      lessThan(trace.indexOf('lan.connect.start')),
    );
  });

  test('success stops fallback', () async {
    await discoverAll();
    final SelectedTransportPath path = await manager.acquire(
      androidToAndroid(),
    );
    expect(path.kind, TransportKind.wifiAware);
    expect(direct.operations, isEmpty);
    expect(lan.operations, isEmpty);
  });

  test('all attempts fail with bounded error', () async {
    aware.failConnect = true;
    direct.failConnect = true;
    lan.failConnect = true;
    await discoverAll();
    await expectLater(
      manager.acquire(androidToAndroid()),
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.connectionFailed,
        ),
      ),
    );
  });

  test('connect attempts are serialized', () async {
    aware.connectBarrier = Completer<void>();
    await discoverAll();
    final Future<SelectedTransportPath> pending = manager.acquire(
      androidToAndroid(),
    );
    await _flush();
    expect(aware.operations, contains('wifiAware.connect.start'));
    expect(direct.operations, isEmpty);
    expect(aware.connectInFlight, 1);
    expect(direct.connectInFlight, 0);
    expect(aware.maxConnectInFlight, 1);
    aware.connectBarrier!.complete();
    final SelectedTransportPath path = await pending;
    expect(path.kind, TransportKind.wifiAware);
    expect(aware.maxConnectInFlight, 1);
    expect(direct.maxConnectInFlight, 0);
  });

  test('healthy current path is sticky in the manager', () async {
    lan.emitCandidate(candidateId: 'l1');
    await _flush();
    aware.setAvailability(TransportAvailability.supportedUnavailable);
    direct.setAvailability(TransportAvailability.supportedUnavailable);
    await _flush();
    final SelectedTransportPath first = await manager.acquire(
      androidToAndroid(),
    );
    expect(first.kind, TransportKind.lan);
    final int disconnects = lan.operations
        .where((String s) => s == 'lan.cleanup.complete')
        .length;
    aware.setAvailability(TransportAvailability.supportedAvailable);
    aware.emitCandidate(candidateId: 'a1');
    await _flush();
    final TransportSelection reconciled = manager.reconcile(androidToAndroid());
    expect(reconciled, isA<TransportRetainCurrent>());
    final SelectedTransportPath again = await manager.acquire(
      androidToAndroid(),
    );
    expect(again.kind, TransportKind.lan);
    expect(
      aware.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
    expect(
      lan.operations.where((String s) => s == 'lan.cleanup.complete').length,
      disconnects,
    );
  });

  test('Aware loss falls back to Direct, not LAN', () async {
    await discoverAll();
    final SelectedTransportPath first = await manager.acquire(
      androidToAndroid(),
    );
    expect(first.kind, TransportKind.wifiAware);
    aware.setAvailability(TransportAvailability.supportedUnavailable);
    await _flush();
    expect(manager.currentPath!.healthy, isFalse);
    final SelectedTransportPath next = await manager.recoverAfterLoss(
      androidToAndroid(),
    );
    expect(next.kind, TransportKind.wifiDirect);
    expect(lan.operations.where((String s) => s.contains('connect')), isEmpty);
  });

  test('Direct loss falls back to LAN', () async {
    aware.setAvailability(TransportAvailability.unsupported);
    await _flush();
    direct.emitCandidate(candidateId: 'd1');
    lan.emitCandidate(candidateId: 'l1');
    await _flush();
    final SelectedTransportPath first = await manager.acquire(
      androidToAndroid(),
    );
    expect(first.kind, TransportKind.wifiDirect);
    direct.setAvailability(TransportAvailability.supportedUnavailable);
    await _flush();
    final SelectedTransportPath next = await manager.recoverAfterLoss(
      androidToAndroid(),
    );
    expect(next.kind, TransportKind.lan);
  });

  test('cancellation prevents later fallback', () async {
    aware.connectBarrier = Completer<void>();
    aware.failConnect = true;
    await discoverAll();
    final TransportAcquisitionToken token = TransportAcquisitionToken();
    final Future<SelectedTransportPath> pending = manager.acquire(
      TransportAcquireRequest(
        localPlatform: TransportPlatform.android,
        remotePlatform: TransportPlatform.android,
        token: token,
      ),
    );
    await _flush();
    token.cancel();
    aware.connectBarrier!.complete();
    await expectLater(
      pending,
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.cancelled,
        ),
      ),
    );
    expect(direct.operations, isEmpty);
    expect(lan.operations, isEmpty);
  });

  test('adapter availability loss makes candidate non-selectable', () async {
    aware.emitCandidate(candidateId: 'a1');
    await _flush();
    aware.setAvailability(TransportAvailability.supportedUnavailable);
    lan.emitCandidate(candidateId: 'l1');
    await _flush();
    final TransportSelection selection = manager.reconcile(androidToAndroid());
    expect((selection as TransportSelected).chosen.kind, TransportKind.lan);
  });

  test('lost candidate is not attempted', () async {
    await discoverAll();
    aware.emitLost('a1');
    await _flush();
    final SelectedTransportPath path = await manager.acquire(
      androidToAndroid(),
    );
    expect(path.kind, TransportKind.wifiDirect);
    expect(
      aware.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
  });

  test('transport result contains no peer identity fields', () async {
    await discoverAll();
    final SelectedTransportPath path = await manager.acquire(
      androidToAndroid(),
    );
    expect(path.toString(), isNot(contains('fingerprint')));
    expect(path.toString(), isNot(contains('PeerSession')));
    expect(path.key.runtimeType.toString(), isNot(contains('Fingerprint')));
  });
}
