import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS native plugin event bridge', () {
    late String plugin;

    setUpAll(() {
      plugin = locate('ios/Runner/FileHopNativePlugin.swift').readAsStringSync();
    });

    test('LAN callback target exists and marshals onto main', () {
      expect(
        plugin.contains('private func emitEvent(_ payload: [String: Any])'),
        isTrue,
      );
      expect(plugin.contains('DispatchQueue.main.async'), isTrue);
      expect(plugin.contains('self?.eventSink?(payload)'), isTrue);
    });
  });

  group('iOS LAN serialized lifecycle', () {
    late String discovery;

    setUpAll(() {
      discovery = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
    });

    test('public start and stop enter the single state authority', () {
      expect(discovery.contains('private func syncState<T>'), isTrue);
      expect(
        RegExp(r'func startBrowse\(\) -> String\? \{\s*syncState \{')
            .hasMatch(discovery),
        isTrue,
      );
      expect(
        RegExp(r'func stopBrowse\(\) \{\s*syncState \{').hasMatch(discovery),
        isTrue,
      );
    });

    test('browser failures guard current generation before mutation', () {
      const String guard =
          'guard self.live(gen), self.browserGeneration == gen else { return }';
      final int guardIndex = discovery.indexOf(guard);
      final int failureIndex = discovery.indexOf('case .failed(let error):');
      final int mutationIndex = discovery.indexOf('self.browsing = false');
      expect(guardIndex, greaterThanOrEqualTo(0));
      expect(failureIndex, greaterThan(guardIndex));
      expect(mutationIndex, greaterThan(failureIndex));
    });

    test('browse-result callbacks re-enter the same queue before handling', () {
      expect(
        RegExp(
          r'browseResultsChangedHandler[\s\S]{0,220}?self\.queue\.async[\s\S]{0,160}?self\.handle\(changes: changes, gen: gen\)',
        ).hasMatch(discovery),
        isTrue,
      );
    });
  });
}

File locate(String relativeFromApp) {
  for (final String path in <String>[
    relativeFromApp,
    '../$relativeFromApp',
    '../../$relativeFromApp',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return File(relativeFromApp);
}
