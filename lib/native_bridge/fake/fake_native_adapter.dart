import 'dart:async';

import '../contract/enums.dart';
import '../contract/errors.dart';
import '../contract/events.dart';
import '../contract/models.dart';

/// Deterministic in-process adapter for tests. Not production transport.
class FakeNativeAdapter {
  FakeNativeAdapter({
    Map<NativeTransportKind, NativeCapabilitySnapshot>? capabilities,
  }) : _capabilities =
           capabilities ??
           <NativeTransportKind, NativeCapabilitySnapshot>{
             for (final NativeTransportKind kind
                 in NativeTransportKind.values.where(
                   (NativeTransportKind item) =>
                       item != NativeTransportKind.unknown,
                 ))
               kind: NativeCapabilitySnapshot(
                 kind: kind,
                 status: NativeCapabilityStatus.unsupported,
                 detail: 'Mission 02 skeleton: adapter not implemented',
               ),
           };

  final Map<NativeTransportKind, NativeCapabilitySnapshot> _capabilities;
  final StreamController<NativeAdapterEvent> _events =
      StreamController<NativeAdapterEvent>.broadcast();
  final Map<String, NativeTransportCandidate> _candidates =
      <String, NativeTransportCandidate>{};

  Stream<NativeAdapterEvent> get events => _events.stream;

  NativePingResult ping() {
    return const NativePingResult(bridgeVersion: 1, ok: true);
  }

  NativeCapabilitySnapshot observeAvailability(NativeTransportKind kind) {
    return _capabilities[kind] ??
        NativeCapabilitySnapshot(
          kind: kind,
          status: NativeCapabilityStatus.unsupported,
        );
  }

  void emitAvailability(NativeCapabilitySnapshot snapshot) {
    _capabilities[snapshot.kind] = snapshot;
    _events.add(
      NativeAdapterEvent(
        kind: NativeEventKind.availabilityChanged,
        transportKind: snapshot.kind,
        capability: snapshot,
      ),
    );
  }

  void emitCandidateFound(NativeTransportCandidate candidate) {
    _candidates[candidate.candidateId] = candidate;
    _events.add(
      NativeAdapterEvent(
        kind: NativeEventKind.candidateFound,
        transportKind: candidate.kind,
        candidate: candidate,
      ),
    );
  }

  void emitCandidateLost(String candidateId) {
    final NativeTransportCandidate? candidate = _candidates.remove(candidateId);
    if (candidate == null) {
      return;
    }
    _events.add(
      NativeAdapterEvent(
        kind: NativeEventKind.candidateLost,
        transportKind: candidate.kind,
        candidate: candidate,
      ),
    );
  }

  void emitEndpointChanged(NativeEndpoint endpoint) {
    _events.add(
      NativeAdapterEvent(
        kind: NativeEventKind.endpointChanged,
        transportKind: endpoint.kind,
        endpoint: endpoint,
      ),
    );
  }

  void emitError(NativeAdapterError error) {
    _events.add(
      NativeAdapterEvent(
        kind: NativeEventKind.adapterError,
        transportKind: error.kind,
        error: error,
      ),
    );
  }

  NativeConnectionHandle connect(NativeTransportCandidate candidate) {
    throw NativeBridgeException(
      errorClass: NativeErrorClass.unsupported,
      message: 'connect is not implemented in Mission 02',
    );
  }

  void dispose() {
    _events.close();
  }
}
