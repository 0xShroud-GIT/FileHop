import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/native_bridge/contract/enums.dart';
import 'package:filehop/transport/adapter/transport_availability.dart';
import 'package:filehop/transport/bridge/transport_kind_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known native kinds map exactly', () {
    expect(
      TransportKindMapping.toDomain(NativeTransportKind.wifiAware),
      TransportKind.wifiAware,
    );
    expect(
      TransportKindMapping.toDomain(NativeTransportKind.wifiDirect),
      TransportKind.wifiDirect,
    );
    expect(
      TransportKindMapping.toDomain(NativeTransportKind.lan),
      TransportKind.lan,
    );
    expect(
      TransportKindMapping.toNative(TransportKind.wifiAware),
      NativeTransportKind.wifiAware,
    );
  });

  test('unknown native kind never becomes LAN', () {
    expect(TransportKindMapping.toDomain(NativeTransportKind.unknown), isNull);
    expect(
      TransportKindMapping.availabilityOf(NativeCapabilityStatus.unknown),
      TransportAvailability.unknown,
    );
    expect(TransportAvailability.unknown.isAutoEligible, isFalse);
  });
}
