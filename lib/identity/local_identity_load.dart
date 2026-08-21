import 'errors.dart';
import 'local_identity.dart';

sealed class LocalIdentityLoad {
  const LocalIdentityLoad();
}

final class IdentityAbsent extends LocalIdentityLoad {
  const IdentityAbsent();
}

final class IdentityAvailable extends LocalIdentityLoad {
  const IdentityAvailable(this.identity);
  final LocalIdentity identity;
}

/// Typed startup inconsistency. Never auto-rotates identity.
final class IdentityUnavailable extends LocalIdentityLoad {
  const IdentityUnavailable(this.kind, {this.message});

  final IdentityFailureKind kind;
  final String? message;
}
