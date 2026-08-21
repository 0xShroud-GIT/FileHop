import 'dart:async';

import '../../../domain/transport/transport_kind.dart';
import '../../adapter/transport_adapter_types.dart';
import '../../adapter/transport_availability.dart';
import '../lan_discovery_backend.dart';
import '../lan_discovery_errors.dart';
import '../lan_discovery_event.dart';
import '../lan_discovery_instance_id.dart';
import '../lan_discovery_record.dart';

/// Deterministic in-process LAN backend. Never a production default.
/// Does not claim mDNS / NSD / Bonjour runtime.
class FakeLanDiscoveryBackend implements LanDiscoveryBackend {
  FakeLanDiscoveryBackend({
    this.availability = TransportAvailability.supportedAvailable,
    this.permission,
  });

  TransportAvailability availability;
  TransportPermissionStatus? permission;

  bool failStartBrowse = false;
  bool failStartAdvertisement = false;

  int _browseGeneration = 0;
  int? _configuredPort;
  LanDiscoveryInstanceId? _localInstanceId;
  bool _browsing = false;
  bool _advertising = false;
  bool _closed = false;

  final StreamController<LanDiscoveryEvent> _events =
      StreamController<LanDiscoveryEvent>.broadcast();

  final List<String> operations = <String>[];

  @override
  Stream<LanDiscoveryEvent> get events => _events.stream;

  @override
  int get browseGeneration => _browseGeneration;

  @override
  LanDiscoveryInstanceId? get localInstanceId => _localInstanceId;

  @override
  bool get browsing => _browsing;

  @override
  bool get advertising => _advertising;

  int? get configuredPort => _configuredPort;

  @override
  Future<TransportCapabilitySnapshot> observeAvailability() async {
    return TransportCapabilitySnapshot(
      kind: TransportKind.lan,
      availability: availability,
      permission: permission,
    );
  }

  void setAvailability(TransportAvailability next) {
    availability = next;
    _events.add(
      LanAvailabilityChanged(
        generation: _browseGeneration,
        snapshot: TransportCapabilitySnapshot(
          kind: TransportKind.lan,
          availability: next,
          permission: permission,
        ),
      ),
    );
  }

  @override
  Future<void> startBrowse() async {
    operations.add('browse.start');
    if (_browsing) {
      operations.add('browse.start.idempotent');
      return;
    }
    if (failStartBrowse) {
      operations.add('browse.start.fail');
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.discoveryStartFailed,
        message: 'fake browse start failed',
      );
    }
    _browseGeneration += 1;
    _browsing = true;
    operations.add('browse.start.generation.$_browseGeneration');
  }

  @override
  Future<void> stopBrowse() async {
    operations.add('browse.stop');
    _browsing = false;
  }

  @override
  Future<void> configureAdvertisement({
    required int port,
    LanDiscoveryInstanceId? instanceId,
  }) async {
    if (port < 1 || port > 65535) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'advertisement port must be 1..65535',
      );
    }
    _configuredPort = port;
    _localInstanceId = instanceId ?? LanDiscoveryInstanceId.generate();
    operations.add('advertise.configure.port.$port');
  }

  @override
  Future<void> startAdvertisement() async {
    operations.add('advertise.start');
    if (_advertising) {
      operations.add('advertise.start.idempotent');
      return;
    }
    if (_configuredPort == null || _localInstanceId == null) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.advertisementNotConfigured,
        message: 'LAN advertisement has no legitimate listener port',
      );
    }
    if (failStartAdvertisement) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.discoveryStartFailed,
        message: 'fake advertisement start failed',
      );
    }
    _advertising = true;
  }

  @override
  Future<void> stopAdvertisement() async {
    operations.add('advertise.stop');
    final bool wasAdvertising = _advertising;
    _advertising = false;
    if (wasAdvertising) {
      _localInstanceId = null;
    }
  }

  /// Emit a resolved record on the current generation.
  void emitFound(LanDiscoveryRecord record) {
    _events.add(LanRecordFound(generation: _browseGeneration, record: record));
  }

  void emitUpdated(LanDiscoveryRecord record) {
    _events.add(
      LanRecordUpdated(generation: _browseGeneration, record: record),
    );
  }

  void emitLost(LanDiscoveryInstanceId instanceId) {
    _events.add(
      LanRecordLost(generation: _browseGeneration, instanceId: instanceId),
    );
  }

  /// Stale callback from an old browse generation. Tests must not sleep.
  void emitStaleFound(int generation, LanDiscoveryRecord record) {
    _events.add(LanRecordFound(generation: generation, record: record));
  }

  void emitStaleLost(int generation, LanDiscoveryInstanceId instanceId) {
    _events.add(LanRecordLost(generation: generation, instanceId: instanceId));
  }

  void emitError(LanDiscoveryFailureKind kind, String message) {
    _events.add(
      LanDiscoveryErrorEvent(
        generation: _browseGeneration,
        kind: kind,
        message: message,
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _browsing = false;
    _advertising = false;
    await _events.close();
  }
}
