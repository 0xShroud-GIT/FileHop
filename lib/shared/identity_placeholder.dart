/// Presentation-only identity copy. Not [PeerIdentity], not a key, not a
/// fingerprint. Cryptographic identity is later missions.
class IdentityPlaceholder {
  const IdentityPlaceholder({
    this.deviceName = 'This device',
    this.securityIdentity = 'Not initialized',
  });

  final String deviceName;
  final String securityIdentity;

  static const disclaimer =
      'The device name is a local label only. It is not a security identity.';
}
