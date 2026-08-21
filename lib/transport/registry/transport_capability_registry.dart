import 'dart:async';

import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_adapter.dart';
import '../adapter/transport_adapter_event.dart';
import '../adapter/transport_adapter_types.dart';
import '../adapter/transport_availability.dart';
import '../errors.dart';

/// Latest local adapter capability per [TransportKind].
class TransportCapabilityRegistry {
  TransportCapabilityRegistry();

  final Map<TransportKind, TransportAdapter> _adapters =
      <TransportKind, TransportAdapter>{};
  final Map<TransportKind, TransportCapabilitySnapshot> _snapshots =
      <TransportKind, TransportCapabilitySnapshot>{};
  final Map<TransportKind, StreamSubscription<TransportAdapterEvent>> _subs =
      <TransportKind, StreamSubscription<TransportAdapterEvent>>{};
  final StreamController<TransportCapabilitySnapshot> _changes =
      StreamController<TransportCapabilitySnapshot>.broadcast();

  TransportException? lastContractError;
  bool _closed = false;

  Stream<TransportCapabilitySnapshot> get changes => _changes.stream;

  Future<void> register(TransportAdapter adapter) async {
    if (_closed) {
      throw const TransportException(
        kind: TransportFailureKind.invalidArgument,
        message: 'transport capability registry is closed',
      );
    }
    if (_adapters.containsKey(adapter.kind)) {
      throw TransportException(
        kind: TransportFailureKind.invalidArgument,
        message: 'adapter already registered for ${adapter.kind.wire}',
      );
    }
    final TransportCapabilitySnapshot snapshot = await adapter
        .observeAvailability();
    if (_closed) {
      throw const TransportException(
        kind: TransportFailureKind.invalidArgument,
        message: 'transport capability registry closed during registration',
      );
    }
    if (snapshot.kind != adapter.kind) {
      throw TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'availability snapshot kind does not match adapter',
      );
    }
    _adapters[adapter.kind] = adapter;
    _snapshots[adapter.kind] = snapshot;
    _subs[adapter.kind] = adapter.events.listen(
      (TransportAdapterEvent event) => ingest(adapter.kind, event),
    );
  }

  TransportAdapter? adapterFor(TransportKind kind) => _adapters[kind];

  TransportCapabilitySnapshot? snapshotFor(TransportKind kind) =>
      _snapshots[kind];

  Map<TransportKind, TransportCapabilitySnapshot> snapshots() {
    return Map<TransportKind, TransportCapabilitySnapshot>.unmodifiable(
      Map<TransportKind, TransportCapabilitySnapshot>.of(_snapshots),
    );
  }

  List<TransportKind> eligibleKinds() {
    return List<TransportKind>.unmodifiable(
      _snapshots.entries
          .where(
            (MapEntry<TransportKind, TransportCapabilitySnapshot> entry) =>
                entry.value.availability.isAutoEligible,
          )
          .map(
            (MapEntry<TransportKind, TransportCapabilitySnapshot> e) => e.key,
          )
          .toList(),
    );
  }

  /// Apply a capability-relevant event. Mismatched kinds are contract failures.
  void ingest(TransportKind registeredKind, TransportAdapterEvent event) {
    if (_closed) {
      return;
    }
    if (event.kind != registeredKind) {
      lastContractError = TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'event kind ${event.kind.wire} != ${registeredKind.wire}',
      );
      return;
    }
    switch (event) {
      case AdapterAvailabilityChanged(
        :final TransportCapabilitySnapshot snapshot,
      ):
        if (snapshot.kind != registeredKind) {
          lastContractError = const TransportException(
            kind: TransportFailureKind.adapterContractViolation,
            message: 'availability snapshot kind mismatch',
          );
          return;
        }
        _snapshots[registeredKind] = snapshot;
        _changes.add(snapshot);
      case AdapterPermissionChanged(:final permission):
        final TransportCapabilitySnapshot? current = _snapshots[registeredKind];
        if (current == null) {
          return;
        }
        final TransportCapabilitySnapshot updated = current.withPermission(
          permission,
        );
        _snapshots[registeredKind] = updated;
        _changes.add(updated);
      case AdapterErrorEvent():
      case AdapterLifecycleChanged():
      case AdapterCandidateFound():
      case AdapterCandidateUpdated():
      case AdapterCandidateLost():
      case AdapterConnectionChanged():
      case AdapterEndpointChanged():
        break;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final StreamSubscription<TransportAdapterEvent> sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    await _changes.close();
  }
}
