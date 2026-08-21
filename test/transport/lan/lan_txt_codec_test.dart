import 'dart:convert';

import 'package:filehop/transport/lan/lan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_fixtures.dart';

void main() {
  const LanTxtCodec codec = LanTxtCodec();

  test('valid v1 advertisement parses', () {
    final LanTxtFields fields = codec.parseStringMap(
      codec.encodeV1(lanId(kLanIdB)),
    );
    expect(fields.discoveryVersion, kFileHopLanDiscoverySchemaVersion);
    expect(fields.instanceId.value, kLanIdB);
    expect(fields.ignoredUnknown, isEmpty);
  });

  test('canonical TXT serialization sorts keys', () {
    final List<MapEntry<String, String>> sorted = codec.encodeV1Sorted(
      lanId(kLanIdA),
    );
    expect(sorted.map((MapEntry<String, String> e) => e.key).toList(), <String>[
      'i',
      'v',
    ]);
    expect(sorted.first.value, kLanIdA);
    expect(sorted.last.value, '1');
  });

  test('v1 encoder contains no secret identity fields', () {
    final Map<String, String> encoded = codec.encodeV1(lanId(kLanIdA));
    expect(encoded.keys.toSet(), <String>{'v', 'i'});
    const List<String> forbidden = <String>[
      'fingerprint',
      'publicKey',
      'privateKey',
      'trust',
      'sas',
      'qr',
      'token',
      'tlsKey',
      'peerSessionId',
    ];
    for (final String key in forbidden) {
      expect(encoded.containsKey(key), isFalse);
      expect(encoded.values, isNot(contains(key)));
    }
  });

  test('missing version rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{'i': kLanIdB}),
      throwsA(
        isA<LanDiscoveryException>().having(
          (LanDiscoveryException e) => e.kind,
          'kind',
          LanDiscoveryFailureKind.malformedDiscoveryRecord,
        ),
      ),
    );
  });

  test('malformed version rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{'v': '999', 'i': kLanIdB}),
      throwsA(
        isA<LanDiscoveryException>().having(
          (LanDiscoveryException e) => e.kind,
          'kind',
          LanDiscoveryFailureKind.unsupportedDiscoveryVersion,
        ),
      ),
    );
  });

  test('missing instance id rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{'v': '1'}),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('uppercase instance id rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{
        'v': '1',
        'i': kLanIdB.toUpperCase(),
      }),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('wrong-length instance id rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{'v': '1', 'i': 'abcd'}),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('non-hex instance id rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{
        'v': '1',
        'i': 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
      }),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('unknown bounded TXT key is ignored', () {
    final LanTxtFields fields = codec.parseStringMap(<String, String>{
      'v': '1',
      'i': kLanIdB,
      'futureHint': 'something',
    });
    expect(fields.instanceId.value, kLanIdB);
    expect(fields.ignoredUnknown['futureHint'], 'something');
  });

  test('too many TXT keys rejected', () {
    final Map<String, String> fields = <String, String>{'v': '1', 'i': kLanIdB};
    for (int n = 0; n < 7; n++) {
      fields['k$n'] = 'x';
    }
    expect(
      () => codec.parseStringMap(fields),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('oversized TXT key rejected', () {
    expect(
      () => codec.parsePairs(<MapEntry<String, List<int>>>[
        MapEntry<String, List<int>>('v', utf8.encode('1')),
        MapEntry<String, List<int>>('i', utf8.encode(kLanIdB)),
        MapEntry<String, List<int>>('k' * 33, utf8.encode('x')),
      ]),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('oversized TXT value rejected', () {
    expect(
      () => codec.parseStringMap(<String, String>{
        'v': '1',
        'i': kLanIdB,
        'x': 'y' * 129,
      }),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('oversized TXT payload rejected', () {
    expect(
      () => codec.parsePairs(<MapEntry<String, List<int>>>[
        MapEntry<String, List<int>>('v', utf8.encode('1')),
        MapEntry<String, List<int>>('i', utf8.encode(kLanIdB)),
        MapEntry<String, List<int>>('a', List<int>.filled(128, 65)),
        MapEntry<String, List<int>>('b', List<int>.filled(128, 65)),
        MapEntry<String, List<int>>('c', List<int>.filled(128, 65)),
        MapEntry<String, List<int>>('d', List<int>.filled(128, 65)),
      ]),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('duplicate TXT keys fail closed', () {
    expect(
      () => codec.parsePairs(<MapEntry<String, List<int>>>[
        MapEntry<String, List<int>>('v', utf8.encode('1')),
        MapEntry<String, List<int>>('i', utf8.encode(kLanIdB)),
        MapEntry<String, List<int>>('v', utf8.encode('1')),
      ]),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('empty data rejected', () {
    expect(
      () => codec.parsePairs(const <MapEntry<String, List<int>>>[]),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('non-UTF8 value rejected', () {
    expect(
      () => codec.parsePairs(<MapEntry<String, List<int>>>[
        MapEntry<String, List<int>>('v', utf8.encode('1')),
        MapEntry<String, List<int>>('i', <int>[0xff, 0xfe]),
      ]),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('TXT snapshots are unmodifiable', () {
    final LanTxtFields fields = codec.parseStringMap(<String, String>{
      'v': '1',
      'i': kLanIdB,
      'x': 'y',
    });
    expect(
      () => fields.ignoredUnknown['z'] = 'no',
      throwsA(isA<UnsupportedError>()),
    );
  });
}
