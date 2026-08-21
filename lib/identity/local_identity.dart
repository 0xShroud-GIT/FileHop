import '../domain/identity/peer_fingerprint.dart';
import 'protected_key_reference.dart';

/// Public local identity. Private key bytes are never a long-lived property.
class LocalIdentity {
  LocalIdentity({
    required List<int> staticPublicKeyBytes,
    required this.fingerprint,
    required this.createdAtUtcMs,
    required this.keyStorageVersion,
    required this.protectedKeyReference,
  }) : staticPublicKeyBytes = List<int>.unmodifiable(
         List<int>.from(staticPublicKeyBytes),
       );

  final List<int> staticPublicKeyBytes;
  final PeerFingerprint fingerprint;
  final int createdAtUtcMs;
  final int keyStorageVersion;
  final ProtectedKeyReference protectedKeyReference;
}
