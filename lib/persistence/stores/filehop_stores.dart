import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

import '../errors.dart';
import '../path_guard.dart';
import '../persist_codec.dart';
import '../records/persistence_records.dart';
import '../tokens.dart';
import '../write_error.dart';

class FileHopStores {
  FileHopStores(this._db);

  final DatabaseExecutor _db;

  Future<void> upsertLocalIdentity(LocalIdentityRecord record) async {
    await persistWrite('upsertLocalIdentity', () async {
      await _db.insert(
        'local_identity',
        _localIdentityMap(record),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Create-only singleton insert. Never replaces an existing identity row.
  Future<void> insertLocalIdentityIfAbsent(LocalIdentityRecord record) async {
    await persistWrite('insertLocalIdentityIfAbsent', () async {
      await _db.insert(
        'local_identity',
        _localIdentityMap(record),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Map<String, Object?> _localIdentityMap(LocalIdentityRecord record) {
    return <String, Object?>{
      'id': 1,
      'public_identity_key': Uint8List.fromList(record.publicIdentityKey),
      'identity_fingerprint': PersistCodec.writeFingerprint(
        record.identityFingerprint,
        'identity fingerprint',
      ),
      'wrapped_key_ref': record.wrappedKeyRef,
      'key_storage_version': record.keyStorageVersion,
      'created_at_utc_ms': record.createdAtUtcMs,
    };
  }

  Future<LocalIdentityRecord?> getLocalIdentity() async {
    final List<Map<String, Object?>> rows = await _db.query('local_identity');
    if (rows.isEmpty) {
      return null;
    }
    return _localIdentityFrom(rows.first);
  }

  Future<void> deleteLocalIdentity() {
    return persistWrite('deleteLocalIdentity', () {
      return _db.delete(
        'local_identity',
        where: 'id = ?',
        whereArgs: <Object>[1],
      );
    });
  }

  LocalIdentityRecord _localIdentityFrom(Map<String, Object?> row) {
    return LocalIdentityRecord(
      publicIdentityKey: PersistCodec.requireBytes(row, 'public_identity_key'),
      identityFingerprint: PersistCodec.decodeFingerprint(
        PersistCodec.requireString(row, 'identity_fingerprint'),
        'identity fingerprint',
      ),
      wrappedKeyRef: PersistCodec.optionalString(row, 'wrapped_key_ref'),
      keyStorageVersion: PersistCodec.requireInt(row, 'key_storage_version'),
      createdAtUtcMs: PersistCodec.requireInt(row, 'created_at_utc_ms'),
    );
  }

  Future<PeerRecord> insertPeer(PeerRecord record) {
    return persistWrite('insertPeer', () async {
      final int id = await _db.insert('peers', _peerMap(record));
      return PeerRecord(
        peerId: id,
        fingerprint: record.fingerprint,
        lastKnownDisplayName: record.lastKnownDisplayName,
        lastSeenUtcMs: record.lastSeenUtcMs,
        lastCapabilities: record.lastCapabilities,
      );
    });
  }

  Future<void> upsertPeer(PeerRecord record) {
    return persistWrite('upsertPeer', () {
      return _db.insert(
        'peers',
        _peerMap(record),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Map<String, Object?> _peerMap(PeerRecord record) {
    return <String, Object?>{
      if (record.peerId != null) 'peer_id': record.peerId,
      'fingerprint': PersistCodec.writeFingerprint(
        record.fingerprint,
        'peer fingerprint',
      ),
      'last_known_display_name': record.lastKnownDisplayName,
      'last_seen_utc_ms': record.lastSeenUtcMs,
      'last_capabilities_json': PersistCodec.encodeCapabilities(
        record.lastCapabilities,
      ),
    };
  }

  Future<PeerRecord?> getPeerByFingerprint(String fingerprint) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'peers',
      where: 'fingerprint = ?',
      whereArgs: <Object>[fingerprint],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _peerFrom(rows.first);
  }

  Future<void> deletePeerByFingerprint(String fingerprint) {
    return persistWrite('deletePeer', () {
      return _db.delete(
        'peers',
        where: 'fingerprint = ?',
        whereArgs: <Object>[fingerprint],
      );
    });
  }

  PeerRecord _peerFrom(Map<String, Object?> row) {
    return PeerRecord(
      peerId: PersistCodec.requireInt(row, 'peer_id'),
      fingerprint: PersistCodec.decodeFingerprint(
        PersistCodec.requireString(row, 'fingerprint'),
        'peer fingerprint',
      ),
      lastKnownDisplayName: PersistCodec.optionalString(
        row,
        'last_known_display_name',
      ),
      lastSeenUtcMs: PersistCodec.optionalInt(row, 'last_seen_utc_ms'),
      lastCapabilities: PersistCodec.decodeCapabilitiesJson(
        row['last_capabilities_json'],
      ),
    );
  }

  Future<void> putTrust(TrustRecordRow record) {
    return persistWrite('putTrust', () {
      return _db.insert('trust_records', <String, Object?>{
        'fingerprint': PersistCodec.writeFingerprint(
          record.fingerprint,
          'trust fingerprint',
        ),
        'state': PersistCodec.writeToken(record.state, const <String>{
          PersistTokens.trusted,
          PersistTokens.blocked,
        }, 'trust state'),
        'verification_method': PersistCodec.writeToken(
          record.verificationMethod,
          const <String>{
            PersistTokens.qr,
            PersistTokens.sas,
            PersistTokens.userBlock,
          },
          'verification method',
        ),
        'created_at_utc_ms': record.createdAtUtcMs,
        'updated_at_utc_ms': record.updatedAtUtcMs,
        'local_note': record.localNote,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<TrustRecordRow?> getTrust(String fingerprint) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'trust_records',
      where: 'fingerprint = ?',
      whereArgs: <Object>[fingerprint],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _trustFrom(rows.first);
  }

  TrustRecordRow _trustFrom(Map<String, Object?> row) {
    return TrustRecordRow(
      fingerprint: PersistCodec.decodeFingerprint(
        PersistCodec.requireString(row, 'fingerprint'),
        'trust fingerprint',
      ),
      state: PersistCodec.decodeToken(row['state'], const <String>{
        PersistTokens.trusted,
        PersistTokens.blocked,
      }, 'trust state'),
      verificationMethod: PersistCodec.decodeToken(
        row['verification_method'],
        const <String>{
          PersistTokens.qr,
          PersistTokens.sas,
          PersistTokens.userBlock,
        },
        'verification method',
      ),
      createdAtUtcMs: PersistCodec.requireInt(row, 'created_at_utc_ms'),
      updatedAtUtcMs: PersistCodec.requireInt(row, 'updated_at_utc_ms'),
      localNote: PersistCodec.optionalString(row, 'local_note'),
    );
  }

  Future<void> deleteTrust(String fingerprint) {
    return persistWrite('deleteTrust', () {
      return _db.delete(
        'trust_records',
        where: 'fingerprint = ?',
        whereArgs: <Object>[fingerprint],
      );
    });
  }

  Future<void> insertShareSession(ShareSessionRecord record) {
    return persistWrite('insertShareSession', () {
      return _db.insert('share_sessions', <String, Object?>{
        'share_session_id': PersistCodec.writeLogicalId(
          record.shareSessionId,
          'shareSessionId',
        ),
        'peer_fingerprint': PersistCodec.writeFingerprint(
          record.peerFingerprint,
          'share fingerprint',
        ),
        'direction': PersistCodec.writeToken(record.direction, const <String>{
          PersistTokens.outgoing,
          PersistTokens.incoming,
        }, 'direction'),
        'created_at_utc_ms': record.createdAtUtcMs,
        'terminal_result': record.terminalResult == null
            ? null
            : PersistCodec.writeToken(
                record.terminalResult!,
                PersistTokens.shareTerminals,
                'share terminal',
              ),
      });
    });
  }

  Future<ShareSessionRecord?> getShareSession(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'share_sessions',
      where: 'share_session_id = ?',
      whereArgs: <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _shareFrom(rows.first);
  }

  ShareSessionRecord _shareFrom(Map<String, Object?> row) {
    final String? terminal = PersistCodec.optionalString(
      row,
      'terminal_result',
    );
    return ShareSessionRecord(
      shareSessionId: PersistCodec.decodeLogicalId(
        row['share_session_id'],
        'shareSessionId',
      ),
      peerFingerprint: PersistCodec.decodeFingerprint(
        row['peer_fingerprint'],
        'share fingerprint',
      ),
      direction: PersistCodec.decodeToken(row['direction'], const <String>{
        PersistTokens.outgoing,
        PersistTokens.incoming,
      }, 'direction'),
      createdAtUtcMs: PersistCodec.requireInt(row, 'created_at_utc_ms'),
      terminalResult: terminal == null
          ? null
          : PersistCodec.decodeToken(
              terminal,
              PersistTokens.shareTerminals,
              'share terminal',
            ),
    );
  }

  Future<void> insertTransfer(TransferRecord record) {
    return persistWrite('insertTransfer', () {
      return _db.insert('transfers', <String, Object?>{
        'transfer_id': PersistCodec.writeLogicalId(
          record.transferId,
          'transferId',
        ),
        'share_session_id': PersistCodec.writeLogicalId(
          record.shareSessionId,
          'shareSessionId',
        ),
        'peer_fingerprint': PersistCodec.writeFingerprint(
          record.peerFingerprint,
          'transfer fingerprint',
        ),
        'direction': PersistCodec.writeToken(record.direction, const <String>{
          PersistTokens.outgoing,
          PersistTokens.incoming,
        }, 'direction'),
        'state': PersistCodec.writeToken(
          record.state,
          PersistTokens.transferStates,
          'transfer state',
        ),
        'created_at_utc_ms': record.createdAtUtcMs,
        'updated_at_utc_ms': record.updatedAtUtcMs,
      });
    });
  }

  Future<TransferRecord?> getTransfer(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'transfers',
      where: 'transfer_id = ?',
      whereArgs: <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _transferFrom(rows.first);
  }

  TransferRecord _transferFrom(Map<String, Object?> row) {
    return TransferRecord(
      transferId: PersistCodec.decodeLogicalId(
        row['transfer_id'],
        'transferId',
      ),
      shareSessionId: PersistCodec.decodeLogicalId(
        row['share_session_id'],
        'shareSessionId',
      ),
      peerFingerprint: PersistCodec.decodeFingerprint(
        row['peer_fingerprint'],
        'transfer fingerprint',
      ),
      direction: PersistCodec.decodeToken(row['direction'], const <String>{
        PersistTokens.outgoing,
        PersistTokens.incoming,
      }, 'direction'),
      state: PersistCodec.decodeToken(
        row['state'],
        PersistTokens.transferStates,
        'transfer state',
      ),
      createdAtUtcMs: PersistCodec.requireInt(row, 'created_at_utc_ms'),
      updatedAtUtcMs: PersistCodec.requireInt(row, 'updated_at_utc_ms'),
    );
  }

  Future<void> insertTransferItem(TransferItemRecord record) {
    return persistWrite('insertTransferItem', () {
      PersistCodec.writeToken(
        record.logicalType,
        PersistTokens.itemTypes,
        'item type',
      );
      PersistCodec.writeToken(
        record.state,
        PersistTokens.itemStates,
        'item state',
      );
      _requireCompleteIntegrity(
        state: record.state,
        expectedLength: record.expectedLength,
        bytesVerified: record.bytesVerified,
        expectedFinalHash: record.expectedFinalHash,
        actualFinalHash: record.actualFinalHash,
        kind: PersistenceFailureKind.constraintViolation,
      );
      return _db.insert('transfer_items', <String, Object?>{
        'item_id': PersistCodec.writeLogicalId(record.itemId, 'itemId'),
        'transfer_id': PersistCodec.writeLogicalId(
          record.transferId,
          'transferId',
        ),
        'logical_type': record.logicalType,
        'display_name': record.displayName,
        'relative_path': PersistedPathGuard.sanitizeRelative(
          record.relativePath,
        ),
        'source_handle': record.sourceHandle,
        'expected_length': record.expectedLength,
        'bytes_verified': record.bytesVerified,
        'expected_final_hash': record.expectedFinalHash,
        'actual_final_hash': record.actualFinalHash,
        'state': record.state,
      });
    });
  }

  Future<TransferItemRecord?> getTransferItem(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'transfer_items',
      where: 'item_id = ?',
      whereArgs: <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _itemFrom(rows.first);
  }

  TransferItemRecord _itemFrom(Map<String, Object?> row) {
    final TransferItemRecord item = TransferItemRecord(
      itemId: PersistCodec.decodeLogicalId(row['item_id'], 'itemId'),
      transferId: PersistCodec.decodeLogicalId(
        row['transfer_id'],
        'transferId',
      ),
      logicalType: PersistCodec.decodeToken(
        row['logical_type'],
        PersistTokens.itemTypes,
        'item type',
      ),
      displayName: PersistCodec.requireString(row, 'display_name'),
      relativePath: PersistCodec.optionalString(row, 'relative_path'),
      sourceHandle: PersistCodec.optionalString(row, 'source_handle'),
      expectedLength: PersistCodec.requireInt(row, 'expected_length'),
      bytesVerified: PersistCodec.requireInt(row, 'bytes_verified'),
      expectedFinalHash: PersistCodec.optionalString(
        row,
        'expected_final_hash',
      ),
      actualFinalHash: PersistCodec.optionalString(row, 'actual_final_hash'),
      state: PersistCodec.decodeToken(
        row['state'],
        PersistTokens.itemStates,
        'item state',
      ),
    );
    _requireCompleteIntegrity(
      state: item.state,
      expectedLength: item.expectedLength,
      bytesVerified: item.bytesVerified,
      expectedFinalHash: item.expectedFinalHash,
      actualFinalHash: item.actualFinalHash,
      kind: PersistenceFailureKind.decodeFailure,
    );
    return item;
  }

  static void _requireCompleteIntegrity({
    required String state,
    required int expectedLength,
    required int bytesVerified,
    required String? expectedFinalHash,
    required String? actualFinalHash,
    required PersistenceFailureKind kind,
  }) {
    if (state != 'COMPLETED') {
      return;
    }
    if (bytesVerified != expectedLength ||
        expectedFinalHash == null ||
        actualFinalHash == null ||
        expectedFinalHash != actualFinalHash) {
      throw PersistenceException(
        kind: kind,
        message: 'COMPLETED items require bytesVerified == expectedLength and matching hashes',
      );
    }
  }

  Future<void> putCheckpoint(TransferCheckpointRecord record) async {
    if (record.verifiedLocalByteOffset < 0) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.invalidArgument,
        message: 'checkpoint offset must be non-negative',
      );
    }
    final String itemId = PersistCodec.writeLogicalId(record.itemId, 'itemId');
    final String transferId = PersistCodec.writeLogicalId(
      record.transferId,
      'transferId',
    );
    final TransferItemRecord? item = await getTransferItem(itemId);
    if (item == null) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.constraintViolation,
        message: 'checkpoint requires an existing transfer item',
      );
    }
    if (transferId != item.transferId) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.constraintViolation,
        message: 'checkpoint transferId must match the item',
      );
    }
    if (record.verifiedLocalByteOffset > item.expectedLength) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.constraintViolation,
        message: 'checkpoint offset exceeds expected source length',
      );
    }
    await persistWrite('putCheckpoint', () {
      return _db.insert('transfer_checkpoints', <String, Object?>{
        'item_id': itemId,
        'transfer_id': transferId,
        'verified_local_byte_offset': record.verifiedLocalByteOffset,
        'source_identity': record.sourceIdentity,
        'destination_partial_identity': record.destinationPartialIdentity,
        'checkpoint_version': record.checkpointVersion,
        'updated_at_utc_ms': record.updatedAtUtcMs,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<TransferCheckpointRecord?> getCheckpoint(String itemId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'transfer_checkpoints',
      where: 'item_id = ?',
      whereArgs: <Object>[itemId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final TransferCheckpointRecord checkpoint = _checkpointFrom(rows.first);
    final TransferItemRecord? item = await getTransferItem(checkpoint.itemId);
    if (item == null) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.decodeFailure,
        message: 'checkpoint references a missing transfer item',
      );
    }
    if (checkpoint.itemId != item.itemId ||
        checkpoint.transferId != item.transferId) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.decodeFailure,
        message: 'checkpoint transfer/item relationship is corrupt',
      );
    }
    if (checkpoint.verifiedLocalByteOffset < 0 ||
        checkpoint.verifiedLocalByteOffset > item.expectedLength) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.decodeFailure,
        message: 'checkpoint offset is outside the persisted item length',
      );
    }
    return checkpoint;
  }

  TransferCheckpointRecord _checkpointFrom(Map<String, Object?> row) {
    return TransferCheckpointRecord(
      itemId: PersistCodec.decodeLogicalId(row['item_id'], 'itemId'),
      transferId: PersistCodec.decodeLogicalId(
        row['transfer_id'],
        'transferId',
      ),
      verifiedLocalByteOffset: PersistCodec.requireInt(
        row,
        'verified_local_byte_offset',
      ),
      sourceIdentity: PersistCodec.requireString(row, 'source_identity'),
      destinationPartialIdentity: PersistCodec.requireString(
        row,
        'destination_partial_identity',
      ),
      checkpointVersion: PersistCodec.requireInt(row, 'checkpoint_version'),
      updatedAtUtcMs: PersistCodec.requireInt(row, 'updated_at_utc_ms'),
    );
  }

  Future<void> insertActivity(ActivityRecord record) {
    return persistWrite('insertActivity', () {
      return _db.insert('activity_records', <String, Object?>{
        'activity_id': PersistCodec.writeLogicalId(
          record.activityId,
          'activityId',
        ),
        'kind': record.kind,
        'peer_fingerprint': record.peerFingerprint == null
            ? null
            : PersistCodec.writeFingerprint(
                record.peerFingerprint!,
                'activity fingerprint',
              ),
        'related_id': record.relatedId == null
            ? null
            : PersistCodec.writeLogicalId(record.relatedId!, 'relatedId'),
        'summary': record.summary,
        'created_at_utc_ms': record.createdAtUtcMs,
      });
    });
  }

  Future<ActivityRecord?> getActivity(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'activity_records',
      where: 'activity_id = ?',
      whereArgs: <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _activityFrom(rows.first);
  }

  ActivityRecord _activityFrom(Map<String, Object?> row) {
    return ActivityRecord(
      activityId: PersistCodec.decodeLogicalId(
        row['activity_id'],
        'activityId',
      ),
      kind: PersistCodec.requireString(row, 'kind'),
      peerFingerprint: PersistCodec.optionalFingerprint(
        row['peer_fingerprint'],
        'activity fingerprint',
      ),
      relatedId: PersistCodec.optionalLogicalId(row['related_id'], 'relatedId'),
      summary: PersistCodec.requireString(row, 'summary'),
      createdAtUtcMs: PersistCodec.requireInt(row, 'created_at_utc_ms'),
    );
  }

  Future<void> deleteActivity(String id) {
    return persistWrite('deleteActivity', () {
      return _db.delete(
        'activity_records',
        where: 'activity_id = ?',
        whereArgs: <Object>[id],
      );
    });
  }

  Future<void> insertScreenHistory(ScreenHistoryRecord record) {
    return persistWrite('insertScreenHistory', () {
      PersistCodec.writeToken(record.role, const <String>{
        PersistTokens.sender,
        PersistTokens.receiver,
      }, 'screen role');
      PersistCodec.writeToken(
        record.terminalResult,
        PersistTokens.screenTerminals,
        'screen terminal',
      );
      if (record.terminalResult == 'LIVE') {
        throw const PersistenceException(
          kind: PersistenceFailureKind.invalidArgument,
          message: 'screen history cannot persist LIVE',
        );
      }
      return _db.insert('screen_history', <String, Object?>{
        'screen_session_id': PersistCodec.writeLogicalId(
          record.screenSessionId,
          'screenSessionId',
        ),
        'peer_fingerprint': PersistCodec.writeFingerprint(
          record.peerFingerprint,
          'screen fingerprint',
        ),
        'role': record.role,
        'started_at_utc_ms': record.startedAtUtcMs,
        'ended_at_utc_ms': record.endedAtUtcMs,
        'terminal_result': record.terminalResult,
      });
    });
  }

  Future<ScreenHistoryRecord?> getScreenHistory(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'screen_history',
      where: 'screen_session_id = ?',
      whereArgs: <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _screenFrom(rows.first);
  }

  ScreenHistoryRecord _screenFrom(Map<String, Object?> row) {
    return ScreenHistoryRecord(
      screenSessionId: PersistCodec.decodeLogicalId(
        row['screen_session_id'],
        'screenSessionId',
      ),
      peerFingerprint: PersistCodec.decodeFingerprint(
        row['peer_fingerprint'],
        'screen fingerprint',
      ),
      role: PersistCodec.decodeToken(row['role'], const <String>{
        PersistTokens.sender,
        PersistTokens.receiver,
      }, 'screen role'),
      startedAtUtcMs: PersistCodec.requireInt(row, 'started_at_utc_ms'),
      endedAtUtcMs: PersistCodec.optionalInt(row, 'ended_at_utc_ms'),
      terminalResult: PersistCodec.decodeToken(
        row['terminal_result'],
        PersistTokens.screenTerminals,
        'screen terminal',
      ),
    );
  }

  Future<void> writeShareTransferAggregate({
    required ShareSessionRecord share,
    required TransferRecord transfer,
    required List<TransferItemRecord> items,
  }) async {
    final DatabaseExecutor executor = _db;
    if (executor is Database) {
      await persistWrite('writeShareTransferAggregate', () {
        return executor.transaction((Transaction txn) async {
          final FileHopStores inner = FileHopStores(txn);
          await inner.insertShareSession(share);
          await inner.insertTransfer(transfer);
          for (final TransferItemRecord item in items) {
            await inner.insertTransferItem(item);
          }
        });
      });
      return;
    }
    await insertShareSession(share);
    await insertTransfer(transfer);
    for (final TransferItemRecord item in items) {
      await insertTransferItem(item);
    }
  }
}
