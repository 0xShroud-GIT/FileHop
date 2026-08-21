import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_availability.dart';

/// Platform/transport attempt qualification. Not peer trust.
///
/// Default production baseline: Android↔iOS Wi-Fi Aware is unverified until
/// Mission 09 physical evidence exists.
class TransportQualificationPolicy {
  const TransportQualificationPolicy({this.androidIosAwareQualified = false});

  /// Policy simulation only. Never device-interop proof.
  final bool androidIosAwareQualified;

  bool allows({
    required TransportKind kind,
    required TransportPlatform local,
    required TransportPlatform? remote,
  }) {
    switch (kind) {
      case TransportKind.wifiDirect:
        if (local != TransportPlatform.android) {
          return false;
        }
        if (remote == TransportPlatform.ios) {
          return false;
        }
        return true;
      case TransportKind.wifiAware:
        if (_isCrossPlatformMobile(local, remote)) {
          return androidIosAwareQualified;
        }
        return true;
      case TransportKind.lan:
        return true;
    }
  }

  static bool _isCrossPlatformMobile(
    TransportPlatform local,
    TransportPlatform? remote,
  ) {
    if (remote == null) {
      return false;
    }
    return local != remote;
  }
}
