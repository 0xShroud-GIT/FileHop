import '../adapter/transport_adapter_types.dart';
import 'lan_discovery_event.dart';
import 'lan_discovery_instance_id.dart';

/// Platform-independent LAN browse/advertise seam.
///
/// Browse is Mission 07. A real listener port is supplied later by Mission 10.
/// Do not bind the FileHop control/data socket here.
abstract class LanDiscoveryBackend {
  Stream<LanDiscoveryEvent> get events;

  int get browseGeneration;

  LanDiscoveryInstanceId? get localInstanceId;

  bool get browsing;

  bool get advertising;

  Future<TransportCapabilitySnapshot> observeAvailability();

  Future<void> startBrowse();

  Future<void> stopBrowse();

  /// Store a future Mission 10 listener port. Does not start advertising.
  ///
  /// [port] must be 1..65535. Port 0 is rejected.
  Future<void> configureAdvertisement({
    required int port,
    LanDiscoveryInstanceId? instanceId,
  });

  Future<void> startAdvertisement();

  Future<void> stopAdvertisement();

  Future<void> close();
}
