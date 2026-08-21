import '../adapter/transport_adapter_types.dart';

enum TransportSelectionReason {
  retainCurrent,
  selected,
  noEligibleTransport,
  permissionBlocked,
  noCandidates,
  interopUnverified,
}

/// Typed selector outcome. Not a connection. No peer identity.
sealed class TransportSelection {
  const TransportSelection(this.reason);

  final TransportSelectionReason reason;
}

final class TransportRetainCurrent extends TransportSelection {
  const TransportRetainCurrent(this.path)
    : super(TransportSelectionReason.retainCurrent);

  final SelectedTransportPath path;
}

final class TransportSelected extends TransportSelection {
  TransportSelected({
    required this.chosen,
    required List<TransportCandidateKey> fallbacks,
  }) : fallbacks = List<TransportCandidateKey>.unmodifiable(
         List<TransportCandidateKey>.of(fallbacks),
       ),
       super(TransportSelectionReason.selected);

  final TransportCandidateKey chosen;
  final List<TransportCandidateKey> fallbacks;

  List<TransportCandidateKey> get attemptOrder => <TransportCandidateKey>[
    chosen,
    ...fallbacks,
  ];
}

final class TransportNone extends TransportSelection {
  const TransportNone(super.reason);
}
