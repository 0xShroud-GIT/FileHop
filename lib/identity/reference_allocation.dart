import 'errors.dart';
import 'protected_key_reference.dart';

/// Occupancy of a FileHop-owned identity-secret reference.
enum SecretReferenceOccupancy { unused, occupied, inspectFailed }

/// Shared allocation policy mirrored by Android and iOS native adapters.
///
/// generate candidate → prove unused → create
/// occupied / inspect-failed → next candidate
/// never delete, adopt, or mutate an existing secret on collision
abstract final class IdentityReferenceAllocator {
  static const int maxAttempts = 8;

  static String allocate({
    required String? Function() nextCandidate,
    required SecretReferenceOccupancy Function(String reference) occupancy,
  }) {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final String? candidate = nextCandidate();
      if (candidate == null) {
        throw const IdentityException(
          kind: IdentityFailureKind.identityAllocationExhausted,
          message: 'identity secret reference allocator produced no candidate',
        );
      }
      ProtectedKeyReference.parse(candidate);
      switch (occupancy(candidate)) {
        case SecretReferenceOccupancy.unused:
          return candidate;
        case SecretReferenceOccupancy.occupied:
        case SecretReferenceOccupancy.inspectFailed:
          continue;
      }
    }
    throw const IdentityException(
      kind: IdentityFailureKind.identityAllocationExhausted,
      message: 'identity secret reference allocation exhausted',
    );
  }
}

/// Android dual-resource occupancy. Alias-only, file-only, and both are occupied.
abstract final class AndroidSecretOccupancy {
  static SecretReferenceOccupancy of({
    required bool? aliasExists,
    required bool? fileExists,
  }) {
    if (aliasExists == null || fileExists == null) {
      return SecretReferenceOccupancy.inspectFailed;
    }
    if (aliasExists || fileExists) {
      return SecretReferenceOccupancy.occupied;
    }
    return SecretReferenceOccupancy.unused;
  }
}

/// Authoritative delete outcome. Success requires confirmed absence.
enum AuthoritativeDeleteOutcome { success, failedPartial, failedInspect }

abstract final class AuthoritativeSecretDelete {
  static AuthoritativeDeleteOutcome conclude({
    required bool inspectOk,
    required bool fileRemains,
    required bool aliasRemains,
  }) {
    if (!inspectOk) {
      return AuthoritativeDeleteOutcome.failedInspect;
    }
    if (fileRemains || aliasRemains) {
      return AuthoritativeDeleteOutcome.failedPartial;
    }
    return AuthoritativeDeleteOutcome.success;
  }
}

/// Rollback may touch only resources created by the current attempt.
class CreationRollbackScope {
  CreationRollbackScope();

  bool createdAlias = false;
  bool createdFile = false;

  Set<String> resourcesToRollBack() {
    return <String>{if (createdAlias) 'alias', if (createdFile) 'file'};
  }
}
