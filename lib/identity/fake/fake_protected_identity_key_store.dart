import 'dart:typed_data';

import '../constants.dart';
import '../errors.dart';
import '../protected_identity_key_store.dart';
import '../protected_key_reference.dart';
import '../protected_key_status.dart';

/// In-memory protected store for Arena A-tests. Never a production default.
class FakeProtectedIdentityKeyStore implements ProtectedIdentityKeyStore {
  FakeProtectedIdentityKeyStore();

  final Map<String, Uint8List> _secrets = <String, Uint8List>{};
  int _next = 1;

  int storeCallCount = 0;
  int deleteCallCount = 0;
  int deleteAllCallCount = 0;

  bool failStore = false;
  bool failDelete = false;
  bool failDeleteAll = false;
  bool unavailable = false;
  final Set<String> corruptReferences = <String>{};
  final Set<String> missingOnLoad = <String>{};

  /// Test-only: inject an orphaned secret without going through [store].
  ProtectedKeyReference injectOrphan(Uint8List privateKeyBytes) {
    _requireLength(privateKeyBytes);
    final ProtectedKeyReference reference = _nextReference();
    _secrets[reference.value] = Uint8List.fromList(privateKeyBytes);
    return reference;
  }

  @override
  Future<ProtectedKeyReference> store(Uint8List privateKeyBytes) async {
    storeCallCount += 1;
    _throwIfUnavailable();
    if (failStore) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'fake protected store refused store',
      );
    }
    _requireLength(privateKeyBytes);
    final ProtectedKeyReference reference = _nextReference();
    _secrets[reference.value] = Uint8List.fromList(privateKeyBytes);
    return reference;
  }

  @override
  Future<T> withPrivateKey<T>(
    ProtectedKeyReference reference,
    Future<T> Function(Uint8List privateKeyBytes) action,
  ) async {
    _throwIfUnavailable();
    if (corruptReferences.contains(reference.value)) {
      throw const IdentityException(
        kind: IdentityFailureKind.identityStoreCorrupt,
        message: 'protected secret is unreadable',
      );
    }
    if (missingOnLoad.contains(reference.value) ||
        !_secrets.containsKey(reference.value)) {
      throw const IdentityException(
        kind: IdentityFailureKind.identityKeyMissing,
        message: 'protected secret is missing',
      );
    }
    final Uint8List copy = Uint8List.fromList(_secrets[reference.value]!);
    try {
      return await action(copy);
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  @override
  Future<void> delete(ProtectedKeyReference reference) async {
    deleteCallCount += 1;
    _throwIfUnavailable();
    if (failDelete) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'fake protected store refused delete',
      );
    }
    _secrets.remove(reference.value);
    corruptReferences.remove(reference.value);
    missingOnLoad.remove(reference.value);
  }

  @override
  Future<ProtectedKeyStatus> status(ProtectedKeyReference reference) async {
    _throwIfUnavailable();
    if (corruptReferences.contains(reference.value)) {
      return ProtectedKeyStatus.corrupt;
    }
    if (missingOnLoad.contains(reference.value)) {
      return ProtectedKeyStatus.absent;
    }
    if (_secrets.containsKey(reference.value)) {
      return ProtectedKeyStatus.present;
    }
    return ProtectedKeyStatus.absent;
  }

  @override
  Future<bool> hasAnySecret() async {
    _throwIfUnavailable();
    return _secrets.isNotEmpty;
  }

  @override
  Future<void> deleteAllFileHopIdentitySecrets() async {
    deleteAllCallCount += 1;
    _throwIfUnavailable();
    if (failDeleteAll) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'fake protected store refused deleteAll',
      );
    }
    _secrets.clear();
    corruptReferences.clear();
    missingOnLoad.clear();
  }

  bool get isEmpty => _secrets.isEmpty;

  int get secretCount => _secrets.length;

  Set<String> get activeReferences => Set<String>.from(_secrets.keys);

  void _requireLength(Uint8List privateKeyBytes) {
    if (privateKeyBytes.length != kFileHopStaticPrivateKeyLength) {
      throw const IdentityException(
        kind: IdentityFailureKind.invalidArgument,
        message: 'private key must be exactly 32 bytes',
      );
    }
  }

  void _throwIfUnavailable() {
    if (unavailable) {
      throw const IdentityException(
        kind: IdentityFailureKind.identityStoreUnavailable,
        message: 'protected store is unavailable',
      );
    }
  }

  ProtectedKeyReference _nextReference() {
    final String hex = _next.toRadixString(16).padLeft(32, '0');
    _next += 1;
    return ProtectedKeyReference.parse('${ProtectedKeyReference.prefix}$hex');
  }
}
