import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/protected_key_reference.dart';
import 'package:filehop/identity/reference_allocation.dart';
import 'package:flutter_test/flutter_test.dart';

const String kRefA = 'fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String kRefB = 'fhik1.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String kRefC = 'fhik1.cccccccccccccccccccccccccccccccc';

void main() {
  test('first-candidate collision selects the next unused reference', () {
    final List<String> produced = <String>[kRefA, kRefB];
    final Set<String> occupied = <String>{kRefA};
    final List<String> deleted = <String>[];

    final String allocated = IdentityReferenceAllocator.allocate(
      nextCandidate: () => produced.isEmpty ? null : produced.removeAt(0),
      occupancy: (String reference) {
        if (deleted.contains(reference)) {
          fail('allocator deleted occupied $reference');
        }
        return occupied.contains(reference)
            ? SecretReferenceOccupancy.occupied
            : SecretReferenceOccupancy.unused;
      },
    );

    expect(allocated, kRefB);
    expect(occupied.contains(kRefA), isTrue);
    expect(deleted, isEmpty);
  });

  test('alias-only and file-only occupancy are skipped', () {
    final List<String> produced = <String>[kRefA, kRefB, kRefC];
    final String allocated = IdentityReferenceAllocator.allocate(
      nextCandidate: () => produced.isEmpty ? null : produced.removeAt(0),
      occupancy: (String reference) {
        if (reference == kRefA || reference == kRefB) {
          return SecretReferenceOccupancy.occupied;
        }
        return SecretReferenceOccupancy.unused;
      },
    );
    expect(allocated, kRefC);
  });

  test('inspect-failed candidates are not treated as unused', () {
    final List<String> produced = <String>[kRefA, kRefB];
    final String allocated = IdentityReferenceAllocator.allocate(
      nextCandidate: () => produced.isEmpty ? null : produced.removeAt(0),
      occupancy: (String reference) {
        if (reference == kRefA) {
          return SecretReferenceOccupancy.inspectFailed;
        }
        return SecretReferenceOccupancy.unused;
      },
    );
    expect(allocated, kRefB);
  });

  test('exhaustion is a typed failure and leaves occupied set unchanged', () {
    final Set<String> occupied = <String>{kRefA, kRefB};
    expect(
      () => IdentityReferenceAllocator.allocate(
        nextCandidate: () => kRefA,
        occupancy: (_) => SecretReferenceOccupancy.occupied,
      ),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityAllocationExhausted,
        ),
      ),
    );
    expect(occupied, <String>{kRefA, kRefB});
    expect(IdentityReferenceAllocator.maxAttempts, 8);
  });

  test('malformed candidates fail closed before occupancy is used', () {
    expect(
      () => IdentityReferenceAllocator.allocate(
        nextCandidate: () => 'fhik1/../etc/passwd0000000000000000',
        occupancy: (_) => fail('occupancy must not run'),
      ),
      throwsA(isA<IdentityException>()),
    );
    expect(
      () =>
          ProtectedKeyReference.parse('fhik1.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
      throwsA(isA<IdentityException>()),
    );
    expect(
      () =>
          ProtectedKeyReference.parse('fhik2.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      throwsA(isA<IdentityException>()),
    );
    expect(
      () => ProtectedKeyReference.parse(''),
      throwsA(isA<IdentityException>()),
    );
  });

  test('Android occupancy treats any present resource as occupied', () {
    expect(
      AndroidSecretOccupancy.of(aliasExists: true, fileExists: true),
      SecretReferenceOccupancy.occupied,
    );
    expect(
      AndroidSecretOccupancy.of(aliasExists: true, fileExists: false),
      SecretReferenceOccupancy.occupied,
    );
    expect(
      AndroidSecretOccupancy.of(aliasExists: false, fileExists: true),
      SecretReferenceOccupancy.occupied,
    );
    expect(
      AndroidSecretOccupancy.of(aliasExists: false, fileExists: false),
      SecretReferenceOccupancy.unused,
    );
    expect(
      AndroidSecretOccupancy.of(aliasExists: null, fileExists: false),
      SecretReferenceOccupancy.inspectFailed,
    );
    expect(
      AndroidSecretOccupancy.of(aliasExists: false, fileExists: null),
      SecretReferenceOccupancy.inspectFailed,
    );
  });

  test('authoritative delete succeeds only when both resources are gone', () {
    expect(
      AuthoritativeSecretDelete.conclude(
        inspectOk: true,
        fileRemains: false,
        aliasRemains: false,
      ),
      AuthoritativeDeleteOutcome.success,
    );
    expect(
      AuthoritativeSecretDelete.conclude(
        inspectOk: true,
        fileRemains: true,
        aliasRemains: false,
      ),
      AuthoritativeDeleteOutcome.failedPartial,
    );
    expect(
      AuthoritativeSecretDelete.conclude(
        inspectOk: true,
        fileRemains: false,
        aliasRemains: true,
      ),
      AuthoritativeDeleteOutcome.failedPartial,
    );
    expect(
      AuthoritativeSecretDelete.conclude(
        inspectOk: false,
        fileRemains: false,
        aliasRemains: false,
      ),
      AuthoritativeDeleteOutcome.failedInspect,
    );
  });

  test('creation rollback lists only resources created by this attempt', () {
    final CreationRollbackScope scope = CreationRollbackScope();
    expect(scope.resourcesToRollBack(), isEmpty);
    scope.createdAlias = true;
    expect(scope.resourcesToRollBack(), <String>{'alias'});
    scope.createdFile = true;
    expect(scope.resourcesToRollBack(), <String>{'alias', 'file'});
  });
}
