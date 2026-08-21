/// Frozen adapter availability. Distinct states; never inferred from each other.
enum TransportAvailability {
  supportedAvailable,
  supportedUnavailable,
  permissionRequired,
  unsupported,
  failed,
  unknown,
}

extension TransportAvailabilityEligibility on TransportAvailability {
  /// Only [TransportAvailability.supportedAvailable] is auto-attempted.
  bool get isAutoEligible => this == TransportAvailability.supportedAvailable;
}

/// Explicit permission snapshot. Not a substitute for [TransportAvailability].
enum TransportPermissionStatus {
  notRequested,
  granted,
  denied,
  restrictedUnavailable,
  revokedLater,
  unknown,
}

enum TransportPlatform { android, ios }
