import 'package:filehop/transport/lan/lan_address.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 07 cleanup: strict address validation contract.
/// Malformed addresses must never become selectable LAN locators.
void main() {
  const LanAddressParser parser = LanAddressParser();

  group('valid IPv4', () {
    const List<String> cases = <String>[
      '127.0.0.1',
      '192.168.0.10',
      '10.0.0.1',
      '255.255.255.255',
      '0.0.0.0',
    ];
    for (final String raw in cases) {
      test('accepts $raw', () {
        final LanResolvedAddress? parsed = parser.tryParse(raw);
        expect(parsed, isNotNull);
        expect(parsed!.family, LanAddressFamily.ipv4);
        expect(parsed.host, raw);
        expect(parsed.diagnostic, raw);
      });
    }
  });

  group('invalid IPv4', () {
    const List<String> cases = <String>[
      '999.1.1.1',
      '256.0.0.1',
      '1.2.3',
      '1.2.3.4.5',
      '-1.2.3.4',
      'abc.def.ghi.jkl',
      '1..2.3',
      '1.2.3.',
      '.1.2.3.4',
      '1.2.3.4 ',
      ' 1.2.3.4',
      '1.2.3.4/24',
    ];
    for (final String raw in cases) {
      test('rejects "$raw"', () {
        expect(parser.tryParse(raw), isNull);
      });
    }
  });

  group('valid IPv6', () {
    const List<String> cases = <String>[
      '::1',
      '::',
      '2001:db8::1',
      'fe80::1',
      '2001:db8:0:0:0:0:0:1',
      '2001:0db8:0000:0000:0000:0000:0000:0001',
      'fd00:1:2:3:4:5:6:7',
      '2001:db8::192.0.2.1',
      '::ffff:192.0.2.1',
      '2001:DB8::1',
    ];
    for (final String raw in cases) {
      test('accepts $raw', () {
        final LanResolvedAddress? parsed = parser.tryParse(raw);
        expect(parsed, isNotNull);
        expect(parsed!.family, LanAddressFamily.ipv6);
        // Never normalized: the accepted host is the exact input.
        expect(parsed.host, raw);
        expect(parsed.diagnostic, '[$raw]');
      });
    }
  });

  group('invalid IPv6', () {
    const List<String> cases = <String>[
      // Too few groups without '::'.
      '1:2:3',
      '1:2:3:4:5:6:7',
      '2001:db8:1',
      // Too many groups.
      '1:2:3:4:5:6:7:8:9',
      '2001:db8:0:0:0:0:0:0:1',
      // Multiple '::'.
      '1::2::3',
      '::1::',
      // Empty group in an invalid position.
      ':1:2:3:4:5:6:7',
      '1:2:3:4:5:6:7:',
      ':::',
      // Hex group longer than 4 digits.
      '12345::1',
      '2001:db8::12345',
      // Non-hex group.
      'gggg::1',
      '2001:db8::zzzz',
      // Invalid IPv4-embedded suffix.
      '::ffff:999.0.2.1',
      '::ffff:1.2.3',
      '2001:db8::1.2.3.4.5',
      // Trailing/leading garbage.
      '2001:db8::1 ',
      ' 2001:db8::1',
      '2001:db8::1/64',
      '2001:db8::1%eth0',
      '[2001:db8::1]',
      '2001:db8::1]',
      'fe80::1%25en0',
      '2001:db8::g',
      'not-an-address',
      '',
    ];
    for (final String raw in cases) {
      test('rejects "$raw"', () {
        expect(parser.tryParse(raw), isNull);
      });
    }
  });

  test('oversized input is rejected before any parsing', () {
    final String oversized = '2001:db8::${'1' * 80}';
    expect(parser.tryParse(oversized), isNull);
  });

  test('hostnames are never selectable locators', () {
    expect(parser.tryParse('filehop.local'), isNull);
    expect(parser.tryParse('localhost'), isNull);
  });

  test('invalid strings are never normalized into valid form', () {
    // The parser either returns the exact input or rejects; there is no
    // repair path for these malformed inputs.
    expect(parser.tryParse('2001:db8:::1'), isNull);
    expect(parser.tryParse('001.2.3.4.'), isNull);
  });
}
