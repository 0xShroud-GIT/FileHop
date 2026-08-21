/// Curve25519 / Noise 25519 key sizes. FileHop does not implement the curve.
const int kFileHopStaticPublicKeyLength = 32;
const int kFileHopStaticPrivateKeyLength = 32;

/// Mission 05 at-rest wrapping scheme. Unknown versions fail closed.
const int kFileHopKeyStorageVersion = 1;
