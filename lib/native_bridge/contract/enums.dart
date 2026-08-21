/// Wire values match `08_PLATFORM_LIFECYCLE_MASTER.md`.
/// Unknown native values map to [unknown] and never crash.
library;

enum NativeCapabilityStatus {
  supportedAvailable('SUPPORTED_AVAILABLE'),
  supportedUnavailable('SUPPORTED_UNAVAILABLE'),
  permissionRequired('PERMISSION_REQUIRED'),
  unsupported('UNSUPPORTED'),
  failed('FAILED'),
  unknown('UNKNOWN');

  const NativeCapabilityStatus(this.wire);
  final String wire;

  static NativeCapabilityStatus fromWire(String value) {
    for (final NativeCapabilityStatus item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeCapabilityStatus.unknown;
  }
}

enum NativePermissionStatus {
  notRequested('notRequested'),
  granted('granted'),
  denied('denied'),
  restrictedUnavailable('restricted/unavailable'),
  revokedLater('revokedLater'),
  unknown('unknown');

  const NativePermissionStatus(this.wire);
  final String wire;

  static NativePermissionStatus fromWire(String value) {
    for (final NativePermissionStatus item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativePermissionStatus.unknown;
  }
}

/// Transport family. Locator metadata only — never FileHop security identity.
enum NativeTransportKind {
  wifiDirect('wifiDirect'),
  wifiAware('wifiAware'),
  lan('lan'),
  unknown('unknown');

  const NativeTransportKind(this.wire);
  final String wire;

  static NativeTransportKind fromWire(String value) {
    for (final NativeTransportKind item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeTransportKind.unknown;
  }
}

enum NativeEndpointReachability {
  socket('socket'),
  nativeStream('nativeStream'),
  unknown('unknown');

  const NativeEndpointReachability(this.wire);
  final String wire;

  static NativeEndpointReachability fromWire(String value) {
    for (final NativeEndpointReachability item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeEndpointReachability.unknown;
  }
}

enum NativeErrorClass {
  unsupported('unsupported'),
  unavailable('unavailable'),
  permissionRequired('permissionRequired'),
  permissionDenied('permissionDenied'),
  invalidArgument('invalidArgument'),
  invalidState('invalidState'),
  operationFailed('operationFailed'),
  cancelled('cancelled'),
  timeout('timeout'),
  nativeFailure('nativeFailure'),
  notFound('notFound'),
  corrupt('corrupt'),
  unknown('unknown');

  const NativeErrorClass(this.wire);
  final String wire;

  static NativeErrorClass fromWire(String value) {
    for (final NativeErrorClass item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeErrorClass.unknown;
  }
}

enum NativeEventKind {
  availabilityChanged('availabilityChanged'),
  candidateFound('candidateFound'),
  candidateUpdated('candidateUpdated'),
  candidateLost('candidateLost'),
  connectionChanged('connectionChanged'),
  endpointChanged('endpointChanged'),
  permissionChanged('permissionChanged'),
  nativeLifecycleChanged('nativeLifecycleChanged'),
  adapterError('adapterError'),
  unknown('unknown');

  const NativeEventKind(this.wire);
  final String wire;

  static NativeEventKind fromWire(String value) {
    for (final NativeEventKind item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeEventKind.unknown;
  }
}

enum NativeLifecycleKind {
  attached('attached'),
  detached('detached'),
  appForeground('appForeground'),
  appBackground('appBackground'),
  unknown('unknown');

  const NativeLifecycleKind(this.wire);
  final String wire;

  static NativeLifecycleKind fromWire(String value) {
    for (final NativeLifecycleKind item in values) {
      if (item.wire == value) {
        return item;
      }
    }
    return NativeLifecycleKind.unknown;
  }
}
