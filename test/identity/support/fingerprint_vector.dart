/// TEST-ONLY public-key fingerprint vector.
///
/// Expected SHA-256 and Base32 values were produced independently in Arena
/// with Python `hashlib.sha256` + `base64.b32encode` (RFC 4648, padding
/// stripped). They are literal fixtures, not recomputed by production Dart.
///
/// These are not real FileHop device keys. No private key is included.
library;

const String kVectorAPublicKeyHex =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
const String kVectorASha256Hex =
    'ae216c2ef5247a3782c135efa279a3e4cdc61094270f5d2be58c6204b7a612c9';
const String kVectorAFingerprint =
    'VYQWYLXVER5DPAWBGXX2E6ND4TG4MEEUE4HV2K7FRRRAJN5GCLEQ';

const String kVectorBPublicKeyHex =
    '2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40';
const String kVectorBSha256Hex =
    '7eee5800ddcd3b3cc9fd047831cd8536e3c3f57f44d746f515da93f048ee9e91';
const String kVectorBFingerprint =
    'P3XFQAG5ZU5TZSP5AR4DDTMFG3R4H5L7ITLUN5IV3KJ7ASHOT2IQ';

List<int> hexToBytes(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('hex length must be even');
  }
  final List<int> out = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
