import '../../domain/transport/transport_candidate.dart';
import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_adapter_types.dart';
import '../adapter/transport_availability.dart';
import 'transport_qualification_policy.dart';
import 'transport_selection.dart';

/// Immutable selector input. No hidden global state.
class TransportSelectionInput {
  TransportSelectionInput({
    required this.localPlatform,
    required this.remotePlatform,
    required this.qualification,
    required Map<TransportKind, TransportCapabilitySnapshot> capabilities,
    required List<SelectableCandidate> candidates,
    required this.currentPath,
    Set<TransportCandidateKey> failedAttempts = const <TransportCandidateKey>{},
  }) : capabilities =
           Map<TransportKind, TransportCapabilitySnapshot>.unmodifiable(
             Map<TransportKind, TransportCapabilitySnapshot>.of(capabilities),
           ),
       candidates = List<SelectableCandidate>.unmodifiable(
         List<SelectableCandidate>.of(candidates),
       ),
       failedAttempts = Set<TransportCandidateKey>.unmodifiable(
         Set<TransportCandidateKey>.of(failedAttempts),
       );

  final TransportPlatform localPlatform;
  final TransportPlatform? remotePlatform;
  final TransportQualificationPolicy qualification;
  final Map<TransportKind, TransportCapabilitySnapshot> capabilities;
  final List<SelectableCandidate> candidates;
  final SelectedTransportPath? currentPath;
  final Set<TransportCandidateKey> failedAttempts;
}

/// Locator-only view used for ranking. Display/locator never identity.
class SelectableCandidate {
  const SelectableCandidate({
    required this.key,
    required this.state,
    this.displayLabel,
    this.locatorHint,
  });

  final TransportCandidateKey key;
  final TransportCandidateState state;
  final String? displayLabel;
  final String? locatorHint;
}

/// Deterministic new-session rank: Aware → Direct → LAN, then candidateId.
class TransportSelector {
  const TransportSelector();

  static const List<TransportKind> preference = <TransportKind>[
    TransportKind.wifiAware,
    TransportKind.wifiDirect,
    TransportKind.lan,
  ];

  TransportSelection select(TransportSelectionInput input) {
    final SelectedTransportPath? current = input.currentPath;
    if (current != null &&
        current.healthy &&
        _adapterEligible(input, current.kind)) {
      return TransportRetainCurrent(current);
    }

    final List<TransportCandidateKey> ranked = _rank(input);
    if (ranked.isNotEmpty) {
      return TransportSelected(
        chosen: ranked.first,
        fallbacks: List<TransportCandidateKey>.unmodifiable(ranked.sublist(1)),
      );
    }
    return TransportNone(_noneReason(input));
  }

  List<TransportCandidateKey> _rank(TransportSelectionInput input) {
    final List<TransportCandidateKey> ranked = <TransportCandidateKey>[];
    for (final TransportKind kind in preference) {
      if (!_kindEligible(input, kind)) {
        continue;
      }
      final List<SelectableCandidate> sameKind = input.candidates
          .where(
            (SelectableCandidate item) =>
                item.key.kind == kind &&
                item.state == TransportCandidateState.available &&
                !input.failedAttempts.contains(item.key),
          )
          .toList();
      sameKind.sort(
        (SelectableCandidate a, SelectableCandidate b) =>
            a.key.candidateId.compareTo(b.key.candidateId),
      );
      for (final SelectableCandidate item in sameKind) {
        ranked.add(item.key);
      }
    }
    return ranked;
  }

  bool _kindEligible(TransportSelectionInput input, TransportKind kind) {
    if (!_adapterEligible(input, kind)) {
      return false;
    }
    return input.qualification.allows(
      kind: kind,
      local: input.localPlatform,
      remote: input.remotePlatform,
    );
  }

  bool _adapterEligible(TransportSelectionInput input, TransportKind kind) {
    final TransportCapabilitySnapshot? snapshot = input.capabilities[kind];
    if (snapshot == null) {
      return false;
    }
    return snapshot.availability.isAutoEligible;
  }

  TransportSelectionReason _noneReason(TransportSelectionInput input) {
    final bool anyCandidate = input.candidates.isNotEmpty;
    final bool anyPermission = input.capabilities.values.any(
      (TransportCapabilitySnapshot snapshot) =>
          snapshot.availability == TransportAvailability.permissionRequired,
    );
    final bool crossAwareBlocked = _crossPlatformAwarePresentButUnqualified(
      input,
    );
    if (!anyCandidate) {
      return TransportSelectionReason.noCandidates;
    }
    if (crossAwareBlocked && !_anyOtherEligibleFamily(input)) {
      return TransportSelectionReason.interopUnverified;
    }
    if (anyPermission && !_anyAutoEligibleAdapter(input)) {
      return TransportSelectionReason.permissionBlocked;
    }
    return TransportSelectionReason.noEligibleTransport;
  }

  bool _anyAutoEligibleAdapter(TransportSelectionInput input) {
    return input.capabilities.values.any(
      (TransportCapabilitySnapshot snapshot) =>
          snapshot.availability.isAutoEligible,
    );
  }

  bool _anyOtherEligibleFamily(TransportSelectionInput input) {
    for (final TransportKind kind in <TransportKind>[
      TransportKind.wifiDirect,
      TransportKind.lan,
    ]) {
      if (_kindEligible(input, kind) &&
          input.candidates.any(
            (SelectableCandidate item) =>
                item.key.kind == kind &&
                item.state == TransportCandidateState.available,
          )) {
        return true;
      }
    }
    return false;
  }

  bool _crossPlatformAwarePresentButUnqualified(TransportSelectionInput input) {
    if (input.remotePlatform == null ||
        input.remotePlatform == input.localPlatform) {
      return false;
    }
    if (input.qualification.androidIosAwareQualified) {
      return false;
    }
    return input.candidates.any(
      (SelectableCandidate item) => item.key.kind == TransportKind.wifiAware,
    );
  }
}
