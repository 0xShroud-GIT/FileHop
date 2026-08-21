import 'dart:typed_data';

import '../domain/identity/peer_fingerprint.dart';
import '../domain/state_machine/invalid_state_transition.dart';
import '../persistence/errors.dart';
import '../persistence/records/persistence_records.dart';
import 'constants.dart';
import 'errors.dart';
import 'fingerprint_deriver.dart';
import 'generated_identity_material.dart';
import 'local_identity.dart';
import 'local_identity_load.dart';
import 'local_identity_metadata_store.dart';
import 'protected_identity_key_store.dart';
import 'protected_key_reference.dart';
import 'protected_key_status.dart';

/// Local FileHop identity lifecycle over metadata + protected secret store.
///
/// Does not generate Curve25519 keys. Does not rotate identity implicitly.
class LocalIdentityService {
  LocalIdentityService({
    required this._metadata,
    required this._secrets,
    int Function()? nowUtcMs,
    this._synchronizeCreateAfterPreflight,
    this._synchronizeCreateMetadataInsert,
  }) : _nowUtcMs = nowUtcMs ?? systemNowUtcMs;

  static int systemNowUtcMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  final LocalIdentityMetadataStore _metadata;
  final ProtectedIdentityKeyStore _secrets;
  final int Function() _nowUtcMs;

  /// Test-only rendezvous after verified [IdentityAbsent], before store.
  /// Not a production lock; concurrent creators may both pass preflight.
  final Future<void> Function()? _synchronizeCreateAfterPreflight;

  /// Test-only rendezvous before the authoritative singleton insert.
  final Future<void> Function()? _synchronizeCreateMetadataInsert;

  /// Authoritative metadata + protected-store classification.
  ///
  /// Used by [loadLocalIdentity], [persistNewIdentity] preflight, and reset
  /// verification. Inspection failure is never treated as [IdentityAbsent].
  Future<LocalIdentityLoad> inspectIdentityState() async {
    final LocalIdentityRecord? row;
    final bool hasSecret;
    try {
      row = await _metadata.read();
      // Confirmed-empty vs inspect-failed are distinct: [hasAnySecret]
      // must throw rather than return false when the store cannot be
      // inspected. A thrown [IdentityException] is fail-closed below.
      hasSecret = await _secrets.hasAnySecret();
    } on IdentityException catch (error) {
      return IdentityUnavailable(error.kind, message: error.message);
    } on PersistenceException catch (error) {
      return IdentityUnavailable(
        _mapPersistence(error),
        message: error.message,
      );
    }

    if (row == null) {
      if (hasSecret) {
        return const IdentityUnavailable(
          IdentityFailureKind.identityStorageInconsistent,
          message: 'orphaned protected identity secret without metadata',
        );
      }
      return const IdentityAbsent();
    }

    return _validatePresentMetadata(row);
  }

  Future<LocalIdentityLoad> loadLocalIdentity() => inspectIdentityState();

  Future<LocalIdentityLoad> _validatePresentMetadata(
    LocalIdentityRecord row,
  ) async {
    if (row.keyStorageVersion != kFileHopKeyStorageVersion) {
      return const IdentityUnavailable(
        IdentityFailureKind.unsupportedKeyStorageVersion,
        message: 'unsupported key-storage version',
      );
    }
    if (row.publicIdentityKey.length != kFileHopStaticPublicKeyLength) {
      return const IdentityUnavailable(
        IdentityFailureKind.identityCorrupt,
        message: 'stored public identity key has an invalid length',
      );
    }
    final PeerFingerprint stored;
    try {
      stored = PeerFingerprint.parse(row.identityFingerprint);
    } on DomainFormatException {
      return const IdentityUnavailable(
        IdentityFailureKind.identityCorrupt,
        message: 'stored identity fingerprint is not canonical',
      );
    }
    final PeerFingerprint derived = FingerprintDeriver.fromStaticPublicKey(
      row.publicIdentityKey,
    );
    if (derived != stored) {
      return const IdentityUnavailable(
        IdentityFailureKind.identityCorrupt,
        message: 'stored fingerprint does not match stored public key',
      );
    }
    final String? rawRef = row.wrappedKeyRef;
    if (rawRef == null) {
      return const IdentityUnavailable(
        IdentityFailureKind.identityCorrupt,
        message: 'local identity is missing a protected-key reference',
      );
    }
    final ProtectedKeyReference reference;
    try {
      reference = ProtectedKeyReference.parse(rawRef);
    } on IdentityException {
      return const IdentityUnavailable(
        IdentityFailureKind.identityCorrupt,
        message: 'stored protected-key reference is invalid',
      );
    }

    final ProtectedKeyStatus status;
    try {
      status = await _secrets.status(reference);
    } on IdentityException catch (error) {
      return IdentityUnavailable(error.kind, message: error.message);
    }

    switch (status) {
      case ProtectedKeyStatus.present:
        return IdentityAvailable(
          LocalIdentity(
            staticPublicKeyBytes: row.publicIdentityKey,
            fingerprint: stored,
            createdAtUtcMs: row.createdAtUtcMs,
            keyStorageVersion: row.keyStorageVersion,
            protectedKeyReference: reference,
          ),
        );
      case ProtectedKeyStatus.absent:
        return const IdentityUnavailable(
          IdentityFailureKind.identityKeyMissing,
          message:
              'identity metadata exists but the protected secret is missing',
        );
      case ProtectedKeyStatus.missingCiphertext:
      case ProtectedKeyStatus.missingWrappingKey:
      case ProtectedKeyStatus.corrupt:
        return const IdentityUnavailable(
          IdentityFailureKind.identityStoreCorrupt,
          message: 'protected identity secret is unreadable',
        );
      case ProtectedKeyStatus.unavailable:
        return const IdentityUnavailable(
          IdentityFailureKind.identityStoreUnavailable,
          message: 'protected identity store is unavailable',
        );
      case ProtectedKeyStatus.unsupported:
        return const IdentityUnavailable(
          IdentityFailureKind.unsupportedKeyStorageVersion,
          message: 'protected identity secret uses an unsupported version',
        );
    }
  }

  Future<LocalIdentity> persistNewIdentity(
    GeneratedIdentityMaterial material,
  ) async {
    await _requireVerifiedIdentityAbsent();
    final Future<void> Function()? afterPreflight =
        _synchronizeCreateAfterPreflight;
    if (afterPreflight != null) {
      await afterPreflight();
    }

    final PeerFingerprint fingerprint = FingerprintDeriver.fromStaticPublicKey(
      material.staticPublicKeyBytes,
    );
    final ProtectedKeyReference reference = await material
        .withPrivateKeyBytes<Future<ProtectedKeyReference>>((
          List<int> privateKeyBytes,
        ) async {
          final Uint8List temporary = Uint8List.fromList(privateKeyBytes);
          try {
            return await _secrets.store(temporary);
          } finally {
            temporary.fillRange(0, temporary.length, 0);
          }
        });

    final Future<void> Function()? synchronize =
        _synchronizeCreateMetadataInsert;
    if (synchronize != null) {
      await synchronize();
    }
    try {
      await _metadata.insertIfAbsent(
        LocalIdentityRecord(
          publicIdentityKey: List<int>.from(material.staticPublicKeyBytes),
          identityFingerprint: fingerprint.value,
          wrappedKeyRef: reference.value,
          keyStorageVersion: kFileHopKeyStorageVersion,
          createdAtUtcMs: _nowUtcMs(),
        ),
      );
    } on PersistenceException catch (error) {
      if (error.kind == PersistenceFailureKind.constraintViolation) {
        await _cleanupNewSecret(
          reference,
          IdentityFailureKind.identityAlreadyExists,
        );
        throw const IdentityException(
          kind: IdentityFailureKind.identityAlreadyExists,
          message: 'FileHop local identity already exists',
        );
      }
      await _cleanupNewSecret(reference, IdentityFailureKind.operationFailure);
      throw IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'failed to persist local identity metadata',
      );
    } catch (error) {
      await _cleanupNewSecret(reference, IdentityFailureKind.operationFailure);
      if (error is IdentityException) {
        rethrow;
      }
      throw IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'failed to persist local identity metadata',
      );
    }

    // The metadata insert above is the commit point. After it succeeds, a
    // transient read/Keychain/Keystore inspection failure must not delete the
    // protected secret while leaving committed metadata behind. Preserve both
    // resources and fail closed so a later load can recover naturally.
    final LocalIdentityLoad reloaded = await loadLocalIdentity();
    if (reloaded is IdentityAvailable) {
      return reloaded.identity;
    }
    if (reloaded is IdentityAbsent) {
      // Metadata genuinely vanished after the commit. No durable row owns the
      // new secret, so cleaning up this attempt's secret is still safe.
      await _cleanupNewSecret(
        reference,
        IdentityFailureKind.identityStorageInconsistent,
      );
      throw const IdentityException(
        kind: IdentityFailureKind.identityStorageInconsistent,
        message: 'identity metadata did not reload after persist',
      );
    }
    final IdentityUnavailable unavailable = reloaded as IdentityUnavailable;
    throw IdentityException(
      kind: unavailable.kind,
      message:
          unavailable.message ?? 'persisted identity could not be verified',
    );
  }

  /// Creation may proceed only after the complete identity-storage state is
  /// [IdentityAbsent]. This is a security-state check, not a lock.
  Future<void> _requireVerifiedIdentityAbsent() async {
    final LocalIdentityLoad state = await inspectIdentityState();
    switch (state) {
      case IdentityAbsent():
        return;
      case IdentityAvailable():
        throw const IdentityException(
          kind: IdentityFailureKind.identityAlreadyExists,
          message: 'FileHop local identity already exists',
        );
      case IdentityUnavailable(:final IdentityFailureKind kind, :final message):
        throw IdentityException(
          kind: kind,
          message: message ?? 'identity storage is not absent',
        );
    }
  }

  Future<void> resetLocalIdentity() async {
    IdentityFailureKind? secretFailure;
    IdentityFailureKind? metadataFailure;
    try {
      await _secrets.deleteAllFileHopIdentitySecrets();
    } on IdentityException catch (error) {
      secretFailure = error.kind;
    } catch (_) {
      secretFailure = IdentityFailureKind.operationFailure;
    }
    try {
      await _metadata.delete();
    } on PersistenceException {
      metadataFailure = IdentityFailureKind.operationFailure;
    } on IdentityException catch (error) {
      metadataFailure = error.kind;
    } catch (_) {
      metadataFailure = IdentityFailureKind.operationFailure;
    }
    if (secretFailure != null || metadataFailure != null) {
      throw IdentityException(
        kind: IdentityFailureKind.identityCleanupFailed,
        message: 'identity reset did not fully complete',
        causeKind: secretFailure ?? metadataFailure,
      );
    }
    final LocalIdentityLoad after = await loadLocalIdentity();
    if (after is! IdentityAbsent) {
      throw const IdentityException(
        kind: IdentityFailureKind.identityStorageInconsistent,
        message: 'identity reset left storage inconsistent',
      );
    }
  }

  Future<void> _cleanupNewSecret(
    ProtectedKeyReference reference,
    IdentityFailureKind original,
  ) async {
    try {
      await _secrets.delete(reference);
    } catch (_) {
      throw IdentityException(
        kind: IdentityFailureKind.identityCleanupFailed,
        message:
            'identity creation failed and protected-secret cleanup also failed',
        causeKind: original,
      );
    }
  }

  static IdentityFailureKind _mapPersistence(PersistenceException error) {
    switch (error.kind) {
      case PersistenceFailureKind.decodeFailure:
        return IdentityFailureKind.identityCorrupt;
      case PersistenceFailureKind.openFailure:
      case PersistenceFailureKind.operationFailure:
        return IdentityFailureKind.operationFailure;
      case PersistenceFailureKind.schemaMismatch:
      case PersistenceFailureKind.migrationFailure:
        return IdentityFailureKind.identityStorageInconsistent;
      case PersistenceFailureKind.constraintViolation:
      case PersistenceFailureKind.invalidArgument:
        return IdentityFailureKind.invalidArgument;
    }
  }
}
