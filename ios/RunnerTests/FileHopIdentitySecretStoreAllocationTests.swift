import XCTest
@testable import Runner

/// Source-level iOS allocation contract. Real Keychain execution is C.
/// Arena cannot run these tests. They exist so a device/Xcode run can prove
/// collision-safe allocation without deleting a pre-existing item.
final class FileHopIdentitySecretStoreAllocationTests: XCTestCase {
  override func tearDown() {
    FileHopIdentitySecretStore.candidateSource = FileHopSecureReferenceCandidateSource()
    super.tearDown()
  }

  func testNewReferenceUsesFileHopNamespace() {
    guard let reference = FileHopIdentitySecretStore.newReference() else {
      XCTFail("secure allocator returned nil")
      return
    }
    XCTAssertTrue(FileHopIdentitySecretStore.isValidReference(reference))
    XCTAssertTrue(reference.hasPrefix(FileHopIdentitySecretStore.referencePrefix))
  }

  func testCollisionRetriesWithoutDeletingExistingItem() {
    let existing = "fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    let fresh = "fhik1.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    let existingBytes = Data(repeating: 0x31, count: 32)
    let newBytes = Data(repeating: 0x32, count: 32)

    FileHopIdentitySecretStore.candidateSource =
      FileHopSequenceReferenceCandidateSource([existing])
    let first = FileHopIdentitySecretStore.store(privateKey: existingBytes)
    XCTAssertEqual(first as? String, existing)

    FileHopIdentitySecretStore.candidateSource =
      FileHopSequenceReferenceCandidateSource([existing, fresh])
    let second = FileHopIdentitySecretStore.store(privateKey: newBytes)
    XCTAssertEqual(second as? String, fresh)

    let loadedExisting = FileHopIdentitySecretStore.load(reference: existing)
    XCTAssertFalse(loadedExisting is FileHopIdentitySecretStore.Failure)

    _ = FileHopIdentitySecretStore.delete(reference: existing)
    _ = FileHopIdentitySecretStore.delete(reference: fresh)
  }

  func testExhaustionLeavesExistingItem() {
    let existing = "fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    FileHopIdentitySecretStore.candidateSource =
      FileHopSequenceReferenceCandidateSource([existing])
    _ = FileHopIdentitySecretStore.store(privateKey: Data(repeating: 0x31, count: 32))

    FileHopIdentitySecretStore.candidateSource =
      FileHopSequenceReferenceCandidateSource(Array(
        repeating: existing,
        count: FileHopIdentitySecretStore.maxAllocationAttempts
      ))
    let outcome = FileHopIdentitySecretStore.store(privateKey: Data(repeating: 0x33, count: 32))
    let failure = outcome as? FileHopIdentitySecretStore.Failure
    XCTAssertEqual(failure?.code, "invalidState")

    let loaded = FileHopIdentitySecretStore.load(reference: existing)
    XCTAssertFalse(loaded is FileHopIdentitySecretStore.Failure)
    _ = FileHopIdentitySecretStore.delete(reference: existing)
  }
}
