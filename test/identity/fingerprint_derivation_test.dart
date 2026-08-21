import 'package:filehop/domain/domain.dart';
import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/fingerprint_deriver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fingerprint_vector.dart';

void main() {
  test('fixed public key produces the independent SHA-256 digest', () {
    expect(
      FingerprintDeriver.sha256Hex(hexToBytes(kVectorAPublicKeyHex)),
      kVectorASha256Hex,
    );
    expect(
      FingerprintDeriver.sha256Hex(hexToBytes(kVectorBPublicKeyHex)),
      kVectorBSha256Hex,
    );
  });

  test(
    'fixed public key produces the independent Base32-no-pad fingerprint',
    () {
      expect(
        FingerprintDeriver.fromStaticPublicKey(hexToBytes(kVectorAPublicKeyHex))
            .value,
        kVectorAFingerprint,
      );
      expect(
        FingerprintDeriver.fromStaticPublicKey(hexToBytes(kVectorBPublicKeyHex))
            .value,
        kVectorBFingerprint,
      );
      expect(kVectorAFingerprint, hasLength(PeerFingerprint.canonicalLength));
      expect(kVectorBFingerprint, hasLength(PeerFingerprint.canonicalLength));
    },
  );

  test('invalid public-key length is rejected', () {
    expect(
      () => FingerprintDeriver.fromStaticPublicKey(<int>[1, 2, 3]),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.invalidArgument,
        ),
      ),
    );
    expect(
      () => FingerprintDeriver.fromStaticPublicKey(List<int>.filled(33, 1)),
      throwsA(isA<IdentityException>()),
    );
  });

  test('display-name change does not change the fingerprint', () {
    final PeerFingerprint fingerprint = FingerprintDeriver.fromStaticPublicKey(
      hexToBytes(kVectorAPublicKeyHex),
    );
    final PeerIdentity first = PeerIdentity(
      fingerprint: fingerprint,
      displayName: DisplayName.parse('Phone'),
    );
    final PeerIdentity renamed = first.withDisplayName(
      DisplayName.parse('Kitchen tablet'),
    );
    expect(renamed.fingerprint, fingerprint);
    expect(renamed.fingerprint.value, kVectorAFingerprint);
    expect(first, renamed);
  });
}
