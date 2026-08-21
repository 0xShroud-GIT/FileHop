/// Resolved LAN locator address. Host and port stay separate (IPv6 has colons).
enum LanAddressFamily { ipv4, ipv6 }

class LanResolvedAddress {
  const LanResolvedAddress({required this.family, required this.host});

  final LanAddressFamily family;

  /// Textual IP without port. Never identity.
  final String host;

  String get diagnostic {
    switch (family) {
      case LanAddressFamily.ipv4:
        return host;
      case LanAddressFamily.ipv6:
        return '[$host]';
    }
  }

  @override
  bool operator ==(Object other) {
    return other is LanResolvedAddress &&
        other.family == family &&
        other.host == host;
  }

  @override
  int get hashCode => Object.hash(family, host);
}

/// Conservative textual IP parser. Hostnames are not selectable locators.
///
/// IPv6 validation delegates to the Dart SDK's deterministic RFC parser
/// (`Uri.parseIPv6Address`, dart:core — no sockets, no added dependency),
/// wrapped with FileHop-specific bounds: no zone index (`%`), no prefix
/// (`/`), no whitespace, no brackets, bounded length. The raw string is
/// never normalized: an invalid string is rejected, not repaired.
/// IPv4-embedded IPv6 (e.g. `2001:db8::192.0.2.1`) is intentionally
/// supported because the SDK parser supports it deterministically.
class LanAddressParser {
  const LanAddressParser();

  static const int _maxLength = 64;

  static final RegExp _ipv4 = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  );

  LanResolvedAddress? tryParse(String raw) {
    if (raw.isEmpty || raw.length > _maxLength) {
      return null;
    }
    if (raw.contains('%') ||
        raw.contains('/') ||
        raw.contains(' ') ||
        raw.contains('\t') ||
        raw.contains('[') ||
        raw.contains(']')) {
      return null;
    }
    final Match? v4 = _ipv4.firstMatch(raw);
    if (v4 != null) {
      for (int i = 1; i <= 4; i++) {
        final int octet = int.parse(v4.group(i)!);
        if (octet > 255) {
          return null;
        }
      }
      return LanResolvedAddress(family: LanAddressFamily.ipv4, host: raw);
    }
    if (_isStrictIpv6(raw)) {
      return LanResolvedAddress(family: LanAddressFamily.ipv6, host: raw);
    }
    return null;
  }

  bool _isStrictIpv6(String raw) {
    // IPv6 requires at least one colon; anything else was either IPv4
    // (handled above) or is not a selectable LAN locator.
    if (!raw.contains(':')) {
      return false;
    }
    try {
      // Deterministic strict RFC 4291 parse from the Dart SDK. Rejects
      // underfilled uncompressed forms, excess groups, multiple `::`,
      // >4-digit hex groups, non-hex characters, malformed embedded IPv4,
      // and trailing garbage. Throws FormatException on invalid input.
      Uri.parseIPv6Address(raw);
      return true;
    } on FormatException {
      return false;
    }
  }
}
