import '../../domain/transport/transport_kind.dart';
import 'transport_adapter_event.dart';
import 'transport_adapter_types.dart';

/// One FileHop transport family. Shared contract; no OS objects leak out.
abstract class TransportAdapter {
  TransportKind get kind;

  Stream<TransportAdapterEvent> get events;

  Future<TransportCapabilitySnapshot> observeAvailability();

  Future<void> startDiscovery();

  Future<void> stopDiscovery();

  Future<TransportConnectionHandle> connect(TransportCandidateKey candidate);

  Future<void> disconnect(TransportConnectionHandle connection);

  Future<TransportEndpoint> openEndpoint(TransportConnectionHandle connection);

  /// Release resources for a failed/incomplete [connect] that never returned
  /// a [TransportConnectionHandle].
  ///
  /// Success means the adapter has established sufficient release for fallback.
  /// Failure means fallback must not assume the previous attempt is released.
  /// Do not invent a connection handle to call [disconnect].
  Future<void> releaseAttempt(TransportCandidateKey candidate);
}
