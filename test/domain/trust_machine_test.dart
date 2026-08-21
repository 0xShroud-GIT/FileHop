import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  TrustRecord apply(TrustRecord record, TrustEvent event) {
    return record.apply(event, authority: TransitionAuthority.localCommand);
  }

  test('every legal trust transition', () {
    TrustRecord record = TrustRecord.none(fixtureFingerprint());
    expect(apply(record, TrustEvent.verifyQr).state, TrustState.trusted);
    expect(apply(record, TrustEvent.verifySas).state, TrustState.trusted);
    expect(apply(record, TrustEvent.block).state, TrustState.blocked);
    expect(apply(record, TrustEvent.forget).state, TrustState.none);

    final TrustRecord trusted = apply(record, TrustEvent.verifyQr);
    expect(apply(trusted, TrustEvent.forget).state, TrustState.none);
    expect(apply(trusted, TrustEvent.block).state, TrustState.blocked);
    expect(trusted.isTrusted, isTrue);
    expect(trusted.isBlocked, isFalse);

    final TrustRecord blocked = apply(record, TrustEvent.block);
    expect(apply(blocked, TrustEvent.unblock).state, TrustState.none);
    expect(blocked.isBlocked, isTrue);
    expect(blocked.isTrusted, isFalse);
  });

  test('trusted and blocked are mutually exclusive', () {
    for (final TrustState state in TrustState.values) {
      expect(
        state == TrustState.trusted && state == TrustState.blocked,
        isFalse,
      );
    }
    final TrustRecord trusted = apply(
      TrustRecord.none(fixtureFingerprint()),
      TrustEvent.verifyQr,
    );
    expect(trusted.isTrusted && trusted.isBlocked, isFalse);
  });

  test('illegal trust transitions fail without mutation', () {
    final TrustRecord none = TrustRecord.none(fixtureFingerprint());
    expect(
      () => apply(none, TrustEvent.unblock),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(none.state, TrustState.none);

    final TrustRecord trusted = apply(none, TrustEvent.verifySas);
    expect(
      () => apply(trusted, TrustEvent.unblock),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(trusted.state, TrustState.trusted);

    final TrustRecord blocked = apply(none, TrustEvent.block);
    expect(
      () => apply(blocked, TrustEvent.verifyQr),
      throwsA(isA<InvalidStateTransition>()),
    );
    expect(blocked.state, TrustState.blocked);
  });
}
