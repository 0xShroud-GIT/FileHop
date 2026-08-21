import 'lan_address.dart';
import 'lan_constants.dart';

/// LAN candidate locator contract (Mission 07 discovery).
///
/// A locator is reachability metadata only: never peer identity, never a
/// fingerprint, never persisted trust. Two honest shapes exist:
///
/// - [LanResolvedSocketLocator]: a socket endpoint the discovery layer
///   actually resolved (localhost/Arena harness, Android NSD resolution).
///   It may claim concrete host/port values because they were obtained
///   without establishing a connection to the remote service.
/// - [LanNativeServiceLocator]: a service-resolvable native endpoint whose
///   host/port are unknown at discovery time. The native adapter retains
///   the OS endpoint internally and resolves it at connection time
///   (Mission 10). It must never fabricate a socket address.
sealed class LanLocator {
  const LanLocator();

  /// Human diagnostic only. Not a structured host:port authority.
  String get locatorHint;
}

/// Resolved socket locator with truthful host/port claims.
final class LanResolvedSocketLocator extends LanLocator {
  const LanResolvedSocketLocator({required this.port, required this.addresses});

  final int port;

  /// Immutable resolved address list (wrapped by [LanDiscoveryRecord.resolved]).
  final List<LanResolvedAddress> addresses;

  @override
  String get locatorHint {
    final String hosts = addresses
        .map((LanResolvedAddress a) => a.diagnostic)
        .join(',');
    return 'port=$port addrs=$hosts';
  }
}

/// Service-resolvable native endpoint pending connection-time resolution.
///
/// The [serviceReference] is an opaque runtime-only correlation token owned
/// by the native adapter (e.g. the iOS discovery layer's retained native
/// endpoint). It is not a raw OS object, not an address claim, not
/// persisted, and not peer identity.
final class LanNativeServiceLocator extends LanLocator {
  const LanNativeServiceLocator({required this.serviceReference});

  /// Max UTF-8 bytes for the opaque reference (bounded, diagnostic-safe).
  static const int kMaxServiceReferenceBytes = 128;

  final String serviceReference;

  @override
  String get locatorHint => kFileHopLanNativeServiceLocatorHint;
}
