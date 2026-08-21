import 'dart:math';
import 'dart:typed_data';

import 'lan_discovery_errors.dart';

/// Ephemeral LAN discovery instance identifier.
///
/// 128 random bits as 32 lowercase hexadecimal characters.
/// Locator correlation only — never peer identity, trust, or persistence.
class LanDiscoveryInstanceId {
  const LanDiscoveryInstanceId._(this.value);

  final String value;

  static final RegExp _canonical = RegExp(r'^[0-9a-f]{32}$');

  /// Production generator. Always [Random.secure]. Tests should [parse].
  factory LanDiscoveryInstanceId.generate() {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(16);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return LanDiscoveryInstanceId._(_hex(bytes));
  }

  /// Canonical parse. No trim, case-fold, or pad-strip.
  static LanDiscoveryInstanceId parse(String raw) {
    if (!_canonical.hasMatch(raw)) {
      throw const LanDiscoveryException(
        kind: LanDiscoveryFailureKind.malformedDiscoveryRecord,
        message: 'LAN instance ID must be 32 lowercase hex characters',
      );
    }
    return LanDiscoveryInstanceId._(raw);
  }

  static LanDiscoveryInstanceId? tryParse(String raw) {
    try {
      return LanDiscoveryInstanceId.parse(raw);
    } on LanDiscoveryException {
      return null;
    }
  }

  static String _hex(Uint8List bytes) {
    const String alphabet = '0123456789abcdef';
    final StringBuffer out = StringBuffer();
    for (final int b in bytes) {
      out.write(alphabet[(b >> 4) & 0x0f]);
      out.write(alphabet[b & 0x0f]);
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) {
    return other is LanDiscoveryInstanceId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
