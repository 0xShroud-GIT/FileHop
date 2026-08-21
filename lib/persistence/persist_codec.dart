import 'dart:convert';

import '../domain/ids/logical_id.dart';
import '../domain/identity/peer_fingerprint.dart';
import '../domain/state_machine/invalid_state_transition.dart';
import 'errors.dart';
import 'tokens.dart';

/// Deterministic row/input validation. Never leaks TypeError/FormatException.
abstract final class PersistCodec {
  static Never _fail(
    PersistenceFailureKind kind,
    String message, [
    Object? cause,
  ]) {
    throw PersistenceException(kind: kind, message: message, cause: cause);
  }

  static T _guard<T>(
    PersistenceFailureKind kind,
    String message,
    T Function() body,
  ) {
    try {
      return body();
    } on PersistenceException {
      rethrow;
    } on DomainFormatException catch (error) {
      _fail(kind, message, error);
    } on FormatException catch (error) {
      _fail(kind, message, error);
    } on TypeError catch (error) {
      _fail(kind, message, error);
    } on StateError catch (error) {
      _fail(kind, message, error);
    }
  }

  static String requireString(Map<String, Object?> row, String key) {
    return _guard(
      PersistenceFailureKind.decodeFailure,
      '$key must be a string',
      () {
        final Object? value = row[key];
        if (value is! String) {
          _fail(PersistenceFailureKind.decodeFailure, '$key must be a string');
        }
        return value;
      },
    );
  }

  static String? optionalString(Map<String, Object?> row, String key) {
    final Object? value = row[key];
    if (value == null) {
      return null;
    }
    return requireString(row, key);
  }

  static int requireInt(Map<String, Object?> row, String key) {
    return _guard(
      PersistenceFailureKind.decodeFailure,
      '$key must be an int',
      () {
        final Object? value = row[key];
        if (value is! int) {
          _fail(PersistenceFailureKind.decodeFailure, '$key must be an int');
        }
        return value;
      },
    );
  }

  static int? optionalInt(Map<String, Object?> row, String key) {
    final Object? value = row[key];
    if (value == null) {
      return null;
    }
    return requireInt(row, key);
  }

  static List<int> requireBytes(Map<String, Object?> row, String key) {
    return _guard(
      PersistenceFailureKind.decodeFailure,
      '$key must be bytes',
      () {
        final Object? value = row[key];
        if (value is! List<int>) {
          _fail(PersistenceFailureKind.decodeFailure, '$key must be bytes');
        }
        return List<int>.from(value);
      },
    );
  }

  static String decodeToken(Object? raw, Set<String> allowed, String label) {
    if (raw is! String) {
      _fail(PersistenceFailureKind.decodeFailure, '$label must be a string');
    }
    return PersistTokens.requireToken(
      raw,
      allowed,
      label,
      kind: PersistenceFailureKind.decodeFailure,
    );
  }

  static String writeToken(String raw, Set<String> allowed, String label) {
    return PersistTokens.requireToken(
      raw,
      allowed,
      label,
      kind: PersistenceFailureKind.constraintViolation,
    );
  }

  static String decodeLogicalId(Object? raw, String label) {
    return _guard(
      PersistenceFailureKind.decodeFailure,
      'corrupt $label',
      () => LogicalId.parse(raw is String ? raw : '').value,
    );
  }

  static String writeLogicalId(String raw, String label) {
    return _guard(
      PersistenceFailureKind.constraintViolation,
      'invalid $label',
      () => LogicalId.parse(raw).value,
    );
  }

  static String decodeFingerprint(Object? raw, String label) {
    return _guard(
      PersistenceFailureKind.decodeFailure,
      'corrupt $label',
      () => PeerFingerprint.parse(raw is String ? raw : '').value,
    );
  }

  static String writeFingerprint(String raw, String label) {
    return _guard(
      PersistenceFailureKind.constraintViolation,
      'invalid $label',
      () => PeerFingerprint.parse(raw).value,
    );
  }

  static String? optionalFingerprint(Object? raw, String label) {
    if (raw == null) {
      return null;
    }
    return decodeFingerprint(raw, label);
  }

  static String? optionalLogicalId(Object? raw, String label) {
    if (raw == null) {
      return null;
    }
    return decodeLogicalId(raw, label);
  }

  static List<String> decodeCapabilitiesJson(Object? raw) {
    return _guard(
      PersistenceFailureKind.decodeFailure,
      'corrupt capabilities',
      () {
        if (raw is! String) {
          _fail(
            PersistenceFailureKind.decodeFailure,
            'capabilities must be a JSON string',
          );
        }
        final Object? decoded = jsonDecode(raw);
        if (decoded is! List) {
          _fail(
            PersistenceFailureKind.decodeFailure,
            'capabilities JSON must be an array',
          );
        }
        final List<String> out = <String>[];
        for (final Object? item in decoded) {
          if (item is! String) {
            _fail(
              PersistenceFailureKind.decodeFailure,
              'capability entries must be strings',
            );
          }
          out.add(item);
        }
        return List<String>.unmodifiable(out);
      },
    );
  }

  static String encodeCapabilities(List<String> capabilities) {
    return jsonEncode(capabilities);
  }
}
