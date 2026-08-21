import 'peer_fingerprint.dart';

/// Result of comparing a remembered fingerprint to an authenticated one.
enum AuthenticatedIdentityComparison { sameIdentity, identityChanged }

/// Pure identity-change policy. Display names and locators are ignored.
abstract final class IdentityChangePolicy {
  static AuthenticatedIdentityComparison compare({
    required PeerFingerprint remembered,
    required PeerFingerprint authenticated,
  }) {
    if (remembered == authenticated) {
      return AuthenticatedIdentityComparison.sameIdentity;
    }
    return AuthenticatedIdentityComparison.identityChanged;
  }
}
