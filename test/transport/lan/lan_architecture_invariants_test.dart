import 'dart:io';

import 'package:filehop/transport/lan/lan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared LAN sources do not mention native radios or identity keys', () {
    final Directory root = Directory('lib/transport/lan');
    final List<File> files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    const List<String> forbidden = <String>[
      'PeerFingerprint',
      'staticPublicKey',
      'privateKey',
      'TrustRecord',
      'TRUSTED',
      'BLOCKED',
      'peerSessionId',
      'share.files',
      'screen.send',
      'NsdManager',
      'WifiP2pManager',
      'WifiAwareManager',
      'NsdManager',
      'NWBrowser',
      'WebSocket',
      'HttpServer',
    ];
    for (final File file in files) {
      final String source = file.readAsStringSync();
      for (final String token in forbidden) {
        expect(source.contains(token), isFalse, reason: '${file.path} $token');
      }
    }
  });

  test('exact FileHop service type is frozen', () {
    expect(kFileHopLanServiceType, '_filehop._tcp');
    expect(kFileHopLanDiscoverySchemaVersion, 1);
    expect(kFileHopLanTxtVersionKey, 'v');
    expect(kFileHopLanTxtInstanceKey, 'i');
  });

  test('shared LAN adapter kind is lan', () {
    final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend();
    final LanTransportAdapter adapter = LanTransportAdapter(backend: backend);
    expect(adapter.kind.name, 'lan');
  });
}
