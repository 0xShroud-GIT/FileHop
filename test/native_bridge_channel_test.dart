import 'package:filehop/native_bridge/channel/native_bridge.dart';
import 'package:filehop/native_bridge/codec/native_codec.dart';
import 'package:filehop/native_bridge/contract/enums.dart';
import 'package:filehop/native_bridge/contract/errors.dart';
import 'package:filehop/native_bridge/fake/fake_native_adapter.dart';
import 'package:filehop/native_bridge/contract/events.dart';
import 'package:filehop/native_bridge/contract/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const NativeCodec codec = NativeCodec();

  test('fake adapter emits deterministic events', () async {
    final FakeNativeAdapter fake = FakeNativeAdapter();
    final List<NativeAdapterEvent> seen = <NativeAdapterEvent>[];
    final sub = fake.events.listen(seen.add);

    fake.emitAvailability(
      const NativeCapabilitySnapshot(
        kind: NativeTransportKind.lan,
        status: NativeCapabilityStatus.supportedUnavailable,
      ),
    );
    fake.emitCandidateFound(
      const NativeTransportCandidate(
        candidateId: 'n1',
        kind: NativeTransportKind.lan,
        displayLabel: 'Desk',
      ),
    );
    fake.emitEndpointChanged(
      const NativeEndpoint(
        endpointId: 'e1',
        kind: NativeTransportKind.lan,
        reachability: NativeEndpointReachability.socket,
        host: '127.0.0.1',
        port: 7240,
      ),
    );
    fake.emitError(
      const NativeAdapterError(
        errorClass: NativeErrorClass.unavailable,
        message: 'wifi off',
        kind: NativeTransportKind.wifiDirect,
      ),
    );
    fake.emitCandidateLost('n1');
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((NativeAdapterEvent e) => e.kind), <NativeEventKind>[
      NativeEventKind.availabilityChanged,
      NativeEventKind.candidateFound,
      NativeEventKind.endpointChanged,
      NativeEventKind.adapterError,
      NativeEventKind.candidateLost,
    ]);
    expect(
      fake.observeAvailability(NativeTransportKind.wifiAware).status,
      NativeCapabilityStatus.unsupported,
    );
    expect(
      () => fake.connect(
        const NativeTransportCandidate(
          candidateId: 'n1',
          kind: NativeTransportKind.lan,
        ),
      ),
      throwsA(isA<NativeBridgeException>()),
    );
    await sub.cancel();
    fake.dispose();
  });

  test('mocked platform channel ping and observeAvailability', () async {
    final MethodChannel commands = const MethodChannel(kNativeCommandChannel);
    testerHandler(commands, (MethodCall call) async {
      expect(call.arguments, isA<Map<Object?, Object?>>());
      final Map<dynamic, dynamic> args =
          call.arguments as Map<dynamic, dynamic>;
      expect(args['bridgeVersion'], kNativeBridgeVersion);
      if (call.method == 'ping') {
        return <String, Object?>{'bridgeVersion': 1, 'ok': true};
      }
      if (call.method == 'observeAvailability') {
        return <String, Object?>{
          'bridgeVersion': 1,
          'kind': args['kind'],
          'status': 'UNSUPPORTED',
          'detail': 'skeleton',
        };
      }
      throw PlatformException(code: 'unsupported', message: call.method);
    });

    final NativeBridge bridge = NativeBridge(commands: commands);
    final NativePingResult ping = await bridge.ping();
    expect(ping.ok, isTrue);
    expect(ping.bridgeVersion, 1);

    final NativeCapabilitySnapshot snap = await bridge.observeAvailability(
      NativeTransportKind.wifiDirect,
    );
    expect(snap.status, NativeCapabilityStatus.unsupported);
    expect(snap.kind, NativeTransportKind.wifiDirect);

    await expectLater(
      bridge.startDiscovery(NativeTransportKind.lan),
      throwsA(
        isA<NativeBridgeException>().having(
          (NativeBridgeException e) => e.errorClass,
          'class',
          NativeErrorClass.unsupported,
        ),
      ),
    );
  });

  test('mocked event channel decodes typed events', () async {
    const EventChannel events = EventChannel(kNativeEventChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (Object? _, MockStreamHandlerEventSink sink) {
              sink.success(
                codec.encodeEvent(
                  const NativeAdapterEvent(
                    kind: NativeEventKind.availabilityChanged,
                    transportKind: NativeTransportKind.lan,
                    capability: NativeCapabilitySnapshot(
                      kind: NativeTransportKind.lan,
                      status: NativeCapabilityStatus.supportedAvailable,
                    ),
                  ),
                ),
              );
            },
          ),
        );

    final NativeBridge bridge = NativeBridge(events: events);
    final NativeAdapterEvent event = await bridge.events().first;
    expect(event.kind, NativeEventKind.availabilityChanged);
    expect(event.capability?.status, NativeCapabilityStatus.supportedAvailable);
  });

  test('mocked event channel drops semantically invalid events', () async {
    const EventChannel events = EventChannel(kNativeEventChannel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (Object? _, MockStreamHandlerEventSink sink) {
              sink.success(<String, Object?>{
                'bridgeVersion': kNativeBridgeVersion,
                'eventKind': 'candidateFound',
              });
              sink.success(
                codec.encodeEvent(
                  const NativeAdapterEvent(
                    kind: NativeEventKind.adapterError,
                    error: NativeAdapterError(
                      errorClass: NativeErrorClass.unavailable,
                      message: 'radio off',
                    ),
                  ),
                ),
              );
            },
          ),
        );

    final NativeBridge bridge = NativeBridge(events: events);
    final NativeAdapterEvent event = await bridge.events().first;
    expect(event.kind, NativeEventKind.adapterError);
    expect(event.error?.errorClass, NativeErrorClass.unavailable);
  });
}

void testerHandler(
  MethodChannel channel,
  Future<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}
