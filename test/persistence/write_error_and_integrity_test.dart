import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ffi_harness.dart';

const String kShareB = '11111111111111111111111111111111';
const String kTransferB = '22222222222222222222222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({FileHopDatabase db, FileHopStores stores, dynamic file})>
  opened() async {
    final handle = await openTempDb();
    addTearDown(() async {
      await handle.db.close();
      await deleteTempDb(handle.file);
    });
    return (db: handle.db, stores: handle.stores, file: handle.file);
  }

  Future<void> seedTransfer(
    FileHopStores stores, {
    String shareId = kShareId,
    String transferId = kTransferId,
    String itemId = kItemId,
    int expectedLength = 100,
  }) async {
    await stores.insertShareSession(
      ShareSessionRecord(
        shareSessionId: shareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    await stores.insertTransfer(
      TransferRecord(
        transferId: transferId,
        shareSessionId: shareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        state: 'TRANSFERRING',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    await stores.insertTransferItem(
      TransferItemRecord(
        itemId: itemId,
        transferId: transferId,
        logicalType: 'file',
        displayName: 'a.bin',
        expectedLength: expectedLength,
        bytesVerified: 0,
        state: 'TRANSFERRING',
      ),
    );
  }

  test('duplicate primary key is constraintViolation not raw SQLite', () async {
    final handle = await opened();
    await handle.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    expect(
      () => handle.stores.insertShareSession(
        const ShareSessionRecord(
          shareSessionId: kShareId,
          peerFingerprint: kFpA,
          direction: PersistTokens.outgoing,
          createdAtUtcMs: kTs,
        ),
      ),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.constraintViolation,
        ),
      ),
    );
  });

  test('missing parent transfer is constraintViolation', () async {
    final handle = await opened();
    expect(
      () => handle.stores.insertTransfer(
        const TransferRecord(
          transferId: kTransferId,
          shareSessionId: kShareId,
          peerFingerprint: kFpA,
          direction: PersistTokens.outgoing,
          state: 'CREATED',
          createdAtUtcMs: kTs,
          updatedAtUtcMs: kTs,
        ),
      ),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.constraintViolation,
        ),
      ),
    );
  });

  test('non-constraint SQLite write is operationFailure', () async {
    final handle = await opened();
    await handle.db.raw.execute(
      'ALTER TABLE activity_records RENAME TO activity_records_gone',
    );
    expect(
      () => handle.stores.insertActivity(
        const ActivityRecord(
          activityId: kActivityId,
          kind: 'note',
          summary: 'x',
          createdAtUtcMs: kTs,
        ),
      ),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.operationFailure,
        ),
      ),
    );
  });

  test(
    'composite FK rejects mismatched item/transfer at SQLite level',
    () async {
      final handle = await opened();
      await seedTransfer(handle.stores);
      await seedTransfer(
        handle.stores,
        shareId: kShareB,
        transferId: kTransferB,
        itemId: '33333333333333333333333333333333',
      );

      await expectLater(
        handle.db.raw.insert('transfer_checkpoints', <String, Object?>{
          'item_id': kItemId,
          'transfer_id': kTransferB,
          'verified_local_byte_offset': 1,
          'source_identity': 'src',
          'destination_partial_identity': 'dst',
          'checkpoint_version': 1,
          'updated_at_utc_ms': kTs,
        }),
        throwsA(anything),
      );

      expect(
        () => handle.stores.putCheckpoint(
          const TransferCheckpointRecord(
            itemId: kItemId,
            transferId: kTransferB,
            verifiedLocalByteOffset: 1,
            sourceIdentity: 'src',
            destinationPartialIdentity: 'dst',
            checkpointVersion: 1,
            updatedAtUtcMs: kTs,
          ),
        ),
        throwsA(
          isA<PersistenceException>().having(
            (PersistenceException e) => e.kind,
            'kind',
            PersistenceFailureKind.constraintViolation,
          ),
        ),
      );

      await handle.db.raw.insert('transfer_checkpoints', <String, Object?>{
        'item_id': kItemId,
        'transfer_id': kTransferId,
        'verified_local_byte_offset': 1,
        'source_identity': 'src',
        'destination_partial_identity': 'dst',
        'checkpoint_version': 1,
        'updated_at_utc_ms': kTs,
      });
      expect(
        (await handle.stores.getCheckpoint(kItemId))?.transferId,
        kTransferId,
      );
    },
  );

  test(
    'valid checkpoint reloads and mismatched transfer is decodeFailure',
    () async {
      final handle = await opened();
      await seedTransfer(handle.stores);
      await seedTransfer(
        handle.stores,
        shareId: kShareB,
        transferId: kTransferB,
        itemId: '33333333333333333333333333333333',
      );
      await handle.stores.putCheckpoint(
        const TransferCheckpointRecord(
          itemId: kItemId,
          transferId: kTransferId,
          verifiedLocalByteOffset: 10,
          sourceIdentity: 'src',
          destinationPartialIdentity: 'dst',
          checkpointVersion: 1,
          updatedAtUtcMs: kTs,
        ),
      );
      expect(
        (await handle.stores.getCheckpoint(kItemId))?.verifiedLocalByteOffset,
        10,
      );

      await handle.db.raw.execute('PRAGMA foreign_keys = OFF');
      await handle.db.raw.update(
        'transfer_checkpoints',
        <String, Object?>{'transfer_id': kTransferB},
        where: 'item_id = ?',
        whereArgs: <Object>[kItemId],
      );
      await handle.db.raw.execute('PRAGMA foreign_keys = ON');
      await expectLater(
        handle.stores.getCheckpoint(kItemId),
        throwsA(
          isA<PersistenceException>().having(
            (PersistenceException e) => e.kind,
            'kind',
            PersistenceFailureKind.decodeFailure,
          ),
        ),
      );
    },
  );

  test('checkpoint offset above expectedLength is decodeFailure', () async {
    final handle = await opened();
    await seedTransfer(handle.stores, expectedLength: 100);
    await handle.db.raw.insert('transfer_checkpoints', <String, Object?>{
      'item_id': kItemId,
      'transfer_id': kTransferId,
      'verified_local_byte_offset': 101,
      'source_identity': 'src',
      'destination_partial_identity': 'dst',
      'checkpoint_version': 1,
      'updated_at_utc_ms': kTs,
    });
    await expectLater(
      handle.stores.getCheckpoint(kItemId),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.decodeFailure,
        ),
      ),
    );
  });

  test('negative checkpoint offset is rejected by schema CHECK', () async {
    final handle = await opened();
    await seedTransfer(handle.stores);
    await expectLater(
      handle.db.raw.insert('transfer_checkpoints', <String, Object?>{
        'item_id': kItemId,
        'transfer_id': kTransferId,
        'verified_local_byte_offset': -1,
        'source_identity': 'src',
        'destination_partial_identity': 'dst',
        'checkpoint_version': 1,
        'updated_at_utc_ms': kTs,
      }),
      throwsA(anything),
    );
  });

  test('COMPLETED requires full byte accounting and hashes', () async {
    final handle = await opened();
    await handle.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    await handle.stores.insertTransfer(
      const TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        state: 'VERIFYING',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );

    await handle.stores.insertTransferItem(
      const TransferItemRecord(
        itemId: kItemId,
        transferId: kTransferId,
        logicalType: 'file',
        displayName: 'full.bin',
        expectedLength: 8,
        bytesVerified: 8,
        expectedFinalHash: 'aa',
        actualFinalHash: 'aa',
        state: 'COMPLETED',
      ),
    );
    expect((await handle.stores.getTransferItem(kItemId))?.state, 'COMPLETED');

    await handle.stores.insertTransferItem(
      const TransferItemRecord(
        itemId: '44444444444444444444444444444444',
        transferId: kTransferId,
        logicalType: 'file',
        displayName: 'empty.bin',
        expectedLength: 0,
        bytesVerified: 0,
        expectedFinalHash: 'ee',
        actualFinalHash: 'ee',
        state: 'COMPLETED',
      ),
    );

    expect(
      () => handle.stores.insertTransferItem(
        const TransferItemRecord(
          itemId: '55555555555555555555555555555555',
          transferId: kTransferId,
          logicalType: 'file',
          displayName: 'partial.bin',
          expectedLength: 100,
          bytesVerified: 50,
          expectedFinalHash: 'hh',
          actualFinalHash: 'hh',
          state: 'COMPLETED',
        ),
      ),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.constraintViolation,
        ),
      ),
    );

    await expectLater(
      handle.db.raw.insert('transfer_items', <String, Object?>{
        'item_id': '66666666666666666666666666666666',
        'transfer_id': kTransferId,
        'logical_type': 'file',
        'display_name': 'bad.bin',
        'expected_length': 100,
        'bytes_verified': 50,
        'expected_final_hash': 'hh',
        'actual_final_hash': 'hh',
        'state': 'COMPLETED',
      }),
      throwsA(anything),
    );
  });
}
