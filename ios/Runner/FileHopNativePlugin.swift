import Flutter
import UIKit

/// Native command/event boundary.
/// Mission 07 adds LAN Bonjour browse only. No Wi-Fi Aware, no Mission 10 sockets.
/// Native adapters never own PeerIdentity/trust policy.
final class FileHopNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  static let bridgeVersion = 1
  static let commands = "app.filehop.native.commands"
  static let events = "app.filehop.native.events"

  private var eventSink: FlutterEventSink?
  private lazy var lanDiscovery = FileHopLanDiscovery { [weak self] payload in
    self?.emitEvent(payload)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FileHopNativePlugin()
    let commandChannel = FlutterMethodChannel(
      name: Self.commands,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: commandChannel)
    let eventChannel = FlutterEventChannel(
      name: Self.events,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let map = call.arguments as? [String: Any] ?? [:]
    if let version = map["bridgeVersion"] as? Int, version != Self.bridgeVersion {
      result(
        FlutterError(
          code: "invalidArgument",
          message: "incompatible bridgeVersion \(version)",
          details: nil
        )
      )
      return
    }
    if call.arguments != nil && (call.arguments as? [String: Any]) == nil {
      result(
        FlutterError(
          code: "invalidArgument",
          message: "payload must be a map",
          details: nil
        )
      )
      return
    }

    switch call.method {
    case "ping":
      result(["bridgeVersion": Self.bridgeVersion, "ok": true])
    case "observeAvailability":
      let kind = map["kind"] as? String ?? "unknown"
      if kind == "lan" {
        result(lanDiscovery.availability())
      } else {
        result([
          "bridgeVersion": Self.bridgeVersion,
          "kind": kind,
          "status": "UNSUPPORTED",
          "detail": "Mission 02 skeleton: transport not implemented",
        ])
      }
    case "startDiscovery":
      let kind = map["kind"] as? String ?? "unknown"
      if kind != "lan" {
        result(
          FlutterError(
            code: "unsupported",
            message: "Mission 02 skeleton: \(call.method) is not implemented",
            details: nil
          )
        )
        return
      }
      if let error = lanDiscovery.startBrowse() {
        result(FlutterError(code: "nativeFailure", message: error, details: nil))
      } else {
        result(["bridgeVersion": Self.bridgeVersion, "ok": true])
      }
    case "stopDiscovery":
      let kind = map["kind"] as? String ?? "unknown"
      if kind != "lan" {
        result(
          FlutterError(
            code: "unsupported",
            message: "Mission 02 skeleton: \(call.method) is not implemented",
            details: nil
          )
        )
        return
      }
      lanDiscovery.stopBrowse()
      result(["bridgeVersion": Self.bridgeVersion, "ok": true])
    case "connect", "disconnect", "openEndpoint":
      result(
        FlutterError(
          code: "unsupported",
          message: "Mission 10 owns LAN connect/openEndpoint; \(call.method) is not implemented",
          details: nil
        )
      )
    case "identitySecret.store":
      handleIdentityStore(map: map, result: result)
    case "identitySecret.load":
      handleIdentityLoad(map: map, result: result)
    case "identitySecret.delete":
      handleIdentityDelete(map: map, result: result)
    case "identitySecret.status":
      handleIdentityStatus(map: map, result: result)
    case "identitySecret.hasAny":
      replyIdentity(FileHopIdentitySecretStore.hasAny(), result: result, anyKey: true)
    case "identitySecret.deleteAll":
      replyIdentity(FileHopIdentitySecretStore.deleteAll(), result: result, ok: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleIdentityStore(map: [String: Any], result: FlutterResult) {
    guard let data = privateKeyData(map["privateKeyBytes"]) else {
      result(
        FlutterError(
          code: "invalidArgument",
          message: "privateKeyBytes must be exactly 32 bytes",
          details: nil
        )
      )
      return
    }
    switch FileHopIdentitySecretStore.store(privateKey: data) {
    case let failure as FileHopIdentitySecretStore.Failure:
      result(FlutterError(code: failure.code, message: failure.message, details: nil))
    case let reference as String:
      result(["bridgeVersion": Self.bridgeVersion, "reference": reference])
    default:
      result(
        FlutterError(
          code: "nativeFailure",
          message: "failed to protect identity secret",
          details: nil
        )
      )
    }
  }

  private func handleIdentityLoad(map: [String: Any], result: FlutterResult) {
    guard let reference = map["reference"] as? String, !reference.isEmpty else {
      result(
        FlutterError(
          code: "invalidArgument",
          message: "reference must be a non-empty string",
          details: nil
        )
      )
      return
    }
    switch FileHopIdentitySecretStore.load(reference: reference) {
    case let failure as FileHopIdentitySecretStore.Failure:
      result(FlutterError(code: failure.code, message: failure.message, details: nil))
    case let bytes as FlutterStandardTypedData:
      result(["bridgeVersion": Self.bridgeVersion, "privateKeyBytes": bytes])
    default:
      result(
        FlutterError(
          code: "nativeFailure",
          message: "failed to load identity secret",
          details: nil
        )
      )
    }
  }

  private func handleIdentityDelete(map: [String: Any], result: FlutterResult) {
    guard let reference = map["reference"] as? String, !reference.isEmpty else {
      result(
        FlutterError(
          code: "invalidArgument",
          message: "reference must be a non-empty string",
          details: nil
        )
      )
      return
    }
    replyIdentity(FileHopIdentitySecretStore.delete(reference: reference), result: result, ok: true)
  }

  private func handleIdentityStatus(map: [String: Any], result: FlutterResult) {
    guard let reference = map["reference"] as? String, !reference.isEmpty else {
      result(
        FlutterError(
          code: "invalidArgument",
          message: "reference must be a non-empty string",
          details: nil
        )
      )
      return
    }
    switch FileHopIdentitySecretStore.status(reference: reference) {
    case let failure as FileHopIdentitySecretStore.Failure:
      result(FlutterError(code: failure.code, message: failure.message, details: nil))
    case let status as String:
      result(["bridgeVersion": Self.bridgeVersion, "status": status])
    default:
      result(
        FlutterError(
          code: "nativeFailure",
          message: "failed to query identity secret",
          details: nil
        )
      )
    }
  }

  private func replyIdentity(
    _ outcome: Any,
    result: FlutterResult,
    ok: Bool = false,
    anyKey: Bool = false
  ) {
    switch outcome {
    case let failure as FileHopIdentitySecretStore.Failure:
      result(FlutterError(code: failure.code, message: failure.message, details: nil))
    case let any as Bool where anyKey:
      result(["bridgeVersion": Self.bridgeVersion, "any": any])
    case is Bool:
      result(["bridgeVersion": Self.bridgeVersion, "ok": true])
    default:
      result(
        FlutterError(
          code: "nativeFailure",
          message: "identity secret operation failed",
          details: nil
        )
      )
    }
  }

  private func privateKeyData(_ value: Any?) -> Data? {
    if let typed = value as? FlutterStandardTypedData,
      typed.data.count == FileHopIdentitySecretStore.privateKeyLength
    {
      return typed.data
    }
    if let data = value as? Data, data.count == FileHopIdentitySecretStore.privateKeyLength {
      return data
    }
    return nil
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  /// Discovery callbacks arrive on FileHopLanDiscovery's private queue.
  /// Flutter event sinks are main-thread objects, and cancellation may race a
  /// queued emission, so resolve the current sink only after hopping to main.
  private func emitEvent(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    lanDiscovery.detach()
    eventSink = nil
  }
}
