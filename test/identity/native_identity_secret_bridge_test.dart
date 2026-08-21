import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/native/native_protected_identity_key_store.dart';
import 'package:filehop/identity/protected_key_reference.dart';
import 'package:filehop/identity/protected_key_status.dart';
import 'package:filehop/native_bridge/channel/native_bridge.dart';
import 'package:filehop/native_bridge/codec/native_codec.dart';
import 'package:filehop/native_bridge/contract/enums.dart';
import 'package:filehop/native_bridge/contract/errors.dart';
import 'package:filehop/native_bridge/contract/events.dart';
import 'package:filehop/native_bridge/contract/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../native_bridge_channel_test.dart';
import 'support/test_key_material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const NativeCodec codec = NativeCodec();

  test(
    'identity secret store/load/status/delete through mocked channel',
    () async {
      final Map<String, Uint8List> secrets = <String, Uint8List>{};
      const String reference = 'fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final MethodChannel commands = const MethodChannel(kNativeCommandChannel);
      testerHandler(commands, (MethodCall call) async {
        expect(call.arguments, isA<Map<Object?, Object?>>());
        final Map<dynamic, dynamic> args =
            call.arguments as Map<dynamic, dynamic>;
        expect(args['bridgeVersion'], kNativeBridgeVersion);
        switch (call.method) {
          case 'identitySecret.store':
            final Object? raw = args['privateKeyBytes'];
            expect(raw, isA<Uint8List>());
            expect((raw as Uint8List).length, 32);
            secrets[reference] = Uint8List.fromList(raw);
            return <String, Object?>{
              'bridgeVersion': 1,
              'reference': reference,
            };
          case 'identitySecret.load':
            final String ref = args['reference'] as String;
            final Uint8List? bytes = secrets[ref];
            if (bytes == null) {
              throw PlatformException(code: 'notFound', message: 'missing');
            }
            return <String, Object?>{
              'bridgeVersion': 1,
              'privateKeyBytes': bytes,
            };
          case 'identitySecret.status':
            final String ref = args['reference'] as String;
            return <String, Object?>{
              'bridgeVersion': 1,
              'status': secrets.containsKey(ref) ? 'present' : 'absent',
            };
          case 'identitySecret.delete':
            secrets.remove(args['reference'] as String);
            return <String, Object?>{'bridgeVersion': 1, 'ok': true};
          case 'identitySecret.hasAny':
            return <String, Object?>{
              'bridgeVersion': 1,
              'any': secrets.isNotEmpty,
            };
          case 'identitySecret.deleteAll':
            secrets.clear();
            return <String, Object?>{'bridgeVersion': 1, 'ok': true};
          default:
            throw PlatformException(code: 'unsupported', message: call.method);
        }
      });

      final NativeBridge bridge = NativeBridge(commands: commands);
      final NativeProtectedIdentityKeyStore store =
          NativeProtectedIdentityKeyStore(bridge);
      final ProtectedKeyReference stored = await store.store(testPrivateA());
      expect(stored.value, reference);
      await store.withPrivateKey(stored, (Uint8List bytes) async {
        expect(bytes, testPrivateA());
      });
      expect(await store.status(stored), ProtectedKeyStatus.present);
      expect(await store.hasAnySecret(), isTrue);
      await store.delete(stored);
      expect(await store.status(stored), ProtectedKeyStatus.absent);
      expect(await store.hasAnySecret(), isFalse);
    },
  );

  test('native missing secret maps to identityKeyMissing', () async {
    final MethodChannel commands = const MethodChannel(kNativeCommandChannel);
    testerHandler(commands, (MethodCall call) async {
      throw PlatformException(code: 'notFound', message: 'missing');
    });
    final NativeProtectedIdentityKeyStore store =
        NativeProtectedIdentityKeyStore(NativeBridge(commands: commands));
    expect(
      () => store.withPrivateKey(
        ProtectedKeyReference.parse('fhik1.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        (_) async {},
      ),
      throwsA(
        isA<IdentityException>().having(
          (IdentityException e) => e.kind,
          'kind',
          IdentityFailureKind.identityKeyMissing,
        ),
      ),
    );
  });

  test('codec rejects invalid identity secret payloads and event secrets', () {
    expect(
      () => codec.encodeIdentitySecretStore(Uint8List(8)),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.requireIdentityReference(
        'fhik2.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      () => codec.requireIdentityReference(
        'FHIK1.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      throwsA(isA<NativeCodecException>()),
    );
    expect(
      codec.decodeEvent(<String, Object?>{
        'bridgeVersion': kNativeBridgeVersion,
        'eventKind': 'adapterError',
        'privateKeyBytes': Uint8List(32),
        'error': <String, Object?>{
          'bridgeVersion': kNativeBridgeVersion,
          'errorClass': 'unavailable',
          'message': 'x',
        },
      }),
      isNull,
    );
  });

  test('identity secret responses reject transport identity fields', () {
    expect(
      () => codec.decodeIdentitySecretReference(<String, Object?>{
        'bridgeVersion': 1,
        'reference': 'fhik1.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'fingerprint': 'nope',
      }),
      throwsA(isA<NativeCodecException>()),
    );
  });

  test('events never encode secret keys', () {
    final Map<String, Object?> encoded = codec.encodeEvent(
      const NativeAdapterEvent(
        kind: NativeEventKind.adapterError,
        error: NativeAdapterError(
          errorClass: NativeErrorClass.unavailable,
          message: 'radio off',
        ),
      ),
    );
    expect(encoded.containsKey('privateKeyBytes'), isFalse);
    expect(encoded.containsKey('fingerprint'), isFalse);
  });
}
