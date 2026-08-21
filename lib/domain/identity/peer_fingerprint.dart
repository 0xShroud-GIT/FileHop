import '../state_machine/invalid_state_transition.dart';

/// Canonical FileHop security identifier.
///
/// `peerFingerprint = BASE32_NOPAD(SHA256(staticPublicKeyBytes))`
///
/// Canonical representation (D-05-01):
/// - RFC 4648 Base32 alphabet `A-Z2-7` only
/// - uppercase
/// - no padding
/// - no whitespace
/// - fixed length [canonicalLength] (SHA-256 digest)
///
/// Security comparisons use the full canonical string. Parse never
/// normalizes malformed input (no trim, no case-fold, no pad-strip).
class PeerFingerprint {
  PeerFingerprint._(this.value);

  /// SHA-256 is 256 bits; Base32 encodes 5 bits/char → 52 characters.
  static const int canonicalLength = 52;

  static final RegExp _canonical = RegExp(r'^[A-Z2-7]{52}$');

  final String value;

  factory PeerFingerprint.parse(String raw) {
    if (raw.length != canonicalLength || !_canonical.hasMatch(raw)) {
      throw const DomainFormatException(
        'peer fingerprint must be a canonical FileHop fingerprint',
      );
    }
    return PeerFingerprint._(raw);
  }

  @override
  bool operator ==(Object other) =>
      other is PeerFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
