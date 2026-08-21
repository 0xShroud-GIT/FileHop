import 'package:filehop/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  test('logical ids validate 32 lowercase hex', () {
    expect(LogicalId.parse(kFixtureLogicalA).value, kFixtureLogicalA);
    expect(() => LogicalId.parse('ABC'), throwsA(isA<DomainFormatException>()));
    expect(
      () => LogicalId.parse('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
      throwsA(isA<DomainFormatException>()),
    );
    expect(
      () => LogicalId.parse('0123456789abcdef0123456789abcde'),
      throwsA(isA<DomainFormatException>()),
    );
  });

  test('LogicalId.generate uses secure 32 lowercase hex values', () {
    final List<LogicalId> generated = <LogicalId>[
      LogicalId.generate(),
      LogicalId.generate(),
      LogicalId.generate(),
    ];
    for (final LogicalId id in generated) {
      expect(id.value, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id.value), isTrue);
      expect(LogicalId.parse(id.value), id);
    }
    expect(
      generated.map((LogicalId id) => id.value).toSet().length,
      greaterThan(1),
    );
  });

  test('peerSessionId is validated and is not randomly derived', () {
    expect(fixturePeerSessionId().value, kFixturePeerSessionId);
    expect(
      () => PeerSessionId.parse('not-a-session-id'),
      throwsA(isA<DomainFormatException>()),
    );
    expect(PeerSessionId.parse, isNot(equals(LogicalId.generate)));
  });

  test('fingerprint is opaque and distinct from display name', () {
    final PeerFingerprint fingerprint = fixtureFingerprint();
    final DisplayName name = fixtureName();
    final PeerIdentity identity = PeerIdentity(
      fingerprint: fingerprint,
      displayName: name,
    );
    expect(
      identity,
      PeerIdentity(
        fingerprint: fingerprint,
        displayName: DisplayName.parse('Other'),
      ),
    );
    expect(identity.displayName, name);
    expect(fingerprint.value.contains(' '), isFalse);
    expect(
      () => PeerFingerprint.parse(''),
      throwsA(isA<DomainFormatException>()),
    );
    expect(
      () => PeerFingerprint.parse('has space'),
      throwsA(isA<DomainFormatException>()),
    );
    expect(
      () => PeerFingerprint.parse(kFixtureFingerprint.toLowerCase()),
      throwsA(isA<DomainFormatException>()),
    );
    expect(
      () => PeerFingerprint.parse('$kFixtureFingerprint===='),
      throwsA(isA<DomainFormatException>()),
    );
    expect(
      () => PeerFingerprint.parse(' $kFixtureFingerprint'),
      throwsA(isA<DomainFormatException>()),
    );
    expect(
      () => DisplayName.parse('x' * 129),
      throwsA(isA<DomainFormatException>()),
    );
  });

  test('peer local record id is not security identity', () {
    final Peer peer = Peer(
      fingerprint: fixtureFingerprint(),
      localRecordId: '42',
      displayName: fixtureName(),
    );
    expect(peer.localRecordId, isNot(peer.fingerprint.value));
    expect(peer.fingerprint, fixtureFingerprint());
  });

  test('share session is an aggregate without a competing lifecycle', () {
    final ShareSession share = ShareSession(
      shareSessionId: idA(),
      transferId: idB(),
      peerFingerprint: fixtureFingerprint(),
      direction: ShareDirection.outgoing,
      itemIds: <LogicalId>[idC()],
    );
    expect(share.shareSessionId, idA());
    expect(share.transferId, idB());
    expect(share.peerFingerprint, fixtureFingerprint());
  });
}
