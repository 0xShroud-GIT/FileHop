import 'dart:typed_data';

import '../../native_bridge/channel/native_bridge.dart';
import '../../native_bridge/contract/enums.dart';
import '../../native_bridge/contract/errors.dart';
import '../../native_bridge/contract/models.dart';
import '../errors.dart';
import '../protected_identity_key_store.dart';
import '../protected_key_reference.dart';
import '../protected_key_status.dart';

/// Production adapter. Talks to Android Keystore / iOS Keychain via the
/// existing native bridge. Not selected automatically in Arena tests.
class NativeProtectedIdentityKeyStore implements ProtectedIdentityKeyStore {
  NativeProtectedIdentityKeyStore(this._bridge);

  final NativeBridge _bridge;

  @override
  Future<ProtectedKeyReference> store(Uint8List privateKeyBytes) async {
    try {
      final NativeIdentitySecretReference stored = await _bridge
          .storeIdentitySecret(privateKeyBytes);
      return ProtectedKeyReference.parse(stored.reference);
    } on NativeBridgeException catch (error) {
      throw _map(error);
    }
  }

  @override
  Future<T> withPrivateKey<T>(
    ProtectedKeyReference reference,
    Future<T> Function(Uint8List privateKeyBytes) action,
  ) async {
    Uint8List? bytes;
    try {
      bytes = await _bridge.loadIdentitySecret(reference.value);
      return await action(bytes);
    } on NativeBridgeException catch (error) {
      throw _map(error);
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<void> delete(ProtectedKeyReference reference) async {
    try {
      await _bridge.deleteIdentitySecret(reference.value);
    } on NativeBridgeException catch (error) {
      throw _map(error);
    }
  }

  @override
  Future<ProtectedKeyStatus> status(ProtectedKeyReference reference) async {
    try {
      final NativeIdentitySecretStatus status = await _bridge
          .identitySecretStatus(reference.value);
      return _statusOf(status);
    } on NativeBridgeException catch (error) {
      throw _map(error);
    }
  }

  @override
  Future<bool> hasAnySecret() async {
    try {
      final NativeIdentitySecretPresence presence = await _bridge
          .identitySecretHasAny();
      return presence.any;
    } on NativeBridgeException catch (error) {
      throw _map(error);
    }
  }

  @override
  Future<void> deleteAllFileHopIdentitySecrets() async {
    try {
      await _bridge.deleteAllIdentitySecrets();
    } on NativeBridgeException catch (error) {
      throw _map(error);
    }
  }

  static ProtectedKeyStatus _statusOf(NativeIdentitySecretStatus status) {
    switch (status) {
      case NativeIdentitySecretStatus.present:
        return ProtectedKeyStatus.present;
      case NativeIdentitySecretStatus.absent:
        return ProtectedKeyStatus.absent;
      case NativeIdentitySecretStatus.missingCiphertext:
        return ProtectedKeyStatus.missingCiphertext;
      case NativeIdentitySecretStatus.missingWrappingKey:
        return ProtectedKeyStatus.missingWrappingKey;
      case NativeIdentitySecretStatus.corrupt:
        return ProtectedKeyStatus.corrupt;
      case NativeIdentitySecretStatus.unavailable:
        return ProtectedKeyStatus.unavailable;
      case NativeIdentitySecretStatus.unsupported:
        return ProtectedKeyStatus.unsupported;
      case NativeIdentitySecretStatus.unknown:
        return ProtectedKeyStatus.corrupt;
    }
  }

  static IdentityException _map(NativeBridgeException error) {
    switch (error.errorClass) {
      case NativeErrorClass.notFound:
        return const IdentityException(
          kind: IdentityFailureKind.identityKeyMissing,
          message: 'protected secret is missing',
        );
      case NativeErrorClass.corrupt:
        return const IdentityException(
          kind: IdentityFailureKind.identityStoreCorrupt,
          message: 'protected secret is unreadable',
        );
      case NativeErrorClass.unavailable:
        return const IdentityException(
          kind: IdentityFailureKind.identityStoreUnavailable,
          message: 'protected store is unavailable',
        );
      case NativeErrorClass.unsupported:
        return const IdentityException(
          kind: IdentityFailureKind.unsupportedKeyStorageVersion,
          message: 'protected store version is unsupported',
        );
      case NativeErrorClass.invalidArgument:
        return const IdentityException(
          kind: IdentityFailureKind.invalidArgument,
          message: 'invalid identity-secret argument',
        );
      case NativeErrorClass.invalidState:
        return const IdentityException(
          kind: IdentityFailureKind.identityAllocationExhausted,
          message: 'identity secret reference allocation exhausted',
        );
      default:
        return const IdentityException(
          kind: IdentityFailureKind.operationFailure,
          message: 'protected store operation failed',
        );
    }
  }
}
