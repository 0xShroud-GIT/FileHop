import 'package:crypto/crypto.dart';

import '../domain/identity/peer_fingerprint.dart';
import 'base32_nopad.dart';
import 'constants.dart';
import 'errors.dart';

/// Derives the canonical FileHop fingerprint from static public-key bytes.
///
/// `peerFingerprint = BASE32_NOPAD(SHA256(staticPublicKeyBytes))`
///
/// Does not implement Curve25519. The caller supplies already-generated
/// public-key bytes from a future Mission 11 crypto provider.
abstract final class FingerprintDeriver {
  static PeerFingerprint fromStaticPublicKey(List<int> staticPublicKeyBytes) {
    if (staticPublicKeyBytes.length != kFileHopStaticPublicKeyLength) {
      throw const IdentityException(
        kind: IdentityFailureKind.invalidArgument,
        message: 'static public key must be exactly 32 bytes',
      );
    }
    final Digest digest = sha256.convert(staticPublicKeyBytes);
    return PeerFingerprint.parse(Rfc4648Base32NoPad.encode(digest.bytes));
  }

  static String sha256Hex(List<int> staticPublicKeyBytes) {
    if (staticPublicKeyBytes.length != kFileHopStaticPublicKeyLength) {
      throw const IdentityException(
        kind: IdentityFailureKind.invalidArgument,
        message: 'static public key must be exactly 32 bytes',
      );
    }
    return sha256.convert(staticPublicKeyBytes).toString();
  }
}
