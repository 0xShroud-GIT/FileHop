import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aggregate write rolls back when a child row is invalid', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });

    await opened.stores.insertActivity(
      const ActivityRecord(
        activityId: kActivityId,
        kind: 'baseline',
        summary: 'before',
        createdAtUtcMs: kTs,
      ),
    );

    expect(
      () => opened.stores.writeShareTransferAggregate(
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
          state: 'OFFERED',
          createdAtUtcMs: kTs,
          updatedAtUtcMs: kTs,
        ),
        items: const <TransferItemRecord>[
          TransferItemRecord(
            itemId: '11111111111111111111111111111111',
            transferId: kTransferId,
            logicalType: 'file',
            displayName: 'ok.bin',
            expectedLength: 1,
            bytesVerified: 0,
            state: 'PENDING',
          ),
          TransferItemRecord(
            itemId: kItemId,
            transferId: kTransferId,
            logicalType: 'file',
            displayName: 'bad.bin',
            expectedLength: 1,
            bytesVerified: 1,
            expectedFinalHash: 'aa',
            actualFinalHash: 'zz',
            state: 'COMPLETED',
          ),
        ],
      ),
      throwsA(isA<PersistenceException>()),
    );

    expect(await opened.stores.getShareSession(kShareId), isNull);
    expect(await opened.stores.getTransfer(kTransferId), isNull);
    expect(await opened.stores.getTransferItem(kItemId), isNull);
    expect(await opened.stores.getActivity(kActivityId), isNotNull);
  });
}
