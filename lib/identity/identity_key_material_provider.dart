import 'generated_identity_material.dart';

/// Produces FileHop static identity key material.
///
/// Production generation is owned by Mission 11 (`snow` / reviewed Curve25519).
/// Mission 05 must not implement Curve25519 or a fake production generator.
abstract class IdentityKeyMaterialProvider {
  Future<GeneratedIdentityMaterial> generate();
}
