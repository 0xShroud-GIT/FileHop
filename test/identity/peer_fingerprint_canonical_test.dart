import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fingerprint_vector.dart';

void main() {
  test('canonical fingerprints parse and compare by full string', () {
    final PeerFingerprint a = PeerFingerprint.parse(kVectorAFingerprint);
    final PeerFingerprint again = PeerFingerprint.parse(kVectorAFingerprint);
    final PeerFingerprint b = PeerFingerprint.parse(kVectorBFingerprint);
    expect(a, again);
    expect(a == b, isFalse);
    expect(a.value, kVectorAFingerprint);
  });

  test('malformed fingerprints are rejected without normalization', () {
    final List<String> malformed = <String>[
      '',
      kVectorAFingerprint.toLowerCase(),
      '${kVectorAFingerprint}A',
      kVectorAFingerprint.substring(1),
      '$kVectorAFingerprint=',
      ' $kVectorAFingerprint',
      '$kVectorAFingerprint ',
      kVectorAFingerprint.replaceRange(0, 1, '1'),
      kVectorAFingerprint.replaceRange(0, 1, '8'),
      'OPAQUEFINGERPRINTNOTANIPORSSID01',
    ];
    for (final String raw in malformed) {
      expect(
        () => PeerFingerprint.parse(raw),
        throwsA(isA<DomainFormatException>()),
        reason: raw,
      );
    }
  });
}
