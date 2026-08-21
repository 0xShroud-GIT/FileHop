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
    this.connected,
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

  /// Required for [NativeEventKind.connectionChanged]. Distinguishes a
  /// connection becoming live from a disconnect/loss notification.
  final bool? connected;

  final NativeCapabilitySnapshot? capability;
  final NativePermissionStatus? permission;
  final NativeLifecycleEvent? lifecycle;
  final NativeAdapterError? error;
  final String? detail;
}
