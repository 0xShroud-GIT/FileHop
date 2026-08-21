import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_fixtures.dart';

void main() {
  late FakeLanDiscoveryBackend backend;
  late LanTransportAdapter adapter;
  late List<TransportAdapterEvent> events;

  setUp(() async {
    backend = FakeLanDiscoveryBackend();
    adapter = LanTransportAdapter(backend: backend);
    events = <TransportAdapterEvent>[];
    adapter.events.listen(events.add);
  });

  tearDown(() async {
    await adapter.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('valid discovery emits LAN candidateFound', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord());
    await pump();
    final AdapterCandidateFound found = events
        .whereType<AdapterCandidateFound>()
        .single;
    expect(found.kind, TransportKind.lan);
    expect(found.candidateId, kLanIdB);
    expect(adapter.liveRecords().containsKey(kLanIdB), isTrue);
  });

  test('self discovery is filtered', () async {
    await adapter.configureAdvertisement(
      port: 7240,
      instanceId: lanId(kLanIdA),
    );
    await adapter.startAdvertisement();
    await adapter.startDiscovery();
    backend.emitFound(lanRecord(id: kLanIdA));
    await pump();
    expect(events.whereType<AdapterCandidateFound>(), isEmpty);
    expect(adapter.liveRecords(), isEmpty);
    backend.emitFound(lanRecord(id: kLanIdB));
    await pump();
    expect(
      events.whereType<AdapterCandidateFound>().single.candidateId,
      kLanIdB,
    );
  });

  test('candidate update preserves key', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord(port: 7240, hosts: <String>['127.0.0.1']));
    await pump();
    backend.emitUpdated(lanRecord(port: 8000, hosts: <String>['::1']));
    await pump();
    expect(events.whereType<AdapterCandidateFound>(), hasLength(1));
    final AdapterCandidateUpdated updated = events
        .whereType<AdapterCandidateUpdated>()
        .single;
    expect(updated.candidateId, kLanIdB);
    expect(updated.kind, TransportKind.lan);
    expect(adapter.liveRecords()[kLanIdB]!.port, 8000);
  });

  test('duplicate found on live candidate is update not reset', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord());
    await pump();
    backend.emitFound(
      lanRecord(port: 9000, hosts: <String>['127.0.0.1', '::1']),
    );
    await pump();
    expect(events.whereType<AdapterCandidateFound>(), hasLength(1));
    expect(events.whereType<AdapterCandidateUpdated>(), hasLength(1));
  });

  test('candidate lost is emitted', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord());
    await pump();
    backend.emitLost(lanId(kLanIdB));
    await pump();
    expect(
      events.whereType<AdapterCandidateLost>().single.candidateId,
      kLanIdB,
    );
    expect(adapter.liveRecords(), isEmpty);
  });

  test('duplicate service names stay distinct candidates', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord(id: kLanIdA, serviceName: 'FileHop'));
    backend.emitFound(lanRecord(id: kLanIdB, serviceName: 'FileHop'));
    await pump();
    expect(
      events.whereType<AdapterCandidateFound>().map(
        (AdapterCandidateFound e) => e.candidateId,
      ),
      <String>[kLanIdA, kLanIdB],
    );
  });

  test('IPv4 and IPv6 stay one candidate', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord(hosts: <String>['127.0.0.1', '::1']));
    await pump();
    expect(events.whereType<AdapterCandidateFound>(), hasLength(1));
    expect(adapter.liveRecords()[kLanIdB]!.addresses, hasLength(2));
  });

  test('wrong service type is rejected', () {
    expect(
      () => lanRecord(serviceType: '_printer._tcp'),
      throwsA(
        isA<LanDiscoveryException>().having(
          (LanDiscoveryException e) => e.kind,
          'kind',
          LanDiscoveryFailureKind.wrongServiceType,
        ),
      ),
    );
  });

  test('invalid port 0 rejected', () {
    expect(() => lanRecord(port: 0), throwsA(isA<LanDiscoveryException>()));
  });

  test('invalid port above 65535 rejected', () {
    expect(() => lanRecord(port: 65536), throwsA(isA<LanDiscoveryException>()));
  });

  test('too many addresses rejected', () {
    expect(
      () => lanRecord(
        hosts: <String>[
          '127.0.0.1',
          '127.0.0.2',
          '127.0.0.3',
          '127.0.0.4',
          '127.0.0.5',
          '127.0.0.6',
          '127.0.0.7',
          '127.0.0.8',
          '127.0.0.9',
        ],
      ),
      throwsA(isA<LanDiscoveryException>()),
    );
  });

  test('stop discovery clears live records via lost events', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord());
    await pump();
    await adapter.stopDiscovery();
    await pump();
    expect(adapter.liveRecords(), isEmpty);
    expect(events.whereType<AdapterCandidateLost>(), isNotEmpty);
    expect(backend.browsing, isFalse);
  });

  test('start start stop stop is idempotent', () async {
    await adapter.startDiscovery();
    await adapter.startDiscovery();
    await adapter.stopDiscovery();
    await adapter.stopDiscovery();
    expect(
      backend.operations.where((String o) => o == 'browse.start'),
      hasLength(2),
    );
    expect(backend.browsing, isFalse);
  });

  test('restart uses a new generation and ignores stale callbacks', () async {
    await adapter.startDiscovery();
    final int gen1 = backend.browseGeneration;
    backend.emitFound(lanRecord(id: kLanIdB));
    await pump();
    await adapter.stopDiscovery();
    await adapter.startDiscovery();
    final int gen2 = backend.browseGeneration;
    expect(gen2, greaterThan(gen1));
    backend.emitStaleFound(gen1, lanRecord(id: kLanIdC));
    await pump();
    expect(
      events.whereType<AdapterCandidateFound>().map(
        (AdapterCandidateFound e) => e.candidateId,
      ),
      isNot(contains(kLanIdC)),
    );
    backend.emitFound(lanRecord(id: kLanIdA));
    await pump();
    expect(events.whereType<AdapterCandidateFound>().last.candidateId, kLanIdA);
  });

  test('advertisement restart generates a new local instance id', () async {
    await adapter.configureAdvertisement(
      port: 7240,
      instanceId: lanId(kLanIdA),
    );
    await adapter.startAdvertisement();
    expect(backend.localInstanceId!.value, kLanIdA);
    await adapter.stopAdvertisement();
    expect(backend.localInstanceId, isNull);
    await adapter.configureAdvertisement(port: 7240);
    expect(backend.localInstanceId!.value, isNot(kLanIdA));
    expect(backend.localInstanceId!.value.length, 32);
  });

  test('port 0 cannot be configured for advertisement', () async {
    await expectLater(
      adapter.configureAdvertisement(port: 0),
      throwsA(isA<LanDiscoveryException>()),
    );
    await expectLater(
      adapter.startAdvertisement(),
      throwsA(
        isA<LanDiscoveryException>().having(
          (LanDiscoveryException e) => e.kind,
          'kind',
          LanDiscoveryFailureKind.advertisementNotConfigured,
        ),
      ),
    );
  });

  test('connect is truthful not-ready', () async {
    await expectLater(
      adapter.connect(
        const TransportCandidateKey(
          kind: TransportKind.lan,
          candidateId: kLanIdB,
        ),
      ),
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.adapterUnavailable,
        ),
      ),
    );
  });

  test('releaseAttempt is not an empty success no-op', () async {
    await adapter.releaseAttempt(
      const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: kLanIdB,
      ),
    );
    expect(adapter.operations, contains('lan.releaseAttempt.success'));
  });

  test('live record snapshots are unmodifiable', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord());
    await pump();
    final Map<String, LanDiscoveryRecord> snap = adapter.liveRecords();
    expect(
      () => snap[kLanIdA] = lanRecord(id: kLanIdA),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => adapter.liveRecords()[kLanIdB]!.addresses.add(
        const LanResolvedAddress(
          family: LanAddressFamily.ipv4,
          host: '1.1.1.1',
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('candidate cap drops extras without crashing', () async {
    await adapter.startDiscovery();
    for (int i = 0; i < kFileHopLanMaxActiveCandidates; i++) {
      final String id = i.toRadixString(16).padLeft(32, '0');
      backend.emitFound(lanRecord(id: id));
    }
    await pump();
    backend.emitFound(lanRecord(id: kLanIdC));
    await pump();
    expect(adapter.liveRecords().length, kFileHopLanMaxActiveCandidates);
    expect(
      events.whereType<AdapterErrorEvent>().any(
        (AdapterErrorEvent e) => e.code == 'candidateLimitExceeded',
      ),
      isTrue,
    );
  });

  test('availability loss does not select LAN and clears discovery', () async {
    await adapter.startDiscovery();
    backend.emitFound(lanRecord());
    await pump();
    backend.setAvailability(TransportAvailability.supportedUnavailable);
    await pump();
    expect(adapter.liveRecords(), isEmpty);
    final TransportCapabilitySnapshot snap = await adapter
        .observeAvailability();
    expect(snap.availability.isAutoEligible, isFalse);
  });

  test('permission required is not auto-selected', () async {
    backend.availability = TransportAvailability.permissionRequired;
    final TransportCapabilitySnapshot snap = await adapter
        .observeAvailability();
    expect(snap.availability, TransportAvailability.permissionRequired);
    expect(snap.availability.isAutoEligible, isFalse);
  });

  test('parse errors do not flip availability to failed', () async {
    await adapter.startDiscovery();
    backend.emitError(
      LanDiscoveryFailureKind.malformedDiscoveryRecord,
      'bad txt',
    );
    await pump();
    expect(events.whereType<AdapterErrorEvent>(), isNotEmpty);
    final TransportCapabilitySnapshot snap = await adapter
        .observeAvailability();
    expect(snap.availability, TransportAvailability.supportedAvailable);
  });

  test('compound key lan vs aware stay distinct', () {
    const TransportCandidateKey lan = TransportCandidateKey(
      kind: TransportKind.lan,
      candidateId: kLanIdA,
    );
    const TransportCandidateKey aware = TransportCandidateKey(
      kind: TransportKind.wifiAware,
      candidateId: kLanIdA,
    );
    expect(lan == aware, isFalse);
  });

  test('instance id generate is 32 lowercase hex', () {
    final LanDiscoveryInstanceId id = LanDiscoveryInstanceId.generate();
    expect(id.value, matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
