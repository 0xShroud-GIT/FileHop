import 'constants.dart';
import 'errors.dart';

/// Identity material supplied by a trusted crypto provider (Mission 11).
///
/// This is an input to storage. It is not the secure store.
/// Private bytes are excluded from equality, hashCode, and toString.
class GeneratedIdentityMaterial {
  GeneratedIdentityMaterial({
    required List<int> staticPublicKeyBytes,
    required List<int> staticPrivateKeyBytes,
  }) : _public = List<int>.unmodifiable(List<int>.from(staticPublicKeyBytes)),
       _private = List<int>.from(staticPrivateKeyBytes) {
    if (_public.length != kFileHopStaticPublicKeyLength) {
      throw const IdentityException(
        kind: IdentityFailureKind.invalidArgument,
        message: 'static public key must be exactly 32 bytes',
      );
    }
    if (_private.length != kFileHopStaticPrivateKeyLength) {
      throw const IdentityException(
        kind: IdentityFailureKind.invalidArgument,
        message: 'static private key must be exactly 32 bytes',
      );
    }
  }

  final List<int> _public;
  final List<int> _private;

  List<int> get staticPublicKeyBytes => _public;

  /// Short-lived private-key access. The callback receives a copy that is
  /// best-effort overwritten afterwards. Managed Dart memory cannot provide
  /// a perfect zeroization guarantee.
  T withPrivateKeyBytes<T>(T Function(List<int> privateKeyBytes) action) {
    final List<int> copy = List<int>.from(_private);
    try {
      return action(copy);
    } finally {
      for (int i = 0; i < copy.length; i++) {
        copy[i] = 0;
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! GeneratedIdentityMaterial) {
      return false;
    }
    if (other._public.length != _public.length) {
      return false;
    }
    for (int i = 0; i < _public.length; i++) {
      if (other._public[i] != _public[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_public);

  @override
  String toString() =>
      'GeneratedIdentityMaterial(publicKeyBytes: ${_public.length})';
}
