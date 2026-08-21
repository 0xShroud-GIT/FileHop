import 'package:filehop/domain/transport/transport_candidate.dart';
import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_fixtures.dart';

void main() {
  test(
    'localhost LAN backend feeds manager and selector as fallback',
    () async {
      final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend();
      final LanTransportAdapter lan = LanTransportAdapter(backend: backend);
      final TransportManager manager = TransportManager();
      await manager.registerAdapter(lan);
      await lan.startDiscovery();
      backend.emitFound(lanRecord());
      await Future<void>.delayed(Duration.zero);

      final TransportCandidateKey key = TransportCandidateKey(
        kind: TransportKind.lan,
        candidateId: kLanIdB,
      );
      expect(manager.candidates[key], isNotNull);
      expect(
        manager.candidates[key]!.candidate.state,
        TransportCandidateState.available,
      );

      final TransportSelection selection = manager.reconcile(
        const TransportAcquireRequest(localPlatform: TransportPlatform.android),
      );
      expect(selection, isA<TransportSelected>());
      expect((selection as TransportSelected).chosen, key);

      await lan.close();
      await manager.close();
    },
  );

  test('healthy Direct path stays sticky when LAN appears', () async {
    final FakeTransportAdapter direct = FakeTransportAdapter(
      kind: TransportKind.wifiDirect,
      availability: TransportAvailability.supportedAvailable,
    );
    final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend();
    final LanTransportAdapter lan = LanTransportAdapter(backend: backend);
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(direct);
    await manager.registerAdapter(lan);

    direct.emitCandidate(candidateId: 'direct-1');
    await Future<void>.delayed(Duration.zero);
    final SelectedTransportPath path = await manager.acquire(
      const TransportAcquireRequest(localPlatform: TransportPlatform.android),
    );
    expect(path.kind, TransportKind.wifiDirect);

    await lan.startDiscovery();
    backend.emitFound(lanRecord());
    await Future<void>.delayed(Duration.zero);

    final TransportSelection selection = manager.reconcile(
      const TransportAcquireRequest(localPlatform: TransportPlatform.android),
    );
    expect(selection, isA<TransportRetainCurrent>());
    expect(
      (selection as TransportRetainCurrent).path.kind,
      TransportKind.wifiDirect,
    );

    await lan.close();
    await manager.close();
    await direct.close();
  });

  test('LAN permissionRequired candidate is not auto-selected', () async {
    final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend(
      availability: TransportAvailability.permissionRequired,
    );
    final LanTransportAdapter lan = LanTransportAdapter(backend: backend);
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    await lan.startDiscovery();
    backend.emitFound(lanRecord());
    await Future<void>.delayed(Duration.zero);

    final TransportSelection selection = manager.reconcile(
      const TransportAcquireRequest(localPlatform: TransportPlatform.android),
    );
    expect(selection, isA<TransportNone>());
    expect(
      (selection as TransportNone).reason,
      TransportSelectionReason.permissionBlocked,
    );

    await lan.close();
    await manager.close();
  });

  test('source-kind isolation still holds for LAN events', () async {
    final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend();
    final LanTransportAdapter lan = LanTransportAdapter(backend: backend);
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    await lan.startDiscovery();
    backend.emitFound(lanRecord());
    await Future<void>.delayed(Duration.zero);
    expect(manager.lastContractError, isNull);
    await lan.close();
    await manager.close();
  });

  test('lost then found creates a fresh Mission 06 generation', () async {
    final FakeLanDiscoveryBackend backend = FakeLanDiscoveryBackend();
    final LanTransportAdapter lan = LanTransportAdapter(backend: backend);
    final TransportManager manager = TransportManager();
    await manager.registerAdapter(lan);
    await lan.startDiscovery();
    backend.emitFound(lanRecord());
    await Future<void>.delayed(Duration.zero);
    final TransportCandidateKey key = TransportCandidateKey(
      kind: TransportKind.lan,
      candidateId: kLanIdB,
    );
    final int gen1 = manager.candidates[key]!.generation;
    backend.emitLost(lanId(kLanIdB));
    await Future<void>.delayed(Duration.zero);
    expect(
      manager.candidates[key]!.candidate.state,
      TransportCandidateState.unavailable,
    );
    backend.emitFound(lanRecord());
    await Future<void>.delayed(Duration.zero);
    expect(
      manager.candidates[key]!.candidate.state,
      TransportCandidateState.available,
    );
    expect(manager.candidates[key]!.generation, greaterThan(gen1));
    await lan.close();
    await manager.close();
  });
}
