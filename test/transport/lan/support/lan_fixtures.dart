import 'package:filehop/transport/lan/lan.dart';

const String kLanIdA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String kLanIdB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String kLanIdC = 'cccccccccccccccccccccccccccccccc';

LanDiscoveryInstanceId lanId(String raw) => LanDiscoveryInstanceId.parse(raw);

LanDiscoveryRecord lanRecord({
  String id = kLanIdB,
  String serviceName = 'FileHop',
  String serviceType = kFileHopLanServiceType,
  int port = 7240,
  List<String> hosts = const <String>['127.0.0.1'],
}) {
  const LanAddressParser parser = LanAddressParser();
  return LanDiscoveryRecord.resolved(
    instanceId: lanId(id),
    serviceInstanceName: serviceName,
    serviceType: serviceType,
    port: port,
    addresses: <LanResolvedAddress>[
      for (final String host in hosts) parser.tryParse(host)!,
    ],
  );
}
