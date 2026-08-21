import Flutter
import Foundation
import Network

/// Pure FileHop TXT validator for LAN discovery metadata.
/// Enforces the frozen Mission 07 bounds natively so hostile advertisements
/// can never bypass the shared Dart parser via native candidate emission.
/// Bounds (frozen): max 8 keys, 32-byte keys, 128-byte values,
/// 512-byte total FileHop TXT payload, `v=1`, `i=<32 lowercase hex>`.
enum FileHopLanTxtValidator {
  static let schemaVersion = 1
  static let maxTxtKeys = 8
  static let maxTxtKeyBytes = 32
  static let maxTxtValueBytes = 128
  static let maxTxtPayloadBytes = 512
  static let instanceHexLength = 32

  /// Validates bounded FileHop TXT entries and returns the canonical
  /// FileHop instance ID, or nil when the record must be rejected.
  /// Unknown bounded non-critical keys are ignored (forward compatible).
  static func validate(entries: [(key: String, value: [UInt8]?)]) -> String? {
    if entries.count > maxTxtKeys {
      return nil
    }
    var total = 0
    var version: String?
    var instance: String?
    var seenVersion = false
    var seenInstance = false
    for entry in entries {
      let keyBytes = Array(entry.key.utf8)
      if keyBytes.isEmpty || keyBytes.count > maxTxtKeyBytes {
        return nil
      }
      let valueBytes = entry.value ?? []
      if valueBytes.count > maxTxtValueBytes {
        return nil
      }
      total += keyBytes.count + valueBytes.count
      if total > maxTxtPayloadBytes {
        return nil
      }
      switch entry.key {
      case "v":
        if seenVersion {
          // Duplicate required field fails closed.
          return nil
        }
        seenVersion = true
        version = String(bytes: valueBytes, encoding: .utf8)
      case "i":
        if seenInstance {
          return nil
        }
        seenInstance = true
        instance = String(bytes: valueBytes, encoding: .utf8)
      default:
        // Unknown bounded non-critical key: ignored.
        break
      }
    }
    guard version == String(schemaVersion) else {
      // Missing or unsupported schema version fails closed.
      return nil
    }
    guard let candidate = instance, isCanonicalInstanceId(candidate) else {
      return nil
    }
    return candidate
  }

  /// Canonical form only: exactly 32 lowercase hex characters.
  static func isCanonicalInstanceId(_ raw: String) -> Bool {
    guard raw.count == instanceHexLength else { return false }
    for scalar in raw.unicodeScalars {
      let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
      let isLowerHex = scalar.value >= 0x61 && scalar.value <= 0x66
      if !isDigit && !isLowerHex {
        return false
      }
    }
    return true
  }
}

/// Thin iOS LAN browse adapter. Mission 07 discovery only.
///
/// Passive discovery contract (final fixes):
/// - `NWBrowser` is browse-only and requests TXT records via the
///   TXT-aware descriptor `bonjourWithTXTRecord` (D-07-09): FileHop
///   requires `v=1` / `i=<instance id>` metadata before any candidate can
///   exist, and TXT absence fails closed. Browse-result processing never
///   establishes a remote transport connection; real connection work
///   belongs to the Mission 10 connect stage.
/// - Host/port are intentionally not resolved here, so no socket address
///   is ever fabricated for a candidate.
/// - One-to-many native path ownership (D-07-10): one FileHop instance ID
///   may be visible through multiple simultaneous native paths/interfaces.
///   `instanceToPaths` maps an instance ID to the SET of owning native
///   endpoints; `candidateLost` is emitted only when the FINAL owner
///   disappears. Duplicate callbacks are idempotent; the per-instance
///   native path bound is `maxNativePathsPerInstance`.
/// - The native endpoint mapping is runtime-only: never peer identity,
///   never persisted, never exposed to Dart.
/// - Advertisement waits for Mission 10 listener ownership.
///
/// Tracking identity: entries are keyed by the native `NWEndpoint` of the
/// browse result (service name + type + domain + interface), never by the
/// human-visible Bonjour display name alone. Two simultaneously discovered
/// services that share a display name remain distinct. After valid TXT
/// metadata the authoritative shared candidate identity is the FileHop
/// ephemeral instance ID.
final class FileHopLanDiscovery {
  static let serviceType = "_filehop._tcp"
  static let maxActive = 128

  /// D-07-10 bound: maximum simultaneous native paths per LAN instance.
  static let maxNativePathsPerInstance = 8

  /// Truthful locator hint for candidates whose endpoint is service-
  /// resolvable but not yet socket-resolved. Carries no host/port claim.
  static let nativeServiceLocatorHint = "nativeService"

  private let emit: ([String: Any]) -> Void
  private let queue = DispatchQueue(label: "app.filehop.lan.browse")
  private var browser: NWBrowser?
  private var browserGeneration = 0
  private var browsing = false
  private var generation = 0

  /// Keyed by native browse-result endpoint, never by display name.
  private var tracked: [NWEndpoint: Tracked] = [:]

  /// FileHop instance ID -> SET of owning native service endpoints for the
  /// later Mission 10 connect stage (one-to-many, D-07-10). Runtime-only
  /// correlation, never identity.
  private var instanceToPaths: [String: Set<NWEndpoint>] = [:]

  /// Ownership outcome of a native path registration (mirrors the shared
  /// Dart `LanPathOutcome` reference model).
  private enum PathOutcome {
    case firstOwner
    case additionalOwner
    case duplicatePath
    case pathLimitReached
  }

  private struct Tracked {
    var instanceId: String?
    var serviceName: String
    var generation: Int
  }

  init(emit: @escaping ([String: Any]) -> Void) {
    self.emit = emit
  }

  func availability() -> [String: Any] {
    [
      "bridgeVersion": FileHopNativePlugin.bridgeVersion,
      "kind": "lan",
      "status": "SUPPORTED_AVAILABLE",
      "detail": "FileHop LAN Bonjour browse (Mission 07); advertisement waits for Mission 10 listener",
    ]
  }

  func startBrowse() -> String? {
    if browsing {
      return nil
    }
    generation += 1
    let gen = generation
    browsing = true
    // D-07-09: TXT-record-aware descriptor. FileHop candidates require the
    // v=1 / i=<instance> TXT metadata, so browsing without TXT would
    // silently discover nothing valid.
    let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
      type: Self.serviceType,
      domain: nil
    )
    let params = NWParameters()
    params.includePeerToPeer = false
    let browser = NWBrowser(for: descriptor, using: params)
    self.browser = browser
    self.browserGeneration = gen
    browser.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .failed(let error):
        // Bounded mapping: NWError stays diagnostic text, never thrown.
        self.emitError(
          code: "discoveryStartFailed",
          message: "NWBrowser failed: \(String(describing: error))",
          gen: gen
        )
        self.browsing = false
        self.queue.async {
          self.cleanupBrowseGeneration(gen, emitLostForResolved: false)
        }
      case .ready, .setup, .cancelled, .waiting:
        break
      @unknown default:
        break
      }
    }
    browser.browseResultsChangedHandler = { [weak self] _, changes in
      guard let self else { return }
      self.queue.async {
        self.handle(changes: changes, gen: gen)
      }
    }
    browser.start(queue: queue)
    return nil
  }

  func stopBrowse() {
    let gen = generation
    browsing = false
    queue.sync {
      cleanupBrowseGeneration(gen, emitLostForResolved: true)
    }
  }

  func detach() {
    stopBrowse()
  }

  /// Central idempotent cleanup for browse generation `gen`.
  /// Cancels the browser and tracking owned by `gen` or older.
  /// Never touches resources owned by a newer generation.
  private func cleanupBrowseGeneration(_ gen: Int, emitLostForResolved: Bool) {
    if let active = browser, browserGeneration <= gen {
      active.cancel()
      browser = nil
    }
    for (endpoint, item) in tracked where item.generation <= gen {
      tracked.removeValue(forKey: endpoint)
      if let id = item.instanceId,
        removeOwner(path: endpoint, of: id),
        emitLostForResolved
      {
        emitLost(id)
      }
    }
  }

  private func handle(changes: Set<NWBrowser.Result.Change>, gen: Int) {
    guard live(gen) else { return }
    for change in changes {
      switch change {
      case .added(let result):
        handleAdded(result, gen: gen)
      case .removed(let result):
        handleRemoved(result, gen: gen)
      case .changed(let old, let new, _):
        if old.endpoint != new.endpoint {
          handleRemoved(old, gen: gen)
        }
        handleAdded(new, gen: gen)
      case .identical:
        break
      @unknown default:
        break
      }
    }
  }

  private func handleAdded(_ result: NWBrowser.Result, gen: Int) {
    guard live(gen) else { return }
    guard case .service(let name, let type, _, _) = result.endpoint else { return }
    guard normalizeType(type) == Self.serviceType else { return }
    let key = result.endpoint
    if tracked.count >= Self.maxActive, tracked[key] == nil {
      emitError(code: "candidateLimitExceeded", message: "active LAN candidate limit exceeded", gen: gen)
      return
    }
    if tracked[key] == nil {
      tracked[key] = Tracked(instanceId: nil, serviceName: name, generation: gen)
    }
    publish(result, key: key, gen: gen)
  }

  private func handleRemoved(_ result: NWBrowser.Result, gen: Int) {
    guard live(gen) else { return }
    guard case .service = result.endpoint else { return }
    let key = result.endpoint
    guard let item = tracked.removeValue(forKey: key), let id = item.instanceId else { return }
    // D-07-10: remove only this endpoint's ownership. candidateLost is
    // emitted solely when the FINAL owner disappears; a partial path loss
    // keeps the shared candidate alive. Unknown endpoints are stale and
    // ignored (tracked lookup above already returned nil).
    if removeOwner(path: key, of: id) {
      emitLost(id)
    }
  }

  /// Passive candidate publication from the browse result alone.
  /// No transport connection is started here; host/port are intentionally
  /// not resolved, and no socket address is fabricated. The native service
  /// endpoint is retained internally for the Mission 10 connect stage.
  private func publish(_ result: NWBrowser.Result, key: NWEndpoint, gen: Int) {
    guard live(gen) else { return }
    guard var item = tracked[key], item.generation == gen else { return }
    guard case .bonjour(let txt) = result.metadata else { return }
    // Native FileHop TXT bound enforcement happens BEFORE any candidate
    // emission. Malformed or oversized metadata never reaches Dart.
    guard let instanceId = validateTxt(txt) else { return }
    let previousId = item.instanceId
    if let old = previousId, old != instanceId {
      // The same native path re-advertised a different ephemeral FileHop
      // instance ID: this path's ownership moves from old to new (D-07-10).
      if removeOwner(path: key, of: old) {
        emitLost(old)
      }
    }
    item.instanceId = instanceId
    tracked[key] = item
    switch addOwner(path: key, of: instanceId) {
    case .firstOwner:
      emitCandidate(
        eventKind: "candidateFound",
        candidateId: instanceId,
        displayLabel: item.serviceName,
        locatorHint: Self.nativeServiceLocatorHint
      )
    case .additionalOwner:
      // Idempotent metadata refresh: one shared candidate, no new identity.
      emitCandidate(
        eventKind: "candidateUpdated",
        candidateId: instanceId,
        displayLabel: item.serviceName,
        locatorHint: Self.nativeServiceLocatorHint
      )
    case .duplicatePath:
      // Duplicate native callback for an already-owned path: no emission.
      break
    case .pathLimitReached:
      // Deterministically drop the additional path; never evict an owner.
      emitError(
        code: "pathLimitExceeded",
        message: "native path limit per LAN instance exceeded",
        gen: gen
      )
    }
  }

  /// Registers `path` as an owner of `instanceId` (one-to-many, D-07-10).
  private func addOwner(path: NWEndpoint, of instanceId: String) -> PathOutcome {
    if let set = instanceToPaths[instanceId] {
      if set.contains(path) {
        return .duplicatePath
      }
      if set.count >= Self.maxNativePathsPerInstance {
        return .pathLimitReached
      }
    }
    var set = instanceToPaths[instanceId] ?? []
    let wasEmpty = set.isEmpty
    set.insert(path)
    instanceToPaths[instanceId] = set
    return wasEmpty ? .firstOwner : .additionalOwner
  }

  /// Removes `path` from `instanceId`. Returns true only when the FINAL
  /// owner was removed (the only case where candidateLost may emit).
  /// Unknown/stale paths return false and change nothing.
  @discardableResult
  private func removeOwner(path: NWEndpoint, of instanceId: String) -> Bool {
    guard var set = instanceToPaths[instanceId], set.contains(path) else { return false }
    set.remove(path)
    if set.isEmpty {
      instanceToPaths.removeValue(forKey: instanceId)
      return true
    }
    instanceToPaths[instanceId] = set
    return false
  }

  /// Applies the frozen FileHop TXT bounds to an `NWTXTRecord` and returns
  /// the canonical instance ID only when every bound holds.
  private func validateTxt(_ record: NWTXTRecord) -> String? {
    var entries: [(key: String, value: [UInt8]?)] = []
    for (key, entry) in record {
      // Stop collecting once the record is already over the key bound so a
      // hostile record cannot force unbounded native work.
      if entries.count > FileHopLanTxtValidator.maxTxtKeys {
        break
      }
      switch entry {
      case .none:
        entries.append((key: key, value: nil))
      case .empty:
        entries.append((key: key, value: []))
      case .string(let value):
        entries.append((key: key, value: Array(value.utf8)))
      case .data(let data):
        entries.append((key: key, value: [UInt8](data)))
      @unknown default:
        return nil
      }
    }
    return FileHopLanTxtValidator.validate(entries: entries)
  }

  private func normalizeType(_ raw: String) -> String {
    var type = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while type.hasSuffix(".") {
      type.removeLast()
    }
    if type.hasSuffix(".local") {
      type = String(type.dropLast(6))
    }
    while type.hasSuffix(".") {
      type.removeLast()
    }
    return type
  }

  private func live(_ gen: Int) -> Bool {
    browsing && generation == gen
  }

  private func emitCandidate(
    eventKind: String,
    candidateId: String,
    displayLabel: String,
    locatorHint: String
  ) {
    emit([
      "bridgeVersion": FileHopNativePlugin.bridgeVersion,
      "eventKind": eventKind,
      "transportKind": "lan",
      "candidate": [
        "bridgeVersion": FileHopNativePlugin.bridgeVersion,
        "candidateId": candidateId,
        "kind": "lan",
        "displayLabel": displayLabel,
        "locatorHint": locatorHint,
      ],
    ])
  }

  private func emitLost(_ candidateId: String) {
    emit([
      "bridgeVersion": FileHopNativePlugin.bridgeVersion,
      "eventKind": "candidateLost",
      "transportKind": "lan",
      "candidate": [
        "bridgeVersion": FileHopNativePlugin.bridgeVersion,
        "candidateId": candidateId,
        "kind": "lan",
      ],
    ])
  }

  /// Raw NWError values stay diagnostic detail, never a thrown error.
  private func emitError(code: String, message: String, gen: Int) {
    emit([
      "bridgeVersion": FileHopNativePlugin.bridgeVersion,
      "eventKind": "adapterError",
      "transportKind": "lan",
      "error": [
        "bridgeVersion": FileHopNativePlugin.bridgeVersion,
        "errorClass": "nativeFailure",
        "message": message,
        "nativeCode": code,
        "kind": "lan",
      ],
    ])
  }
}
