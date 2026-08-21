import '../../domain/transport/transport_kind.dart';
import '../../native_bridge/contract/enums.dart';
import '../adapter/transport_availability.dart';

/// Exact mapping between Mission 02 native kinds and Mission 03 domain kinds.
/// Unknown never becomes LAN (or any known family).
class TransportKindMapping {
  const TransportKindMapping();

  static TransportKind? toDomain(NativeTransportKind kind) {
    switch (kind) {
      case NativeTransportKind.wifiDirect:
        return TransportKind.wifiDirect;
      case NativeTransportKind.wifiAware:
        return TransportKind.wifiAware;
      case NativeTransportKind.lan:
        return TransportKind.lan;
      case NativeTransportKind.unknown:
        return null;
    }
  }

  static NativeTransportKind toNative(TransportKind kind) {
    switch (kind) {
      case TransportKind.wifiDirect:
        return NativeTransportKind.wifiDirect;
      case TransportKind.wifiAware:
        return NativeTransportKind.wifiAware;
      case TransportKind.lan:
        return NativeTransportKind.lan;
    }
  }

  static TransportAvailability availabilityOf(NativeCapabilityStatus status) {
    switch (status) {
      case NativeCapabilityStatus.supportedAvailable:
        return TransportAvailability.supportedAvailable;
      case NativeCapabilityStatus.supportedUnavailable:
        return TransportAvailability.supportedUnavailable;
      case NativeCapabilityStatus.permissionRequired:
        return TransportAvailability.permissionRequired;
      case NativeCapabilityStatus.unsupported:
        return TransportAvailability.unsupported;
      case NativeCapabilityStatus.failed:
        return TransportAvailability.failed;
      case NativeCapabilityStatus.unknown:
        return TransportAvailability.unknown;
    }
  }

  static TransportPermissionStatus permissionOf(NativePermissionStatus status) {
    switch (status) {
      case NativePermissionStatus.notRequested:
        return TransportPermissionStatus.notRequested;
      case NativePermissionStatus.granted:
        return TransportPermissionStatus.granted;
      case NativePermissionStatus.denied:
        return TransportPermissionStatus.denied;
      case NativePermissionStatus.restrictedUnavailable:
        return TransportPermissionStatus.restrictedUnavailable;
      case NativePermissionStatus.revokedLater:
        return TransportPermissionStatus.revokedLater;
      case NativePermissionStatus.unknown:
        return TransportPermissionStatus.unknown;
    }
  }
}
