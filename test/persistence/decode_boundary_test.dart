import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ffi_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Matcher decodeFailure() {
    return isA<PersistenceException>().having(
      (PersistenceException e) => e.kind,
      'kind',
      PersistenceFailureKind.decodeFailure,
    );
  }

  Matcher writeFailure() {
    return isA<PersistenceException>().having(
      (PersistenceException e) => e.kind,
      'kind',
      PersistenceFailureKind.constraintViolation,
    );
  }

  test('unknown tokens fail as decodeFailure', () {
    expect(
      () => PersistCodec.decodeToken('SIDEWAYS', const <String>{
        PersistTokens.outgoing,
        PersistTokens.incoming,
      }, 'direction'),
      throwsA(decodeFailure()),
    );
    expect(
      () => PersistCodec.decodeToken('MAYBE', const <String>{
        PersistTokens.trusted,
        PersistTokens.blocked,
      }, 'trust state'),
      throwsA(decodeFailure()),
    );
    expect(
      () => PersistCodec.decodeToken('narrator', const <String>{
        PersistTokens.sender,
        PersistTokens.receiver,
      }, 'screen role'),
      throwsA(decodeFailure()),
    );
  });

  test('corrupt transfer state in SQLite decodes as decodeFailure', () async {
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
    await opened.db.raw.update(
      'transfers',
      <String, Object?>{'state': 'MAGIC'},
      where: 'transfer_id = ?',
      whereArgs: <Object>[kTransferId],
    );
    await expectLater(
      opened.stores.getTransfer(kTransferId),
      throwsA(decodeFailure()),
    );
  });

  test('capabilities JSON must be an array of strings', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });
    await opened.stores.insertPeer(
      const PeerRecord(
        fingerprint: kFpA,
        lastCapabilities: <String>['share.files'],
      ),
    );

    await opened.db.raw.update(
      'peers',
      <String, Object?>{'last_capabilities_json': '["share.files", 123]'},
      where: 'fingerprint = ?',
      whereArgs: <Object>[kFpA],
    );
    await expectLater(
      opened.stores.getPeerByFingerprint(kFpA),
      throwsA(decodeFailure()),
    );

    await opened.db.raw.update(
      'peers',
      <String, Object?>{'last_capabilities_json': '{"share.files": true}'},
      where: 'fingerprint = ?',
      whereArgs: <Object>[kFpA],
    );
    await expectLater(
      opened.stores.getPeerByFingerprint(kFpA),
      throwsA(decodeFailure()),
    );

    await opened.db.raw.update(
      'peers',
      <String, Object?>{'last_capabilities_json': '["future.capability.v99"]'},
      where: 'fingerprint = ?',
      whereArgs: <Object>[kFpA],
    );
    final PeerRecord? peer = await opened.stores.getPeerByFingerprint(kFpA);
    expect(peer?.lastCapabilities, <String>['future.capability.v99']);
  });

  test(
    'corrupt logical IDs and fingerprints decode as decodeFailure',
    () async {
      final opened = await openTempDb();
      addTearDown(() async {
        await opened.db.close();
        await deleteTempDb(opened.file);
      });
      await opened.db.raw.insert('share_sessions', <String, Object?>{
        'share_session_id': 'abc',
        'peer_fingerprint': kFpA,
        'direction': PersistTokens.outgoing,
        'created_at_utc_ms': kTs,
      });
      await expectLater(
        opened.stores.getShareSession('abc'),
        throwsA(decodeFailure()),
      );

      await opened.db.raw.insert('share_sessions', <String, Object?>{
        'share_session_id': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'peer_fingerprint': kFpA,
        'direction': PersistTokens.outgoing,
        'created_at_utc_ms': kTs,
      });
      await expectLater(
        opened.stores.getShareSession('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
        throwsA(decodeFailure()),
      );

      await opened.db.raw.insert('peers', <String, Object?>{
        'fingerprint': 'has space',
        'last_capabilities_json': '[]',
      });
      await expectLater(
        opened.stores.getPeerByFingerprint('has space'),
        throwsA(decodeFailure()),
      );
    },
  );

  test('write APIs reject invalid IDs fingerprints and tokens', () async {
    final opened = await openTempDb();
    addTearDown(() async {
      await opened.db.close();
      await deleteTempDb(opened.file);
    });

    expect(
      () => opened.stores.insertShareSession(
        const ShareSessionRecord(
          shareSessionId: 'abc',
          peerFingerprint: kFpA,
          direction: PersistTokens.outgoing,
          createdAtUtcMs: kTs,
        ),
      ),
      throwsA(writeFailure()),
    );
    expect(
      () => opened.stores.insertPeer(
        const PeerRecord(
          fingerprint: 'has space',
          lastCapabilities: <String>[],
        ),
      ),
      throwsA(writeFailure()),
    );
    expect(
      () => opened.stores.insertTransfer(
        const TransferRecord(
          transferId: kTransferId,
          shareSessionId: kShareId,
          peerFingerprint: kFpA,
          direction: PersistTokens.outgoing,
          state: 'MAGIC',
          createdAtUtcMs: kTs,
          updatedAtUtcMs: kTs,
        ),
      ),
      throwsA(writeFailure()),
    );
    expect(
      () => opened.stores.putTrust(
        const TrustRecordRow(
          fingerprint: kFpA,
          state: 'MAYBE',
          verificationMethod: PersistTokens.qr,
          createdAtUtcMs: kTs,
          updatedAtUtcMs: kTs,
        ),
      ),
      throwsA(writeFailure()),
    );
  });
}
