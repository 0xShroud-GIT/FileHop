import XCTest

@testable import Runner

/// Mission 07 native TXT bound contract for the iOS LAN browse path.
/// These tests validate `FileHopLanTxtValidator`, which the iOS adapter
/// applies BEFORE emitting any LAN candidate, so hostile metadata cannot
/// bypass the shared Dart parser via the native path.
/// Frozen bounds: max 8 keys, 32-byte keys, 128-byte values,
/// 512-byte total payload, v=1, i=<32 lowercase hex>.
final class FileHopLanTxtBoundsTests: XCTestCase {
  private let validId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  private func entries(
    _ pairs: [(String, String?)]
  ) -> [(key: String, value: [UInt8]?)] {
    pairs.map { (key: $0.0, value: $0.1.map { Array($0.utf8) }) }
  }

  func testValidV1MetadataAccepted() {
    let result = FileHopLanTxtValidator.validate(
      entries: entries([("v", "1"), ("i", validId)])
    )
    XCTAssertEqual(result, validId)
  }

  func testUnknownBoundedFieldAccepted() {
    let result = FileHopLanTxtValidator.validate(
      entries: entries([("v", "1"), ("i", validId), ("futureField", "ok")])
    )
    XCTAssertEqual(result, validId)
  }

  func testTooManyKeysRejected() {
    var pairs: [(String, String?)] = [("v", "1"), ("i", validId)]
    for index in 0..<7 {
      pairs.append(("k\(index)", "x"))
    }
    XCTAssertEqual(pairs.count, 9)
    XCTAssertNil(FileHopLanTxtValidator.validate(entries: entries(pairs)))
  }

  func testOversizedKeyRejected() {
    let bigKey = String(repeating: "k", count: 33)
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", "1"), ("i", validId), (bigKey, "x")])
      )
    )
  }

  func testEmptyKeyRejected() {
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", "1"), ("i", validId), ("", "x")])
      )
    )
  }

  func testOversizedValueRejected() {
    let bigValue = String(repeating: "x", count: 129)
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", "1"), ("i", validId), ("d", bigValue)])
      )
    )
  }

  func testOversizedTotalPayloadRejected() {
    // 5 keys x ~103 bytes each stays inside per-entry bounds but
    // exceeds the 512-byte total payload bound.
    var pairs: [(String, String?)] = [("v", "1"), ("i", validId)]
    for index in 0..<5 {
      pairs.append(("d\(index)", String(repeating: "x", count: 100)))
    }
    XCTAssertNil(FileHopLanTxtValidator.validate(entries: entries(pairs)))
  }

  func testMissingVersionRejected() {
    XCTAssertNil(
      FileHopLanTxtValidator.validate(entries: entries([("i", validId)]))
    )
  }

  func testUnsupportedVersionRejected() {
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", "2"), ("i", validId)])
      )
    )
  }

  func testMissingInstanceRejected() {
    XCTAssertNil(
      FileHopLanTxtValidator.validate(entries: entries([("v", "1")]))
    )
  }

  func testMalformedInstanceRejected() {
    let malformed = [
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "gggggggggggggggggggggggggggggggg",
      " aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "",
    ]
    for raw in malformed {
      XCTAssertNil(
        FileHopLanTxtValidator.validate(
          entries: entries([("v", "1"), ("i", raw)])
        ),
        "expected rejection for instance id: \(raw)"
      )
    }
  }

  func testDuplicateRequiredFieldsRejected() {
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", "1"), ("v", "1"), ("i", validId)])
      )
    )
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", "1"), ("i", validId), ("i", validId)])
      )
    )
  }

  func testNilAndEmptyValuesStayBoundedButFailRequiredFields() {
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", nil), ("i", validId)])
      )
    )
    XCTAssertNil(
      FileHopLanTxtValidator.validate(
        entries: entries([("v", ""), ("i", validId)])
      )
    )
  }
}
