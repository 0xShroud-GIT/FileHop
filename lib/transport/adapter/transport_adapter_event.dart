import '../../domain/transport/transport_kind.dart';
import 'transport_adapter_types.dart';
import 'transport_availability.dart';

/// Shared adapter events. No OS objects, keys, fingerprints, or trust.
sealed class TransportAdapterEvent {
  const TransportAdapterEvent({required this.kind});

  final TransportKind kind;
}

final class AdapterAvailabilityChanged extends TransportAdapterEvent {
  const AdapterAvailabilityChanged({
    required super.kind,
    required this.snapshot,
  });

  final TransportCapabilitySnapshot snapshot;
}

final class AdapterCandidateFound extends TransportAdapterEvent {
  const AdapterCandidateFound({
    required super.kind,
    required this.candidateId,
    this.displayLabel,
    this.locatorHint,
  });

  final String candidateId;
  final String? displayLabel;
  final String? locatorHint;
}

final class AdapterCandidateUpdated extends TransportAdapterEvent {
  const AdapterCandidateUpdated({
    required super.kind,
    required this.candidateId,
    this.displayLabel,
    this.locatorHint,
  });

  final String candidateId;
  final String? displayLabel;
  final String? locatorHint;
}

final class AdapterCandidateLost extends TransportAdapterEvent {
  const AdapterCandidateLost({required super.kind, required this.candidateId});

  final String candidateId;
}

final class AdapterConnectionChanged extends TransportAdapterEvent {
  const AdapterConnectionChanged({
    required super.kind,
    required this.connection,
    required this.connected,
  });

  final TransportConnectionHandle connection;
  final bool connected;
}

final class AdapterEndpointChanged extends TransportAdapterEvent {
  const AdapterEndpointChanged({required super.kind, required this.endpoint});

  final TransportEndpoint endpoint;
}

final class AdapterPermissionChanged extends TransportAdapterEvent {
  const AdapterPermissionChanged({
    required super.kind,
    required this.permission,
  });

  final TransportPermissionStatus permission;
}

final class AdapterLifecycleChanged extends TransportAdapterEvent {
  const AdapterLifecycleChanged({required super.kind, required this.detail});

  final String detail;
}

final class AdapterErrorEvent extends TransportAdapterEvent {
  const AdapterErrorEvent({
    required super.kind,
    required this.message,
    this.code,
  });

  final String message;
  final String? code;
}
