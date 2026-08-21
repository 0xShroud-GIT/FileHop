import 'package:filehop/domain/transport/transport_kind.dart';
import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('permission changes are published without inventing availability', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.lan,
      availability: TransportAvailability.supportedAvailable,
    );
    await registry.register(adapter);

    final Future<TransportCapabilitySnapshot> changed = registry.changes.first;
    adapter.emit(
      const AdapterPermissionChanged(
        kind: TransportKind.lan,
        permission: TransportPermissionStatus.denied,
      ),
    );

    final TransportCapabilitySnapshot snapshot = await changed;
    expect(snapshot.kind, TransportKind.lan);
    expect(snapshot.availability, TransportAvailability.supportedAvailable);
    expect(snapshot.permission, TransportPermissionStatus.denied);
    expect(
      registry.snapshotFor(TransportKind.lan)?.permission,
      TransportPermissionStatus.denied,
    );

    await registry.close();
    await adapter.close();
  });

  test('registration after close is rejected', () async {
    final TransportCapabilityRegistry registry = TransportCapabilityRegistry();
    await registry.close();
    final FakeTransportAdapter adapter = FakeTransportAdapter(
      kind: TransportKind.lan,
    );

    await expectLater(
      registry.register(adapter),
      throwsA(
        isA<TransportException>().having(
          (TransportException error) => error.kind,
          'kind',
          TransportFailureKind.invalidArgument,
        ),
      ),
    );

    await adapter.close();
  });
}
