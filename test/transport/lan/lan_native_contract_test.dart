import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android LAN source uses NsdManager and FileHop service type', () {
    final File file = locate(
      'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
    );
    expect(file.existsSync(), isTrue);
    final String source = file.readAsStringSync();
    expect(source.contains('NsdManager'), isTrue);
    expect(source.contains('_filehop._tcp'), isTrue);
    expect(source.contains('WifiP2pManager'), isFalse);
    expect(source.contains('WifiAwareManager'), isFalse);
    expect(source.contains('PeerFingerprint'), isFalse);
    expect(source.contains('TrustRecord'), isFalse);
    expect(source.contains('staticPublicKey'), isFalse);
    expect(source.contains('ServerSocket'), isFalse);
    expect(source.contains('WebSocket'), isFalse);
    expect(source.contains('HttpServer'), isFalse);
  });

  test('iOS LAN source uses NWBrowser and FileHop service type', () {
    final File file = locate('ios/Runner/FileHopLanDiscovery.swift');
    expect(file.existsSync(), isTrue);
    final String source = file.readAsStringSync();
    expect(source.contains('NWBrowser'), isTrue);
    expect(source.contains('_filehop._tcp'), isTrue);
    expect(source.contains('NWListener'), isFalse);
    expect(source.contains('PeerFingerprint'), isFalse);
    expect(source.contains('TrustRecord'), isFalse);
    expect(source.contains('WifiAware'), isFalse);
    expect(source.contains('WebSocket'), isFalse);
  });

  test('iOS Info.plist declares local network and FileHop Bonjour type', () {
    final File file = locate('ios/Runner/Info.plist');
    final String text = file.readAsStringSync();
    expect(text.contains('NSLocalNetworkUsageDescription'), isTrue);
    expect(text.contains('NSBonjourServices'), isTrue);
    expect(text.contains('_filehop._tcp'), isTrue);
  });

  test('Android manifest has multicast permission and not Nearby Wi-Fi', () {
    final File file = locate('android/app/src/main/AndroidManifest.xml');
    final String text = file.readAsStringSync();
    expect(text.contains('CHANGE_WIFI_MULTICAST_STATE'), isTrue);
    expect(text.contains('NEARBY_WIFI_DEVICES'), isFalse);
    expect(text.contains('ACCESS_FINE_LOCATION'), isFalse);
  });

  test('FileHopLanDiscovery.swift is in Runner Sources', () {
    final File project = locate('ios/Runner.xcodeproj/project.pbxproj');
    final String text = project.readAsStringSync();
    expect(text.contains('FileHopLanDiscovery.swift in Sources'), isTrue);
    final RegExp runnerSources = RegExp(
      r'97C146EA1CF9000F007C117D /\* Sources \*/ = \{.*?files = \((.*?)\);',
      dotAll: true,
    );
    final Match? match = runnerSources.firstMatch(text);
    expect(match, isNotNull);
    expect(match!.group(1)!.contains('FileHopLanDiscovery.swift'), isTrue);
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
