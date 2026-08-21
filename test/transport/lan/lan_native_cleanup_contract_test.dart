import 'dart:io';

import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_fixtures.dart';

/// Mission 07 native discovery cleanup contracts.
///
/// Evidence class: these are deterministic SOURCE/BUILD contract proofs
/// (B-level for native behavior). They prove the committed Kotlin/Swift
/// source implements the required wiring, tracking, bounds, gating and
/// cleanup. They are NOT native runtime evidence; Android NSD / iOS Bonjour
/// runtime behavior remains on the physical-device C checklists.
void main() {
  group('Android LAN command bridge wiring', () {
    late String plugin;

    setUpAll(() {
      plugin = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopNativePlugin.kt',
      ).readAsStringSync();
    });

    test('plugin constructs the LAN discovery adapter', () {
      expect(plugin.contains('FileHopLanDiscovery(context)'), isTrue);
      expect(plugin.contains('lanDiscovery'), isTrue);
    });

    test('observeAvailability(lan) routes to lanDiscovery.availability()', () {
      final RegExp route = RegExp(
        r'"observeAvailability"[\s\S]{0,400}?'
        r'if \(kind == "lan"\)\s*\{\s*'
        r'result\.success\(lanDiscovery\.availability\(\)\)',
      );
      expect(route.hasMatch(plugin), isTrue);
    });

    test('startDiscovery(lan) routes to lanDiscovery.startBrowse()', () {
      final RegExp route = RegExp(
        r'"startDiscovery"[\s\S]{0,600}?'
        r'if \(kind != "lan"\)[\s\S]{0,300}?'
        r'lanDiscovery\.startBrowse\(\)',
      );
      expect(route.hasMatch(plugin), isTrue);
    });

    test('stopDiscovery(lan) routes to lanDiscovery.stopBrowse()', () {
      final RegExp route = RegExp(
        r'"stopDiscovery"[\s\S]{0,600}?'
        r'if \(kind != "lan"\)[\s\S]{0,300}?'
        r'lanDiscovery\.stopBrowse\(\)',
      );
      expect(route.hasMatch(plugin), isTrue);
    });

    test('LAN discovery commands no longer return generic unsupported', () {
      // The old Mission 02 skeleton listed startDiscovery/stopDiscovery in
      // one unconditional unsupported branch. That form must be gone.
      final RegExp skeleton = RegExp(
        r'"startDiscovery",\s*"stopDiscovery",\s*"connect"',
      );
      expect(skeleton.hasMatch(plugin), isFalse);
    });

    test('non-LAN discovery kinds remain bounded unsupported failures', () {
      // Wrong/unknown kinds fail with the bounded "unsupported" error and
      // are never silently mapped onto the LAN implementation.
      final RegExp guardedStart = RegExp(
        r'"startDiscovery"[\s\S]{0,400}?if \(kind != "lan"\)\s*\{\s*'
        r'result\.error\(\s*"unsupported"',
      );
      final RegExp guardedStop = RegExp(
        r'"stopDiscovery"[\s\S]{0,400}?if \(kind != "lan"\)\s*\{\s*'
        r'result\.error\(\s*"unsupported"',
      );
      expect(guardedStart.hasMatch(plugin), isTrue);
      expect(guardedStop.hasMatch(plugin), isTrue);
    });

    test('Wi-Fi Direct / Aware are not routed anywhere in Android source', () {
      final Directory kotlinDir = Directory(
        locate('android/app/src/main/kotlin').path,
      );
      for (final FileSystemEntity entity in kotlinDir.listSync(
        recursive: true,
      )) {
        if (entity is! File || !entity.path.endsWith('.kt')) {
          continue;
        }
        final String source = entity.readAsStringSync();
        expect(
          source.contains('WifiP2pManager'),
          isFalse,
          reason: '${entity.path} must not touch Wi-Fi Direct',
        );
        expect(
          source.contains('WifiAwareManager'),
          isFalse,
          reason: '${entity.path} must not touch Wi-Fi Aware',
        );
        expect(source.contains('"wifiDirect" -> lanDiscovery'), isFalse);
        expect(source.contains('"wifiAware" -> lanDiscovery'), isFalse);
      }
    });
  });

  group('Android manifest structure', () {
    late String manifest;

    setUpAll(() {
      manifest = locate('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
    });

    test('<application> attributes live inside the open tag', () {
      final int open = manifest.indexOf('<application');
      expect(open, greaterThanOrEqualTo(0));
      final int close = manifest.indexOf('>', open);
      expect(close, greaterThan(open));
      final String openTag = manifest.substring(open, close + 1);
      // Attributes are inside the tag itself, not text nodes after it.
      expect(openTag.contains('android:label="FileHop"'), isTrue);
      expect(openTag.contains(r'android:name="${applicationName}"'), isTrue);
      expect(openTag.contains('android:icon="@mipmap/ic_launcher"'), isTrue);
      // The broken text-node form '<application>' followed by attribute
      // text must be gone.
      expect(openTag, isNot('<application>'));
    });

    test('no attribute text leaks between <application> and children', () {
      final int open = manifest.indexOf('<application');
      final int close = manifest.indexOf('>', open);
      final int firstChild = manifest.indexOf('<', close + 1);
      final String between = manifest.substring(close + 1, firstChild);
      expect(
        between.trim(),
        isEmpty,
        reason: 'text between <application> and first child must be empty',
      );
    });

    test('legitimate children are preserved', () {
      expect(manifest.contains('android:name=".MainActivity"'), isTrue);
      expect(manifest.contains('android.intent.action.MAIN'), isTrue);
      expect(manifest.contains('android.intent.category.LAUNCHER'), isTrue);
      expect(manifest.contains('flutterEmbedding'), isTrue);
      expect(
        manifest.contains('io.flutter.embedding.android.NormalTheme'),
        isTrue,
      );
    });

    test('python XML structural validator passes', () {
      final File script = locateProjectFile(
        'scripts/validate_android_manifest.py',
      );
      expect(
        script.existsSync(),
        isTrue,
        reason: 'manifest XML validator script must exist',
      );
      final ProcessResult run = Process.runSync('python3', <String>[
        script.path,
        locate('android/app/src/main/AndroidManifest.xml').path,
      ]);
      expect(
        run.exitCode,
        0,
        reason: 'XML parse validation failed: ${run.stderr}',
      );
      expect('${run.stdout}'.contains('PASS'), isTrue);
    });
  });

  group('Android native candidate tracking', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('tracking key is a platform-local composite, not bare name', () {
      expect(discovery.contains('fun trackKey('), isTrue);
      expect(discovery.contains(r'"$network|$name"'), isTrue);
      // The old form keyed the map directly by service name.
      expect(discovery.contains('tracked[name] = entry'), isFalse);
    });

    test('instance ID owns shared candidate identity after TXT parse', () {
      // D-07-10/15: one-to-many — the instance owns a SET of path keys;
      // each registration binds paths to instances via bindPath.
      expect(discovery.contains('instanceToKeys'), isTrue);
      expect(
        discovery.contains('bindPath(entry, resolved, instanceId, gen)'),
        isTrue,
      );
      // Losing one service only emits lost when the FINAL owner disappears.
      expect(
        discovery.contains('cleanupRegistration(entry, emitLostForResolved)'),
        isTrue,
      );
    });

    test(
      'a path re-advertising a new instance ID emits lost only on final',
      () {
        // D-07-15: bindPath detects the per-path instance switch, unbinds
        // only that path from the old instance, and emits lost(old) only
        // when old lost its FINAL global owner.
        expect(discovery.contains('if (existingInstance != null) {'), isTrue);
        expect(
          discovery.contains(
            'if (removeOwner(existingInstance, pathKey)) emitLost(existingInstance)',
          ),
          isTrue,
        );
      },
    );
  });

  group('Android NSD gating and multicast cleanup', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('modern NSD gate includes the Android T extension check', () {
      expect(discovery.contains('SdkExtensions.getExtensionVersion'), isTrue);
      expect(discovery.contains('Build.VERSION_CODES.TIRAMISU'), isTrue);
      expect(discovery.contains('T_EXTENSION_MODERN_NSD = 7'), isTrue);
      expect(discovery.contains('fun modernNsdAvailable()'), isTrue);
      // The gate is consumed everywhere instead of raw SDK_INT >= 34 checks.
      expect(
        RegExp(r'SDK_INT >= API_SERVICE_INFO_CALLBACK').hasMatch(discovery),
        isFalse,
      );
    });

    test('modern path uses official getHostAddresses, not reflection', () {
      expect(discovery.contains('info.hostAddresses'), isTrue);
      expect(discovery.contains('getMethod'), isFalse);
      expect(discovery.contains('registerServiceInfoCallback'), isTrue);
    });

    test('legacy resolveService path is kept for pre-extension devices', () {
      expect(discovery.contains('@Suppress("DEPRECATION")'), isTrue);
      expect(discovery.contains('resolveService(service, listener)'), isTrue);
    });

    test('multicast lock rule follows the modern-NSD gate', () {
      expect(discovery.contains('acquireMulticastLockIfRequired'), isTrue);
      final RegExp gated = RegExp(
        r'acquireMulticastLockIfRequired\(gen: Int\): MulticastPreparation\s*\{\s*'
        r'if \(modernNsd\)',
      );
      expect(gated.hasMatch(discovery), isTrue);
    });

    test('central cleanup helper exists and is generation-guarded', () {
      expect(discovery.contains('fun cleanupBrowseGeneration('), isTrue);
      expect(
        discovery.contains('if (entry.generation > gen) continue'),
        isTrue,
      );
      expect(discovery.contains('releaseMulticastLock(gen)'), isTrue);
      expect(discovery.contains('if (multicastLockGen > gen) return'), isTrue);
    });

    test('onStartDiscoveryFailed performs full generation cleanup', () {
      // Window and whitespace tolerance account for the final-fix
      // lifecycle structure (synchronized state check + multi-line call).
      final RegExp cleanup = RegExp(
        r'onStartDiscoveryFailed[\s\S]{0,1400}?'
        r'cleanupBrowseGeneration\(\s*gen\b',
      );
      expect(cleanup.hasMatch(discovery), isTrue);
      // The failure branch must not be a lone `browsing.set(false)`.
      final RegExp lone = RegExp(
        r'onStartDiscoveryFailed\(regType: String, errorCode: Int\) \{\s*'
        r'browsing\.set\(false\)\s*'
        r'emitError[^}]*\}\s*$',
        multiLine: true,
      );
      expect(lone.hasMatch(discovery), isFalse);
    });

    test('synchronous discoverServices failure also cleans up', () {
      final RegExp cleanup = RegExp(
        r'catch \(_: RuntimeException\) \{\s*'
        r'browsing\.set\(false\)\s*'
        r'lifecycle = BrowseLifecycle\.STOPPED\s*'
        r'cleanupBrowseGeneration\(\s*gen\b',
      );
      expect(cleanup.hasMatch(discovery), isTrue);
    });

    test('stop failure keeps a bounded uncertain state', () {
      expect(discovery.contains('onStopDiscoveryFailed'), isTrue);
      expect(discovery.contains('uncertainStopListener'), isTrue);
      // A new browse must not stack over an uncertain old session.
      final RegExp guard = RegExp(
        r'fun startBrowse\(\)[\s\S]{0,600}?uncertainStopListener',
      );
      expect(guard.hasMatch(discovery), isTrue);
      expect(
        discovery.contains('previous LAN discovery session is still stopping'),
        isTrue,
      );
    });

    test('stopBrowse and detach reuse the central cleanup', () {
      final RegExp stop = RegExp(
        r'fun stopBrowse\(\)[\s\S]{0,300}?cleanupBrowseGeneration\(\s*gen\b',
      );
      expect(stop.hasMatch(discovery), isTrue);
      final RegExp detach = RegExp(r'fun detach\(\)\s*\{\s*stopBrowse\(\)');
      expect(detach.hasMatch(discovery), isTrue);
    });

    test('raw NSD numeric errors stay diagnostic, never thrown', () {
      expect(discovery.contains('"nativeCode" to code'), isTrue);
      expect(discovery.contains('throw '), isFalse);
    });
  });

  group('iOS native candidate tracking and TXT bounds', () {
    late String discovery;

    setUpAll(() {
      discovery = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
    });

    test('tracking is keyed by NWEndpoint, never display name', () {
      expect(discovery.contains('tracked: [NWEndpoint: Tracked]'), isTrue);
      expect(
        discovery.contains('instanceToPaths: [String: Set<NWEndpoint>]'),
        isTrue,
      );
      // The old maps keyed by the human-visible service name string.
      expect(discovery.contains('tracked: [String: Tracked]'), isFalse);
      expect(discovery.contains('resolvers: [String: NWConnection]'), isFalse);
      // Final fix: discovery owns no connection resolvers at all.
      expect(discovery.contains('resolvers'), isFalse);
    });

    test(
      'removal only emits lost when the final endpoint owner disappears',
      () {
        final RegExp owned = RegExp(
          r'handleRemoved[\s\S]{0,700}?removeOwner\(path: key, of: id\)',
        );
        expect(owned.hasMatch(discovery), isTrue);
      },
    );

    test('native TXT validator enforces frozen FileHop bounds', () {
      expect(discovery.contains('enum FileHopLanTxtValidator'), isTrue);
      expect(discovery.contains('maxTxtKeys = 8'), isTrue);
      expect(discovery.contains('maxTxtKeyBytes = 32'), isTrue);
      expect(discovery.contains('maxTxtValueBytes = 128'), isTrue);
      expect(discovery.contains('maxTxtPayloadBytes = 512'), isTrue);
      expect(discovery.contains('isCanonicalInstanceId'), isTrue);
      expect(discovery.contains('schemaVersion = 1'), isTrue);
    });

    test('TXT validation runs before any candidate emission', () {
      final RegExp order = RegExp(
        r'publish[\s\S]{0,900}?guard let instanceId = validateTxt\(txt\) '
        r'else \{ return \}[\s\S]{0,900}?emitCandidate',
      );
      expect(order.hasMatch(discovery), isTrue);
    });

    test('duplicate required TXT fields fail closed', () {
      expect(discovery.contains('seenVersion'), isTrue);
      expect(discovery.contains('seenInstance'), isTrue);
    });

    test('browser failure performs generation cleanup', () {
      final RegExp cleanup = RegExp(
        r'case \.failed[\s\S]{0,600}?cleanupBrowseGeneration\(gen',
      );
      expect(cleanup.hasMatch(discovery), isTrue);
      expect(discovery.contains('func cleanupBrowseGeneration('), isTrue);
      expect(discovery.contains('item.generation <= gen'), isTrue);
      expect(discovery.contains('browserGeneration <= gen'), isTrue);
    });

    test('XCTest TXT bounds source exists and is wired into RunnerTests', () {
      final File tests = locate(
        'ios/RunnerTests/FileHopLanTxtBoundsTests.swift',
      );
      expect(tests.existsSync(), isTrue);
      final String source = tests.readAsStringSync();
      expect(source.contains('testTooManyKeysRejected'), isTrue);
      expect(source.contains('testOversizedKeyRejected'), isTrue);
      expect(source.contains('testOversizedValueRejected'), isTrue);
      expect(source.contains('testOversizedTotalPayloadRejected'), isTrue);
      expect(source.contains('testMalformedInstanceRejected'), isTrue);
      expect(source.contains('testUnknownBoundedFieldAccepted'), isTrue);
      expect(source.contains('testUnsupportedVersionRejected'), isTrue);
      final String pbxproj = locate('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(
        pbxproj.contains('FileHopLanTxtBoundsTests.swift in Sources'),
        isTrue,
      );
    });
  });

  group('shared duplicate-name candidate isolation', () {
    late FakeLanDiscoveryBackend backend;
    late LanTransportAdapter adapter;
    late List<TransportAdapterEvent> events;

    setUp(() async {
      backend = FakeLanDiscoveryBackend();
      adapter = LanTransportAdapter(backend: backend);
      events = <TransportAdapterEvent>[];
      adapter.events.listen(events.add);
      await adapter.startDiscovery();
    });

    tearDown(() async {
      await adapter.close();
    });

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    test('same name, different instance IDs stay two candidates', () async {
      backend.emitFound(lanRecord(id: kLanIdA, serviceName: 'FileHop'));
      backend.emitFound(lanRecord(id: kLanIdB, serviceName: 'FileHop'));
      await pump();
      expect(
        events
            .whereType<AdapterCandidateFound>()
            .map((AdapterCandidateFound e) => e.candidateId)
            .toSet(),
        <String>{kLanIdA, kLanIdB},
      );
      expect(adapter.liveRecords().length, 2);
      expect(
        events.whereType<AdapterCandidateFound>().every(
          (AdapterCandidateFound e) => e.kind == TransportKind.lan,
        ),
        isTrue,
      );
    });

    test('updating A does not mutate B', () async {
      backend.emitFound(lanRecord(id: kLanIdA, serviceName: 'FileHop'));
      backend.emitFound(
        lanRecord(id: kLanIdB, serviceName: 'FileHop', port: 7300),
      );
      await pump();
      backend.emitUpdated(
        lanRecord(id: kLanIdA, serviceName: 'FileHop', port: 9000),
      );
      await pump();
      expect(adapter.liveRecords()[kLanIdA]!.port, 9000);
      expect(adapter.liveRecords()[kLanIdB]!.port, 7300);
      expect(events.whereType<AdapterCandidateLost>(), isEmpty);
    });

    test('losing A does not remove B', () async {
      backend.emitFound(lanRecord(id: kLanIdA, serviceName: 'FileHop'));
      backend.emitFound(lanRecord(id: kLanIdB, serviceName: 'FileHop'));
      await pump();
      backend.emitLost(lanId(kLanIdA));
      await pump();
      expect(
        events.whereType<AdapterCandidateLost>().single.candidateId,
        kLanIdA,
      );
      expect(adapter.liveRecords().containsKey(kLanIdA), isFalse);
      expect(adapter.liveRecords().containsKey(kLanIdB), isTrue);
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

File locateProjectFile(String relativeFromProjectRoot) {
  for (final String path in <String>[
    relativeFromProjectRoot,
    '../$relativeFromProjectRoot',
    '../../$relativeFromProjectRoot',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return File(relativeFromProjectRoot);
}
