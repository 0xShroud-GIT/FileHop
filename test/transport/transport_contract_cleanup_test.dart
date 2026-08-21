import 'dart:async';

import 'package:filehop/domain/state_machine/transition_authority.dart';
import 'package:filehop/domain/transport/transport_candidate.dart';
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
    aware.emitCandidate(candidateId: 'a1');
    direct.emitCandidate(candidateId: 'd1');
    lan.emitCandidate(candidateId: 'l1');
    await _flush();
  }

  const TransportAcquireRequest androidReq = TransportAcquireRequest(
    localPlatform: TransportPlatform.android,
    remotePlatform: TransportPlatform.android,
  );

  test(
    'manager rejects wrong-source candidate event without mutation',
    () async {
      lan.emitCandidate(candidateId: 'keep');
      await _flush();
      final int lanCount = manager.candidates.ofKind(TransportKind.lan).length;
      final int awareCount = manager.candidates
          .ofKind(TransportKind.wifiAware)
          .length;
      lan.emit(
        const AdapterCandidateFound(
          kind: TransportKind.wifiAware,
          candidateId: 'forged',
        ),
      );
      await _flush();
      expect(
        manager.lastContractError?.kind,
        TransportFailureKind.adapterContractViolation,
      );
      expect(manager.candidates.ofKind(TransportKind.lan), hasLength(lanCount));
      expect(
        manager.candidates.ofKind(TransportKind.wifiAware),
        hasLength(awareCount),
      );
      expect(
        manager.candidates[const TransportCandidateKey(
          kind: TransportKind.wifiAware,
          candidateId: 'forged',
        )],
        isNull,
      );
    },
  );

  test(
    'manager rejects wrong-source availability event without mutation',
    () async {
      final TransportAvailability before = manager.capabilities
          .snapshotFor(TransportKind.lan)!
          .availability;
      direct.emit(
        const AdapterAvailabilityChanged(
          kind: TransportKind.lan,
          snapshot: TransportCapabilitySnapshot(
            kind: TransportKind.lan,
            availability: TransportAvailability.failed,
          ),
        ),
      );
      await _flush();
      expect(
        manager.lastContractError?.kind,
        TransportFailureKind.adapterContractViolation,
      );
      expect(
        manager.capabilities.snapshotFor(TransportKind.lan)!.availability,
        before,
      );
      expect(
        manager.capabilities
            .snapshotFor(TransportKind.wifiDirect)!
            .availability,
        TransportAvailability.supportedAvailable,
      );
    },
  );

  test('valid same-kind candidate event is still processed', () async {
    lan.emitCandidate(candidateId: 'l-ok', locatorHint: 'hint');
    await _flush();
    expect(
      manager
          .candidates[const TransportCandidateKey(
            kind: TransportKind.lan,
            candidateId: 'l-ok',
          )]
          ?.candidate
          .state,
      TransportCandidateState.available,
    );
  });

  test('duplicate found preserves AVAILABLE CONNECTING CONNECTED', () async {
    lan.emitCandidate(candidateId: 'l1', locatorHint: 'a');
    await _flush();
    final TransportCandidateKey key = const TransportCandidateKey(
      kind: TransportKind.lan,
      candidateId: 'l1',
    );
    lan.emitCandidate(candidateId: 'l1', locatorHint: 'b');
    await _flush();
    expect(
      manager.candidates[key]!.candidate.state,
      TransportCandidateState.available,
    );
    expect(manager.candidates[key]!.candidate.locatorHint, 'b');
    manager.candidates.tryApply(
      key,
      TransportCandidateEvent.startConnect,
      authority: TransitionAuthority.localCommand,
    );
    lan.emitCandidate(candidateId: 'l1', locatorHint: 'c');
    await _flush();
    expect(
      manager.candidates[key]!.candidate.state,
      TransportCandidateState.connecting,
    );
    manager.candidates.tryApply(
      key,
      TransportCandidateEvent.connected,
      authority: TransitionAuthority.transportEvent,
    );
    lan.emitCandidate(candidateId: 'l1', locatorHint: 'd');
    await _flush();
    expect(
      manager.candidates[key]!.candidate.state,
      TransportCandidateState.connected,
    );
    expect(manager.candidates[key]!.candidate.locatorHint, 'd');
  });

  test('cleanup failure stops fallback', () async {
    aware.failEndpoint = true;
    aware.failDisconnect = true;
    await discoverAll();
    await expectLater(
      manager.acquire(androidReq),
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.cleanupFailed,
        ),
      ),
    );
    expect(trace, contains('wifiAware.connect.start'));
    expect(trace, contains('wifiAware.disconnect.start'));
    expect(trace, contains('wifiAware.disconnect.fail'));
    expect(trace, isNot(contains('wifiDirect.connect.start')));
    expect(trace, isNot(contains('lan.connect.start')));
    expect(
      direct.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
    expect(lan.operations.where((String s) => s.contains('connect')), isEmpty);
  });

  test('successful cleanup permits fallback', () async {
    aware.failEndpoint = true;
    await discoverAll();
    final SelectedTransportPath path = await manager.acquire(androidReq);
    expect(path.kind, TransportKind.wifiDirect);
    expect(trace.indexOf('wifiAware.disconnect.success'), greaterThan(-1));
    expect(
      trace.indexOf('wifiAware.disconnect.success'),
      lessThan(trace.indexOf('wifiDirect.connect.start')),
    );
    expect(trace, isNot(contains('lan.connect.start')));
  });

  test('recovery cleanup and reacquire are serialized', () async {
    await discoverAll();
    final SelectedTransportPath first = await manager.acquire(androidReq);
    expect(first.kind, TransportKind.wifiAware);
    aware.setAvailability(TransportAvailability.supportedUnavailable);
    await _flush();
    aware.disconnectBarrier = Completer<void>();
    final Future<SelectedTransportPath> recovery = manager.recoverAfterLoss(
      androidReq,
    );
    await _flush();
    expect(trace, contains('wifiAware.disconnect.start'));
    expect(
      direct.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
    final Future<SelectedTransportPath> second = manager.acquire(androidReq);
    await _flush();
    expect(direct.connectInFlight, 0);
    expect(
      direct.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
    aware.disconnectBarrier!.complete();
    final SelectedTransportPath recovered = await recovery;
    expect(recovered.kind, TransportKind.wifiDirect);
    final SelectedTransportPath retained = await second;
    expect(retained.kind, TransportKind.wifiDirect);
  });

  test('cancel before connect does not start fallback', () async {
    await discoverAll();
    final TransportAcquisitionToken token = TransportAcquisitionToken()
      ..cancel();
    await expectLater(
      manager.acquire(
        TransportAcquireRequest(
          localPlatform: TransportPlatform.android,
          remotePlatform: TransportPlatform.android,
          token: token,
        ),
      ),
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.cancelled,
        ),
      ),
    );
    expect(
      aware.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
    expect(direct.operations, isEmpty);
  });

  test('cancel during connect cannot return success', () async {
    aware.connectBarrier = Completer<void>();
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
    expect(manager.currentPath, isNull);
    expect(direct.operations, isEmpty);
  });

  test('cancel after endpoint cannot return success', () async {
    aware.endpointBarrier = Completer<void>();
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
    expect(trace, contains('wifiAware.endpoint.start'));
    token.cancel();
    aware.endpointBarrier!.complete();
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
    expect(manager.currentPath, isNull);
    final TransportCandidateKey key = const TransportCandidateKey(
      kind: TransportKind.wifiAware,
      candidateId: 'a1',
    );
    expect(
      manager.candidates[key]!.candidate.state,
      isNot(TransportCandidateState.connected),
    );
    expect(trace, contains('wifiAware.disconnect.start'));
    expect(
      direct.operations.where((String s) => s.contains('connect')),
      isEmpty,
    );
  });

  test(
    'cancel during endpoint with cleanup failure is not clean cancelled',
    () async {
      aware.endpointBarrier = Completer<void>();
      aware.failDisconnect = true;
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
      aware.endpointBarrier!.complete();
      await expectLater(
        pending,
        throwsA(
          isA<TransportException>().having(
            (TransportException e) => e.kind,
            'kind',
            TransportFailureKind.cleanupFailed,
          ),
        ),
      );
      expect(manager.currentPath, isNull);
    },
  );

  test('manager close cancels subscriptions and is idempotent', () async {
    lan.emitCandidate(candidateId: 'before');
    await _flush();
    await manager.close();
    await manager.close();
    lan.emitCandidate(candidateId: 'after-close');
    await _flush();
    expect(
      manager.candidates[const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'after-close',
      )],
      isNull,
    );
    expect(
      manager.candidates[const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'before',
      )],
      isNotNull,
    );
  });
}
