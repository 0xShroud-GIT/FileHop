import '../domain/identity/display_name.dart';
import '../domain/identity/peer_fingerprint.dart';
import '../domain/peer/trust.dart';
import '../domain/state_machine/transition_authority.dart';
import '../persistence/errors.dart';
import '../persistence/records/persistence_records.dart';
import '../persistence/stores/filehop_stores.dart';
import '../persistence/tokens.dart';
import 'errors.dart';

/// Caller-asserted verification method. Mission 05 does not verify QR/SAS.
enum VerifiedTrustMethod { qr, sas }

/// Persistent fingerprint trust. Trust never implies content acceptance.
class TrustService {
  TrustService(this._stores, {int Function()? nowUtcMs})
    : _nowUtcMs = nowUtcMs ?? systemNowUtcMs;

  static int systemNowUtcMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  final FileHopStores _stores;
  final int Function() _nowUtcMs;

  Future<TrustState> getTrustState(PeerFingerprint fingerprint) async {
    final TrustRecordRow? row = await _read(fingerprint);
    if (row == null) {
      return TrustState.none;
    }
    return _stateOf(row);
  }

  Future<bool> isBlocked(PeerFingerprint fingerprint) async {
    return await getTrustState(fingerprint) == TrustState.blocked;
  }

  /// Records that QR or SAS verification has already succeeded.
  ///
  /// Not named `setTrusted` — the caller must assert a real verification method.
  Future<void> trustVerifiedPeer(
    PeerFingerprint fingerprint, {
    required VerifiedTrustMethod method,
  }) async {
    final TrustRecord current = await _current(fingerprint);
    try {
      current.apply(
        method == VerifiedTrustMethod.qr
            ? TrustEvent.verifyQr
            : TrustEvent.verifySas,
        authority: TransitionAuthority.localCommand,
      );
    } catch (_) {
      throw const TrustException(
        kind: TrustFailureKind.invalidTrustTransition,
        message: 'cannot persist TRUSTED from the current trust state',
      );
    }
    await _write(
      fingerprint: fingerprint,
      state: PersistTokens.trusted,
      method: method == VerifiedTrustMethod.qr
          ? PersistTokens.qr
          : PersistTokens.sas,
      existing: await _read(fingerprint),
    );
  }

  Future<void> blockPeer(PeerFingerprint fingerprint) async {
    final TrustRecord current = await _current(fingerprint);
    try {
      current.apply(
        TrustEvent.block,
        authority: TransitionAuthority.localCommand,
      );
    } catch (_) {
      throw const TrustException(
        kind: TrustFailureKind.invalidTrustTransition,
        message: 'cannot persist BLOCKED from the current trust state',
      );
    }
    await _write(
      fingerprint: fingerprint,
      state: PersistTokens.blocked,
      method: PersistTokens.userBlock,
      existing: await _read(fingerprint),
    );
  }

  /// BLOCKED → NONE. Does not restore a previous TRUSTED state.
  Future<void> unblockPeer(PeerFingerprint fingerprint) async {
    final TrustRecord current = await _current(fingerprint);
    try {
      current.apply(
        TrustEvent.unblock,
        authority: TransitionAuthority.localCommand,
      );
    } catch (_) {
      throw const TrustException(
        kind: TrustFailureKind.invalidTrustTransition,
        message: 'cannot unblock from the current trust state',
      );
    }
    await _deleteTrust(fingerprint);
  }

  /// Removes current peer metadata and trust. History rows are not rewritten.
  Future<void> forgetPeer(PeerFingerprint fingerprint) async {
    try {
      await _stores.deleteTrust(fingerprint.value);
      await _stores.deletePeerByFingerprint(fingerprint.value);
    } on PersistenceException catch (error) {
      throw TrustException(
        kind: TrustFailureKind.trustPersistenceFailure,
        message: error.message,
      );
    }
  }

  Future<void> rememberPeer({
    required PeerFingerprint fingerprint,
    DisplayName? displayName,
    List<String> lastCapabilities = const <String>[],
    int? lastSeenUtcMs,
  }) async {
    try {
      final PeerRecord? existing = await _stores.getPeerByFingerprint(
        fingerprint.value,
      );
      await _stores.upsertPeer(
        PeerRecord(
          peerId: existing?.peerId,
          fingerprint: fingerprint.value,
          lastKnownDisplayName:
              displayName?.value ?? existing?.lastKnownDisplayName,
          lastSeenUtcMs: lastSeenUtcMs ?? existing?.lastSeenUtcMs,
          lastCapabilities: lastCapabilities.isEmpty
              ? (existing?.lastCapabilities ?? const <String>[])
              : lastCapabilities,
        ),
      );
    } on PersistenceException catch (error) {
      throw TrustException(
        kind: TrustFailureKind.trustPersistenceFailure,
        message: error.message,
      );
    }
  }

  Future<TrustRecord> _current(PeerFingerprint fingerprint) async {
    final TrustRecordRow? row = await _read(fingerprint);
    if (row == null) {
      return TrustRecord.none(fingerprint);
    }
    return TrustRecord.rehydrate(
      fingerprint: fingerprint,
      state: _stateOf(row),
    );
  }

  Future<TrustRecordRow?> _read(PeerFingerprint fingerprint) async {
    try {
      return await _stores.getTrust(fingerprint.value);
    } on PersistenceException catch (error) {
      throw TrustException(
        kind: TrustFailureKind.trustPersistenceFailure,
        message: error.message,
      );
    }
  }

  Future<void> _write({
    required PeerFingerprint fingerprint,
    required String state,
    required String method,
    required TrustRecordRow? existing,
  }) async {
    final int now = _nowUtcMs();
    try {
      await _stores.putTrust(
        TrustRecordRow(
          fingerprint: fingerprint.value,
          state: state,
          verificationMethod: method,
          createdAtUtcMs: existing?.createdAtUtcMs ?? now,
          updatedAtUtcMs: now,
        ),
      );
    } on PersistenceException catch (error) {
      throw TrustException(
        kind: TrustFailureKind.trustPersistenceFailure,
        message: error.message,
      );
    }
  }

  Future<void> _deleteTrust(PeerFingerprint fingerprint) async {
    try {
      await _stores.deleteTrust(fingerprint.value);
    } on PersistenceException catch (error) {
      throw TrustException(
        kind: TrustFailureKind.trustPersistenceFailure,
        message: error.message,
      );
    }
  }

  static TrustState _stateOf(TrustRecordRow row) {
    if (row.state == PersistTokens.trusted) {
      return TrustState.trusted;
    }
    if (row.state == PersistTokens.blocked) {
      return TrustState.blocked;
    }
    throw const TrustException(
      kind: TrustFailureKind.trustPersistenceFailure,
      message: 'unknown persisted trust state',
    );
  }
}
