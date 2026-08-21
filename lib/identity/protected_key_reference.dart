import 'errors.dart';

/// Opaque handle to platform-protected private-key material.
///
/// Contains no private key. Format is platform-independent:
/// `fhik1.` + 32 lowercase hex characters.
class ProtectedKeyReference {
  ProtectedKeyReference._(this.value);

  static const int version = 1;
  static const String prefix = 'fhik1.';
  static const int hexLength = 32;
  static final RegExp _canonical = RegExp(r'^fhik1\.[0-9a-f]{32}$');

  final String value;

  factory ProtectedKeyReference.parse(String raw) {
    if (!_canonical.hasMatch(raw)) {
      throw const IdentityException(
        kind: IdentityFailureKind.invalidArgument,
        message: 'protected-key reference is not a supported FileHop reference',
      );
    }
    return ProtectedKeyReference._(raw);
  }

  @override
  bool operator ==(Object other) =>
      other is ProtectedKeyReference && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
