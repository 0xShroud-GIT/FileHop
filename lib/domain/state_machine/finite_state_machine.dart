import 'invalid_state_transition.dart';
import 'transition_authority.dart';

/// Successful reduction. Illegal combinations throw [InvalidStateTransition].
class AppliedTransition<S extends Enum, E extends Enum> {
  const AppliedTransition({
    required this.from,
    required this.to,
    required this.event,
    required this.authority,
  });

  final S from;
  final S to;
  final E event;
  final TransitionAuthority authority;

  bool get changed => from != to;
}

/// Explicit table reducer. No I/O, timers, or hidden mutation.
///
/// Transition tables are copied and frozen at construction. Callers cannot
/// add, replace, or remove mappings through [allowed] or [noop].
class FiniteStateMachine<S extends Enum, E extends Enum> {
  FiniteStateMachine({
    required this.machine,
    required Map<S, Map<E, S>> allowed,
    Set<(Object, Object)> noop = const <(Object, Object)>{},
  }) : _allowed = _freezeAllowed(allowed),
       _noop = Set<(Object, Object)>.unmodifiable(
         Set<(Object, Object)>.of(noop),
       );

  final String machine;
  final Map<S, Map<E, S>> _allowed;
  final Set<(Object, Object)> _noop;

  /// Read-only view. Mutation throws [UnsupportedError].
  Map<S, Map<E, S>> get allowed => _allowed;

  /// Read-only view. Mutation throws [UnsupportedError].
  Set<(Object, Object)> get noop => _noop;

  static Map<S, Map<E, S>> _freezeAllowed<S extends Enum, E extends Enum>(
    Map<S, Map<E, S>> allowed,
  ) {
    final Map<S, Map<E, S>> copy = <S, Map<E, S>>{};
    allowed.forEach((S from, Map<E, S> targets) {
      copy[from] = Map<E, S>.unmodifiable(Map<E, S>.of(targets));
    });
    return Map<S, Map<E, S>>.unmodifiable(copy);
  }

  bool isLegal(S from, E event) {
    return _noop.contains((from, event)) ||
        (_allowed[from]?.containsKey(event) ?? false);
  }

  AppliedTransition<S, E> reduce({
    required S from,
    required E event,
    required TransitionAuthority authority,
  }) {
    if (_noop.contains((from, event))) {
      return AppliedTransition<S, E>(
        from: from,
        to: from,
        event: event,
        authority: authority,
      );
    }
    final S? to = _allowed[from]?[event];
    if (to == null) {
      throw InvalidStateTransition(
        machine: machine,
        from: from,
        event: event,
        authority: authority,
      );
    }
    return AppliedTransition<S, E>(
      from: from,
      to: to,
      event: event,
      authority: authority,
    );
  }
}
