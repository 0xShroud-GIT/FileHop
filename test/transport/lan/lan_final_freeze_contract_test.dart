import 'dart:io';

import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 07 final-freeze contracts.
///
/// Evidence classes:
/// - A: Dart-side behaviors executed here (LanPathOwnership migration
///   semantics, export-manifest determinism regression).
/// - B: committed Kotlin/Swift source structure proven by deterministic
///   source contracts. NOT native runtime evidence.
/// - C: real device multipath/NSD/Bonjour behavior stays NOT_RUN.
void main() {
  group('iOS NWTXTRecord type-name fix', () {
    late String discovery;
    late String passiveTests;
    late String txtBoundsTests;

    setUpAll(() {
      discovery = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
      passiveTests = locate(
        'ios/RunnerTests/FileHopLanPassiveDiscoveryTests.swift',
      ).readAsStringSync();
      txtBoundsTests = locate('ios/RunnerTests/FileHopLanTxtBoundsTests.swift')
          .readAsStringSync();
    });

    test('production uses the correct Apple Network type NWTXTRecord', () {
      expect(discovery.contains('NWTXTRecord'), isTrue);
      expect(
        discovery.contains('private func validateTxt(_ record: NWTXTRecord)'),
        isTrue,
      );
    });

    test('the incorrect NWTxtRecord spelling is absent from production', () {
      expect(discovery.contains('NWTxtRecord'), isFalse);
      expect(passiveTests.contains('NWTxtRecord'), isFalse);
      expect(txtBoundsTests.contains('NWTxtRecord'), isFalse);
    });

    test('TXT-aware Bonjour descriptor and passive discovery retained', () {
      expect(
        discovery.contains('NWBrowser.Descriptor.bonjourWithTXTRecord('),
        isTrue,
      );
      expect(discovery.contains('NWBrowser.Descriptor.bonjour('), isFalse);
      expect(discovery.contains('NWConnection'), isFalse);
      expect(discovery.contains('connection.start('), isFalse);
      expect(discovery.contains('browser.start(queue:'), isTrue);
    });
  });

  group('Android resolved native path-key hardening (D-07-12/15)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('Tracked binds each path to its own instance (map model)', () {
      expect(
        discovery.contains(
          'val pathOwners: MutableMap<String, String> = LinkedHashMap()',
        ),
        isTrue,
      );
      // The old single mutable pathKey and owner-SET models must be gone.
      expect(discovery.contains('var pathKey: String = trackKey'), isFalse);
      expect(
        discovery.contains('val ownedPathKeys: MutableSet<String>'),
        isFalse,
      );
      expect(discovery.contains('migrateOwnerKey('), isFalse);
    });

    test('resolved correlation prefers the concrete Network (API 33+)', () {
      final RegExp network = RegExp(
        r'fun resolvedNetwork\(info: NsdServiceInfo\): String\? \{[\s\S]{0,200}?'
        r'info\.network\?\.toString\(\)',
      );
      expect(network.hasMatch(discovery), isTrue);
      expect(
        discovery.contains(
          'Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU',
        ),
        isTrue,
      );
    });

    test(
      'resolved path key falls back to legacy host, then the seed stand-in',
      () {
        final RegExp host = RegExp(
          r'fun resolvedPathKey\(info: NsdServiceInfo, entry: Tracked\): String \{'
          r'[\s\S]{0,400}?'
          r'info\.host\?\.hostAddress',
        );
        expect(host.hasMatch(discovery), isTrue);
        expect(
          discovery.contains('return entry.registrationKey'),
          isTrue,
          reason:
              'no stronger correlation must keep the seed stand-in, '
              'never fabricate a network identity',
        );
      },
    );

    test('seed key remains a bounded temporary correlation', () {
      expect(discovery.contains(r'"$network|$name"'), isTrue);
      expect(
        discovery.contains('Never fabricates a network identity.'),
        isTrue,
      );
    });

    test('seed refinement is silent (no fake candidate restart)', () {
      final RegExp refine = RegExp(
        r'private fun refineSeedBinding\(entry: Tracked, instanceId: String, resolvedKey: String\) \{'
        r'[\s\S]*?'
        r'entry\.pathOwners\[resolvedKey\] = instanceId[\s\S]*?\n    \}',
      );
      final Match? match = refine.firstMatch(discovery);
      expect(match, isNotNull);
      final String body = match!.group(0)!;
      expect(body.contains('emitLost('), isFalse);
      expect(body.contains('emitCandidate('), isFalse);
      expect(body.contains('emitError('), isFalse);
    });

    test('publishResolved refines the seed, then registers via bindPath', () {
      final RegExp order = RegExp(
        r'if \(entry\.pathOwners\.size == 1 &&[\s\S]{0,900}?'
        r'refineSeedBinding\(entry, instanceId, resolved\)[\s\S]{0,400}?'
        r'bindPath\(entry, resolved, instanceId, gen\)',
      );
      expect(order.hasMatch(discovery), isTrue);
    });

    test('bindPath never migrates unrelated bindings', () {
      // The path-specific switch removes ONLY the switching path from the
      // old instance, then binds the new one.
      final RegExp switchOnly = RegExp(
        r'if \(existingInstance != null\) \{[\s\S]{0,400}?'
        r'entry\.pathOwners\.remove\(pathKey\)[\s\S]{0,200}?'
        r'removeOwner\(existingInstance, pathKey\)',
      );
      expect(switchOnly.hasMatch(discovery), isTrue);
      expect(
        discovery.contains(
          'if (removeOwner(existingInstance, pathKey)) emitLost(existingInstance)',
        ),
        isTrue,
      );
    });

    test('cleanup removes every binding, never the stale seed key', () {
      final RegExp cleanup = RegExp(
        r'fun cleanupBrowseGeneration\([\s\S]{0,1200}?'
        r'cleanupRegistration\(entry, emitLostForResolved\)',
      );
      expect(cleanup.hasMatch(discovery), isTrue);
      final RegExp removeAll = RegExp(
        r'fun cleanupRegistration\(entry: Tracked, emitLostForResolved: Boolean\) \{'
        r'[\s\S]{0,500}?'
        r'for \(\(path, instanceId\) in entry\.pathOwners\.toList\(\)\)',
      );
      expect(removeAll.hasMatch(discovery), isTrue);
      expect(
        discovery.contains('tracked.remove(entry.registrationKey)'),
        isTrue,
      );
    });

    test('null-network loss disambiguation is bounded and fail-safe', () {
      expect(discovery.contains('lookupKey.startsWith("-|")'), isTrue);
      expect(discovery.contains('candidates.size != 1'), isTrue);
      expect(discovery.contains('lossCorrelationAmbiguous'), isTrue);
    });

    test('modern duplicate found callbacks are idempotent', () {
      final RegExp idempotent = RegExp(
        r'if \(modernNsd && existing\.callback != null\) return',
      );
      expect(idempotent.hasMatch(discovery), isTrue);
    });

    test('legacy and modern resolve paths converge on publishResolved', () {
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

  group('global instance→paths ownership reference (D-07-10)', () {
    const String instance = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('same instance on two resolved networks owns two paths', () {
      final LanPathOwnership ownership = LanPathOwnership();
      expect(
        ownership.add(instanceId: instance, pathKey: 'networkA|FileHop'),
        LanPathOutcome.firstOwner,
      );
      expect(
        ownership.add(instanceId: instance, pathKey: 'networkB|FileHop'),
        LanPathOutcome.additionalOwner,
      );
      expect(ownership.ownersOf(instance).length, 2);
      // Loss of one network keeps the candidate.
      expect(
        ownership.remove(instanceId: instance, pathKey: 'networkA|FileHop'),
        isFalse,
      );
      // Loss of the final network terminates it.
      expect(
        ownership.remove(instanceId: instance, pathKey: 'networkB|FileHop'),
        isTrue,
      );
    });

    test('partial vs final loss emits exactly once', () {
      final LanPathOwnership ownership = LanPathOwnership();
      ownership.add(instanceId: instance, pathKey: 'networkA|FileHop');
      ownership.add(instanceId: instance, pathKey: 'networkB|FileHop');
      expect(
        ownership.remove(instanceId: instance, pathKey: 'networkA|FileHop'),
        isFalse,
      );
      expect(
        ownership.remove(instanceId: instance, pathKey: 'networkB|FileHop'),
        isTrue,
      );
      // A stale repeat removal changes nothing and never re-signals.
      expect(
        ownership.remove(instanceId: instance, pathKey: 'networkB|FileHop'),
        isFalse,
      );
      expect(ownership.trackedInstances, 0);
    });
  });

  group('export manifest determinism', () {
    late Directory temp;
    late String zipPath;
    late File manifest;

    setUpAll(() {
      temp = Directory.systemTemp.createTempSync('filehop-export-test-');
      zipPath = '${temp.path}/filehop-review-07.zip';
      final File script = locate('scripts/export_review_bundle.sh');
      expect(script.existsSync(), isTrue);
      final ProcessResult run = Process.runSync('bash', <String>[
        script.path,
        '07',
        zipPath,
      ]);
      expect(
        run.exitCode,
        0,
        reason: 'exporter failed:\n${run.stdout}\n${run.stderr}',
      );
      manifest = locateProjectFile(
        'artifacts/evidence/mission-07/export-manifest.txt',
      );
      expect(manifest.existsSync(), isTrue);
    });

    tearDownAll(() {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // best effort
      }
    });

    List<String> manifestFileList(File file) {
      final List<String> lines = file.readAsLinesSync();
      final int marker = lines.indexOf('files:');
      expect(marker, greaterThanOrEqualTo(0));
      return lines.sublist(marker + 1);
    }

    test('manifest listing is fully lexicographically sorted', () {
      final List<String> lines = manifestFileList(manifest);
      expect(lines, isNotEmpty);
      final List<String> sorted = List<String>.of(lines)..sort();
      expect(lines, sorted, reason: 'manifest listing must be sorted');
      expect(
        lines,
        contains('FileHop/artifacts/evidence/mission-07/export-manifest.txt'),
        reason: 'the manifest must list itself at its sorted position',
      );
    });

    test('includedFileCount equals the manifest listing length', () {
      final List<String> lines = manifestFileList(manifest);
      final String countLine = manifest.readAsLinesSync().firstWhere(
        (String line) => line.startsWith('includedFileCount:'),
      );
      final int count = int.parse(countLine.split(':')[1].trim());
      expect(count, lines.length);
    });

    test('ZIP file listing exactly matches the manifest listing', () {
      final List<String> lines = manifestFileList(manifest);
      final ProcessResult listing = Process.runSync('unzip', <String>[
        '-Z1',
        zipPath,
      ]);
      expect(listing.exitCode, 0, reason: '${listing.stderr}');
      final List<String> zipLines =
          (listing.stdout as String)
              .split('\n')
              .where((String line) => line.trim().isNotEmpty)
              .toList()
            ..sort();
      final List<String> manifestSorted = List<String>.of(lines)..sort();
      expect(zipLines, manifestSorted);
    });

    test('forbidden generated paths are absent from the export', () {
      final ProcessResult listing = Process.runSync('unzip', <String>[
        '-Z1',
        zipPath,
      ]);
      final String all = listing.stdout as String;
      expect(
        RegExp(r'(^|/)(\.dart_tool|\.gradle|node_modules|packet/)')
            .hasMatch(all),
        isFalse,
      );
      expect(
        RegExp(r'(^|/)local\.properties$', multiLine: true).hasMatch(all),
        isFalse,
      );
      expect(all.contains('kotlin-compile/classes'), isFalse);
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
