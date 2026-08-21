import 'package:filehop/domain/state_machine/transition_authority.dart';
import 'package:filehop/domain/transport/transport_candidate.dart';
import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/native_bridge/channel/native_bridge.dart';
import 'package:filehop/native_bridge/codec/native_codec.dart';
import 'package:filehop/transport/bridge/native_transport_adapter.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('native releaseAttempt', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'NativeTransportAdapter.releaseAttempt does not silently succeed',
      () async {
        final NativeTransportAdapter adapter = NativeTransportAdapter(
          bridge: NativeBridge(
            commands: const MethodChannel('app.filehop.native.commands.rl1'),
          ),
          kind: TransportKind.lan,
        );
        await expectLater(
          adapter.releaseAttempt(
            const TransportCandidateKey(
              kind: TransportKind.lan,
              candidateId: 'l1',
            ),
          ),
          throwsA(
            isA<TransportException>().having(
              (TransportException e) => e.kind,
              'kind',
              TransportFailureKind.attemptCleanupUnavailable,
            ),
          ),
        );
      },
    );

    test('native no-handle cleanup unavailability stops fallback', () async {
      const MethodChannel channel = MethodChannel(
        'app.filehop.native.commands.rl2',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'observeAvailability') {
              return <String, Object?>{
                'bridgeVersion': kNativeBridgeVersion,
                'kind': 'wifiAware',
                'status': 'SUPPORTED_AVAILABLE',
              };
            }
            if (call.method == 'connect') {
              throw PlatformException(
                code: 'operationFailed',
                message: 'no handle',
              );
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final NativeTransportAdapter nativeAware = NativeTransportAdapter(
        bridge: NativeBridge(commands: channel),
        kind: TransportKind.wifiAware,
      );
      final FakeTransportAdapter direct = FakeTransportAdapter(
        kind: TransportKind.wifiDirect,
        availability: TransportAvailability.supportedAvailable,
      );
      final TransportManager manager = TransportManager();
      await manager.registerAdapter(nativeAware);
      await manager.registerAdapter(direct);
      addTearDown(() async {
        await manager.close();
        await direct.close();
      });
      direct.emitCandidate(candidateId: 'd1');
      manager.candidates.recordFound(
        kind: TransportKind.wifiAware,
        candidateId: 'a1',
      );
      await _flush();

      await expectLater(
        manager.acquire(
          const TransportAcquireRequest(
            localPlatform: TransportPlatform.android,
            remotePlatform: TransportPlatform.android,
          ),
        ),
        throwsA(
          isA<TransportException>().having(
            (TransportException e) => e.kind,
            'kind',
            TransportFailureKind.cleanupFailed,
          ),
        ),
      );
      expect(direct.connectCallCount, 0);
    });
  });

  group('fake release ownership', () {
    late FakeTransportAdapter aware;
    late FakeTransportAdapter direct;
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
      manager = TransportManager();
      await manager.registerAdapter(aware);
      await manager.registerAdapter(direct);
    });

    tearDown(() async {
      await manager.close();
      await aware.close();
      await direct.close();
    });

    test(
      'releaseAttempt success after no-handle fail permits fallback',
      () async {
        aware.failConnect = true;
        aware.emitCandidate(candidateId: 'a1');
        direct.emitCandidate(candidateId: 'd1');
        await _flush();
        final SelectedTransportPath path = await manager.acquire(
          const TransportAcquireRequest(
            localPlatform: TransportPlatform.android,
            remotePlatform: TransportPlatform.android,
          ),
        );
        expect(path.kind, TransportKind.wifiDirect);
        expect(trace, contains('wifiAware.connect.failBeforeHandle'));
        expect(trace, contains('wifiAware.releaseAttempt.start'));
        expect(trace, contains('wifiAware.releaseAttempt.success'));
        expect(
          trace.indexOf('wifiAware.releaseAttempt.success'),
          lessThan(trace.indexOf('wifiDirect.connect.start')),
        );
        expect(aware.releaseAttemptCallCount, 1);
        expect(aware.disconnectCallCount, 0);
      },
    );

    test(
      'releaseAttempt failure after no-handle fail stops fallback',
      () async {
        aware.failConnect = true;
        aware.failRelease = true;
        aware.emitCandidate(candidateId: 'a1');
        direct.emitCandidate(candidateId: 'd1');
        await _flush();
        await expectLater(
          manager.acquire(
            const TransportAcquireRequest(
              localPlatform: TransportPlatform.android,
              remotePlatform: TransportPlatform.android,
            ),
          ),
          throwsA(
            isA<TransportException>().having(
              (TransportException e) => e.kind,
              'kind',
              TransportFailureKind.cleanupFailed,
            ),
          ),
        );
        expect(trace, contains('wifiAware.releaseAttempt.fail'));
        expect(trace, isNot(contains('wifiDirect.connect.start')));
        expect(direct.connectCallCount, 0);
      },
    );

    test('endpoint failure uses disconnect not releaseAttempt', () async {
      aware.failEndpoint = true;
      aware.emitCandidate(candidateId: 'a1');
      direct.emitCandidate(candidateId: 'd1');
      await _flush();
      final SelectedTransportPath path = await manager.acquire(
        const TransportAcquireRequest(
          localPlatform: TransportPlatform.android,
          remotePlatform: TransportPlatform.android,
        ),
      );
      expect(path.kind, TransportKind.wifiDirect);
      expect(aware.disconnectCallCount, 1);
      expect(aware.releaseAttemptCallCount, 0);
      expect(trace, contains('wifiAware.disconnect.start'));
      expect(trace, contains('wifiAware.disconnect.success'));
    });
  });

  group('fresh terminal lifecycle', () {
    test('FAILED + candidateFound creates a new generation', () {
      final TransportCandidateRegistry registry = TransportCandidateRegistry();
      registry.recordFound(kind: TransportKind.lan, candidateId: 'l1');
      final TransportCandidateKey key = const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'l1',
      );
      registry.tryApply(
        key,
        TransportCandidateEvent.startConnect,
        authority: TransitionAuthority.localCommand,
      );
      registry.tryApply(
        key,
        TransportCandidateEvent.fail,
        authority: TransitionAuthority.transportEvent,
      );
      final TransportCandidate failedGeneration = registry[key]!.candidate;
      final int oldGeneration = registry[key]!.generation;
      expect(failedGeneration.state, TransportCandidateState.failed);
      registry.recordFound(kind: TransportKind.lan, candidateId: 'l1');
      expect(failedGeneration.state, TransportCandidateState.failed);
      expect(registry[key]!.candidate.state, TransportCandidateState.available);
      expect(registry[key]!.generation, oldGeneration + 1);
      expect(identical(failedGeneration, registry[key]!.candidate), isFalse);
    });

    test('terminal candidateUpdated does not resurrect', () {
      final TransportCandidateRegistry registry = TransportCandidateRegistry();
      registry.recordFound(kind: TransportKind.lan, candidateId: 'l1');
      final TransportCandidateKey key = const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'l1',
      );
      registry.tryApply(
        key,
        TransportCandidateEvent.startConnect,
        authority: TransitionAuthority.localCommand,
      );
      registry.tryApply(
        key,
        TransportCandidateEvent.fail,
        authority: TransitionAuthority.transportEvent,
      );
      registry.recordUpdated(
        kind: TransportKind.lan,
        candidateId: 'l1',
        locatorHint: 'locator-b',
      );
      expect(registry[key]!.candidate.state, TransportCandidateState.failed);
      registry.recordFound(
        kind: TransportKind.lan,
        candidateId: 'l1',
        locatorHint: 'locator-c',
      );
      expect(registry[key]!.candidate.state, TransportCandidateState.available);
    });

    test('LOST then candidateFound is a fresh generation', () {
      final TransportCandidateRegistry registry = TransportCandidateRegistry();
      registry.recordFound(kind: TransportKind.lan, candidateId: 'l1');
      final TransportCandidateKey key = const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'l1',
      );
      registry.recordLost(kind: TransportKind.lan, candidateId: 'l1');
      final TransportCandidate lostGeneration = registry[key]!.candidate;
      expect(lostGeneration.state, TransportCandidateState.unavailable);
      registry.recordFound(kind: TransportKind.lan, candidateId: 'l1');
      expect(lostGeneration.state, TransportCandidateState.unavailable);
      expect(registry[key]!.candidate.state, TransportCandidateState.available);
      expect(identical(lostGeneration, registry[key]!.candidate), isFalse);
    });
  });

  group('retry scope', () {
    late FakeTransportAdapter lan;
    late TransportManager manager;

    setUp(() async {
      lan = FakeTransportAdapter(
        kind: TransportKind.lan,
        availability: TransportAvailability.supportedAvailable,
      );
      manager = TransportManager();
      await manager.registerAdapter(lan);
    });

    tearDown(() async {
      await manager.close();
      await lan.close();
    });

    test('retry after rediscovery can connect again', () async {
      lan.failConnect = true;
      lan.emitCandidate(candidateId: 'l1');
      await _flush();
      await expectLater(
        manager.acquire(
          const TransportAcquireRequest(
            localPlatform: TransportPlatform.android,
          ),
        ),
        throwsA(isA<TransportException>()),
      );
      expect(lan.connectCallCount, 1);
      final TransportCandidate failed = manager
          .candidates[const TransportCandidateKey(
            kind: TransportKind.lan,
            candidateId: 'l1',
          )]!
          .candidate;
      expect(failed.state, TransportCandidateState.failed);

      lan.failConnect = false;
      lan.emitCandidate(candidateId: 'l1');
      await _flush();
      expect(failed.state, TransportCandidateState.failed);
      expect(
        manager
            .candidates[const TransportCandidateKey(
              kind: TransportKind.lan,
              candidateId: 'l1',
            )]!
            .candidate
            .state,
        TransportCandidateState.available,
      );
      final SelectedTransportPath path = await manager.acquire(
        const TransportAcquireRequest(localPlatform: TransportPlatform.android),
      );
      expect(path.kind, TransportKind.lan);
      expect(lan.connectCallCount, 2);
    });

    test('no retry without rediscovery', () async {
      lan.failConnect = true;
      lan.emitCandidate(candidateId: 'l1');
      await _flush();
      await expectLater(
        manager.acquire(
          const TransportAcquireRequest(
            localPlatform: TransportPlatform.android,
          ),
        ),
        throwsA(isA<TransportException>()),
      );
      lan.failConnect = false;
      await expectLater(
        manager.acquire(
          const TransportAcquireRequest(
            localPlatform: TransportPlatform.android,
          ),
        ),
        throwsA(
          isA<TransportException>().having(
            (TransportException e) => e.kind,
            'kind',
            TransportFailureKind.noEligibleTransport,
          ),
        ),
      );
      expect(lan.connectCallCount, 1);
    });

    test('failed suppression is scoped to one acquisition', () async {
      final FakeTransportAdapter aware = FakeTransportAdapter(
        kind: TransportKind.wifiAware,
        availability: TransportAvailability.supportedAvailable,
      )..failConnect = true;
      final FakeTransportAdapter direct = FakeTransportAdapter(
        kind: TransportKind.wifiDirect,
        availability: TransportAvailability.supportedAvailable,
      )..failConnect = true;
      await manager.registerAdapter(aware);
      await manager.registerAdapter(direct);
      addTearDown(() async {
        await aware.close();
        await direct.close();
      });
      aware.emitCandidate(candidateId: 'a1');
      direct.emitCandidate(candidateId: 'd1');
      lan.emitCandidate(candidateId: 'l1');
      lan.failConnect = true;
      await _flush();
      await expectLater(
        manager.acquire(
          const TransportAcquireRequest(
            localPlatform: TransportPlatform.android,
            remotePlatform: TransportPlatform.android,
          ),
        ),
        throwsA(isA<TransportException>()),
      );
      expect(aware.connectCallCount, 1);
      expect(direct.connectCallCount, 1);
      expect(lan.connectCallCount, 1);

      aware.emitCandidate(candidateId: 'a1');
      direct.emitCandidate(candidateId: 'd1');
      lan.emitCandidate(candidateId: 'l1');
      aware.failConnect = false;
      await _flush();
      final SelectedTransportPath path = await manager.acquire(
        const TransportAcquireRequest(
          localPlatform: TransportPlatform.android,
          remotePlatform: TransportPlatform.android,
        ),
      );
      expect(path.kind, TransportKind.wifiAware);
      expect(aware.connectCallCount, 2);
    });
  });
}
