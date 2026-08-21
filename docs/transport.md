# Transport

## Abstraction

A transport adapter has one job: discover/acquire and own a usable connection for the shared engine.

A transport must not own:

- peer identity or trust
- filenames/folder semantics
- transfer/checkpoint semantics
- application navigation/UI state
- screen-session product state

The upper peer/session/transfer engine must remain transport-independent.

## Selection vs qualification

The existing selector architecture and preference order are preserved: Aware → Direct → LAN when candidates are healthy/qualified.

That ranking does **not** define current implementation order. Qualification is independent:

1. prove LAN end-to-end as the reference path;
2. prove Wi-Fi Direct independently;
3. prove Wi-Fi Aware independently;
4. only then rely on automatic selector/fallback behavior as end-to-end evidence.

Fallback must never hide a broken individual transport.

## LAN discovery contract

Current discovery rules:

- DNS-SD service type: `_filehop._tcp`
- TXT schema: `v=1`, `i=<32 lowercase hex>`
- discovery instance ID is ephemeral and is not peer identity
- self-filter by discovery instance ID
- malformed TXT/addresses/locators fail closed
- iOS discovery is passive; browsing must not open a remote connection
- native service/endpoints may be retained only as runtime locator state

### Android lifecycle

Android NSD state is serialized through one state authority. Discovery/resource callbacks are generation-checked before mutation. Multicast ownership and registration/path ownership are generation-scoped and cleaned idempotently.

Service-name equality is never sufficient identity. Native path ownership and FileHop discovery instance identity are separate concepts.

### iOS lifecycle

Bonjour uses Network.framework browsing with TXT metadata. Endpoint ownership is runtime-only, discovery stays passive, and native TXT bounds are enforced before candidate emission.

## Physical qualification

Hardware-dependent transports must be tested independently on real devices soon after implementation. At minimum, exercise repeated discover/connect/real-byte-exchange/disconnect/reconnect cycles and lifecycle permutations such as background/foreground, screen off/on, radio toggles, permission denial/recovery, app kill and rapid stop/start.

Only evidence-backed capabilities may be advertised.
