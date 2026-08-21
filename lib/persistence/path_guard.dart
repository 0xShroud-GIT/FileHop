import 'errors.dart';

/// Minimal Mission 04 path gate. Full folder hardening is Mission 17.
abstract final class PersistedPathGuard {
  static String? sanitizeRelative(
    String? raw, {
    PersistenceFailureKind kind = PersistenceFailureKind.invalidArgument,
  }) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('/') ||
        raw.contains('\\') ||
        raw.contains('\u0000') ||
        raw.contains(':')) {
      throw PersistenceException(
        kind: kind,
        message: 'persisted path metadata must be a sanitized relative path',
      );
    }
    final List<String> parts = raw.split('/');
    for (final String part in parts) {
      if (part.isEmpty || part == '.' || part == '..') {
        throw PersistenceException(
          kind: kind,
          message: 'persisted path metadata must not contain traversal',
        );
      }
    }
    return raw;
  }
}
