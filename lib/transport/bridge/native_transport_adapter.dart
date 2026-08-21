import 'dart:async';

import '../../domain/transport/transport_kind.dart';
import '../../native_bridge/channel/native_bridge.dart';
import '../../native_bridge/contract/enums.dart';
import '../../native_bridge/contract/events.dart';
import '../../native_bridge/contract/models.dart';
import '../adapter/transport_adapter.dart';
import '../adapter/transport_adapter_event.dart';
import '../adapter/transport_adapter_types.dart';
import '../errors.dart';
import 'transport_kind_mapping.dart';

/// Thin NativeBridge wrapper bound to exactly one [TransportKind].
///
/// Does not implement radios. Unknown native kinds stay non-selectable.
class NativeTransportAdapter implements TransportAdapter {
  NativeTransportAdapter({required this._bridge, required this.kind});

  final NativeBridge _bridge;

  @override
  final TransportKind kind;

  @override
  Stream<TransportAdapterEvent> get events {
    return _bridge
        .events()
        .map(_mapEvent)
        .where((TransportAdapterEvent? event) => event != null)
        .cast<TransportAdapterEvent>();
  }

  @override
  Future<TransportCapabilitySnapshot> observeAvailability() async {
    final NativeCapabilitySnapshot native = await _bridge.observeAvailability(
      TransportKindMapping.toNative(kind),
    );
    final TransportKind? mapped = TransportKindMapping.toDomain(native.kind);
    if (mapped == null || mapped != kind) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'native availability kind mismatch or unknown',
      );
    }
    return TransportCapabilitySnapshot(
      kind: mapped,
      availability: TransportKindMapping.availabilityOf(native.status),
      permission: native.permission == null
          ? null
          : TransportKindMapping.permissionOf(native.permission!),
      detail: native.detail,
    );
  }

  @override
  Future<void> startDiscovery() {
    return _bridge.startDiscovery(TransportKindMapping.toNative(kind));
  }

  @override
  Future<void> stopDiscovery() {
    return _bridge.stopDiscovery(TransportKindMapping.toNative(kind));
  }

  @override
  Future<TransportConnectionHandle> connect(
    TransportCandidateKey candidate,
  ) async {
    if (candidate.kind != kind) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'connect candidate kind mismatch',
      );
    }
    return _mapConnection(
      await _bridge.connect(
        NativeTransportCandidate(
          candidateId: candidate.candidateId,
          kind: TransportKindMapping.toNative(kind),
        ),
      ),
    );
  }

  @override
  Future<void> disconnect(TransportConnectionHandle connection) async {
    _requireHandleKind(connection);
    await _bridge.disconnect(
      NativeConnectionHandle(
        handleId: connection.handleId,
        kind: TransportKindMapping.toNative(kind),
      ),
    );
  }

  @override
  Future<TransportEndpoint> openEndpoint(
    TransportConnectionHandle connection,
  ) async {
    _requireHandleKind(connection);
    return _mapEndpoint(
      await _bridge.openEndpoint(
        NativeConnectionHandle(
          handleId: connection.handleId,
          kind: TransportKindMapping.toNative(kind),
        ),
      ),
    );
  }

  void _requireHandleKind(TransportConnectionHandle connection) {
    if (connection.kind != kind) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'connection handle kind does not match adapter',
      );
    }
  }

  @override
  Future<void> releaseAttempt(TransportCandidateKey candidate) async {
    if (candidate.kind != kind) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'releaseAttempt candidate kind does not match adapter',
      );
    }
    throw const TransportException(
      kind: TransportFailureKind.attemptCleanupUnavailable,
      message: 'native releaseAttempt has no Mission 06 command; cannot prove no-handle cleanup',
    );
  }

  TransportAdapterEvent? _mapEvent(NativeAdapterEvent event) {
    if (event.kind == NativeEventKind.unknown) {
      return null;
    }
    final NativeTransportKind? nativeKind =
        event.transportKind ?? event.capability?.kind ?? event.candidate?.kind;
    if (nativeKind == null) {
      return null;
    }
    final TransportKind? mapped = TransportKindMapping.toDomain(nativeKind);
    if (mapped == null || mapped != kind) {
      return null;
    }
    switch (event.kind) {
      case NativeEventKind.availabilityChanged:
        final NativeCapabilitySnapshot? cap = event.capability;
        if (cap == null) {
          return null;
        }
        return AdapterAvailabilityChanged(
          kind: mapped,
          snapshot: TransportCapabilitySnapshot(
            kind: mapped,
            availability: TransportKindMapping.availabilityOf(cap.status),
            permission: cap.permission == null
                ? null
                : TransportKindMapping.permissionOf(cap.permission!),
            detail: cap.detail,
          ),
        );
      case NativeEventKind.candidateFound:
        final NativeTransportCandidate? candidate = event.candidate;
        if (candidate == null) {
          return null;
        }
        return AdapterCandidateFound(
          kind: mapped,
          candidateId: candidate.candidateId,
          displayLabel: candidate.displayLabel,
          locatorHint: candidate.locatorHint,
        );
      case NativeEventKind.candidateUpdated:
        final NativeTransportCandidate? candidate = event.candidate;
        if (candidate == null) {
          return null;
        }
        return AdapterCandidateUpdated(
          kind: mapped,
          candidateId: candidate.candidateId,
          displayLabel: candidate.displayLabel,
          locatorHint: candidate.locatorHint,
        );
      case NativeEventKind.candidateLost:
        final NativeTransportCandidate? candidate = event.candidate;
        if (candidate == null) {
          return null;
        }
        return AdapterCandidateLost(
          kind: mapped,
          candidateId: candidate.candidateId,
        );
      case NativeEventKind.connectionChanged:
        final NativeConnectionHandle? connection = event.connection;
        if (connection == null) {
          return null;
        }
        return AdapterConnectionChanged(
          kind: mapped,
          connection: TransportConnectionHandle(
            handleId: connection.handleId,
            kind: mapped,
          ),
          connected: true,
        );
      case NativeEventKind.endpointChanged:
        final NativeEndpoint? endpoint = event.endpoint;
        if (endpoint == null) {
          return null;
        }
        return AdapterEndpointChanged(
          kind: mapped,
          endpoint: TransportEndpoint(
            endpointId: endpoint.endpointId,
            kind: mapped,
            host: endpoint.host,
            port: endpoint.port,
            nativePathHandle: endpoint.nativePathHandle,
          ),
        );
      case NativeEventKind.permissionChanged:
        final NativePermissionStatus? permission = event.permission;
        if (permission == null) {
          return null;
        }
        return AdapterPermissionChanged(
          kind: mapped,
          permission: TransportKindMapping.permissionOf(permission),
        );
      case NativeEventKind.nativeLifecycleChanged:
        return AdapterLifecycleChanged(
          kind: mapped,
          detail: event.lifecycle?.kind.wire ?? event.detail ?? 'lifecycle',
        );
      case NativeEventKind.adapterError:
        return AdapterErrorEvent(
          kind: mapped,
          message: event.error?.message ?? event.detail ?? 'adapter error',
          code: event.error?.errorClass.wire,
        );
      case NativeEventKind.unknown:
        return null;
    }
  }

  TransportConnectionHandle _mapConnection(NativeConnectionHandle handle) {
    final TransportKind? mapped = TransportKindMapping.toDomain(handle.kind);
    if (mapped == null || mapped != kind) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'native connection kind mismatch or unknown',
      );
    }
    return TransportConnectionHandle(handleId: handle.handleId, kind: mapped);
  }

  TransportEndpoint _mapEndpoint(NativeEndpoint endpoint) {
    final TransportKind? mapped = TransportKindMapping.toDomain(endpoint.kind);
    if (mapped == null || mapped != kind) {
      throw const TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'native endpoint kind mismatch or unknown',
      );
    }
    return TransportEndpoint(
      endpointId: endpoint.endpointId,
      kind: mapped,
      host: endpoint.host,
      port: endpoint.port,
      nativePathHandle: endpoint.nativePathHandle,
    );
  }
}
