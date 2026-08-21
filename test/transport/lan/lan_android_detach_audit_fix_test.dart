import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine detach retains a bounded NSD stop retry window', () {
    final String plugin = locate(
      'android/app/src/main/kotlin/app/filehop/filehop/FileHopNativePlugin.kt',
    ).readAsStringSync();

    expect(plugin.contains('DETACH_STOP_RETRY_COUNT'), isTrue);
    expect(plugin.contains('DETACH_STOP_RETRY_INTERVAL_MS'), isTrue);
    expect(
      RegExp(
        r'fun detach\(\) \{[\s\S]{0,900}?lanDiscovery\.detach\(\)[\s\S]{0,900}?mainHandler\.postDelayed\([\s\S]{0,500}?lanDiscovery\.detach\(\)',
      ).hasMatch(plugin),
      isTrue,
    );
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
