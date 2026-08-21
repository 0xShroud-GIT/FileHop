import Flutter
import Foundation
import Security

/// Test-only candidate source. Production uses [FileHopSecureReferenceCandidateSource].
protocol FileHopReferenceCandidateSource: AnyObject {
  func nextCandidate() -> String?
}

/// Official Apple `SecRandomCopyBytes` allocator. 128 bits of entropy, `fhik1.` prefix.
final class FileHopSecureReferenceCandidateSource: FileHopReferenceCandidateSource {
  func nextCandidate() -> String? {
    FileHopIdentitySecretStore.newReference()
  }
}

/// Deterministic sequence for native tests. Never a production default.
final class FileHopSequenceReferenceCandidateSource: FileHopReferenceCandidateSource {
  private var remaining: [String]

  init(_ candidates: [String]) {
    remaining = candidates
  }

  func nextCandidate() -> String? {
    guard !remaining.isEmpty else {
      return nil
    }
    return remaining.removeFirst()
  }
}

/// iOS at-rest identity secret store.
///
/// FileHop static private bytes are stored as a generic-password Keychain item.
/// Accessibility is AfterFirstUnlockThisDeviceOnly so later reconnect can use
/// the identity after first unlock without iCloud Keychain sync.
/// SQLite, UserDefaults, and ordinary app files never receive the private key.
///
/// Collision handling never deletes a pre-existing item. A duplicate account
/// generates a new candidate. Exhaustion is a typed failure.
///
/// Official APIs:
/// - https://developer.apple.com/documentation/security/keychain-services
/// - https://developer.apple.com/documentation/security/secrandomcopybytes
/// - https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly
/// - https://developer.apple.com/documentation/security/ksecattrsynchronizable
enum FileHopIdentitySecretStore {
  static let service = "app.filehop.identity.secret"
  static let privateKeyLength = 32
  static let referencePrefix = "fhik1."
  static let maxAllocationAttempts = 8

  /// Production default is secure randomness. Tests may replace this seam.
  static var candidateSource: FileHopReferenceCandidateSource =
    FileHopSecureReferenceCandidateSource()

  struct Failure {
    let code: String
    let message: String
  }

  /// Cryptographically strong opaque reference: `fhik1.` + 32 lowercase hex.
  static func newReference() -> String? {
    var bytes = [UInt8](repeating: 0, count: 16)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      return nil
    }
    return referencePrefix + bytes.map { String(format: "%02x", $0) }.joined()
  }

  static func store(privateKey: Data) -> Any {
    guard privateKey.count == privateKeyLength else {
      return Failure(code: "invalidArgument", message: "privateKeyBytes must be exactly 32 bytes")
    }
    for _ in 1...maxAllocationAttempts {
      guard let reference = candidateSource.nextCandidate() else {
        return Failure(
          code: "invalidState",
          message: "identity secret reference allocator produced no candidate"
        )
      }
      guard isValidReference(reference) else {
        return Failure(
          code: "invalidArgument",
          message: "identity secret reference is not a supported FileHop reference"
        )
      }
      var query = baseQuery(account: reference)
      query[kSecValueData as String] = privateKey
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      query[kSecAttrSynchronizable as String] = kCFBooleanFalse
      let status = SecItemAdd(query as CFDictionary, nil)
      if status == errSecSuccess {
        return reference
      }
      if status == errSecDuplicateItem {
        // Occupied candidate. Do not delete or mutate the existing item.
        continue
      }
      return Failure(code: "nativeFailure", message: "failed to protect identity secret")
    }
    return Failure(
      code: "invalidState",
      message: "identity secret reference allocation exhausted"
    )
  }

  static func load(reference: String) -> Any {
    guard isValidReference(reference) else {
      return Failure(
        code: "invalidArgument",
        message: "identity secret reference is not a supported FileHop reference"
      )
    }
    var query = baseQuery(account: reference)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return Failure(code: "notFound", message: "protected secret is missing")
    }
    if status != errSecSuccess {
      return Failure(code: "nativeFailure", message: "failed to load identity secret")
    }
    guard let data = result as? Data, data.count == privateKeyLength else {
      return Failure(code: "corrupt", message: "protected secret is unreadable")
    }
    return FlutterStandardTypedData(bytes: data)
  }

  static func delete(reference: String) -> Any {
    guard isValidReference(reference) else {
      return Failure(
        code: "invalidArgument",
        message: "identity secret reference is not a supported FileHop reference"
      )
    }
    let status = SecItemDelete(baseQuery(account: reference) as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      return true
    }
    return Failure(code: "nativeFailure", message: "failed to delete identity secret")
  }

  static func status(reference: String) -> Any {
    guard isValidReference(reference) else {
      return Failure(
        code: "invalidArgument",
        message: "identity secret reference is not a supported FileHop reference"
      )
    }
    var query = baseQuery(account: reference)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return "absent"
    }
    if status != errSecSuccess {
      return Failure(code: "unavailable", message: "failed to inspect identity secret")
    }
    guard let data = result as? Data, data.count == privateKeyLength else {
      return "corrupt"
    }
    return "present"
  }

  static func hasAny() -> Any {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnAttributes as String: kCFBooleanTrue as Any,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess {
      return true
    }
    if status == errSecItemNotFound {
      return false
    }
    return Failure(code: "unavailable", message: "failed to inspect identity secrets")
  }

  static func deleteAll() -> Any {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      return true
    }
    return Failure(code: "nativeFailure", message: "failed to delete identity secrets")
  }

  static func isValidReference(_ raw: String) -> Bool {
    guard raw.count == referencePrefix.count + 32, raw.hasPrefix(referencePrefix) else {
      return false
    }
    if raw.contains("/") || raw.contains("\\") || raw.contains("\0") || raw.contains("..") {
      return false
    }
    let hex = raw.dropFirst(referencePrefix.count)
    return hex.allSatisfy { character in
      ("0"..."9").contains(character) || ("a"..."f").contains(character)
    }
  }

  private static func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }
}
