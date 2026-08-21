import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  TransferItem pending() {
    return TransferItem.pending(
      itemId: idC(),
      transferId: idA(),
      kind: TransferItemKind.file,
      name: 'notes.txt',
    );
  }

  TransferItem apply(TransferItem item, TransferItemEvent event) {
    return item.apply(event, authority: TransitionAuthority.localCommand);
  }

  TransferItem happyThrough(TransferItemEvent last) {
    final List<TransferItemEvent> path = <TransferItemEvent>[
      TransferItemEvent.markReady,
      TransferItemEvent.startTransfer,
      TransferItemEvent.beginVerify,
      TransferItemEvent.verificationSucceeded,
    ];
    TransferItem current = pending();
    for (final TransferItemEvent event in path) {
      current = apply(current, event);
      if (event == last) {
        return current;
      }
    }
    return current;
  }

  test('item happy path requires verification success', () {
    final TransferItem done = happyThrough(
      TransferItemEvent.verificationSucceeded,
    );
    expect(done.state, TransferItemState.completed);
    expect(done.lastTransition?.event, TransferItemEvent.verificationSucceeded);
  });

  test('item pause and resume', () {
    TransferItem item = happyThrough(TransferItemEvent.startTransfer);
    item = apply(item, TransferItemEvent.pause);
    expect(item.state, TransferItemState.paused);
    item = apply(item, TransferItemEvent.resume);
    expect(item.state, TransferItemState.transferring);
  });

  test('item skipped cancelled failed exits', () {
    expect(
      apply(pending(), TransferItemEvent.skip).state,
      TransferItemState.skipped,
    );
    expect(
      apply(pending(), TransferItemEvent.cancel).state,
      TransferItemState.cancelled,
    );
    expect(
      apply(pending(), TransferItemEvent.fail).state,
      TransferItemState.failed,
    );
  });

  test('VERIFYING to COMPLETED requires verificationSucceeded', () {
    final TransferItem verifying = happyThrough(TransferItemEvent.beginVerify);
    expect(verifying.state, TransferItemState.verifying);
    expect(
      apply(verifying, TransferItemEvent.verificationSucceeded).state,
      TransferItemState.completed,
    );
    expect(
      apply(verifying, TransferItemEvent.verificationFailed).state,
      TransferItemState.failed,
    );
    expect(
      () => apply(verifying, TransferItemEvent.markReady),
      throwsA(isA<InvalidStateTransition>()),
    );
  });

  test('no direct completion from earlier states', () {
    for (final TransferItem item in <TransferItem>[
      pending(),
      apply(pending(), TransferItemEvent.markReady),
      happyThrough(TransferItemEvent.startTransfer),
    ]) {
      expect(
        () => apply(item, TransferItemEvent.verificationSucceeded),
        throwsA(isA<InvalidStateTransition>()),
      );
      expect(item.state, isNot(TransferItemState.completed));
    }
  });
}
