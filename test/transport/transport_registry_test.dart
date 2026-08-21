import 'package:filehop/domain/state_machine/transition_authority.dart';
import 'package:filehop/domain/transport/transport_candidate.dart';
import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('duplicate adapter registration is rejected', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter first = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    final FakeTransportAdapter second = FakeTransportAdapter(
      kind: TransportKind.lan,
    );
    await registry.register(first);
    await expectLater(
      registry.register(second),
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.invalidArgument,
        ),
      ),
    );
    expect(identical(registry.adapterFor(TransportKind.lan), first), isTrue);
    await registry.close();
    await first.close();
    await second.close();
  });

  test('registration does not invent SUPPORTED_AVAILABLE', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.wifiAware,
    );
    await registry.register(adapter);
    expect(
      registry.snapshotFor(TransportKind.wifiAware)!.availability,
      TransportAvailability.unsupported,
    );
    expect(registry.eligibleKinds(), isEmpty);
    await registry.close();
    await adapter.close();
  });

  test('five availability states remain distinct', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.permissionRequired,
    );
    await registry.register(adapter);
    expect(
      registry.snapshotFor(TransportKind.lan)!.availability,
      isNot(TransportAvailability.supportedUnavailable),
    );
    expect(
      registry.snapshotFor(TransportKind.lan)!.availability,
      isNot(TransportAvailability.failed),
    );
    adapter.setAvailability(TransportAvailability.failed);
    await Future<void>.delayed(Duration.zero);
    expect(
      registry.snapshotFor(TransportKind.lan)!.availability,
      TransportAvailability.failed,
    );
    expect(
      registry.snapshotFor(TransportKind.lan)!.availability,
      isNot(TransportAvailability.unsupported),
    );
    await registry.close();
    await adapter.close();
  });

  test('permission event does not invent availability', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.wifiAware,
      availability: TransportAvailability.supportedUnavailable,
    );
    await registry.register(adapter);
    registry.ingest(
      TransportKind.wifiAware,
      const AdapterPermissionChanged(
        kind: TransportKind.wifiAware,
        permission: TransportPermissionStatus.denied,
      ),
    );
    expect(
      registry.snapshotFor(TransportKind.wifiAware)!.availability,
      TransportAvailability.supportedUnavailable,
    );
    expect(
      registry.snapshotFor(TransportKind.wifiAware)!.permission,
      TransportPermissionStatus.denied,
    );
    await registry.close();
    await adapter.close();
  });

  test('adapter error does not become FAILED', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    await registry.register(adapter);
    registry.ingest(
      TransportKind.lan,
      const AdapterErrorEvent(kind: TransportKind.lan, message: 'radio glitch'),
    );
    expect(
      registry.snapshotFor(TransportKind.lan)!.availability,
      TransportAvailability.supportedAvailable,
    );
    await registry.close();
    await adapter.close();
  });

  test('mismatched event kind is a bounded contract failure', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    await registry.register(adapter);
    registry.ingest(
      TransportKind.lan,
      const AdapterAvailabilityChanged(
        kind: TransportKind.wifiAware,
        snapshot: TransportCapabilitySnapshot(
          kind: TransportKind.wifiAware,
          availability: TransportAvailability.failed,
        ),
      ),
    );
    expect(
      registry.lastContractError?.kind,
      TransportFailureKind.adapterContractViolation,
    );
    expect(
      registry.snapshotFor(TransportKind.lan)!.availability,
      TransportAvailability.supportedAvailable,
    );
    await registry.close();
    await adapter.close();
  });

  test('snapshots are immutable to callers', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    await registry.register(adapter);
    final Map<TransportKind, TransportCapabilitySnapshot> view = registry
        .snapshots();
    expect(() => view.remove(TransportKind.lan), throwsUnsupportedError);
    expect(registry.snapshotFor(TransportKind.lan), isNotNull);
    await registry.close();
    await adapter.close();
  });

  test('same candidateId on Aware and LAN coexist', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(
      kind: TransportKind.wifiAware,
      candidateId: 'candidate-1',
      displayLabel: 'Phone',
    );
    candidates.recordFound(
      kind: TransportKind.lan,
      candidateId: 'candidate-1',
      displayLabel: 'Phone',
      locatorHint: '192.0.2.8',
    );
    expect(candidates.all(), hasLength(2));
    candidates.recordLost(
      kind: TransportKind.wifiAware,
      candidateId: 'candidate-1',
    );
    expect(
      candidates[const TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: 'candidate-1',
      )],
      isNotNull,
    );
    expect(
      candidates[const TransportCandidateKey(
            kind: TransportKind.wifiAware,
            candidateId: 'candidate-1',
          )]!
          .candidate
          .state,
      TransportCandidateState.unavailable,
    );
  });

  test('stale update does not resurrect a lost candidate', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(kind: TransportKind.lan, candidateId: 'l1');
    candidates.recordLost(kind: TransportKind.lan, candidateId: 'l1');
    candidates.recordUpdated(
      kind: TransportKind.lan,
      candidateId: 'l1',
      locatorHint: 'new',
    );
    expect(
      candidates[const TransportCandidateKey(
            kind: TransportKind.lan,
            candidateId: 'l1',
          )]!
          .candidate
          .state,
      TransportCandidateState.unavailable,
    );
    candidates.recordLost(kind: TransportKind.lan, candidateId: 'l1');
  });

  test('candidate views cannot mutate registry state', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(kind: TransportKind.lan, candidateId: 'l1');
    final views = candidates.selectableViews();
    expect(() => views.removeLast(), throwsUnsupportedError);
    expect(candidates.all(), hasLength(1));
  });

  test('candidate update applies locator metadata and keeps state', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(
      kind: TransportKind.lan,
      candidateId: 'l1',
      locatorHint: 'locator-a',
    );
    final TransportCandidateKey key = const TransportCandidateKey(
      kind: TransportKind.lan,
      candidateId: 'l1',
    );
    candidates.tryApply(
      key,
      TransportCandidateEvent.startConnect,
      authority: TransitionAuthority.localCommand,
    );
    candidates.recordUpdated(
      kind: TransportKind.lan,
      candidateId: 'l1',
      locatorHint: 'locator-b',
      displayLabel: 'Desk',
    );
    expect(
      candidates[key]!.candidate.state,
      TransportCandidateState.connecting,
    );
    expect(candidates[key]!.candidate.locatorHint, 'locator-b');
    expect(candidates[key]!.displayLabel, 'Desk');
  });

  test('duplicate found preserves CONNECTING and CONNECTED', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(kind: TransportKind.lan, candidateId: 'l1');
    final TransportCandidateKey key = const TransportCandidateKey(
      kind: TransportKind.lan,
      candidateId: 'l1',
    );
    candidates.tryApply(
      key,
      TransportCandidateEvent.startConnect,
      authority: TransitionAuthority.localCommand,
    );
    candidates.recordFound(
      kind: TransportKind.lan,
      candidateId: 'l1',
      locatorHint: 'hint-2',
    );
    expect(
      candidates[key]!.candidate.state,
      TransportCandidateState.connecting,
    );
    candidates.tryApply(
      key,
      TransportCandidateEvent.connected,
      authority: TransitionAuthority.transportEvent,
    );
    candidates.recordFound(
      kind: TransportKind.lan,
      candidateId: 'l1',
      locatorHint: 'hint-3',
    );
    expect(candidates[key]!.candidate.state, TransportCandidateState.connected);
    expect(candidates[key]!.candidate.locatorHint, 'hint-3');
  });

  test('lost then found starts a fresh AVAILABLE lifecycle', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(kind: TransportKind.lan, candidateId: 'l1');
    candidates.recordLost(kind: TransportKind.lan, candidateId: 'l1');
    candidates.recordFound(kind: TransportKind.lan, candidateId: 'l1');
    expect(
      candidates[const TransportCandidateKey(
            kind: TransportKind.lan,
            candidateId: 'l1',
          )]!
          .candidate
          .state,
      TransportCandidateState.available,
    );
  });

  test('Mission 03 state machine remains authoritative', () {
    final TransportCandidateRegistry candidates = TransportCandidateRegistry();
    candidates.recordFound(kind: TransportKind.lan, candidateId: 'l1');
    final TransportCandidateKey key = const TransportCandidateKey(
      kind: TransportKind.lan,
      candidateId: 'l1',
    );
    expect(candidates[key]!.candidate.state, TransportCandidateState.available);
    expect(
      candidates.tryApply(
        key,
        TransportCandidateEvent.connected,
        authority: TransitionAuthority.transportEvent,
      ),
      isFalse,
    );
    expect(candidates[key]!.candidate.state, TransportCandidateState.available);
  });
}
