import 'dart:math';

import '../state_machine/invalid_state_transition.dart';

/// 128-bit FileHop logical identifier: 32 lowercase hex characters.
///
/// Opaque. No timestamp, MAC, IP, path, or device name is encoded.
/// Not an authorization secret. [peerSessionId] is *not* generated here.
class LogicalId {
  LogicalId._(this.value);

  static final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

  final String value;

  factory LogicalId.parse(String raw) {
    if (!_hex32.hasMatch(raw)) {
      throw DomainFormatException(
        'logical id must be 32 lowercase hex characters',
      );
    }
    return LogicalId._(raw);
  }

  /// Cryptographically secure random id. Not used for [PeerSessionId].
  ///
  /// Always uses [Random.secure]. There is no weaker injectable generator.
  factory LogicalId.generate() {
    final Random source = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return LogicalId._(buffer.toString());
  }

  @override
  bool operator ==(Object other) => other is LogicalId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Validated `peerSessionId` format only.
///
/// Derivation is `HEX128(SHA256("FileHop/PeerSession/1" || handshakeHash))`
/// in Mission 11. This type must not invent a random stand-in.
class PeerSessionId {
  PeerSessionId._(this.value);

  static final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

  final String value;

  factory PeerSessionId.parse(String raw) {
    if (!_hex32.hasMatch(raw)) {
      throw DomainFormatException(
        'peerSessionId must be 32 lowercase hex characters',
      );
    }
    return PeerSessionId._(raw);
  }

  @override
  bool operator ==(Object other) =>
      other is PeerSessionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
