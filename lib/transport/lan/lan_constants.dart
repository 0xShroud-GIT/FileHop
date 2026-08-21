/// Frozen FileHop LAN discovery constants. Locator metadata only.
library;

/// Identical DNS-SD / Bonjour service type on Android and iOS.
const String kFileHopLanServiceType = '_filehop._tcp';

/// Diagnostic service instance name prefix. Not identity. OS may rename.
const String kFileHopLanServiceNamePrefix = 'FileHop';

/// Discovery TXT schema version. Unknown versions fail closed.
const int kFileHopLanDiscoverySchemaVersion = 1;

const String kFileHopLanTxtVersionKey = 'v';
const String kFileHopLanTxtInstanceKey = 'i';

const int kFileHopLanMaxTxtKeys = 8;
const int kFileHopLanMaxTxtKeyBytes = 32;
const int kFileHopLanMaxTxtValueBytes = 128;
const int kFileHopLanMaxTxtPayloadBytes = 512;
const int kFileHopLanMaxAddressesPerCandidate = 8;
const int kFileHopLanMaxActiveCandidates = 128;
const int kFileHopLanInstanceIdHexLength = 32;

/// Locator hint emitted by native discovery when a candidate is a
/// service-resolvable native endpoint pending connection-time resolution.
/// It deliberately carries no host/port claim.
const String kFileHopLanNativeServiceLocatorHint = 'nativeService';
