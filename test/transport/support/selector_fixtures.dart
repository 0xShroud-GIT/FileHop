import 'package:filehop/domain/transport/transport_candidate.dart';
import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';

TransportCapabilitySnapshot cap(
  TransportKind kind,
  TransportAvailability availability,
) {
  return TransportCapabilitySnapshot(kind: kind, availability: availability);
}

SelectableCandidate availableCandidate(TransportKind kind, String id) {
  return SelectableCandidate(
    key: TransportCandidateKey(kind: kind, candidateId: id),
    state: TransportCandidateState.available,
  );
}

TransportSelectionInput input({
  required TransportPlatform local,
  TransportPlatform? remote,
  TransportQualificationPolicy qualification =
      const TransportQualificationPolicy(),
  required Map<TransportKind, TransportAvailability> adapters,
  required List<SelectableCandidate> candidates,
  SelectedTransportPath? current,
}) {
  return TransportSelectionInput(
    localPlatform: local,
    remotePlatform: remote,
    qualification: qualification,
    capabilities: <TransportKind, TransportCapabilitySnapshot>{
      for (final MapEntry<TransportKind, TransportAvailability> entry
          in adapters.entries)
        entry.key: cap(entry.key, entry.value),
    },
    candidates: candidates,
    currentPath: current,
  );
}

SelectedTransportPath healthyPath(TransportKind kind, String id) {
  return SelectedTransportPath(
    key: TransportCandidateKey(kind: kind, candidateId: id),
    connection: TransportConnectionHandle(handleId: 'h-$id', kind: kind),
    healthy: true,
  );
}
