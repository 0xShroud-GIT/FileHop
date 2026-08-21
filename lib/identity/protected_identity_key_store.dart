import 'dart:typed_data';

import 'protected_key_reference.dart';
import 'protected_key_status.dart';

/// Protected identity-secret storage. Private bytes never enter SQLite.
///
/// Production implementations talk to Android Keystore / iOS Keychain through
/// the native bridge. The in-memory fake is test-only.
abstract class ProtectedIdentityKeyStore {
  Future<ProtectedKeyReference> store(Uint8List privateKeyBytes);

  /// Short-lived private-key access. Implementations must not cache the
  /// bytes globally. Best-effort overwrite of temporary buffers after [action]
  /// is not a perfect zeroization guarantee in Dart.
  Future<T> withPrivateKey<T>(
    ProtectedKeyReference reference,
    Future<T> Function(Uint8List privateKeyBytes) action,
  );

  /// Idempotent when the reference is already absent.
  Future<void> delete(ProtectedKeyReference reference);

  Future<ProtectedKeyStatus> status(ProtectedKeyReference reference);

  Future<bool> hasAnySecret();

  Future<void> deleteAllFileHopIdentitySecrets();
}
