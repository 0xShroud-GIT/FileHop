import 'dart:convert';
import 'dart:io';

import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_fixtures.dart';

/// Mission 07 final Bonjour/multipath contracts (prompt: final
/// Bonjour/multipath fix).
///
/// Evidence classes:
/// - A: the Dart-side `LanPathOwnership` reference model and the UTF-8
///   reference bound are executed here deterministically.
/// - B: the committed Kotlin/Swift source is proven to mirror the frozen
///   one-to-many semantics structurally (source contracts).
/// - C: real multi-interface Bonjour/NSD runtime behavior remains on the
///   physical-device checklists and is never claimed here.
void main() {
  group('iOS Bonjour TXT descriptor (D-07-09)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
    });

    test('browse requests TXT records', () {
      expect(
        discovery.contains('NWBrowser.Descriptor.bonjourWithTXTRecord('),
        isTrue,
      );
    });

    test(
      'plain bonjour descriptor is not the production browse descriptor',
      () {
        expect(discovery.contains('NWBrowser.Descriptor.bonjour('), isFalse);
      },
    );

    test('TXT metadata remains mandatory and fail-closed', () {
      expect(
        discovery.contains('guard case .bonjour(let txt) = result.metadata'),
        isTrue,
      );
      expect(
        discovery.contains(
          'guard let instanceId = validateTxt(txt) else { return }',
        ),
        isTrue,
      );
    });

    test('passive discovery preserved: no discovery-time connection', () {
      expect(discovery.contains('NWConnection'), isFalse);
      expect(discovery.contains('connection.start('), isFalse);
      expect(discovery.contains('browser.start(queue:'), isTrue);
    });
  });

  group('iOS one-to-many native path ownership (D-07-10)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
    });

    test('instance owns a SET of native endpoints', () {
      expect(
        discovery.contains('instanceToPaths: [String: Set<NWEndpoint>]'),
        isTrue,
      );
      expect(
        discovery.contains('instanceToEndpoint: [String: NWEndpoint]'),
        isFalse,
      );
    });

    test('per-instance native path bound is frozen at 8', () {
      expect(discovery.contains('maxNativePathsPerInstance = 8'), isTrue);
    });

    test('first owner emits found; additional owner emits updated', () {
      expect(discovery.contains('case .firstOwner:'), isTrue);
      expect(discovery.contains('eventKind: "candidateFound"'), isTrue);
      expect(discovery.contains('case .additionalOwner:'), isTrue);
      expect(discovery.contains('eventKind: "candidateUpdated"'), isTrue);
    });

    test('duplicate path callback is idempotent with no emission', () {
      expect(discovery.contains('case .duplicatePath:'), isTrue);
    });

    test('path limit is a deterministic drop with bounded diagnostic', () {
      expect(discovery.contains('case .pathLimitReached:'), isTrue);
      expect(discovery.contains('code: "pathLimitExceeded"'), isTrue);
    });

    test('removal emits lost only when the final owner disappears', () {
      final RegExp finalOnly = RegExp(
        r'removeOwner\(path: NWEndpoint, of instanceId: String\) -> Bool \{'
        r'[\s\S]{0,300}?'
        r'set\.isEmpty \{[\s\S]{0,120}?'
        r'instanceToPaths\.removeValue\(forKey: instanceId\)[\s\S]{0,80}?'
        r'return true',
      );
      expect(finalOnly.hasMatch(discovery), isTrue);
    });

    test('instance switch moves path ownership from old to new', () {
      final RegExp switchPath = RegExp(
        r'if let old = previousId, old != instanceId \{[\s\S]{0,300}?'
        r'removeOwner\(path: key, of: old\)',
      );
      expect(switchPath.hasMatch(discovery), isTrue);
    });
  });

  group('Android one-to-many native path ownership (D-07-10)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('instance owns a SET of native track keys', () {
      expect(
        discovery.contains('HashMap<String, MutableSet<String>>()'),
        isTrue,
      );
      expect(discovery.contains('instanceToKeys'), isTrue);
      // The old one-to-one map declaration and its ops must be gone
      // (word-boundary forms so `instanceToKeys` itself does not match).
      expect(discovery.contains('instanceToKey ='), isFalse);
      expect(discovery.contains('instanceToKey.putIfAbsent'), isFalse);
      expect(discovery.contains('instanceToKey.remove'), isFalse);
    });

    test('per-instance native path bound is frozen at 8', () {
      expect(discovery.contains('MAX_NATIVE_PATHS_PER_INSTANCE = 8'), isTrue);
    });

    test('ownership outcomes mirror the shared reference model', () {
      expect(discovery.contains('enum class PathOutcome'), isTrue);
      expect(discovery.contains('FIRST_OWNER,'), isTrue);
      expect(discovery.contains('ADDITIONAL_OWNER,'), isTrue);
      expect(discovery.contains('DUPLICATE_PATH,'), isTrue);
      expect(discovery.contains('PATH_LIMIT_REACHED,'), isTrue);
    });

    test('loss correlates the registration, then removes its binding(s)', () {
      // D-07-15: path-identified loss removes exactly the identified path;
      // null-network loss is bounded (1 binding removes it, >1 ambiguous).
      final RegExp loss = RegExp(
        r'fun handleLost[\s\S]{0,2500}?'
        r'handleCorrelatedLoss\(direct, service, gen\)',
      );
      expect(loss.hasMatch(discovery), isTrue);
      final RegExp correlated = RegExp(
        r'fun handleCorrelatedLoss\(entry: Tracked, service: NsdServiceInfo, gen: Int\) \{'
        r'[\s\S]{0,800}?'
        r'removeBinding\(entry, "\$network|\$\{entry\.serviceName\}"\)',
      );
      expect(correlated.hasMatch(discovery), isTrue);
    });

    test('removeOwner returns true only for the final owner', () {
      final RegExp finalOnly = RegExp(
        r'fun removeOwner\(instanceId: String, pathKey: String\): Boolean \{'
        r'[\s\S]{0,300}?'
        r'set\.isEmpty\(\)\) \{[\s\S]{0,120}?'
        r'instanceToKeys\.remove\(instanceId\)[\s\S]{0,80}?'
        r'return true',
      );
      expect(finalOnly.hasMatch(discovery), isTrue);
    });

    test('a path switching instance unbinds only itself', () {
      final RegExp switchPath = RegExp(
        r'if \(existingInstance != null\) \{[\s\S]{0,300}?'
        r'removeOwner\(existingInstance, pathKey\)',
      );
      expect(switchPath.hasMatch(discovery), isTrue);
      expect(discovery.contains('emitLost(existingInstance)'), isTrue);
    });

    test('duplicate and limit paths never emit found/updated', () {
      // instanceId is assigned before the outcome switch; the duplicate
      // branch contains no emit call of any kind.
      final RegExp instanceSet = RegExp(
        r'when \(bindPath\(entry, resolved, instanceId, gen\)\) \{'
        r'[\s\S]{0,1200}?'
        r'PathBindOutcome\.DUPLICATE_BINDING -> \{[\s\S]{0,400}?'
        r'// Duplicate native callback',
      );
      expect(instanceSet.hasMatch(discovery), isTrue);
      final RegExp duplicate = RegExp(
        r'PathBindOutcome\.DUPLICATE_BINDING -> \{[\s\S]{0,400}?'
        r'// Duplicate native callback',
      );
      expect(duplicate.hasMatch(discovery), isTrue);
      final RegExp limit = RegExp(
        r'PathOutcome\.PATH_LIMIT_REACHED -> \{[\s\S]{0,300}?'
        r'"pathLimitExceeded"',
      );
      expect(limit.hasMatch(discovery), isTrue);
    });

    test('modern and legacy resolve paths converge on publishResolved', () {
      expect(discovery.contains('registerModern'), isTrue);
      expect(discovery.contains('registerLegacy'), isTrue);
      final RegExp modern = RegExp(
        r'onServiceUpdated\(info: NsdServiceInfo\) \{\s*'
        r'(?://[^\n]*\n\s*)*dispatchState \{ publishResolved\(info, entry, gen\) \}',
      );
      expect(modern.hasMatch(discovery), isTrue);
      final RegExp legacy = RegExp(
        r'onServiceResolved\(serviceInfo: NsdServiceInfo\) \{\s*'
        r'(?://[^\n]*\n\s*)*dispatchState \{ publishResolved\(serviceInfo, entry, gen\) \}',
      );
      expect(legacy.hasMatch(discovery), isTrue);
    });
  });

  group('LanPathOwnership reference behavior (D-07-10)', () {
    const String instance = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const String otherInstance = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    test('first path emits found; second path does not duplicate identity', () {
      final LanPathOwnership ownership = LanPathOwnership();
      expect(
        ownership.add(instanceId: instance, pathKey: 'pathA'),
        LanPathOutcome.firstOwner,
      );
      expect(
        ownership.add(instanceId: instance, pathKey: 'pathB'),
        LanPathOutcome.additionalOwner,
      );
      expect(ownership.trackedInstances, 1);
      expect(ownership.ownersOf(instance), <String>{'pathA', 'pathB'});
    });

    test('partial path loss does not terminally lose the candidate', () {
      final LanPathOwnership ownership = LanPathOwnership();
      ownership.add(instanceId: instance, pathKey: 'pathA');
      ownership.add(instanceId: instance, pathKey: 'pathB');
      expect(ownership.remove(instanceId: instance, pathKey: 'pathA'), isFalse);
      expect(ownership.owns(instance, 'pathB'), isTrue);
      expect(ownership.trackedInstances, 1);
    });

    test('final path loss terminally loses the candidate', () {
      final LanPathOwnership ownership = LanPathOwnership();
      ownership.add(instanceId: instance, pathKey: 'pathB');
      expect(ownership.remove(instanceId: instance, pathKey: 'pathB'), isTrue);
      expect(ownership.trackedInstances, 0);
      expect(ownership.ownersOf(instance), isEmpty);
    });

    test('duplicate path callbacks are idempotent', () {
      final LanPathOwnership ownership = LanPathOwnership();
      expect(
        ownership.add(instanceId: instance, pathKey: 'pathA'),
        LanPathOutcome.firstOwner,
      );
      expect(
        ownership.add(instanceId: instance, pathKey: 'pathA'),
        LanPathOutcome.duplicatePath,
      );
      expect(ownership.ownersOf(instance), <String>{'pathA'});
      expect(ownership.remove(instanceId: instance, pathKey: 'pathA'), isTrue);
    });

    test('same name / different instance stays two distinct candidates', () {
      final LanPathOwnership ownership = LanPathOwnership();
      expect(
        ownership.add(instanceId: instance, pathKey: 'p1'),
        LanPathOutcome.firstOwner,
      );
      expect(
        ownership.add(instanceId: otherInstance, pathKey: 'p2'),
        LanPathOutcome.firstOwner,
      );
      expect(ownership.trackedInstances, 2);
      expect(ownership.remove(instanceId: instance, pathKey: 'p1'), isTrue);
      expect(ownership.owns(otherInstance, 'p2'), isTrue);
      expect(ownership.trackedInstances, 1);
    });

    test('same instance / different paths stays one shared candidate', () {
      final LanPathOwnership ownership = LanPathOwnership();
      ownership.add(instanceId: instance, pathKey: 'path1');
      ownership.add(instanceId: instance, pathKey: 'path2');
      expect(ownership.trackedInstances, 1);
      expect(ownership.ownersOf(instance).length, 2);
    });

    test('instance switch on one path moves ownership safely', () {
      final LanPathOwnership ownership = LanPathOwnership();
      ownership.add(instanceId: instance, pathKey: 'pathA');
      // Same path now advertises a different instance ID.
      expect(ownership.remove(instanceId: instance, pathKey: 'pathA'), isTrue);
      expect(
        ownership.add(instanceId: otherInstance, pathKey: 'pathA'),
        LanPathOutcome.firstOwner,
      );
      expect(ownership.owns(instance, 'pathA'), isFalse);
      expect(ownership.owns(otherInstance, 'pathA'), isTrue);
    });

    test(
      'instance switch with a surviving owner does not lose the old one',
      () {
        final LanPathOwnership ownership = LanPathOwnership();
        ownership.add(instanceId: instance, pathKey: 'pathA');
        ownership.add(instanceId: instance, pathKey: 'pathB');
        // pathA re-advertises a new instance: old keeps pathB.
        expect(
          ownership.remove(instanceId: instance, pathKey: 'pathA'),
          isFalse,
        );
        expect(
          ownership.add(instanceId: otherInstance, pathKey: 'pathA'),
          LanPathOutcome.firstOwner,
        );
        expect(ownership.owns(instance, 'pathB'), isTrue);
        expect(ownership.owns(otherInstance, 'pathA'), isTrue);
      },
    );

    test('unknown/stale path loss changes nothing', () {
      final LanPathOwnership ownership = LanPathOwnership();
      ownership.add(instanceId: instance, pathKey: 'pathA');
      expect(
        ownership.remove(instanceId: instance, pathKey: 'neverTracked'),
        isFalse,
      );
      expect(
        ownership.remove(instanceId: otherInstance, pathKey: 'neverTracked'),
        isFalse,
      );
      expect(ownership.owns(instance, 'pathA'), isTrue);
    });

    test(
      'per-instance path bound drops additional paths deterministically',
      () {
        final LanPathOwnership ownership = LanPathOwnership();
        for (int i = 0; i < LanPathOwnership.kMaxNativePathsPerInstance; i++) {
          final LanPathOutcome outcome = ownership.add(
            instanceId: instance,
            pathKey: 'path$i',
          );
          expect(
            outcome,
            i == 0 ? LanPathOutcome.firstOwner : LanPathOutcome.additionalOwner,
          );
        }
        expect(
          ownership.add(instanceId: instance, pathKey: 'overflow'),
          LanPathOutcome.pathLimitReached,
        );
        expect(
          ownership.ownersOf(instance).length,
          LanPathOwnership.kMaxNativePathsPerInstance,
        );
        // Existing owners are never evicted.
        expect(ownership.owns(instance, 'path0'), isTrue);
        expect(ownership.owns(instance, 'overflow'), isFalse);
      },
    );
  });

  group('native-service reference UTF-8 byte bound (D-07-11)', () {
    test('ASCII reference of exactly 128 UTF-8 bytes is accepted', () {
      final LanDiscoveryRecord record = LanDiscoveryRecord.nativeService(
        instanceId: lanId(kLanIdA),
        serviceInstanceName: 'FileHop',
        serviceType: kFileHopLanServiceType,
        serviceReference: 'a' * 128,
      );
      final LanNativeServiceLocator locator =
          record.locator as LanNativeServiceLocator;
      expect(utf8.encode(locator.serviceReference).length, 128);
    });

    test('ASCII reference of 129 UTF-8 bytes is rejected', () {
      expect(
        () => LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          serviceReference: 'a' * 129,
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
    });

    test('multibyte reference with code units < 128 but UTF-8 bytes > 128 '
        'is rejected', () {
      final String multibyte = 'é' * 100; // 100 code units, 200 UTF-8 bytes
      expect(multibyte.length, lessThan(128));
      expect(utf8.encode(multibyte).length, greaterThan(128));
      expect(
        () => LanDiscoveryRecord.nativeService(
          instanceId: lanId(kLanIdA),
          serviceInstanceName: 'FileHop',
          serviceType: kFileHopLanServiceType,
          serviceReference: multibyte,
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
    });

    test('multibyte reference within 128 UTF-8 bytes is accepted', () {
      final String multibyte = 'é' * 60; // 60 code units, 120 UTF-8 bytes
      expect(utf8.encode(multibyte).length, 120);
      final LanDiscoveryRecord record = LanDiscoveryRecord.nativeService(
        instanceId: lanId(kLanIdA),
        serviceInstanceName: 'FileHop',
        serviceType: kFileHopLanServiceType,
        serviceReference: multibyte,
      );
      expect(record.locatorHint, 'nativeService');
    });

    test('control characters and empty references still fail closed', () {
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
          serviceReference: 'bad\u0000token',
        ),
        throwsA(isA<LanDiscoveryException>()),
      );
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
