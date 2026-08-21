import 'transition_authority.dart';

/// Typed illegal-transition failure. Never a generic "bad state" string only.
class InvalidStateTransition implements Exception {
  const InvalidStateTransition({
    required this.machine,
    required this.from,
    required this.event,
    required this.authority,
  });

  final String machine;
  final Object from;
  final Object event;
  final TransitionAuthority authority;

  @override
  String toString() {
    return 'InvalidStateTransition($machine: $from + $event / ${authority.wire})';
  }
}

/// Value-object / construction failure. Not a state-machine error.
class DomainFormatException implements Exception {
  const DomainFormatException(this.message);
  final String message;

  @override
  String toString() => 'DomainFormatException($message)';
}

/// Authenticated fingerprint mismatch. Identity is not updated.
class PeerIdentityMismatch implements Exception {
  const PeerIdentityMismatch({required this.existing, required this.attempted});

  final Object existing;
  final Object attempted;

  @override
  String toString() {
    return 'PeerIdentityMismatch(existing: $existing, attempted: $attempted)';
  }
}
