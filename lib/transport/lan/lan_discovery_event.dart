import '../adapter/transport_adapter_types.dart';
import 'lan_discovery_errors.dart';
import 'lan_discovery_instance_id.dart';
import 'lan_discovery_record.dart';

sealed class LanDiscoveryEvent {
  const LanDiscoveryEvent({required this.generation});

  /// Browse-session correlation. Not candidate ID or peer identity.
  final int generation;
}

final class LanRecordFound extends LanDiscoveryEvent {
  const LanRecordFound({required super.generation, required this.record});

  final LanDiscoveryRecord record;
}

final class LanRecordUpdated extends LanDiscoveryEvent {
  const LanRecordUpdated({required super.generation, required this.record});

  final LanDiscoveryRecord record;
}

final class LanRecordLost extends LanDiscoveryEvent {
  const LanRecordLost({required super.generation, required this.instanceId});

  final LanDiscoveryInstanceId instanceId;
}

final class LanAvailabilityChanged extends LanDiscoveryEvent {
  const LanAvailabilityChanged({
    required super.generation,
    required this.snapshot,
  });

  final TransportCapabilitySnapshot snapshot;
}

final class LanDiscoveryErrorEvent extends LanDiscoveryEvent {
  const LanDiscoveryErrorEvent({
    required super.generation,
    required this.kind,
    required this.message,
  });

  final LanDiscoveryFailureKind kind;
  final String message;
}
