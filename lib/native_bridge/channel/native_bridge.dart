import 'package:flutter/services.dart';

import '../codec/native_codec.dart';
import '../contract/enums.dart';
import '../contract/errors.dart';
import '../contract/events.dart';
import '../contract/models.dart';

/// Shared Dart API. Callers do not distinguish Kotlin vs Swift.
class NativeBridge {
  NativeBridge({
    MethodChannel? commands,
    EventChannel? events,
    this._codec = const NativeCodec(),
  }) : _commands = commands ?? const MethodChannel(kNativeCommandChannel),
       _events = events ?? const EventChannel(kNativeEventChannel);

  final MethodChannel _commands;
  final EventChannel _events;
  final NativeCodec _codec;

  /// One EventChannel stream per bridge instance.
  ///
  /// [EventChannel.receiveBroadcastStream] creates a new native listen/cancel
  /// lifecycle each time it is invoked. TransportManager and
  /// TransportCapabilityRegistry both subscribe to adapter events, so the
  /// native stream must be created once and shared rather than reopening the
  /// platform channel for every getter access.
  late final Stream<NativeAdapterEvent> _eventStream = _events
      .receiveBroadcastStream()
      .map(_codec.decodeEvent)
      .where((NativeAdapterEvent? event) => event != null)
      .cast<NativeAdapterEvent>();

  Stream<NativeAdapterEvent> events() => _eventStream;

  Future<NativePingResult> ping() async {
    return _invoke('ping', <String, Object?>{}, _codec.decodePing);
  }

  Future<NativeCapabilitySnapshot> observeAvailability(
    NativeTransportKind kind,
  ) {
    return _invoke('observeAvailability', <String, Object?>{
      'kind': kind.wire,
    }, _codec.decodeCapability);
  }

  Future<void> startDiscovery(NativeTransportKind kind) {
    return _invokeVoid('startDiscovery', <String, Object?>{'kind': kind.wire});
  }

  Future<void> stopDiscovery(NativeTransportKind kind) {
    return _invokeVoid('stopDiscovery', <String, Object?>{'kind': kind.wire});
  }

  Future<NativeConnectionHandle> connect(NativeTransportCandidate candidate) {
    return _invoke(
      'connect',
      _codec.encodeCandidate(candidate),
      _codec.decodeConnection,
    );
  }

  Future<void> disconnect(NativeConnectionHandle handle) {
    return _invokeVoid('disconnect', _codec.encodeConnection(handle));
  }

  Future<NativeEndpoint> openEndpoint(NativeConnectionHandle handle) {
    return _invoke(
      'openEndpoint',
      _codec.encodeConnection(handle),
      _codec.decodeEndpoint,
    );
  }

  Future<NativeIdentitySecretReference> storeIdentitySecret(
    Uint8List privateKeyBytes,
  ) {
    return _invoke(
      'identitySecret.store',
      _codec.encodeIdentitySecretStore(privateKeyBytes),
      _codec.decodeIdentitySecretReference,
    );
  }

  Future<Uint8List> loadIdentitySecret(String reference) {
    return _invoke(
      'identitySecret.load',
      _codec.encodeIdentitySecretReference(reference),
      _codec.decodeIdentitySecretBytes,
    );
  }

  Future<void> deleteIdentitySecret(String reference) {
    return _invokeVoid(
      'identitySecret.delete',
      _codec.encodeIdentitySecretReference(reference),
    );
  }

  Future<NativeIdentitySecretStatus> identitySecretStatus(String reference) {
    return _invoke(
      'identitySecret.status',
      _codec.encodeIdentitySecretReference(reference),
      _codec.decodeIdentitySecretStatus,
    );
  }

  Future<NativeIdentitySecretPresence> identitySecretHasAny() {
    return _invoke(
      'identitySecret.hasAny',
      const <String, Object?>{},
      _codec.decodeIdentitySecretPresence,
    );
  }

  Future<void> deleteAllIdentitySecrets() {
    return _invokeVoid('identitySecret.deleteAll', const <String, Object?>{});
  }

  Future<T> _invoke<T>(
    String method,
    Map<String, Object?> payload,
    T Function(Object? raw) decode,
  ) async {
    try {
      final Object? raw = await _commands.invokeMethod<Object>(
        method,
        _codec.envelope(payload),
      );
      return decode(raw);
    } on NativeCodecException catch (error) {
      throw NativeBridgeException(
        errorClass: NativeErrorClass.invalidArgument,
        message: error.message,
      );
    } on PlatformException catch (error) {
      throw NativeBridgeException(
        errorClass: NativeErrorClass.fromWire(error.code),
        message: error.message ?? 'native failure',
        nativeCode: error.code,
        diagnostic: error.details?.toString(),
      );
    }
  }

  Future<void> _invokeVoid(String method, Map<String, Object?> payload) async {
    await _invoke<NativePingResult>(method, payload, (Object? raw) {
      if (raw == null) {
        return const NativePingResult(
          bridgeVersion: kNativeBridgeVersion,
          ok: true,
        );
      }
      return _codec.decodePing(raw);
    });
  }
}
