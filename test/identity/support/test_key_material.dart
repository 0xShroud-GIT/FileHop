import 'dart:typed_data';

import 'package:filehop/identity/generated_identity_material.dart';

import 'fingerprint_vector.dart';

/// TEST-ONLY deterministic private bytes. Not a real Curve25519 scalar.
/// Never copy these into evidence, logs, or export manifests.
const List<int> kTestOnlyPrivateKeyA = <int>[
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
  0x11,
];

const List<int> kTestOnlyPrivateKeyB = <int>[
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
  0x22,
];

GeneratedIdentityMaterial testMaterialA() {
  return GeneratedIdentityMaterial(
    staticPublicKeyBytes: hexToBytes(kVectorAPublicKeyHex),
    staticPrivateKeyBytes: kTestOnlyPrivateKeyA,
  );
}

GeneratedIdentityMaterial testMaterialB() {
  return GeneratedIdentityMaterial(
    staticPublicKeyBytes: hexToBytes(kVectorBPublicKeyHex),
    staticPrivateKeyBytes: kTestOnlyPrivateKeyB,
  );
}

Uint8List testPrivateA() => Uint8List.fromList(kTestOnlyPrivateKeyA);
