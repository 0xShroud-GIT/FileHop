import 'dart:async';

import '../../domain/state_machine/transition_authority.dart';
import '../../domain/transport/transport_candidate.dart';
import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_adapter.dart';
import '../adapter/transport_adapter_event.dart';
import '../adapter/transport_adapter_types.dart';
import '../adapter/transport_availability.dart';
import '../errors.dart';
import '../registry/transport_candidate_registry.dart';
import '../registry/transport_capability_registry.dart';
import '../selection/transport_qualification_policy.dart';
import '../selection/transport_selection.dart';
import '../selection/transport_selector.dart';

class TransportAcquisitionToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class TransportAcquireRequest {
  const TransportAcquireRequest({
    required this.localPlatform,
    this.remotePlatform,
    this.qualification = const TransportQualificationPolicy(),
    this.token,
  });

  final TransportPlatform localPlatform;
  final TransportPlatform? remotePlatform;
  final TransportQualificationPolicy qualification;
  final TransportAcquisitionToken? token;
}

/// Smallest coordinator that serializes fallback. Not a PeerSession owner.
class TransportManager {
  TransportManager({
    TransportCapabilityRegistry? capabilities,
    TransportCandidateRegistry? candidates,
    this.selector = const TransportSelector(),
  }) : capabilities = capabilities ?? TransportCapabilityRegistry(),
       candidates = candidates ?? TransportCandidateRegistry();

  final TransportCapabilityRegistry capabilities;
  final TransportCandidateRegistry candidates;
  final TransportSelector selector;

  SelectedTransportPath? _current;
  Future<void>? _busy;
  Future<void>? _closeFuture;
  final List<String> operations = <String>[];
  final List<StreamSubscription<TransportAdapterEvent>> _subscriptions =
      <StreamSubscription<TransportAdapterEvent>>[];
  bool _closing = false;
  bool _closed = false;

  TransportException? lastContractError;

  SelectedTransportPath? get currentPath => _current;

  Future<void> registerAdapter(TransportAdapter adapter) {
    return _serialized<void>(() async {
      await capabilities.register(adapter);
      final TransportKind sourceKind = adapter.kind;
      _subscriptions.add(
        adapter.events.listen(
          (TransportAdapterEvent event) => _onAdapterEvent(sourceKind, event),
        ),
      );
    });
  }

  void _onAdapterEvent(TransportKind sourceKind, TransportAdapterEvent event) {
    if (_closing || _closed) {
      return;
    }
    if (event.kind != sourceKind) {
      lastContractError = TransportException(
        kind: TransportFailureKind.adapterContractViolation,
        message: 'event kind ${event.kind.wire} != source ${sourceKind.wire}',
      );
      return;
    }
    switch (event) {
      case AdapterCandidateFound():
        candidates.recordFound(
          kind: sourceKind,
          candidateId: event.candidateId,
          displayLabel: event.displayLabel,
          locatorHint: event.locatorHint,
        );
      case AdapterCandidateUpdated():
        candidates.recordUpdated(
          kind: sourceKind,
          candidateId: event.candidateId,
          displayLabel: event.displayLabel,
          locatorHint: event.locatorHint,
        );
      case AdapterCandidateLost():
        final TransportCandidateKey key = TransportCandidateKey(
          kind: sourceKind,
          candidateId: event.candidateId,
        );
        candidates.recordLost(kind: sourceKind, candidateId: event.candidateId);
        if (_current?.key == key) {
          _current = _current?.markUnhealthy();
        }
      case AdapterAvailabilityChanged(:final snapshot):
        if (snapshot.kind != sourceKind) {
          lastContractError = const TransportException(
            kind: TransportFailureKind.adapterContractViolation,
            message: 'availability snapshot kind mismatch',
          );
          return;
        }
        if (_current != null &&
            _current!.kind == sourceKind &&
            !snapshot.availability.isAutoEligible) {
          _current = _current!.markUnhealthy();
        }
      case AdapterConnectionChanged():
      case AdapterEndpointChanged():
      case AdapterPermissionChanged():
      case AdapterLifecycleChanged():
      case AdapterErrorEvent():
        break;
    }
  }

  TransportSelection reconcile(TransportAcquireRequest request) {
    _throwIfNotOpen();
    return selector.select(_input(request, const <TransportCandidateKey>{}));
  }

  Future<SelectedTransportPath> acquire(TransportAcquireRequest request) {
    return _serialized(() => _acquireBody(request));
  }

  Future<SelectedTransportPath> recoverAfterLoss(
    TransportAcquireRequest request,
  ) {
    return _serialized(() async {
      final SelectedTransportPath? previous = _current;
      if (previous != null) {
        _current = previous.markUnhealthy();
        final TransportAdapter? adapter = capabilities.adapterFor(
          previous.kind,
        );
        if (adapter != null) {
          await _releaseForFallback(
            adapter,
            previous.connection,
            previous.key,
            TransportFailureKind.adapterUnavailable,
          );
        }
        _current = null;
      }
      return _acquireBody(request);
    });
  }

  Future<T> _serialized<T>(
    Future<T> Function() body, {
    bool allowClosing = false,
  }) async {
    if (!allowClosing) {
      _throwIfNotOpen();
    }
    while (_busy != null) {
      final Future<void> pending = _busy!;
      await pending;
      if (!allowClosing) {
        _throwIfNotOpen();
      }
    }
    if (!allowClosing) {
      _throwIfNotOpen();
    }
    final Completer<void> gate = Completer<void>();
    _busy = gate.future;
    try {
      return await body();
    } finally {
      _busy = null;
      gate.complete();
    }
  }

  Future<SelectedTransportPath> _acquireBody(
    TransportAcquireRequest request,
  ) async {
    final Set<TransportCandidateKey> failedThisOperation =
        <TransportCandidateKey>{};
    TransportException? last;
    while (true) {
      _throwIfCancelled(request.token);
      final TransportSelection selection = selector.select(
        _input(request, failedThisOperation),
      );
      switch (selection) {
        case TransportRetainCurrent(:final SelectedTransportPath path):
          operations.add('retain.${path.kind.wire}');
          return path;
        case TransportNone(:final TransportSelectionReason reason):
          throw last ??
              TransportException(
                kind: _mapNone(reason),
                message: 'no transport path (${reason.name})',
              );
        case TransportSelected(:final TransportCandidateKey chosen):
          last = await _attemptOne(chosen, request, failedThisOperation);
          if (last == null) {
            return _current!;
          }
      }
    }
  }

  /// Returns null on success (path stored in [_current]).
  Future<TransportException?> _attemptOne(
    TransportCandidateKey key,
    TransportAcquireRequest request,
    Set<TransportCandidateKey> failedThisOperation,
  ) async {
    final TransportAdapter? adapter = capabilities.adapterFor(key.kind);
    final TransportCapabilitySnapshot? snap = capabilities.snapshotFor(
      key.kind,
    );
    final RegisteredTransportCandidate? registered = candidates[key];
    if (adapter == null ||
        snap == null ||
        !snap.availability.isAutoEligible ||
        registered == null ||
        registered.candidate.state != TransportCandidateState.available) {
      failedThisOperation.add(key);
      return const TransportException(
        kind: TransportFailureKind.noEligibleTransport,
        message: 'selected candidate is not currently eligible',
      );
    }
    candidates.tryApply(
      key,
      TransportCandidateEvent.startConnect,
      authority: TransitionAuthority.localCommand,
    );
    TransportConnectionHandle? handle;
    try {
      handle = await adapter.connect(key);
      if (request.token != null && request.token!.isCancelled) {
        await _abandonCancelledAttempt(adapter, handle, key);
      }
      final TransportEndpoint endpoint = await adapter.openEndpoint(handle);
      if (request.token != null && request.token!.isCancelled) {
        await _abandonCancelledAttempt(adapter, handle, key);
      }
      candidates.tryApply(
        key,
        TransportCandidateEvent.connected,
        authority: TransitionAuthority.transportEvent,
      );
      _current = SelectedTransportPath(
        key: key,
        connection: handle,
        endpoint: endpoint,
        healthy: true,
      );
      return null;
    } catch (error) {
      if (error is TransportException &&
          (error.kind == TransportFailureKind.cleanupFailed ||
              error.kind == TransportFailureKind.cancelled)) {
        rethrow;
      }
      final TransportException last = error is TransportException
          ? error
          : const TransportException(
              kind: TransportFailureKind.connectionFailed,
              message: 'transport attempt failed',
            );
      failedThisOperation.add(key);
      candidates.tryApply(
        key,
        TransportCandidateEvent.fail,
        authority: TransitionAuthority.transportEvent,
      );
      await _releaseForFallback(adapter, handle, key, last.kind);
      return last;
    }
  }

  TransportSelectionInput _input(
    TransportAcquireRequest request,
    Set<TransportCandidateKey> failedThisOperation,
  ) {
    return TransportSelectionInput(
      localPlatform: request.localPlatform,
      remotePlatform: request.remotePlatform,
      qualification: request.qualification,
      capabilities: capabilities.snapshots(),
      candidates: candidates.selectableViews(),
      currentPath: _current,
      failedAttempts: failedThisOperation,
    );
  }

  Future<void> _abandonCancelledAttempt(
    TransportAdapter adapter,
    TransportConnectionHandle handle,
    TransportCandidateKey key,
  ) async {
    candidates.tryApply(
      key,
      TransportCandidateEvent.fail,
      authority: TransitionAuthority.transportEvent,
    );
    await _releaseForFallback(
      adapter,
      handle,
      key,
      TransportFailureKind.cancelled,
    );
    throw const TransportException(
      kind: TransportFailureKind.cancelled,
      message: 'transport acquisition cancelled',
    );
  }

  Future<void> _releaseForFallback(
    TransportAdapter adapter,
    TransportConnectionHandle? handle,
    TransportCandidateKey key,
    TransportFailureKind originating,
  ) async {
    try {
      if (handle != null) {
        await adapter.disconnect(handle);
      } else {
        await adapter.releaseAttempt(key);
      }
    } on TransportException catch (error) {
      throw TransportException(
        kind: TransportFailureKind.cleanupFailed,
        message: 'failed to release ${key.kind.wire} before next attempt',
        causeKind: error.kind == TransportFailureKind.cleanupFailed
            ? originating
            : error.kind,
      );
    } catch (_) {
      throw TransportException(
        kind: TransportFailureKind.cleanupFailed,
        message: 'failed to release ${key.kind.wire} before next attempt',
        causeKind: originating,
      );
    }
  }

  void _throwIfCancelled(TransportAcquisitionToken? token) {
    if (token != null && token.isCancelled) {
      throw const TransportException(
        kind: TransportFailureKind.cancelled,
        message: 'transport acquisition cancelled',
      );
    }
  }

  void _throwIfNotOpen() {
    if (_closing || _closed) {
      throw const TransportException(
        kind: TransportFailureKind.invalidArgument,
        message: 'transport manager is closing or closed',
      );
    }
  }

  static TransportFailureKind _mapNone(TransportSelectionReason reason) {
    switch (reason) {
      case TransportSelectionReason.permissionBlocked:
        return TransportFailureKind.permissionRequired;
      case TransportSelectionReason.interopUnverified:
        return TransportFailureKind.interopUnverified;
      case TransportSelectionReason.noCandidates:
        return TransportFailureKind.noCandidates;
      case TransportSelectionReason.noEligibleTransport:
        return TransportFailureKind.noEligibleTransport;
      case TransportSelectionReason.retainCurrent:
      case TransportSelectionReason.selected:
        return TransportFailureKind.noEligibleTransport;
    }
  }

  Future<void> close() {
    if (_closed) {
      return Future<void>.value();
    }
    final Future<void>? pending = _closeFuture;
    if (pending != null) {
      return pending;
    }
    final Future<void> next = _closeBody();
    _closeFuture = next;
    return next;
  }

  Future<void> _closeBody() async {
    _closing = true;
    try {
      await _serialized<void>(() async {
        final SelectedTransportPath? current = _current;
        if (current != null) {
          final TransportAdapter? adapter = capabilities.adapterFor(
            current.kind,
          );
          if (adapter == null) {
            throw const TransportException(
              kind: TransportFailureKind.cleanupFailed,
              message: 'active transport has no registered adapter at close',
            );
          }
          try {
            await adapter.disconnect(current.connection);
          } on TransportException catch (error) {
            throw TransportException(
              kind: TransportFailureKind.cleanupFailed,
              message: 'failed to disconnect active transport at close',
              causeKind: error.kind,
            );
          } catch (_) {
            throw const TransportException(
              kind: TransportFailureKind.cleanupFailed,
              message: 'failed to disconnect active transport at close',
            );
          }
          // Clear ownership only after the adapter confirms release. A failed
          // close keeps the handle reachable for a later close retry.
          _current = null;
        }

        TransportException? teardownError;
        for (final StreamSubscription<TransportAdapterEvent> sub
            in _subscriptions) {
          try {
            await sub.cancel();
          } catch (_) {
            teardownError ??= const TransportException(
              kind: TransportFailureKind.cleanupFailed,
              message: 'failed to cancel transport event subscription',
            );
          }
        }
        _subscriptions.clear();
        try {
          await capabilities.close();
        } catch (_) {
          teardownError ??= const TransportException(
            kind: TransportFailureKind.cleanupFailed,
            message: 'failed to close transport capability registry',
          );
        }

        // Event/capability teardown is one-way. Once the live connection has
        // been released, this manager is closed even if a teardown operation
        // reports an error to the caller.
        _closed = true;
        if (teardownError != null) {
          throw teardownError;
        }
      }, allowClosing: true);
    } finally {
      if (_closed) {
        _closing = false;
      } else {
        // Active connection release failed before one-way teardown. Stay in
        // closing state so ordinary work remains blocked, but permit close()
        // itself to retry the same retained handle.
        _closeFuture = null;
      }
    }
  }
}
