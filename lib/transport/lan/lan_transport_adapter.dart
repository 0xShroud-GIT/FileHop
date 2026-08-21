import 'dart:async';

import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_adapter.dart';
import '../adapter/transport_adapter_event.dart';
import '../adapter/transport_adapter_types.dart';
import '../adapter/transport_availability.dart';
import '../errors.dart';
import 'lan_constants.dart';
import 'lan_discovery_backend.dart';
import 'lan_discovery_errors.dart';
import 'lan_discovery_event.dart';
import 'lan_discovery_instance_id.dart';
import 'lan_discovery_record.dart';

/// Shared LAN [TransportAdapter]. Discovery only — no Mission 10 data plane.
class LanTransportAdapter implements TransportAdapter {
  LanTransportAdapter({required this._backend}) {
    _subscription = _backend.events.listen(_onBackendEvent);
  }

  final LanDiscoveryBackend _backend;
  late final StreamSubscription<LanDiscoveryEvent> _subscription;

  final StreamController<TransportAdapterEvent> _events =
      StreamController<TransportAdapterEvent>.broadcast();

  final Map<String, LanDiscoveryRecord> _live = <String, LanDiscoveryRecord>{};
  final List<String> operations = <String>[];
  int _acceptedGeneration = 0;
  bool _closed = false;

  @override
  TransportKind get kind => TransportKind.lan;

  @override
  Stream<TransportAdapterEvent> get events => _events.stream;

  Map<String, LanDiscoveryRecord> liveRecords() {
    return Map<String, LanDiscoveryRecord>.unmodifiable(
      Map<String, LanDiscoveryRecord>.of(_live),
    );
  }

  @override
  Future<TransportCapabilitySnapshot> observeAvailability() {
    return _backend.observeAvailability();
  }

  @override
  Future<void> startDiscovery() async {
    operations.add('lan.discovery.start');
    try {
      await _backend.startBrowse();
      _acceptedGeneration = _backend.browseGeneration;
    } on LanDiscoveryException catch (error) {
      _events.add(
        AdapterErrorEvent(
          kind: TransportKind.lan,
          message: error.message,
          code: error.kind.name,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    operations.add('lan.discovery.stop');
    await _backend.stopBrowse();
    _clearLiveAsLost();
  }

  Future<void> configureAdvertisement({
    required int port,
    LanDiscoveryInstanceId? instanceId,
  }) {
    return _backend.configureAdvertisement(port: port, instanceId: instanceId);
  }

  Future<void> startAdvertisement() => _backend.startAdvertisement();

  Future<void> stopAdvertisement() => _backend.stopAdvertisement();

  @override
  Future<TransportConnectionHandle> connect(
    TransportCandidateKey candidate,
  ) async {
    if (candidate.kind != TransportKind.lan) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'LAN adapter connect kind mismatch',
      );
    }
    throw const TransportException(
      kind: TransportFailureKind.adapterUnavailable,
      message: 'LAN connect is Mission 10; discovery-only adapter',
    );
  }

  @override
  Future<void> disconnect(TransportConnectionHandle connection) async {
    if (connection.kind != TransportKind.lan) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'LAN adapter disconnect kind mismatch',
      );
    }
    throw const TransportException(
      kind: TransportFailureKind.adapterUnavailable,
      message: 'LAN disconnect is Mission 10; discovery-only adapter',
    );
  }

  @override
  Future<TransportEndpoint> openEndpoint(
    TransportConnectionHandle connection,
  ) async {
    if (connection.kind != TransportKind.lan) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'LAN adapter openEndpoint kind mismatch',
      );
    }
    throw const TransportException(
      kind: TransportFailureKind.adapterUnavailable,
      message: 'LAN openEndpoint is Mission 10; discovery-only adapter',
    );
  }

  @override
  Future<void> releaseAttempt(TransportCandidateKey candidate) async {
    if (candidate.kind != TransportKind.lan) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'LAN adapter releaseAttempt kind mismatch',
      );
    }
    operations.add('lan.releaseAttempt.success');
  }

  void _onBackendEvent(LanDiscoveryEvent event) {
    if (_closed) {
      return;
    }
    switch (event) {
      case LanAvailabilityChanged(:final snapshot):
        if (snapshot.kind != TransportKind.lan) {
          return;
        }
        _events.add(
          AdapterAvailabilityChanged(
            kind: TransportKind.lan,
            snapshot: snapshot,
          ),
        );
        if (!snapshot.availability.isAutoEligible) {
          _clearLiveAsLost();
        }
      case LanDiscoveryErrorEvent(:final kind, :final message):
        _events.add(
          AdapterErrorEvent(
            kind: TransportKind.lan,
            message: message,
            code: kind.name,
          ),
        );
      case LanRecordFound(:final generation, :final record):
        _onFoundOrUpdated(generation: generation, record: record, found: true);
      case LanRecordUpdated(:final generation, :final record):
        _onFoundOrUpdated(generation: generation, record: record, found: false);
      case LanRecordLost(:final generation, :final instanceId):
        if (!_generationLive(generation)) {
          return;
        }
        _lose(instanceId.value);
    }
  }

  bool _generationLive(int generation) {
    return generation == _acceptedGeneration && generation != 0;
  }

  void _onFoundOrUpdated({
    required int generation,
    required LanDiscoveryRecord record,
    required bool found,
  }) {
    if (!_generationLive(generation)) {
      return;
    }
    if (record.serviceType != kFileHopLanServiceType) {
      _events.add(
        const AdapterErrorEvent(
          kind: TransportKind.lan,
          message: 'wrong LAN service type',
          code: 'wrongServiceType',
        ),
      );
      return;
    }
    final LanDiscoveryInstanceId? self = _backend.localInstanceId;
    if (self != null && self == record.instanceId) {
      operations.add('lan.selfFiltered.${record.candidateId}');
      return;
    }
    final String id = record.candidateId;
    final bool known = _live.containsKey(id);
    if (!known && _live.length >= kFileHopLanMaxActiveCandidates) {
      _events.add(
        const AdapterErrorEvent(
          kind: TransportKind.lan,
          message: 'active LAN candidate limit exceeded',
          code: 'candidateLimitExceeded',
        ),
      );
      return;
    }
    _live[id] = record;
    if (!known && found) {
      _events.add(
        AdapterCandidateFound(
          kind: TransportKind.lan,
          candidateId: id,
          displayLabel: record.serviceInstanceName,
          locatorHint: record.locatorHint,
        ),
      );
    } else {
      _events.add(
        AdapterCandidateUpdated(
          kind: TransportKind.lan,
          candidateId: id,
          displayLabel: record.serviceInstanceName,
          locatorHint: record.locatorHint,
        ),
      );
    }
  }

  void _lose(String candidateId) {
    if (!_live.containsKey(candidateId)) {
      return;
    }
    _live.remove(candidateId);
    _events.add(
      AdapterCandidateLost(kind: TransportKind.lan, candidateId: candidateId),
    );
  }

  void _clearLiveAsLost() {
    final List<String> ids = _live.keys.toList();
    _live.clear();
    for (final String id in ids) {
      _events.add(
        AdapterCandidateLost(kind: TransportKind.lan, candidateId: id),
      );
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription.cancel();
    await _backend.close();
    await _events.close();
  }
}
