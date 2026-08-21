import 'dart:io';

import 'package:filehop/domain/domain.dart';
import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/trust_service.dart';
import 'package:filehop/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../persistence/support/ffi_harness.dart';
import 'support/fingerprint_vector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File dbFile;
  late FileHopDatabase db;
  late FileHopStores stores;
  late TrustService trust;
  final PeerFingerprint fpA = PeerFingerprint.parse(kVectorAFingerprint);
  final PeerFingerprint fpB = PeerFingerprint.parse(kVectorBFingerprint);

  setUp(() async {
    final opened = await openTempDb();
    db = opened.db;
    dbFile = opened.file;
    stores = opened.stores;
    trust = TrustService(stores, nowUtcMs: () => kTs);
  });

  tearDown(() async {
    await db.close();
    await deleteTempDb(dbFile);
  });

  test('QR and SAS trust, block, unblock, forget', () async {
    expect(await trust.getTrustState(fpA), TrustState.none);

    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.qr);
    expect(await trust.getTrustState(fpA), TrustState.trusted);

    await trust.forgetPeer(fpA);
    expect(await trust.getTrustState(fpA), TrustState.none);

    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.sas);
    expect(await trust.getTrustState(fpA), TrustState.trusted);

    await trust.blockPeer(fpA);
    expect(await trust.getTrustState(fpA), TrustState.blocked);
    expect(await trust.isBlocked(fpA), isTrue);

    await trust.unblockPeer(fpA);
    expect(await trust.getTrustState(fpA), TrustState.none);
    expect(await trust.isBlocked(fpA), isFalse);
  });

  test('blocked cannot become trusted without unblock', () async {
    await trust.blockPeer(fpA);
    await expectLater(
      trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.qr),
      throwsA(
        isA<TrustException>().having(
          (TrustException e) => e.kind,
          'kind',
          TrustFailureKind.invalidTrustTransition,
        ),
      ),
    );
    expect(await trust.getTrustState(fpA), TrustState.blocked);

    await trust.unblockPeer(fpA);
    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.sas);
    expect(await trust.getTrustState(fpA), TrustState.trusted);
  });

  test('unblock returns to NONE not previous TRUSTED', () async {
    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.qr);
    await trust.blockPeer(fpA);
    await trust.unblockPeer(fpA);
    expect(await trust.getTrustState(fpA), TrustState.none);
  });

  test('TRUSTED and BLOCKED survive close/reopen', () async {
    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.qr);
    await trust.blockPeer(fpB);
    final String path = dbFile.path;
    await db.close();

    final FileHopDatabase reopened = await FileHopDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(() async {
      await reopened.close();
    });
    final TrustService again = TrustService(FileHopStores(reopened.raw));
    expect(await again.getTrustState(fpA), TrustState.trusted);
    expect(await again.getTrustState(fpB), TrustState.blocked);
    expect(await again.isBlocked(fpB), isTrue);
  });

  test('same display name does not merge or transfer trust', () async {
    await trust.rememberPeer(
      fingerprint: fpA,
      displayName: DisplayName.parse('Phone'),
    );
    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.qr);
    await trust.rememberPeer(
      fingerprint: fpB,
      displayName: DisplayName.parse('Phone'),
    );

    expect(await trust.getTrustState(fpA), TrustState.trusted);
    expect(await trust.getTrustState(fpB), TrustState.none);

    final PeerRecord? peerA = await stores.getPeerByFingerprint(fpA.value);
    final PeerRecord? peerB = await stores.getPeerByFingerprint(fpB.value);
    expect(peerA?.lastKnownDisplayName, 'Phone');
    expect(peerB?.lastKnownDisplayName, 'Phone');
    expect(peerA?.fingerprint, isNot(peerB?.fingerprint));

    await trust.blockPeer(fpB);
    expect(await trust.getTrustState(fpA), TrustState.trusted);
    expect(await trust.isBlocked(fpB), isTrue);
    expect(await trust.isBlocked(fpA), isFalse);
  });

  test('identity change never migrates trust', () async {
    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.sas);
    expect(
      IdentityChangePolicy.compare(remembered: fpA, authenticated: fpB),
      AuthenticatedIdentityComparison.identityChanged,
    );
    expect(await trust.getTrustState(fpB), TrustState.none);
    expect(await trust.getTrustState(fpA), TrustState.trusted);
  });

  test('forget removes trust and peer but keeps history', () async {
    await trust.rememberPeer(
      fingerprint: fpA,
      displayName: DisplayName.parse('Phone'),
    );
    await trust.trustVerifiedPeer(fpA, method: VerifiedTrustMethod.qr);
    await stores.writeShareTransferAggregate(
      share: ShareSessionRecord(
        shareSessionId: kShareId,
        peerFingerprint: fpA.value,
        direction: PersistTokens.outgoing,
        createdAtUtcMs: kTs,
        terminalResult: 'COMPLETED',
      ),
      transfer: TransferRecord(
        transferId: kTransferId,
        shareSessionId: kShareId,
        peerFingerprint: fpA.value,
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
          expectedLength: 1,
          bytesVerified: 1,
          expectedFinalHash: 'aa',
          actualFinalHash: 'aa',
          state: 'COMPLETED',
        ),
      ],
    );

    await trust.forgetPeer(fpA);
    expect(await trust.getTrustState(fpA), TrustState.none);
    expect(await stores.getPeerByFingerprint(fpA.value), isNull);
    expect(await stores.getTrust(fpA.value), isNull);
    expect(await stores.getTransfer(kTransferId), isNotNull);
    expect(await stores.getShareSession(kShareId), isNotNull);
    expect(await stores.getTransferItem(kItemId), isNotNull);
  });
}
