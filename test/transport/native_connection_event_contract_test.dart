import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/native_bridge/channel/native_bridge.dart';
import 'package:filehop/native_bridge/codec/native_codec.dart';
import 'package:filehop/native_bridge/contract/enums.dart';
import 'package:filehop/native_bridge/contract/events.dart';
import 'package:filehop/native_bridge/contract/models.dart';
import 'package:filehop/transport/bridge/native_transport_adapter.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const NativeCodec codec = NativeCodec();

  test('connectionChanged round-trips an explicit disconnect state', () {
    const NativeAdapterEvent source = NativeAdapterEvent(
      kind: NativeEventKind.connectionChanged,
      transportKind: NativeTransportKind.lan,
      connection: NativeConnectionHandle(
        handleId: 'connection-1',
        kind: NativeTransportKind.lan,
      ),
      connected: false,
    );

    final NativeAdapterEvent? decoded = codec.decodeEvent(
      codec.encodeEvent(source),
    );

    expect(decoded, isNotNull);
    expect(decoded!.connected, isFalse);
    expect(decoded.connection?.handleId, 'connection-1');
  });

  test('connectionChanged without connected is rejected by the codec', () {
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'connectionChanged',
        'transportKind': 'lan',
        'connection': codec.encodeConnection(
          const NativeConnectionHandle(
            handleId: 'connection-1',
            kind: NativeTransportKind.lan,
          ),
        ),
      }),
      isNull,
    );
  });

  test('native transport adapter preserves disconnect state', () async {
    const EventChannel events = EventChannel(
      'app.filehop.native.events.connection-state-test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (Object? _, MockStreamHandlerEventSink sink) {
              sink.success(
                codec.encodeEvent(
                  const NativeAdapterEvent(
                    kind: NativeEventKind.connectionChanged,
                    transportKind: NativeTransportKind.lan,
                    connection: NativeConnectionHandle(
                      handleId: 'connection-2',
                      kind: NativeTransportKind.lan,
                    ),
                    connected: false,
                  ),
                ),
              );
            },
          ),
        );

    final NativeTransportAdapter adapter = NativeTransportAdapter(
      bridge: NativeBridge(events: events),
      kind: TransportKind.lan,
    );

    final TransportAdapterEvent event = await adapter.events.first;
    expect(event, isA<AdapterConnectionChanged>());
    expect((event as AdapterConnectionChanged).connected, isFalse);
    expect(event.connection.handleId, 'connection-2');
  });
}
