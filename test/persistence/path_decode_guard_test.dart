import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsafe path already present in SQLite fails closed on decode', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });

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
    await opened.stores.insertTransferItem(
      const TransferItemRecord(
        itemId: kItemId,
        transferId: kTransferId,
        logicalType: 'file',
        displayName: 'safe.bin',
        relativePath: 'folder/safe.bin',
        expectedLength: 1,
        bytesVerified: 0,
        state: 'PENDING',
      ),
    );

    await opened.db.raw.update(
      'transfer_items',
      <String, Object?>{'relative_path': '../escape.bin'},
      where: 'item_id = ?',
      whereArgs: <Object>[kItemId],
    );

    await expectLater(
      opened.stores.getTransferItem(kItemId),
      throwsA(
        isA<PersistenceException>().having(
          (PersistenceException error) => error.kind,
          'kind',
          PersistenceFailureKind.decodeFailure,
        ),
      ),
    );
  });
}
