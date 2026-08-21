import 'dart:io';

import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_fixtures.dart';

/// Mission 07 final native-lifecycle contracts.
///
/// Evidence class: deterministic SOURCE contracts executed inside the Dart
/// suite (A for the Dart-side locator semantics, B for committed native
/// source structure). Native runtime behavior (real NSD/Bonjour callbacks,
/// real MulticastLock, real browse teardown) remains on the physical-device
/// C checklists — these tests never claim it.
void main() {
  group('iOS passive discovery (final fix)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
    });

    test('browse-result processing never constructs a connection', () {
      // The final fix removes discovery-time connection establishment.
      // No NWConnection token may appear anywhere in the LAN source.
      expect(discovery.contains('NWConnection'), isFalse);
      expect(discovery.contains('connection.start('), isFalse);
      expect(discovery.contains('currentPath'), isFalse);
    });

    test(
      'NWBrowser browse itself still starts, with TXT records (D-07-09)',
      () {
        expect(discovery.contains('browser.start(queue:'), isTrue);
        // The TXT-aware descriptor must be the production browse descriptor;
        // the plain descriptor form is not acceptable.
        expect(
          discovery.contains('NWBrowser.Descriptor.bonjourWithTXTRecord('),
          isTrue,
        );
        expect(discovery.contains('NWBrowser.Descriptor.bonjour('), isFalse);
      },
    );

    test(
      'native service endpoints are retained for the later connect stage',
      () {
        // Runtime-only instanceId -> Set<NWEndpoint> correlation (D-07-10);
        // never leaked to Dart, never persisted, never peer identity.
        expect(
          discovery.contains('instanceToPaths: [String: Set<NWEndpoint>]'),
          isTrue,
        );
        expect(
          discovery.contains('addOwner(path: key, of: instanceId)'),
          isTrue,
        );
        expect(discovery.contains('removeOwner(path: key, of: id)'), isTrue);
      },
    );

    test('candidate locator makes no socket address claim', () {
      expect(discovery.contains('"nativeService"'), isTrue);
      expect(discovery.contains('port='), isFalse);
      expect(discovery.contains('addrs='), isFalse);
      expect(discovery.contains('127.0.0.1'), isFalse);
    });

    test('TXT validation precedes candidate emission in publish', () {
      final RegExp order = RegExp(
        r'publish[\s\S]{0,900}?guard let instanceId = validateTxt\(txt\) '
        r'else \{ return \}[\s\S]{0,900}?emitCandidate',
      );
      expect(order.hasMatch(discovery), isTrue);
    });

    test('passive-discovery XCTest source exists and is wired', () {
      final File tests = locate(
        'ios/RunnerTests/FileHopLanPassiveDiscoveryTests.swift',
      );
      expect(tests.existsSync(), isTrue);
      final String source = tests.readAsStringSync();
      expect(
        source.contains('testDiscoverySourceNeverConstructsAConnection'),
        isTrue,
      );
      expect(
        source.contains(
          'testNativeServiceEndpointsAreRetainedForLaterConnectStage',
        ),
        isTrue,
      );
      expect(source.contains('testBrowseDescriptorRequestsTxtRecords'), isTrue);
      expect(
        source.contains('testCandidateLocatorMakesNoSocketAddressClaim'),
        isTrue,
      );
      final String pbxproj = locate('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(
        pbxproj.contains('FileHopLanPassiveDiscoveryTests.swift in Sources'),
        isTrue,
      );
    });
  });

  group('Android browse lifecycle (final fix)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('explicit lifecycle enum exists with all five states', () {
      expect(discovery.contains('enum class BrowseLifecycle'), isTrue);
      expect(discovery.contains('STOPPED,'), isTrue);
      expect(discovery.contains('STARTING,'), isTrue);
      expect(discovery.contains('BROWSING,'), isTrue);
      expect(discovery.contains('STOPPING,'), isTrue);
      expect(discovery.contains('UNCERTAIN,'), isTrue);
    });

    test('exactly one discoverServices call site: no overlap possible', () {
      // A rejected start cannot reach NSD: the single call site is guarded
      // by the STOPPED branch, and STOPPING/UNCERTAIN return early.
      expect('discoverServices('.allMatches(discovery).length, 1);
    });

    test('startBrowse is blocked while STOPPING', () {
      final RegExp blocked = RegExp(
        r'BrowseLifecycle\.STOPPING ->\s*'
        r'return "previous LAN discovery stop is still pending"',
      );
      expect(blocked.hasMatch(discovery), isTrue);
    });

    test('startBrowse is blocked while UNCERTAIN', () {
      final RegExp blocked = RegExp(
        r'BrowseLifecycle\.UNCERTAIN -> \{\s*'
        r'[\s\S]{0,400}?'
        r'return "previous LAN discovery session is still stopping"',
      );
      expect(blocked.hasMatch(discovery), isTrue);
      expect(
        discovery.contains('previous LAN discovery session is still stopping'),
        isTrue,
      );
    });

    test('stopBrowse never claims STOPPED synchronously', () {
      final RegExp body = RegExp(r'fun stopBrowse\(\) \{[\s\S]*?\n    \}');
      final Match? match = body.firstMatch(discovery);
      expect(match, isNotNull);
      expect(
        match!.group(0)!.contains('lifecycle = BrowseLifecycle.STOPPED'),
        isFalse,
        reason:
            'stopBrowse must not treat a normal stopServiceDiscovery '
            'return as stop confirmation',
      );
      expect(match.group(0)!.contains('cleanupBrowseGeneration('), isTrue);
      expect(
        match.group(0)!.contains('releaseNativeOwnership = false'),
        isTrue,
        reason: 'stop request must not release native ownership',
      );
    });

    test('onDiscoveryStopped is the authoritative confirmed-stop callback', () {
      final RegExp confirmed = RegExp(
        r'onDiscoveryStopped\(serviceType: String\) \{[\s\S]{0,1400}?'
        r'lifecycle = BrowseLifecycle\.STOPPED[\s\S]{0,600}?'
        r'releaseNativeOwnership = true',
      );
      expect(confirmed.hasMatch(discovery), isTrue);
    });

    test('onStartDiscoveryFailed releases ownership immediately', () {
      final RegExp startFail = RegExp(
        r'onStartDiscoveryFailed[\s\S]{0,1500}?'
        r'lifecycle = BrowseLifecycle\.STOPPED[\s\S]{0,700}?'
        r'releaseNativeOwnership = true',
      );
      expect(startFail.hasMatch(discovery), isTrue);
    });

    test(
      'stopServiceDiscovery is requested only from the stop coordinator',
      () {
        // Both code call sites use manager?.stopServiceDiscovery inside
        // requestStopAfterCleanup; cleanup and startBrowse never request
        // stops.
        expect(
          'manager?.stopServiceDiscovery('.allMatches(discovery).length,
          2,
        );
        expect(discovery.contains('manager.stopServiceDiscovery('), isFalse);
        final int coordinator = discovery.indexOf('requestStopAfterCleanup');
        final int firstCall = discovery.indexOf(
          'manager?.stopServiceDiscovery(',
        );
        final int secondCall = discovery.indexOf(
          'manager?.stopServiceDiscovery(',
          firstCall + 1,
        );
        expect(coordinator, greaterThanOrEqualTo(0));
        expect(firstCall, greaterThan(coordinator));
        expect(secondCall, greaterThan(coordinator));
        final int coordinatorEnd = discovery.indexOf(
          'private fun acquireMulticastLockIfRequired(',
        );
        expect(coordinatorEnd, greaterThan(coordinator));
        expect(firstCall, lessThan(coordinatorEnd));
        expect(secondCall, lessThan(coordinatorEnd));
      },
    );

    test('stop failure moves to UNCERTAIN and keeps ownership', () {
      final RegExp stopFail = RegExp(
        r'onStopDiscoveryFailed\(serviceType: String, errorCode: Int\) \{'
        r'[\s\S]{0,1500}?'
        r'lifecycle = BrowseLifecycle\.UNCERTAIN[\s\S]{0,400}?'
        r'uncertainStopListener = this',
      );
      expect(stopFail.hasMatch(discovery), isTrue);
      // Availability reports the uncertainty; it never claims availability.
      final RegExp availability = RegExp(
        r'lifecycle == BrowseLifecycle\.UNCERTAIN \|\|[\s\S]{0,80}?'
        r'SUPPORTED_UNAVAILABLE',
      );
      expect(availability.hasMatch(discovery), isTrue);
    });

    test(
      'retry stop stays asynchronous and never clears uncertainty alone',
      () {
        final RegExp retry = RegExp(
          r'BrowseLifecycle\.UNCERTAIN -> \{[\s\S]{0,300}?'
          r'lifecycle = BrowseLifecycle\.STOPPING[\s\S]{0,300}?'
          r'stopServiceDiscovery\(listener\)',
        );
        expect(retry.hasMatch(discovery), isTrue);
        final RegExp retryThrow = RegExp(
          r'catch \(_: RuntimeException\) \{[\s\S]{0,120}?'
          r'lifecycle = BrowseLifecycle\.UNCERTAIN',
        );
        expect(retryThrow.hasMatch(discovery), isTrue);
      },
    );
  });

  group('Android multicast prerequisite (final fix)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('preparation result type distinguishes the three outcomes', () {
      expect(discovery.contains('enum class MulticastPreparation'), isTrue);
      expect(discovery.contains('NOT_REQUIRED,'), isTrue);
      expect(discovery.contains('ACQUIRED,'), isTrue);
      expect(discovery.contains('FAILED,'), isTrue);
    });

    test('modern T-extension path requires no manual lock', () {
      final RegExp modern = RegExp(
        r'acquireMulticastLockIfRequired\(gen: Int\): MulticastPreparation\s*\{\s*'
        r'if \(modernNsd\) \{\s*return MulticastPreparation\.NOT_REQUIRED',
      );
      expect(modern.hasMatch(discovery), isTrue);
    });

    test('lock failure blocks discovery before discoverServices', () {
      // Fail-closed ordering: FAILED must return an error before the single
      // discoverServices call site, which is the only path to NSD.
      final RegExp failClosed = RegExp(
        r'MulticastPreparation\.FAILED\) \{[\s\S]{0,500}?'
        r'return "multicast lock required but unavailable"[\s\S]{0,6000}?'
        r'discoverServices\(',
      );
      expect(failClosed.hasMatch(discovery), isTrue);
    });

    test(
      'missing WifiManager, create failure, and acquire failure all fail',
      () {
        expect(
          discovery.contains(
            'val wifiManager = wifi ?: return MulticastPreparation.FAILED',
          ),
          isTrue,
        );
        expect(
          discovery.contains('createMulticastLock("filehop-lan-nsd")'),
          isTrue,
        );
        final RegExp acquireFail = RegExp(
          r'catch \(_: RuntimeException\) \{\s*MulticastPreparation\.FAILED',
        );
        expect(acquireFail.hasMatch(discovery), isTrue);
      },
    );

    test('legacy lock success allows the browse to proceed', () {
      final RegExp legacy = RegExp(
        r'lock\.acquire\(\)[\s\S]{0,200}?'
        r'multicastLock = lock[\s\S]{0,100}?'
        r'MulticastPreparation\.ACQUIRED',
      );
      expect(legacy.hasMatch(discovery), isTrue);
    });

    test('confirmed stop releases the owned lock exactly once', () {
      // The only release call site is inside cleanupBrowseGeneration,
      // guarded by releaseNativeOwnership; ownership-true paths are the
      // confirmed stop, the async start failure, and the synchronous
      // discoverServices failure — three exactly.
      expect('releaseMulticastLock('.allMatches(discovery).length, 2);
      expect('releaseNativeOwnership = true'.allMatches(discovery).length, 3);
      expect('releaseNativeOwnership = false'.allMatches(discovery).length, 1);
      expect(discovery.contains('if (multicastLockGen > gen) return'), isTrue);
    });
  });

  group('shared LanLocator contract (final fix)', () {
    test('nativeService locator hint is honest and constant', () {
      expect(kFileHopLanNativeServiceLocatorHint, 'nativeService');
      const LanNativeServiceLocator locator = LanNativeServiceLocator(
        serviceReference: 'bonjour-a',
      );
      expect(locator.locatorHint, 'nativeService');
      expect(locator.serviceReference, 'bonjour-a');
    });

    test('nativeService record carries no socket address claim', () {
      final LanDiscoveryRecord record = LanDiscoveryRecord.nativeService(
        instanceId: lanId(kLanIdA),
        serviceInstanceName: 'FileHop',
        serviceType: kFileHopLanServiceType,
        serviceReference: 'opaque-runtime-token',
      );
      expect(record.port, isNull);
      expect(record.addresses, isEmpty);
      expect(record.locatorHint, 'nativeService');
      expect(record.candidateId, kLanIdA);
    });

    test('nativeService factory rejects malformed references', () {
      expect(
        () => LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          serviceReference: '',
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
      expect(
        () => LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          serviceReference: 'x' * 129,
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
      expect(
        () => LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          serviceReference: 'bad\u0000token',
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
      expect(
        () => LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: '_wrong._tcp',
          serviceReference: 'ok',
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
    });

    test('resolved factory behavior is unchanged', () {
      final LanDiscoveryRecord record = lanRecord(
        hosts: const <String>['127.0.0.1', '::1'],
      );
      expect(record.port, 7240);
      expect(record.locator, isA<LanResolvedSocketLocator>());
      expect(record.locatorHint, contains('port=7240'));
      expect(
        () => LanDiscoveryRecord.resolved(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          port: 0,
          addresses: const <LanResolvedAddress>[],
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
    });

    test('adapter forwards a nativeService record truthfully', () async {
      final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend();
      final LanTransportAdapter adapter = LanTransportAdapter(backend: backend);
      final List<TransportAdapterEvent> events = <TransportAdapterEvent>[];
      adapter.events.listen(events.add);
      await adapter.startDiscovery();
      backend.emitFound(
        LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdC),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          serviceReference: 'runtime-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final AdapterCandidateFound found = events
          .whereType<AdapterCandidateFound>()
          .single;
      expect(found.candidateId, kLanIdC);
      expect(found.locatorHint, 'nativeService');
      expect(adapter.liveRecords()[kLanIdC]!.port, isNull);
      await adapter.close();
    });
  });
}

File locate(String relativeFromApp) {
  for (final String path in <String>[
    relativeFromApp,
    '../$relativeFromApp',
    'app/$relativeFromApp',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return File(relativeFromApp);
}
