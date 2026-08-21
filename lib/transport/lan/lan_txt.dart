import 'dart:convert';
import 'dart:typed_data';

import 'lan_constants.dart';
import 'lan_discovery_errors.dart';
import 'lan_discovery_instance_id.dart';

/// Parsed FileHop LAN TXT. Unknown bounded keys are ignored, never identity.
class LanTxtFields {
  const LanTxtFields({
    required this.discoveryVersion,
    required this.instanceId,
    required this.ignoredUnknown,
  });

  final int discoveryVersion;
  final LanDiscoveryInstanceId instanceId;
  final Map<String, String> ignoredUnknown;
}

/// Strict bounded TXT encoder/decoder. Deterministic key order on encode.
class LanTxtCodec {
  const LanTxtCodec();

  /// v1 advertisement: only `v` and `i`. Keys sorted for canonical tests.
  Map<String, String> encodeV1(LanDiscoveryInstanceId instanceId) {
    return <String, String>{
      kFileHopLanTxtInstanceKey: instanceId.value,
      kFileHopLanTxtVersionKey: '$kFileHopLanDiscoverySchemaVersion',
    };
  }

  List<MapEntry<String, String>> encodeV1Sorted(LanDiscoveryInstanceId id) {
    final Map<String, String> map = encodeV1(id);
    final List<String> keys = map.keys.toList()..sort();
    return <MapEntry<String, String>>[
      for (final String key in keys) MapEntry<String, String>(key, map[key]!),
    ];
  }

  LanTxtFields parsePairs(List<MapEntry<String, List<int>>> pairs) {
    if (pairs.length > kFileHopLanMaxTxtKeys) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'too many TXT keys',
      );
    }
    int total = 0;
    final Map<String, List<int>> seen = <String, List<int>>{};
    for (final MapEntry<String, List<int>> pair in pairs) {
      final List<int> keyBytes = utf8.encode(pair.key);
      if (keyBytes.isEmpty || keyBytes.length > kFileHopLanMaxTxtKeyBytes) {
        throw const LanDiscoveryException(
          kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
          message: 'TXT key length out of bounds',
        );
      }
      if (pair.value.length > kFileHopLanMaxTxtValueBytes) {
        throw const LanDiscoveryException(
          kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
          message: 'TXT value length out of bounds',
        );
      }
      total += keyBytes.length + pair.value.length;
      if (total > kFileHopLanMaxTxtPayloadBytes) {
        throw const LanDiscoveryException(
          kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
          message: 'TXT payload exceeds bound',
        );
      }
      if (seen.containsKey(pair.key)) {
        throw const LanDiscoveryException(
          kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
          message: 'duplicate TXT key',
        );
      }
      seen[pair.key] = pair.value;
    }
    return _finish(seen);
  }

  LanTxtFields parseStringMap(Map<String, String> fields) {
    return parsePairs(<MapEntry<String, List<int>>>[
      for (final MapEntry<String, String> e in fields.entries)
        MapEntry<String, List<int>>(e.key, utf8.encode(e.value)),
    ]);
  }

  LanTxtFields _finish(Map<String, List<int>> seen) {
    final List<int>? versionBytes = seen[kFileHopLanTxtVersionKey];
    final List<int>? instanceBytes = seen[kFileHopLanTxtInstanceKey];
    if (versionBytes == null) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'missing TXT version',
      );
    }
    if (instanceBytes == null) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'missing TXT instance id',
      );
    }
    final String versionText = _utf8(versionBytes);
    final int? version = int.tryParse(versionText);
    if (version == null) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'TXT version is not an integer',
      );
    }
    if (version != kFileHopLanDiscoverySchemaVersion) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.unsupportedDiscoveryVersion,
        message: 'unsupported LAN discovery schema version',
      );
    }
    final String instanceText = _utf8(instanceBytes);
    final LanDiscoveryInstanceId instanceId = LanDiscoveryInstanceId.parse(
      instanceText,
    );

    final Map<String, String> unknown = <String, String>{};
    seen.forEach((String key, List<int> value) {
      if (key == kFileHopLanTxtVersionKey || key == kFileHopLanTxtInstanceKey) {
        return;
      }
      unknown[key] = _utf8(value);
    });
    return LanTxtFields(
      discoveryVersion: version,
      instanceId: instanceId,
      ignoredUnknown: Map<String, String>.unmodifiable(unknown),
    );
  }

  String _utf8(List<int> bytes) {
    try {
      return utf8.decode(Uint8List.fromList(bytes), allowMalformed: false);
    } on FormatException {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'TXT value is not UTF-8',
      );
    }
  }
}
