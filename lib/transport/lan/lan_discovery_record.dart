import 'dart:convert';

import 'lan_address.dart';
import 'lan_constants.dart';
import 'lan_discovery_errors.dart';
import 'lan_discovery_instance_id.dart';
import 'lan_locator.dart';

/// Resolved LAN service record. Locator metadata, not peer identity.
///
/// A record carries exactly one [LanLocator]: either a truthful resolved
/// socket ([LanResolvedSocketLocator]) or a native service endpoint pending
/// connection-time resolution ([LanNativeServiceLocator]). Discovery must
/// never fabricate a resolved socket address for the native-service case.
class LanDiscoveryRecord {
  LanDiscoveryRecord({
    required this.instanceId,
    required this.serviceInstanceName,
    required this.serviceType,
    required this.locator,
    required this.discoveryVersion,
  });

  final LanDiscoveryInstanceId instanceId;
  final String serviceInstanceName;
  final String serviceType;
  final LanLocator locator;
  final int discoveryVersion;

  String get candidateId => instanceId.value;

  /// Resolved port; null when the locator is a pending native service.
  int? get port => switch (locator) {
    LanResolvedSocketLocator(:final int port) => port,
    _ => null,
  };

  /// Resolved addresses; empty when the locator is a pending native service.
  List<LanResolvedAddress> get addresses => switch (locator) {
    LanResolvedSocketLocator(:final List<LanResolvedAddress> addresses) =>
      addresses,
    _ => const <LanResolvedAddress>[],
  };

  /// Human diagnostic only. Not a structured host:port authority.
  String get locatorHint => locator.locatorHint;

  static LanDiscoveryRecord resolved({
    required LanDiscoveryInstanceId instanceId,
    required String serviceInstanceName,
    required String serviceType,
    required int port,
    required List<LanResolvedAddress> addresses,
    int discoveryVersion = kFileHopLanDiscoverySchemaVersion,
  }) {
    if (serviceType != kFileHopLanServiceType) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.wrongServiceType,
        message: 'service type is not FileHop LAN',
      );
    }
    if (port < 1 || port > 65535) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'LAN port must be 1..65535',
      );
    }
    if (addresses.isEmpty) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'LAN record has no resolved address',
      );
    }
    if (addresses.length > kFileHopLanMaxAddressesPerCandidate) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'too many LAN addresses',
      );
    }
    final List<LanResolvedAddress> unique = <LanResolvedAddress>[];
    for (final LanResolvedAddress address in addresses) {
      if (!unique.contains(address)) {
        unique.add(address);
      }
    }
    return LanDiscoveryRecord(
      instanceId: instanceId,
      serviceInstanceName: serviceInstanceName,
      serviceType: serviceType,
      locator: LanResolvedSocketLocator(
        port: port,
        addresses: List<LanResolvedAddress>.unmodifiable(unique),
      ),
      discoveryVersion: discoveryVersion,
    );
  }

  /// Native service endpoint pending connection-time resolution.
  /// No host/port claim is made or accepted here.
  static LanDiscoveryRecord nativeService({
    required LanDiscoveryInstanceId instanceId,
    required String serviceInstanceName,
    required String serviceType,
    required String serviceReference,
    int discoveryVersion = kFileHopLanDiscoverySchemaVersion,
  }) {
    if (serviceType != kFileHopLanServiceType) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.wrongServiceType,
        message: 'service type is not FileHop LAN',
      );
    }
    if (serviceReference.isEmpty) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'native service reference must not be empty',
      );
    }
    // D-07-11: the bound is UTF-8 BYTES, not Dart code units. A multibyte
    // reference whose code-unit length is below the limit but whose UTF-8
    // encoding exceeds it must fail closed (no truncation).
    final int utf8Length = utf8.encode(serviceReference).length;
    if (utf8Length > LanNativeServiceLocator.kMaxServiceReferenceBytes) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'native service reference exceeds the UTF-8 byte bound',
      );
    }
    for (final int unit in serviceReference.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) {
        throw const LanDiscoveryException(
          kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
          message: 'native service reference has control characters',
        );
      }
    }
    return LanDiscoveryRecord(
      instanceId: instanceId,
      serviceInstanceName: serviceInstanceName,
      serviceType: serviceType,
      locator: LanNativeServiceLocator(serviceReference: serviceReference),
      discoveryVersion: discoveryVersion,
    );
  }
}
