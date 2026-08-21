import 'enums.dart';
import 'models.dart';

/// Asynchronous native callback. Coordinators interpret these later.
class NativeAdapterEvent {
  const NativeAdapterEvent({
    required this.kind,
    this.transportKind,
    this.candidate,
    this.endpoint,
    this.connection,
    this.capability,
    this.permission,
    this.lifecycle,
    this.error,
    this.detail,
  });

  final NativeEventKind kind;
  final NativeTransportKind? transportKind;
  final NativeTransportCandidate? candidate;
  final NativeEndpoint? endpoint;
  final NativeConnectionHandle? connection;
  final NativeCapabilitySnapshot? capability;
  final NativePermissionStatus? permission;
  final NativeLifecycleEvent? lifecycle;
  final NativeAdapterError? error;
  final String? detail;
}
