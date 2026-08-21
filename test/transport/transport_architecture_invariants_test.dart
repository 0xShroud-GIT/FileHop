import 'dart:io';

import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transport layer source does not mention security identity keys', () {
    final Directory root = Directory('lib/transport');
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
      'schemaVersion',
      'WifiP2pManager',
      'WifiAwareManager',
      'NsdManager',
    ];
    for (final File file in files) {
      if (file.path.contains('/bridge/')) {
        continue;
      }
      final String source = file.readAsStringSync();
      for (final String token in forbidden) {
        expect(source.contains(token), isFalse, reason: '${file.path} $token');
      }
    }
  });

  test('qualification is independent of trust tokens', () {
    const TransportQualificationPolicy policy = TransportQualificationPolicy();
    expect(
      policy.allows(
        kind: TransportKind.wifiAware,
        local: TransportPlatform.android,
        remote: TransportPlatform.ios,
      ),
      isFalse,
    );
    expect(
      policy.allows(
        kind: TransportKind.lan,
        local: TransportPlatform.android,
        remote: TransportPlatform.ios,
      ),
      isTrue,
    );
  });

  test('only three v1 transport families exist', () {
    expect(TransportKind.values, hasLength(3));
    expect(TransportKind.values.toSet(), <TransportKind>{
      TransportKind.wifiAware,
      TransportKind.wifiDirect,
      TransportKind.lan,
    });
  });
}
