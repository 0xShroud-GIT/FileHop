import XCTest

/// Mission 07 final native-lifecycle fix — iOS passive-discovery contract.
///
/// Evidence class B/C: committed and wired into the RunnerTests target, but
/// NOT_EXECUTED inside Arena (no Xcode/macOS). These are deterministic
/// source-contract tests; real Bonjour browse runtime remains on the
/// physical-device C checklist and is never claimed here.
final class FileHopLanPassiveDiscoveryTests: XCTestCase {

  /// Deterministic repo-relative lookup: RunnerTests/ -> Runner/.
  private func lanSource() -> String {
    let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let runnerDir = testsDir.deletingLastPathComponent().appendingPathComponent("Runner")
    let url = runnerDir.appendingPathComponent("FileHopLanDiscovery.swift")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }

  /// Discovery is browse-only: browse-result processing never constructs or
  /// starts a remote transport connection.
  func testDiscoverySourceNeverConstructsAConnection() throws {
    let source = lanSource()
    XCTAssertFalse(source.isEmpty, "adapter source must be locatable")
    XCTAssertFalse(source.contains("NWConnection("), "discovery must not construct connections")
    XCTAssertFalse(source.contains("connection.start("), "discovery must not start connections")
    XCTAssertTrue(source.contains("browser.start(queue:"), "browse itself must still start")
  }

  /// Browse requests TXT records via the TXT-aware descriptor (D-07-09);
  /// the plain descriptor form is not the production browse descriptor.
  func testBrowseDescriptorRequestsTxtRecords() throws {
    let source = lanSource()
    XCTAssertTrue(source.contains("NWBrowser.Descriptor.bonjourWithTXTRecord("))
    XCTAssertFalse(source.contains("NWBrowser.Descriptor.bonjour("))
  }

  /// The native service endpoints are retained internally, keyed by the
  /// FileHop instance ID (one-to-many, D-07-10), for the later Mission 10
  /// connect stage.
  func testNativeServiceEndpointsAreRetainedForLaterConnectStage() throws {
    let source = lanSource()
    XCTAssertTrue(source.contains("instanceToPaths: [String: Set<NWEndpoint>]"))
    XCTAssertTrue(source.contains("addOwner(path: key, of: instanceId)"))
    XCTAssertTrue(source.contains("removeOwner(path: key, of: id)"))
    XCTAssertTrue(source.contains("nativeServiceLocatorHint"))
  }

  /// Partial native-path loss never terminally loses the shared candidate.
  func testFinalOwnerRemovalIsTheOnlyLostEmission() throws {
    let source = lanSource()
    XCTAssertTrue(source.contains("if removeOwner(path: key, of: id) {"))
    XCTAssertTrue(source.contains("instanceToPaths.removeValue(forKey: instanceId)"))
  }

  /// The emitted candidate locator carries no fabricated socket address.
  func testCandidateLocatorMakesNoSocketAddressClaim() throws {
    let source = lanSource()
    XCTAssertTrue(source.contains("\"nativeService\""))
    XCTAssertFalse(source.contains("port="), "no fabricated port claim")
    XCTAssertFalse(source.contains("addrs="), "no fabricated address claim")
  }

  /// TXT bounds are enforced before any candidate emission.
  func testTxtBoundsAreValidatedBeforeCandidateEmission() throws {
    let source = lanSource()
    XCTAssertTrue(
      source.contains("guard let instanceId = validateTxt(txt) else { return }")
    )
    XCTAssertTrue(source.contains("emitCandidate("))
  }
}
