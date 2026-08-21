import 'dart:async';

import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_adapter.dart';
import '../adapter/transport_adapter_event.dart';
import '../adapter/transport_adapter_types.dart';
import '../adapter/transport_availability.dart';
import '../errors.dart';

/// Deterministic in-process adapter. Never a production default.
class FakeTransportAdapter implements TransportAdapter {
  FakeTransportAdapter({
    required this.kind,
    this._availability = TransportAvailability.unsupported,
    this.permission,
    this.sharedTrace,
  });

  @override
  final TransportKind kind;

  TransportAvailability _availability;
  TransportPermissionStatus? permission;

  bool failConnect = false;
  bool failEndpoint = false;
  bool failDisconnect = false;
  bool failRelease = false;
  Completer<void>? connectBarrier;
  Completer<void>? disconnectBarrier;
  Completer<void>? endpointBarrier;

  final List<String> operations = <String>[];
  final List<String>? sharedTrace;
  int connectInFlight = 0;
  int maxConnectInFlight = 0;
  int connectCallCount = 0;
  int releaseAttemptCallCount = 0;
  int disconnectCallCount = 0;

  void _log(String operation) {
    operations.add(operation);
    sharedTrace?.add(operation);
  }

  final StreamController<TransportAdapterEvent> _events =
      StreamController<TransportAdapterEvent>.broadcast();

  @override
  Stream<TransportAdapterEvent> get events => _events.stream;

  TransportAvailability get availability => _availability;

  void emit(TransportAdapterEvent event) => _events.add(event);

  void setAvailability(TransportAvailability next, {String? detail}) {
    _availability = next;
    emit(
      AdapterAvailabilityChanged(
        kind: kind,
        snapshot: TransportCapabilitySnapshot(
          kind: kind,
          availability: next,
          permission: permission,
          detail: detail,
        ),
      ),
    );
  }

  void emitCandidate({
    required String candidateId,
    String? displayLabel,
    String? locatorHint,
  }) {
    emit(
      AdapterCandidateFound(
        kind: kind,
        candidateId: candidateId,
        displayLabel: displayLabel,
        locatorHint: locatorHint,
      ),
    );
  }

  void emitLost(String candidateId) {
    emit(AdapterCandidateLost(kind: kind, candidateId: candidateId));
  }

  @override
  Future<TransportCapabilitySnapshot> observeAvailability() async {
    return TransportCapabilitySnapshot(
      kind: kind,
      availability: _availability,
      permission: permission,
    );
  }

  @override
  Future<void> startDiscovery() async {
    _log('${kind.wire}.discovery.start');
  }

  @override
  Future<void> stopDiscovery() async {
    _log('${kind.wire}.discovery.stop');
  }

  @override
  Future<TransportConnectionHandle> connect(
    TransportCandidateKey candidate,
  ) async {
    connectInFlight += 1;
    if (connectInFlight > maxConnectInFlight) {
      maxConnectInFlight = connectInFlight;
    }
    connectCallCount += 1;
    _log('${kind.wire}.connect.start');
    try {
      final Completer<void>? barrier = connectBarrier;
      if (barrier != null) {
        await barrier.future;
      }
      if (failConnect) {
        _log('${kind.wire}.connect.fail');
        _log('${kind.wire}.connect.failBeforeHandle');
        throw TransportException(
          kind: TransportFailureKind.connectionFailed,
          message: '${kind.wire} connect failed',
        );
      }
      _log('${kind.wire}.connect.success');
      return TransportConnectionHandle(
        handleId: '${kind.wire}-${candidate.candidateId}',
        kind: kind,
      );
    } finally {
      connectInFlight -= 1;
    }
  }

  @override
  Future<void> disconnect(TransportConnectionHandle connection) async {
    disconnectCallCount += 1;
    _log('${kind.wire}.disconnect.start');
    final Completer<void>? barrier = disconnectBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    if (failDisconnect) {
      _log('${kind.wire}.disconnect.fail');
      throw TransportException(
        kind: TransportFailureKind.cleanupFailed,
        message: '${kind.wire} disconnect failed',
      );
    }
    _log('${kind.wire}.disconnect.success');
    _log('${kind.wire}.cleanup.complete');
  }

  @override
  Future<void> releaseAttempt(TransportCandidateKey candidate) async {
    releaseAttemptCallCount += 1;
    _log('${kind.wire}.releaseAttempt.start');
    if (failRelease) {
      _log('${kind.wire}.releaseAttempt.fail');
      throw TransportException(
        kind: TransportFailureKind.cleanupFailed,
        message: '${kind.wire} release failed',
      );
    }
    _log('${kind.wire}.releaseAttempt.success');
    _log('${kind.wire}.cleanup.complete');
  }

  @override
  Future<TransportEndpoint> openEndpoint(
    TransportConnectionHandle connection,
  ) async {
    _log('${kind.wire}.endpoint.start');
    final Completer<void>? barrier = endpointBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    if (failEndpoint) {
      _log('${kind.wire}.endpoint.fail');
      throw TransportException(
        kind: TransportFailureKind.endpointFailed,
        message: '${kind.wire} endpoint failed',
      );
    }
    _log('${kind.wire}.endpoint.success');
    return TransportEndpoint(
      endpointId: '${connection.handleId}-ep',
      kind: kind,
      host: '203.0.113.10',
      port: 7240,
    );
  }

  Future<void> close() => _events.close();
}
