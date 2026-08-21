import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file-backed close/reopen preserves representative rows', () async {
    ensureSqfliteFfi();
    final opened = await openTempDb();
    final String path = opened.file.path;
    final FileHopStores stores = opened.stores;

    await stores.upsertLocalIdentity(
      const LocalIdentityRecord(
        publicIdentityKey: <int>[1, 2, 3, 4],
        identityFingerprint: kFpA,
        wrappedKeyRef: 'keystore:filehop-identity-v1',
        keyStorageVersion: 1,
        createdAtUtcMs: kTs,
      ),
    );
    await stores.insertPeer(
      const PeerRecord(
        fingerprint: kFpA,
        lastKnownDisplayName: 'Kitchen tablet',
        lastSeenUtcMs: kTs,
        lastCapabilities: <String>['share.files', 'future.token'],
      ),
    );
    await stores.putTrust(
      const TrustRecordRow(
        fingerprint: kFpA,
        state: PersistTokens.trusted,
        verificationMethod: PersistTokens.qr,
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    await stores.writeShareTransferAggregate(
      share: const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
      ),
      transfer: const TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.outgoing,
        state: 'TRANSFERRING',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
      items: const <TransferItemRecord>[
        TransferItemRecord(
          itemId: kItemId,
          transferId: kTransferId,
          logicalType: 'file',
          displayName: 'notes.txt',
          relativePath: 'docs/notes.txt',
          expectedLength: 0,
          bytesVerified: 0,
          state: 'READY',
        ),
      ],
    );
    await stores.putCheckpoint(
      const TransferCheckpointRecord(
        itemId: kItemId,
        transferId: kTransferId,
        verifiedLocalByteOffset: 0,
        sourceIdentity: 'src-v1',
        destinationPartialIdentity: 'dst-partial-v1',
        checkpointVersion: 1,
        updatedAtUtcMs: kTs,
      ),
    );
    await stores.insertActivity(
      const ActivityRecord(
        activityId: kActivityId,
        kind: 'transfer.progress',
        peerFingerprint: kFpA,
        relatedId: kTransferId,
        summary: 'Sending notes.txt',
        createdAtUtcMs: kTs,
      ),
    );
    await stores.insertScreenHistory(
      const ScreenHistoryRecord(
        screenSessionId: kScreenId,
        peerFingerprint: kFpA,
        role: PersistTokens.sender,
        startedAtUtcMs: kTs,
        endedAtUtcMs: kTs + 1000,
        terminalResult: 'CLOSED',
      ),
    );

    await opened.db.close();

    final FileHopDatabase reopened = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(() async {
      await reopened.close();
      await deleteTempDb(opened.file);
    });
    final FileHopStores again = FileHopStores(reopened.raw);

    final LocalIdentityRecord? identity = await again.getLocalIdentity();
    expect(identity?.identityFingerprint, kFpA);
    expect(identity?.publicIdentityKey, <int>[1, 2, 3, 4]);
    expect(identity?.wrappedKeyRef, 'keystore:filehop-identity-v1');

    final PeerRecord? peer = await again.getPeerByFingerprint(kFpA);
    expect(peer?.lastKnownDisplayName, 'Kitchen tablet');
    expect(peer?.lastCapabilities, <String>['share.files', 'future.token']);
    expect(peer?.lastSeenUtcMs, kTs);

    final TrustRecordRow? trust = await again.getTrust(kFpA);
    expect(trust?.state, PersistTokens.trusted);
    expect(trust?.verificationMethod, PersistTokens.qr);

    expect((await again.getShareSession(kShareId))?.direction, 'outgoing');
    expect((await again.getTransfer(kTransferId))?.state, 'TRANSFERRING');
    final TransferItemRecord? item = await again.getTransferItem(kItemId);
    expect(item?.expectedLength, 0);
    expect(item?.relativePath, 'docs/notes.txt');
    expect((await again.getCheckpoint(kItemId))?.verifiedLocalByteOffset, 0);
    expect(
      (await again.getActivity(kActivityId))?.summary,
      'Sending notes.txt',
    );
    expect((await again.getScreenHistory(kScreenId))?.terminalResult, 'CLOSED');
    expect(await reopened.userVersion(), 1);
  });

  test('large safe integer byte counts round-trip', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });
    const int big = 1099511627776; // 2^40
    await opened.stores.insertShareSession(
      const ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.incoming,
        createdAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertTransfer(
      const TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: kFpA,
        direction: PersistTokens.incoming,
        state: 'CREATED',
        createdAtUtcMs: kTs,
        updatedAtUtcMs: kTs,
      ),
    );
    await opened.stores.insertTransferItem(
      const TransferItemRecord(
        itemId: kItemId,
        transferId: kTransferId,
        logicalType: 'file',
        displayName: 'big.bin',
        expectedLength: big,
        bytesVerified: big,
        state: 'PAUSED',
      ),
    );
    expect((await opened.stores.getTransferItem(kItemId))?.expectedLength, big);
  });
}
