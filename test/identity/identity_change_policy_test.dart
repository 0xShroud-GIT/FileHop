import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fingerprint_vector.dart';

void main() {
  test('same fingerprint is the same identity', () {
    final PeerFingerprint remembered = PeerFingerprint.parse(
      kVectorAFingerprint,
    );
    expect(
      IdentityChangePolicy.compare(
        remembered: remembered,
        authenticated: PeerFingerprint.parse(kVectorAFingerprint),
      ),
      AuthenticatedIdentityComparison.sameIdentity,
    );
  });

  test('different fingerprint is identityChanged', () {
    expect(
      IdentityChangePolicy.compare(
        remembered: PeerFingerprint.parse(kVectorAFingerprint),
        authenticated: PeerFingerprint.parse(kVectorBFingerprint),
      ),
      AuthenticatedIdentityComparison.identityChanged,
    );
  });

  test('matching display names are not used for identity comparison', () {
    final PeerIdentity a = PeerIdentity(
      fingerprint: PeerFingerprint.parse(kVectorAFingerprint),
      displayName: DisplayName.parse('Phone'),
    );
    final PeerIdentity b = PeerIdentity(
      fingerprint: PeerFingerprint.parse(kVectorBFingerprint),
      displayName: DisplayName.parse('Phone'),
    );
    expect(a == b, isFalse);
    expect(
      IdentityChangePolicy.compare(
        remembered: a.fingerprint,
        authenticated: b.fingerprint,
      ),
      AuthenticatedIdentityComparison.identityChanged,
    );
  });
}
