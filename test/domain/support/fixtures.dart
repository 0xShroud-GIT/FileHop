import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canonical FileHop fingerprints from the Mission 05 public-key vector.
/// Independent Python hashlib+base32 expected values. Not security identity
/// derived from a real private key.
const String kFixtureFingerprint =
    'VYQWYLXVER5DPAWBGXX2E6ND4TG4MEEUE4HV2K7FRRRAJN5GCLEQ';
const String kFixtureFingerprintOther =
    'P3XFQAG5ZU5TZSP5AR4DDTMFG3R4H5L7ITLUN5IV3KJ7ASHOT2IQ';
const String kFixturePeerSessionId = '0123456789abcdef0123456789abcdef';
const String kFixturePeerSessionIdOther = 'fedcba9876543210fedcba9876543210';
const String kFixtureLogicalA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String kFixtureLogicalB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String kFixtureLogicalC = 'cccccccccccccccccccccccccccccccc';

PeerFingerprint fixtureFingerprint() =>
    PeerFingerprint.parse(kFixtureFingerprint);

PeerFingerprint fixtureFingerprintOther() =>
    PeerFingerprint.parse(kFixtureFingerprintOther);

DisplayName fixtureName() => DisplayName.parse('Kitchen tablet');

LogicalId idA() => LogicalId.parse(kFixtureLogicalA);
LogicalId idB() => LogicalId.parse(kFixtureLogicalB);
LogicalId idC() => LogicalId.parse(kFixtureLogicalC);

PeerSessionId fixturePeerSessionId() =>
    PeerSessionId.parse(kFixturePeerSessionId);

PeerSessionId fixturePeerSessionIdOther() =>
    PeerSessionId.parse(kFixturePeerSessionIdOther);

HandshakeAuthenticated trustedHandshake({
  PeerFingerprint? fingerprint,
  PeerSessionId? peerSessionId,
}) {
  return HandshakeAuthenticated.trusted(
    authenticatedFingerprint: fingerprint ?? fixtureFingerprint(),
    peerSessionId: peerSessionId ?? fixturePeerSessionId(),
  );
}

HandshakeAuthenticated firstContactHandshake({
  PeerFingerprint? fingerprint,
  PeerSessionId? peerSessionId,
}) {
  return HandshakeAuthenticated.firstContact(
    authenticatedFingerprint: fingerprint ?? fixtureFingerprint(),
    peerSessionId: peerSessionId ?? fixturePeerSessionId(),
  );
}

/// Independent expected-matrix check. Does not consult production isLegal().
void expectIndependentMatrix<S extends Enum, E extends Enum, T>({
  required Map<S, T> specimens,
  required Map<S, Map<E, S>> expected,
  required List<S> states,
  required List<E> events,
  required T Function(T current, E event) apply,
  required S Function(T current) stateOf,
}) {
  for (final S from in states) {
    final T? specimen = specimens[from];
    expect(specimen, isNotNull, reason: 'missing specimen for $from');
    expect(stateOf(specimen as T), from, reason: 'specimen not in $from');
    for (final E event in events) {
      final S? want = expected[from]?[event];
      if (want != null) {
        final T next = apply(specimen, event);
        expect(stateOf(next), want, reason: '$from + $event');
        expect(
          stateOf(specimen),
          from,
          reason: 'source mutated: $from + $event',
        );
      } else {
        expect(
          () => apply(specimen, event),
          throwsA(isA<InvalidStateTransition>()),
          reason: '$from + $event should be illegal',
        );
        expect(
          stateOf(specimen),
          from,
          reason: 'illegal mutated $from + $event',
        );
      }
    }
  }
}
