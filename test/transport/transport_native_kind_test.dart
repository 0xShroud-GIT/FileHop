import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/native_bridge/channel/native_bridge.dart';
import 'package:filehop/native_bridge/codec/native_codec.dart';
import 'package:filehop/transport/adapter/transport_adapter_types.dart';
import 'package:filehop/transport/bridge/native_transport_adapter.dart';
import 'package:filehop/transport/errors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'app.filehop.native.commands.mission06-kind',
  );

  late List<String> methods;

  setUp(() {
    methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          methods.add(call.method);
          if (call.method == 'observeAvailability') {
            return <String, Object?>{
              'bridgeVersion': kNativeBridgeVersion,
              'kind': 'lan',
              'status': 'SUPPORTED_AVAILABLE',
            };
          }
          if (call.method == 'connect') {
            return <String, Object?>{
              'bridgeVersion': kNativeBridgeVersion,
              'handleId': 'h-wrong',
              'kind': 'wifiDirect',
            };
          }
          if (call.method == 'disconnect' || call.method == 'openEndpoint') {
            return <String, Object?>{
              'bridgeVersion': kNativeBridgeVersion,
              'ok': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  NativeTransportAdapter lanAdapter() {
    return NativeTransportAdapter(
      bridge: NativeBridge(commands: channel),
      kind: TransportKind.lan,
    );
  }

  test(
    'disconnect rejects wrong-kind connection without native call',
    () async {
      final NativeTransportAdapter adapter = lanAdapter();
      await expectLater(
        adapter.disconnect(
          const TransportConnectionHandle(
            handleId: 'x',
            kind: TransportKind.wifiDirect,
          ),
        ),
        throwsA(
          isA<TransportException>().having(
            (TransportException e) => e.kind,
            'kind',
            TransportFailureKind.adapterContractViolation,
          ),
        ),
      );
      expect(methods, isNot(contains('disconnect')));
    },
  );

  test(
    'openEndpoint rejects wrong-kind connection without native call',
    () async {
      final NativeTransportAdapter adapter = lanAdapter();
      await expectLater(
        adapter.openEndpoint(
          const TransportConnectionHandle(
            handleId: 'x',
            kind: TransportKind.wifiDirect,
          ),
        ),
        throwsA(
          isA<TransportException>().having(
            (TransportException e) => e.kind,
            'kind',
            TransportFailureKind.adapterContractViolation,
          ),
        ),
      );
      expect(methods, isNot(contains('openEndpoint')));
    },
  );

  test('connect result with mismatched kind fails closed', () async {
    final NativeTransportAdapter adapter = lanAdapter();
    await expectLater(
      adapter.connect(
        const TransportCandidateKey(kind: TransportKind.lan, candidateId: 'l1'),
      ),
      throwsA(
        isA<TransportException>().having(
          (TransportException e) => e.kind,
          'kind',
          TransportFailureKind.adapterContractViolation,
        ),
      ),
    );
    expect(methods, contains('connect'));
  });
}
