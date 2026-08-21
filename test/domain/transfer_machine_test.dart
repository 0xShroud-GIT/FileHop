import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  Transfer created() {
    return Transfer.created(
      transferId: idA(),
      shareSessionId: idB(),
      peerFingerprint: fixtureFingerprint(),
      direction: ShareDirection.outgoing,
    );
  }

  Transfer apply(Transfer transfer, TransferEvent event) {
    return transfer.apply(event, authority: TransitionAuthority.localCommand);
  }

  Transfer happyThrough(TransferEvent last) {
    final List<TransferEvent> path = <TransferEvent>[
      TransferEvent.offer,
      TransferEvent.accept,
      TransferEvent.startTransfer,
      TransferEvent.beginVerify,
      TransferEvent.verificationSucceeded,
    ];
    Transfer current = created();
    for (final TransferEvent event in path) {
      current = apply(current, event);
      if (event == last) {
        return current;
      }
    }
    return current;
  }

  test('happy path CREATED through COMPLETED', () {
    final Transfer done = happyThrough(TransferEvent.verificationSucceeded);
    expect(done.state, TransferState.completed);
    expect(done.isTerminal, isTrue);
    expect(done.lastTransition?.event, TransferEvent.verificationSucceeded);
  });

  test('pause and resume', () {
    Transfer transfer = happyThrough(TransferEvent.startTransfer);
    transfer = apply(transfer, TransferEvent.pause);
    expect(transfer.state, TransferState.paused);
    transfer = apply(transfer, TransferEvent.resume);
    expect(transfer.state, TransferState.transferring);
  });

  test('reject cancel fail side exits', () {
    expect(
      apply(apply(created(), TransferEvent.offer), TransferEvent.reject).state,
      TransferState.rejected,
    );
    expect(
      apply(created(), TransferEvent.cancel).state,
      TransferState.cancelled,
    );
    expect(
      apply(
        happyThrough(TransferEvent.startTransfer),
        TransferEvent.fail,
      ).state,
      TransferState.failed,
    );
  });

  test('recovery pending maps to PAUSED or FAILED', () {
    final Transfer transferring = happyThrough(TransferEvent.startTransfer);
    final Transfer pending = transferring.apply(
      TransferEvent.processInterrupted,
      authority: TransitionAuthority.recovery,
    );
    expect(pending.state, TransferState.recoveryPending);
    expect(pending.lastTransition?.authority, TransitionAuthority.recovery);
    expect(
      pending
          .apply(
            TransferEvent.checkpointResumable,
            authority: TransitionAuthority.recovery,
          )
          .state,
      TransferState.paused,
    );
    expect(
      pending
          .apply(
            TransferEvent.checkpointInvalid,
            authority: TransitionAuthority.recovery,
          )
          .state,
      TransferState.failed,
    );

    final Transfer fromPaused = apply(
      apply(transferring, TransferEvent.pause),
      TransferEvent.processInterrupted,
    );
    expect(fromPaused.state, TransferState.recoveryPending);

    final Transfer fromVerifying = apply(
      apply(transferring, TransferEvent.beginVerify),
      TransferEvent.processInterrupted,
    );
    expect(fromVerifying.state, TransferState.recoveryPending);
  });

  test('explicit illegal transfer examples', () {
    final Transfer fresh = created();
    expect(
      () => apply(fresh, TransferEvent.verificationSucceeded),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(fresh.state, TransferState.created);

    final Transfer offered = apply(fresh, TransferEvent.offer);
    expect(
      () => apply(offered, TransferEvent.beginVerify),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(offered.state, TransferState.offered);

    final Transfer completed = happyThrough(
      TransferEvent.verificationSucceeded,
    );
    expect(
      () => apply(completed, TransferEvent.startTransfer),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(completed.state, TransferState.completed);

    final Transfer rejected = apply(offered, TransferEvent.reject);
    expect(
      () => apply(rejected, TransferEvent.accept),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(rejected.state, TransferState.rejected);

    final Transfer cancelled = apply(fresh, TransferEvent.cancel);
    expect(
      () => apply(cancelled, TransferEvent.startTransfer),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(cancelled.state, TransferState.cancelled);
  });

  test('terminal states reject resurrection', () {
    for (final Transfer transfer in <Transfer>[
      happyThrough(TransferEvent.verificationSucceeded),
      apply(apply(created(), TransferEvent.offer), TransferEvent.reject),
      apply(created(), TransferEvent.cancel),
      apply(created(), TransferEvent.fail),
    ]) {
      expect(transfer.isTerminal, isTrue);
      for (final TransferEvent event in TransferEvent.values) {
        expect(
          () => apply(transfer, event),
          throwsA(isA<InvalidStateTransition>()),
        );
        expect(Transfer.terminal.contains(transfer.state), isTrue);
      }
    }
  });
}
