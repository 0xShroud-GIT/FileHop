import 'package:filehop/native_bridge/codec/native_codec.dart';
import 'package:filehop/native_bridge/contract/enums.dart';
import 'package:filehop/native_bridge/contract/errors.dart';
import 'package:filehop/native_bridge/contract/events.dart';
import 'package:filehop/native_bridge/contract/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const NativeCodec codec = NativeCodec();

  test('capability statuses round-trip including master wire names', () {
    for (final NativeCapabilityStatus status in NativeCapabilityStatus.values) {
      if (status == NativeCapabilityStatus.unknown) {
        continue;
      }
      final NativeCapabilitySnapshot snapshot = NativeCapabilitySnapshot(
        kind: NativeTransportKind.wifiDirect,
        status: status,
      );
      final NativeCapabilitySnapshot decoded = codec.decodeCapability(
        codec.encodeCapability(snapshot),
      );
      expect(decoded.status, status);
      expect(decoded.kind, NativeTransportKind.wifiDirect);
    }
  });

  test('transport kinds, endpoints, errors, and events round-trip', () {
    const NativeTransportCandidate candidate = NativeTransportCandidate(
      candidateId: 'c1',
      kind: NativeTransportKind.lan,
      displayLabel: 'Kitchen tablet',
      locatorHint: 'filehop.local',
    );
    expect(
      codec.decodeCandidate(codec.encodeCandidate(candidate)).locatorHint,
      'filehop.local',
    );

    const NativeEndpoint endpoint = NativeEndpoint(
      endpointId: 'e1',
      kind: NativeTransportKind.wifiAware,
      reachability: NativeEndpointReachability.nativeStream,
      nativePathHandle: 'path-7',
    );
    final NativeEndpoint decodedEndpoint = codec.decodeEndpoint(
      codec.encodeEndpoint(endpoint),
    );
    expect(
      decodedEndpoint.reachability,
      NativeEndpointReachability.nativeStream,
    );
    expect(decodedEndpoint.nativePathHandle, 'path-7');
    expect(decodedEndpoint.host, isNull);

    const NativeAdapterError error = NativeAdapterError(
      errorClass: NativeErrorClass.permissionRequired,
      message: 'nearby wifi',
      nativeCode: '13',
      kind: NativeTransportKind.wifiDirect,
    );
    expect(
      codec.decodeError(codec.encodeError(error)).errorClass,
      NativeErrorClass.permissionRequired,
    );

    final NativeAdapterEvent event = NativeAdapterEvent(
      kind: NativeEventKind.candidateFound,
      transportKind: NativeTransportKind.lan,
      candidate: candidate,
    );
    expect(
      codec.decodeEvent(codec.encodeEvent(event))!.kind,
      NativeEventKind.candidateFound,
    );
  });

  test('unknown enum values fail safely', () {
    expect(
      NativeCapabilityStatus.fromWire('SOMETHING_NEW'),
      NativeCapabilityStatus.unknown,
    );
    expect(NativeTransportKind.fromWire('ble'), NativeTransportKind.unknown);
    expect(NativeErrorClass.fromWire('oops'), NativeErrorClass.unknown);
    expect(NativeEventKind.fromWire('mystery'), NativeEventKind.unknown);
  });

  test('malformed payloads produce codec failures', () {
    expect(
      () => codec.decodeCandidate('nope'),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.decodeCandidate(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'kind': 'lan',
      }),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.decodeCandidate(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'candidateId': 12,
        'kind': 'lan',
      }),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.requireBridgeVersion(<String, Object?>{'bridgeVersion': 99}),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
      }),
      isNull,
    );
  });

  test('events without required payloads are dropped, not thrown', () {
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'candidateFound',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'candidateUpdated',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'candidateLost',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'endpointChanged',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'connectionChanged',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'availabilityChanged',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'permissionChanged',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'nativeLifecycleChanged',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'adapterError',
      }),
      isNull,
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'futureEventKind',
      }),
      isNull,
    );
  });

  test('socket and nativeStream endpoints reject unusable locators', () {
    Map<String, Object?> socket({String? host, int? port}) {
      return <String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'endpointId': 'e1',
        'kind': 'lan',
        'reachability': 'socket',
        'host': ?host,
        'port': ?port,
      };
    }

    expect(
      () => codec.decodeEndpoint(socket(port: 7240)),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.decodeEndpoint(socket(host: '127.0.0.1')),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.decodeEndpoint(socket(host: '127.0.0.1', port: 0)),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.decodeEndpoint(socket(host: '127.0.0.1', port: 65536)),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.decodeEndpoint(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'endpointId': 'e1',
        'kind': 'wifiAware',
        'reachability': 'nativeStream',
      }),
      throwsA(isA<NativeCodecException>()),
    );

    final NativeEndpoint ignoredExtra = codec.decodeEndpoint(<String, Object?>{
      'bridgeVersion': kNativeBridgeVersion,
      'endpointId': 'e1',
      'kind': 'lan',
      'reachability': 'socket',
      'host': '127.0.0.1',
      'port': 7240,
      'nativePathHandle': 'ignored-for-socket',
    });
    expect(ignoredExtra.host, '127.0.0.1');
    expect(ignoredExtra.port, 7240);
    expect(ignoredExtra.reachability, NativeEndpointReachability.socket);
  });

  test('security identity fields are rejected on the codec boundary', () {
    expect(
      () => codec.requireMap(<String, Object?>{
        'candidateId': 'c1',
        'fingerprint': 'abc',
      }, 'candidate'),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.requireMap(<String, Object?>{'peerIdentity': 'x'}, 'event'),
      throwsA(isA<NativeCodecException>()),
    );
    const NativeTransportCandidate candidate = NativeTransportCandidate(
      candidateId: 'c1',
      kind: NativeTransportKind.wifiDirect,
    );
    final Map<String, Object?> encoded = codec.encodeCandidate(candidate);
    expect(encoded.containsKey('fingerprint'), isFalse);
    expect(encoded.containsKey('peerIdentity'), isFalse);
  });
}
