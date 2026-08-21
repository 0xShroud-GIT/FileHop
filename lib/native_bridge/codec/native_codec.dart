import 'dart:typed_data';

import '../contract/enums.dart';
import '../contract/errors.dart';
import '../contract/events.dart';
import '../contract/models.dart';

/// Dart/native application-build contract. Not the FileHop peer protocol.
const int kNativeBridgeVersion = 1;

const String kNativeCommandChannel = 'app.filehop.native.commands';
const String kNativeEventChannel = 'app.filehop.native.events';

/// Low-level Map codec. Application/engine code uses typed DTOs only.
class NativeCodec {
  const NativeCodec();

  static const Set<String> forbiddenIdentityKeys = {
    'peerIdentity',
    'peerFingerprint',
    'fingerprint',
    'staticPublicKey',
    'identityKey',
    'sas',
  };

  /// Secret material must never appear on the event channel.
  static const Set<String> forbiddenSecretKeys = {
    'privateKeyBytes',
    'privateKey',
    'staticPrivateKey',
    'wrappedKey',
    'wrappingKey',
  };

  static const int identityPrivateKeyLength = 32;
  static const int identityReferenceMaxLength = 64;
  static final RegExp identityReferencePattern = RegExp(
    r'^fhik1\.[0-9a-f]{32}$',
  );

  Map<String, Object?> requireMap(Object? raw, String label) {
    if (raw is! Map) {
      throw NativeCodecException('$label must be a map');
    }
    final Map<String, Object?> out = <String, Object?>{};
    raw.forEach((Object? key, Object? value) {
      if (key is! String) {
        throw NativeCodecException('$label keys must be strings');
      }
      if (forbiddenIdentityKeys.contains(key)) {
        throw NativeCodecException(
          '$label must not carry security identity field "$key"',
        );
      }
      out[key] = value;
    });
    return out;
  }

  void requireBridgeVersion(Map<String, Object?> map) {
    final Object? version = map['bridgeVersion'];
    if (version is! int) {
      throw NativeCodecException('bridgeVersion must be an int');
    }
    if (version != kNativeBridgeVersion) {
      throw NativeCodecException(
        'incompatible bridgeVersion $version (expected $kNativeBridgeVersion)',
      );
    }
  }

  String requireString(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! String || value.isEmpty) {
      throw NativeCodecException('$key must be a non-empty string');
    }
    return value;
  }

  String? optionalString(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw NativeCodecException('$key must be a string or null');
    }
    return value;
  }

  int? optionalInt(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw NativeCodecException('$key must be an int or null');
    }
    return value;
  }

  bool? optionalBool(Map<String, Object?> map, String key) {
    final Object? value = map[key];
    if (value == null) {
      return null;
    }
    if (value is! bool) {
      throw NativeCodecException('$key must be a bool or null');
    }
    return value;
  }

  Map<String, Object?> envelope(Map<String, Object?> payload) {
    return <String, Object?>{'bridgeVersion': kNativeBridgeVersion, ...payload};
  }

  Map<String, Object?> encodeCandidate(NativeTransportCandidate candidate) {
    return envelope(<String, Object?>{
      'candidateId': candidate.candidateId,
      'kind': candidate.kind.wire,
      'displayLabel': candidate.displayLabel,
      'locatorHint': candidate.locatorHint,
    });
  }

  NativeTransportCandidate decodeCandidate(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'candidate');
    requireBridgeVersion(map);
    return NativeTransportCandidate(
      candidateId: requireString(map, 'candidateId'),
      kind: NativeTransportKind.fromWire(requireString(map, 'kind')),
      displayLabel: optionalString(map, 'displayLabel'),
      locatorHint: optionalString(map, 'locatorHint'),
    );
  }

  Map<String, Object?> encodeConnection(NativeConnectionHandle handle) {
    return envelope(<String, Object?>{
      'handleId': handle.handleId,
      'kind': handle.kind.wire,
    });
  }

  NativeConnectionHandle decodeConnection(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'connection');
    requireBridgeVersion(map);
    return NativeConnectionHandle(
      handleId: requireString(map, 'handleId'),
      kind: NativeTransportKind.fromWire(requireString(map, 'kind')),
    );
  }

  Map<String, Object?> encodeEndpoint(NativeEndpoint endpoint) {
    return envelope(<String, Object?>{
      'endpointId': endpoint.endpointId,
      'kind': endpoint.kind.wire,
      'reachability': endpoint.reachability.wire,
      'host': endpoint.host,
      'port': endpoint.port,
      'nativePathHandle': endpoint.nativePathHandle,
    });
  }

  NativeEndpoint decodeEndpoint(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'endpoint');
    requireBridgeVersion(map);
    final NativeEndpointReachability reachability =
        NativeEndpointReachability.fromWire(requireString(map, 'reachability'));
    final String? host = optionalString(map, 'host');
    final int? port = optionalInt(map, 'port');
    final String? nativePathHandle = optionalString(map, 'nativePathHandle');
    _validateEndpointReachability(
      reachability: reachability,
      host: host,
      port: port,
      nativePathHandle: nativePathHandle,
    );
    return NativeEndpoint(
      endpointId: requireString(map, 'endpointId'),
      kind: NativeTransportKind.fromWire(requireString(map, 'kind')),
      reachability: reachability,
      host: host,
      port: port,
      nativePathHandle: nativePathHandle,
    );
  }

  /// Required fields follow the selected reachability. The other mode's
  /// locator fields may be present and are ignored. Locators are not identity.
  void _validateEndpointReachability({
    required NativeEndpointReachability reachability,
    required String? host,
    required int? port,
    required String? nativePathHandle,
  }) {
    switch (reachability) {
      case NativeEndpointReachability.socket:
        if (host == null || host.isEmpty) {
          throw const NativeCodecException(
            'socket endpoint requires a non-empty host',
          );
        }
        if (port == null) {
          throw const NativeCodecException('socket endpoint requires port');
        }
        if (port < 1 || port > 65535) {
          throw const NativeCodecException(
            'socket endpoint port must be an integer in 1..65535',
          );
        }
      case NativeEndpointReachability.nativeStream:
        if (nativePathHandle == null || nativePathHandle.isEmpty) {
          throw const NativeCodecException(
            'nativeStream endpoint requires nativePathHandle',
          );
        }
      case NativeEndpointReachability.unknown:
        throw const NativeCodecException(
          'endpoint reachability must be socket or nativeStream',
        );
    }
  }

  Map<String, Object?> encodeCapability(NativeCapabilitySnapshot snapshot) {
    return envelope(<String, Object?>{
      'kind': snapshot.kind.wire,
      'status': snapshot.status.wire,
      'permission': snapshot.permission?.wire,
      'detail': snapshot.detail,
    });
  }

  NativeCapabilitySnapshot decodeCapability(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'capability');
    requireBridgeVersion(map);
    final String? permission = optionalString(map, 'permission');
    return NativeCapabilitySnapshot(
      kind: NativeTransportKind.fromWire(requireString(map, 'kind')),
      status: NativeCapabilityStatus.fromWire(requireString(map, 'status')),
      permission: permission == null
          ? null
          : NativePermissionStatus.fromWire(permission),
      detail: optionalString(map, 'detail'),
    );
  }

  Map<String, Object?> encodeError(NativeAdapterError error) {
    return envelope(<String, Object?>{
      'errorClass': error.errorClass.wire,
      'message': error.message,
      'nativeCode': error.nativeCode,
      'kind': error.kind?.wire,
    });
  }

  NativeAdapterError decodeError(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'error');
    requireBridgeVersion(map);
    final String? kind = optionalString(map, 'kind');
    return NativeAdapterError(
      errorClass: NativeErrorClass.fromWire(requireString(map, 'errorClass')),
      message: requireString(map, 'message'),
      nativeCode: optionalString(map, 'nativeCode'),
      kind: kind == null ? null : NativeTransportKind.fromWire(kind),
    );
  }

  NativePingResult decodePing(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'ping');
    requireBridgeVersion(map);
    final Object? ok = map['ok'];
    if (ok is! bool) {
      throw NativeCodecException('ok must be a bool');
    }
    return NativePingResult(bridgeVersion: kNativeBridgeVersion, ok: ok);
  }

  NativeLifecycleEvent decodeLifecycle(Object? raw) {
    final Map<String, Object?> map = requireMap(raw, 'lifecycle');
    return NativeLifecycleEvent(
      kind: NativeLifecycleKind.fromWire(requireString(map, 'kind')),
      detail: optionalString(map, 'detail'),
    );
  }

  NativeAdapterEvent? decodeEvent(Object? raw) {
    try {
      final Map<String, Object?> map = requireMap(raw, 'event');
      for (final String key in forbiddenSecretKeys) {
        if (map.containsKey(key) && map[key] != null) {
          return null;
        }
      }
      requireBridgeVersion(map);
      final NativeEventKind kind = NativeEventKind.fromWire(
        requireString(map, 'eventKind'),
      );
      if (kind == NativeEventKind.unknown) {
        throw const NativeCodecException('unknown event kind');
      }
      final String? transport = optionalString(map, 'transportKind');
      final NativeTransportCandidate? candidate = map['candidate'] == null
          ? null
          : decodeCandidate(map['candidate']);
      final NativeEndpoint? endpoint = map['endpoint'] == null
          ? null
          : decodeEndpoint(map['endpoint']);
      final NativeConnectionHandle? connection = map['connection'] == null
          ? null
          : decodeConnection(map['connection']);
      final bool? connected = optionalBool(map, 'connected');
      final NativeCapabilitySnapshot? capability = map['capability'] == null
          ? null
          : decodeCapability(map['capability']);
      final String? permissionWire = optionalString(map, 'permission');
      final NativePermissionStatus? permission = permissionWire == null
          ? null
          : NativePermissionStatus.fromWire(permissionWire);
      final NativeLifecycleEvent? lifecycle = map['lifecycle'] == null
          ? null
          : decodeLifecycle(map['lifecycle']);
      final NativeAdapterError? error = map['error'] == null
          ? null
          : decodeError(map['error']);
      _requireEventPayload(
        kind: kind,
        candidate: candidate,
        endpoint: endpoint,
        connection: connection,
        connected: connected,
        capability: capability,
        permission: permission,
        lifecycle: lifecycle,
        error: error,
      );
      return NativeAdapterEvent(
        kind: kind,
        transportKind: transport == null
            ? null
            : NativeTransportKind.fromWire(transport),
        candidate: candidate,
        endpoint: endpoint,
        connection: connection,
        connected: connected,
        capability: capability,
        permission: permission,
        lifecycle: lifecycle,
        error: error,
        detail: optionalString(map, 'detail'),
      );
    } on NativeCodecException {
      return null;
    } on TypeError {
      return null;
    }
  }

  void _requireEventPayload({
    required NativeEventKind kind,
    required NativeTransportCandidate? candidate,
    required NativeEndpoint? endpoint,
    required NativeConnectionHandle? connection,
    required bool? connected,
    required NativeCapabilitySnapshot? capability,
    required NativePermissionStatus? permission,
    required NativeLifecycleEvent? lifecycle,
    required NativeAdapterError? error,
  }) {
    switch (kind) {
      case NativeEventKind.availabilityChanged:
        if (capability == null) {
          throw const NativeCodecException(
            'availabilityChanged requires capability',
          );
        }
      case NativeEventKind.candidateFound:
        if (candidate == null) {
          throw const NativeCodecException('candidateFound requires candidate');
        }
      case NativeEventKind.candidateUpdated:
        if (candidate == null) {
          throw const NativeCodecException(
            'candidateUpdated requires candidate',
          );
        }
      case NativeEventKind.candidateLost:
        if (candidate == null) {
          throw const NativeCodecException('candidateLost requires candidate');
        }
      case NativeEventKind.connectionChanged:
        if (connection == null || connected == null) {
          throw const NativeCodecException(
            'connectionChanged requires connection and connected',
          );
        }
      case NativeEventKind.endpointChanged:
        if (endpoint == null) {
          throw const NativeCodecException('endpointChanged requires endpoint');
        }
      case NativeEventKind.permissionChanged:
        if (permission == null) {
          throw const NativeCodecException(
            'permissionChanged requires permission',
          );
        }
      case NativeEventKind.nativeLifecycleChanged:
        if (lifecycle == null) {
          throw const NativeCodecException(
            'nativeLifecycleChanged requires lifecycle',
          );
        }
      case NativeEventKind.adapterError:
        if (error == null) {
          throw const NativeCodecException('adapterError requires error');
        }
      case NativeEventKind.unknown:
        throw const NativeCodecException('unknown event kind');
    }
  }

  Map<String, Object?> encodeIdentitySecretStore(Uint8List privateKeyBytes) {
    _requirePrivateKeyBytes(privateKeyBytes);
    return envelope(<String, Object?>{'privateKeyBytes': privateKeyBytes});
  }

  Map<String, Object?> encodeIdentitySecretReference(String reference) {
    return envelope(<String, Object?>{
      'reference': requireIdentityReference(reference),
    });
  }

  NativeIdentitySecretReference decodeIdentitySecretReference(Object? raw) {
    final Map<String, Object?> map = _requireIdentitySecretMap(
      raw,
      'identitySecret.reference',
    );
    requireBridgeVersion(map);
    return NativeIdentitySecretReference(
      reference: requireIdentityReference(requireString(map, 'reference')),
    );
  }

  Uint8List decodeIdentitySecretBytes(Object? raw) {
    final Map<String, Object?> map = _requireIdentitySecretMap(
      raw,
      'identitySecret.bytes',
    );
    requireBridgeVersion(map);
    return requireIdentityPrivateKeyBytes(map);
  }

  NativeIdentitySecretStatus decodeIdentitySecretStatus(Object? raw) {
    final Map<String, Object?> map = _requireIdentitySecretMap(
      raw,
      'identitySecret.status',
    );
    requireBridgeVersion(map);
    return NativeIdentitySecretStatus.fromWire(requireString(map, 'status'));
  }

  NativeIdentitySecretPresence decodeIdentitySecretPresence(Object? raw) {
    final Map<String, Object?> map = _requireIdentitySecretMap(
      raw,
      'identitySecret.hasAny',
    );
    requireBridgeVersion(map);
    final Object? any = map['any'];
    if (any is! bool) {
      throw const NativeCodecException('any must be a bool');
    }
    return NativeIdentitySecretPresence(any: any);
  }

  String requireIdentityReference(String raw) {
    if (raw.length > identityReferenceMaxLength ||
        !identityReferencePattern.hasMatch(raw)) {
      throw const NativeCodecException(
        'identity secret reference is not a supported FileHop reference',
      );
    }
    return raw;
  }

  Uint8List requireIdentityPrivateKeyBytes(Map<String, Object?> map) {
    final Object? value = map['privateKeyBytes'];
    if (value is! List<int> || value.length != identityPrivateKeyLength) {
      throw const NativeCodecException(
        'privateKeyBytes must be exactly 32 bytes',
      );
    }
    return Uint8List.fromList(value);
  }

  void _requirePrivateKeyBytes(Uint8List privateKeyBytes) {
    if (privateKeyBytes.length != identityPrivateKeyLength) {
      throw const NativeCodecException(
        'privateKeyBytes must be exactly 32 bytes',
      );
    }
  }

  Map<String, Object?> _requireIdentitySecretMap(Object? raw, String label) {
    if (raw is! Map) {
      throw NativeCodecException('$label must be a map');
    }
    final Map<String, Object?> out = <String, Object?>{};
    raw.forEach((Object? key, Object? value) {
      if (key is! String) {
        throw NativeCodecException('$label keys must be strings');
      }
      if (forbiddenIdentityKeys.contains(key)) {
        throw NativeCodecException(
          '$label must not carry security identity field "$key"',
        );
      }
      out[key] = value;
    });
    return out;
  }

  Map<String, Object?> encodeEvent(NativeAdapterEvent event) {
    return envelope(<String, Object?>{
      'eventKind': event.kind.wire,
      'transportKind': event.transportKind?.wire,
      'candidate': event.candidate == null
          ? null
          : encodeCandidate(event.candidate!),
      'endpoint': event.endpoint == null
          ? null
          : encodeEndpoint(event.endpoint!),
      'connection': event.connection == null
          ? null
          : encodeConnection(event.connection!),
      'connected': event.connected,
      'capability': event.capability == null
          ? null
          : encodeCapability(event.capability!),
      'permission': event.permission?.wire,
      'lifecycle': event.lifecycle == null
          ? null
          : <String, Object?>{
              'kind': event.lifecycle!.kind.wire,
              'detail': event.lifecycle!.detail,
            },
      'error': event.error == null ? null : encodeError(event.error!),
      'detail': event.detail,
    });
  }
}
