import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({dynamic db, dynamic file, FileHopStores stores})> db() async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });
    return opened;
  }

  test('duplicate peer fingerprint is rejected', () async {
    final opened = await db();
    await opened.stores.insertPeer(
      const PeerRecord(fingerprint: kFpA, lastCapabilities: <String>[]),
    );
    expect(
      () => opened.stores.insertPeer(
        const PeerRecord(fingerprint: kFpA, lastCapabilities: <String>[]),
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

  test('one fingerprint cannot be trusted and blocked at once', () async {
    final opened = await db();
    await opened.stores.putTrust(
      const TrustRecordRow(
        fingerprint: kFpA,
        state: PersistTokens.trusted,
        verificationMethod: PersistTokens.sas,
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    await opened.stores.putTrust(
      const TrustRecordRow(
        fingerprint: kFpA,
        state: PersistTokens.blocked,
        verificationMethod: PersistTokens.userBlock,
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs + 1,
      ),
    );
    final TrustRecordRow? row = await opened.stores.getTrust(kFpA);
    expect(row?.state, PersistTokens.blocked);
    expect(row?.state, isNot(PersistTokens.trusted));
  });

  test('forgetting trust does not remove historical transfer rows', () async {
    final opened = await db();
    await opened.stores.insertPeer(
      const PeerRecord(fingerprint: kFpA, lastCapabilities: <String>[]),
    );
    await opened.stores.putTrust(
      const TrustRecordRow(
        fingerprint: kFpA,
        state: PersistTokens.trusted,
        verificationMethod: PersistTokens.qr,
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    await opened.stores.writeShareTransferAggregate(
      share: const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
        terminalResult: 'COMPLETED',
      ),
      transfer: const TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        state: 'COMPLETED',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
      items: const <TransferItemRecord>[
        TransferItemRecord(
          itemId: kItemId,
          transferId: kTransferId,
          logicalType: 'file',
          displayName: 'a.bin',
          expectedLength: 4,
          bytesVerified: 4,
          expectedFinalHash: 'abc',
          actualFinalHash: 'abc',
          state: 'COMPLETED',
        ),
      ],
    );
    await opened.stores.deleteTrust(kFpA);
    await opened.stores.deletePeerByFingerprint(kFpA);
    expect(await opened.stores.getTrust(kFpA), isNull);
    expect(await opened.stores.getPeerByFingerprint(kFpA), isNull);
    expect(await opened.stores.getTransfer(kTransferId), isNotNull);
    expect(await opened.stores.getShareSession(kShareId), isNotNull);
  });

  test('checkpoint invariants', () async {
    final opened = await db();
    await opened.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertTransfer(
      const TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        state: 'TRANSFERRING',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertTransferItem(
      const TransferItemRecord(
        itemId: kItemId,
        transferId: kTransferId,
        logicalType: 'file',
        displayName: 'a.bin',
        expectedLength: 10,
        bytesVerified: 4,
        state: 'TRANSFERRING',
      ),
    );

    expect(
      () => opened.stores.putCheckpoint(
        const TransferCheckpointRecord(
          itemId: 'ffffffffffffffffffffffffffffffff',
          transferId: kTransferId,
          verifiedLocalByteOffset: 1,
          sourceIdentity: 's',
          destinationPartialIdentity: 'd',
          checkpointVersion: 1,
          updatedAtUtcMs: kTs,
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );
    expect(
      () => opened.stores.putCheckpoint(
        const TransferCheckpointRecord(
          itemId: kItemId,
          transferId: kTransferId,
          verifiedLocalByteOffset: -1,
          sourceIdentity: 's',
          destinationPartialIdentity: 'd',
          checkpointVersion: 1,
          updatedAtUtcMs: kTs,
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );
    expect(
      () => opened.stores.putCheckpoint(
        const TransferCheckpointRecord(
          itemId: kItemId,
          transferId: kTransferId,
          verifiedLocalByteOffset: 11,
          sourceIdentity: 's',
          destinationPartialIdentity: 'd',
          checkpointVersion: 1,
          updatedAtUtcMs: kTs,
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );

    await opened.stores.putCheckpoint(
      const TransferCheckpointRecord(
        itemId: kItemId,
        transferId: kTransferId,
        verifiedLocalByteOffset: 4,
        sourceIdentity: 's',
        destinationPartialIdentity: 'd',
        checkpointVersion: 1,
        updatedAtUtcMs: kTs,
      ),
    );
    await opened.stores.putCheckpoint(
      const TransferCheckpointRecord(
        itemId: kItemId,
        transferId: kTransferId,
        verifiedLocalByteOffset: 6,
        sourceIdentity: 's2',
        destinationPartialIdentity: 'd2',
        checkpointVersion: 2,
        updatedAtUtcMs: kTs + 1,
      ),
    );
    expect((await opened.stores.getCheckpoint(kItemId))?.checkpointVersion, 2);
  });

  test('COMPLETED requires matching hashes', () async {
    final opened = await db();
    await opened.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertTransfer(
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
    expect(
      () => opened.stores.insertTransferItem(
        const TransferItemRecord(
          itemId: kItemId,
          transferId: kTransferId,
          logicalType: 'file',
          displayName: 'a.bin',
          expectedLength: 1,
          bytesVerified: 1,
          expectedFinalHash: 'aa',
          actualFinalHash: 'bb',
          state: 'COMPLETED',
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );
    expect(
      () => opened.stores.insertTransferItem(
        const TransferItemRecord(
          itemId: kItemId,
          transferId: kTransferId,
          logicalType: 'file',
          displayName: 'a.bin',
          expectedLength: 1,
          bytesVerified: 1,
          state: 'COMPLETED',
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );
  });

  test('unsafe relative path metadata is rejected', () async {
    final opened = await db();
    await opened.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertTransfer(
      const TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        state: 'CREATED',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    expect(
      () => opened.stores.insertTransferItem(
        const TransferItemRecord(
          itemId: kItemId,
          transferId: kTransferId,
          logicalType: 'file',
          displayName: 'x',
          relativePath: '../etc/passwd',
          expectedLength: 1,
          bytesVerified: 0,
          state: 'PENDING',
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );
  });

  test('unknown persisted token fails closed', () async {
    expect(
      () =>
          PersistTokens.requireToken('NOPE', PersistTokens.transferStates, 's'),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException e) => e.kind,
          'kind',
          PersistenceFailureKind.decodeFailure,
        ),
      ),
    );
  });

  test('screen history cannot be LIVE', () async {
    final opened = await db();
    expect(
      () => opened.stores.insertScreenHistory(
        const ScreenHistoryRecord(
          screenSessionId: kScreenId,
          peerFingerprint: kFpA,
          role: PersistTokens.sender,
          startedAtUtcMs: kTs,
          terminalResult: 'LIVE',
        ),
      ),
      throwsA(isA<PersistenceException>()),
    );
  });

  test('activity deletion does not delete transfer metadata', () async {
    final opened = await db();
    await opened.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertActivity(
      const ActivityRecord(
        activityId: kActivityId,
        kind: 'note',
        relatedId: kShareId,
        summary: 'hello',
        createdAtUtcMs: kTs,
      ),
    );
    await opened.stores.deleteActivity(kActivityId);
    expect(await opened.stores.getActivity(kActivityId), isNull);
    expect(await opened.stores.getShareSession(kShareId), isNotNull);
  });
}
