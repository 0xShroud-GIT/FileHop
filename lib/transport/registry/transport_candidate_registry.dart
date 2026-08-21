import '../../domain/state_machine/invalid_state_transition.dart';
import '../../domain/state_machine/transition_authority.dart';
import '../../domain/transport/transport_candidate.dart';
import '../../domain/transport/transport_kind.dart';
import '../adapter/transport_adapter_types.dart';
import '../adapter/transport_availability.dart';
import '../selection/transport_selector.dart';

class RegisteredTransportCandidate {
  const RegisteredTransportCandidate({
    required this.candidate,
    this.displayLabel,
    this.generation = 1,
  });

  final TransportCandidate candidate;
  final String? displayLabel;

  /// Discovery generation. Increments only on a fresh lifecycle, never identity.
  final int generation;

  TransportCandidateKey get key => TransportCandidateKey(
    kind: candidate.kind,
    candidateId: candidate.candidateId,
  );
}

/// Candidates keyed by ([TransportKind], candidateId). Locator ≠ identity.
class TransportCandidateRegistry {
  TransportCandidateRegistry();

  final Map<TransportCandidateKey, RegisteredTransportCandidate> _items =
      <TransportCandidateKey, RegisteredTransportCandidate>{};

  RegisteredTransportCandidate? operator [](TransportCandidateKey key) =>
      _items[key];

  Map<TransportCandidateKey, RegisteredTransportCandidate> all() {
    return Map<
      TransportCandidateKey,
      RegisteredTransportCandidate
    >.unmodifiable(
      Map<TransportCandidateKey, RegisteredTransportCandidate>.of(_items),
    );
  }

  List<RegisteredTransportCandidate> ofKind(TransportKind kind) {
    return List<RegisteredTransportCandidate>.unmodifiable(
      _items.values
          .where(
            (RegisteredTransportCandidate item) => item.candidate.kind == kind,
          )
          .toList(),
    );
  }

  List<SelectableCandidate> selectableViews() {
    return List<SelectableCandidate>.unmodifiable(
      _items.values
          .map(
            (RegisteredTransportCandidate item) => SelectableCandidate(
              key: item.key,
              state: item.candidate.state,
              displayLabel: item.displayLabel,
              locatorHint: item.candidate.locatorHint,
            ),
          )
          .toList(),
    );
  }

  void recordFound({
    required TransportKind kind,
    required String candidateId,
    String? displayLabel,
    String? locatorHint,
  }) {
    final TransportCandidateKey key = TransportCandidateKey(
      kind: kind,
      candidateId: candidateId,
    );
    final RegisteredTransportCandidate? existing = _items[key];
    if (existing != null && !_isTerminal(existing.candidate.state)) {
      _refreshMetadata(
        key,
        existing,
        displayLabel: displayLabel,
        locatorHint: locatorHint,
      );
      return;
    }
    TransportCandidate candidate = TransportCandidate.observed(
      candidateId: candidateId,
      kind: kind,
      locatorHint: locatorHint,
    );
    candidate = candidate.apply(
      TransportCandidateEvent.becomeAvailable,
      authority: TransitionAuthority.transportEvent,
    );
    _items[key] = RegisteredTransportCandidate(
      candidate: candidate,
      displayLabel: displayLabel,
      generation: (existing?.generation ?? 0) + 1,
    );
  }

  /// Stale updates do not resurrect lost candidates.
  void recordUpdated({
    required TransportKind kind,
    required String candidateId,
    String? displayLabel,
    String? locatorHint,
  }) {
    final TransportCandidateKey key = TransportCandidateKey(
      kind: kind,
      candidateId: candidateId,
    );
    final RegisteredTransportCandidate? current = _items[key];
    if (current == null || _isTerminal(current.candidate.state)) {
      return;
    }
    _refreshMetadata(
      key,
      current,
      displayLabel: displayLabel,
      locatorHint: locatorHint,
    );
  }

  void _refreshMetadata(
    TransportCandidateKey key,
    RegisteredTransportCandidate current, {
    String? displayLabel,
    String? locatorHint,
  }) {
    _items[key] = RegisteredTransportCandidate(
      candidate: locatorHint == null
          ? current.candidate
          : current.candidate.withLocatorHint(locatorHint),
      displayLabel: displayLabel ?? current.displayLabel,
      generation: current.generation,
    );
  }

  void recordLost({required TransportKind kind, required String candidateId}) {
    final TransportCandidateKey key = TransportCandidateKey(
      kind: kind,
      candidateId: candidateId,
    );
    final RegisteredTransportCandidate? current = _items[key];
    if (current == null || _isTerminal(current.candidate.state)) {
      return;
    }
    try {
      final TransportCandidateEvent event = _lossEvent(current.candidate.state);
      _items[key] = RegisteredTransportCandidate(
        candidate: current.candidate.apply(
          event,
          authority: TransitionAuthority.transportEvent,
        ),
        displayLabel: current.displayLabel,
        generation: current.generation,
      );
    } on InvalidStateTransition {
      // Already terminal: leave unchanged.
    }
  }

  RegisteredTransportCandidate apply(
    TransportCandidateKey key,
    TransportCandidateEvent event, {
    required TransitionAuthority authority,
  }) {
    final RegisteredTransportCandidate? current = _items[key];
    if (current == null) {
      throw StateError('unknown candidate $key');
    }
    final RegisteredTransportCandidate next = RegisteredTransportCandidate(
      candidate: current.candidate.apply(event, authority: authority),
      displayLabel: current.displayLabel,
      generation: current.generation,
    );
    _items[key] = next;
    return next;
  }

  bool tryApply(
    TransportCandidateKey key,
    TransportCandidateEvent event, {
    required TransitionAuthority authority,
  }) {
    final RegisteredTransportCandidate? current = _items[key];
    if (current == null) {
      return false;
    }
    try {
      _items[key] = RegisteredTransportCandidate(
        candidate: current.candidate.apply(event, authority: authority),
        displayLabel: current.displayLabel,
      );
      return true;
    } on InvalidStateTransition {
      return false;
    }
  }

  List<SelectableCandidate> eligibleAgainst(
    Map<TransportKind, TransportCapabilitySnapshot> capabilities,
  ) {
    return List<SelectableCandidate>.unmodifiable(
      _items.values
          .where((RegisteredTransportCandidate item) {
            final TransportCapabilitySnapshot? snapshot =
                capabilities[item.candidate.kind];
            return snapshot != null &&
                snapshot.availability.isAutoEligible &&
                item.candidate.state == TransportCandidateState.available;
          })
          .map(
            (RegisteredTransportCandidate item) => SelectableCandidate(
              key: item.key,
              state: item.candidate.state,
              displayLabel: item.displayLabel,
              locatorHint: item.candidate.locatorHint,
            ),
          )
          .toList(),
    );
  }

  static bool _isTerminal(TransportCandidateState state) {
    switch (state) {
      case TransportCandidateState.failed:
      case TransportCandidateState.lost:
      case TransportCandidateState.unavailable:
        return true;
      case TransportCandidateState.observed:
      case TransportCandidateState.available:
      case TransportCandidateState.connecting:
      case TransportCandidateState.connected:
        return false;
    }
  }

  static TransportCandidateEvent _lossEvent(TransportCandidateState state) {
    switch (state) {
      case TransportCandidateState.available:
        return TransportCandidateEvent.unavailable;
      case TransportCandidateState.connecting:
      case TransportCandidateState.connected:
        return TransportCandidateEvent.lost;
      case TransportCandidateState.observed:
      case TransportCandidateState.unavailable:
      case TransportCandidateState.failed:
      case TransportCandidateState.lost:
        return TransportCandidateEvent.lost;
    }
  }
}
