# Architecture

## Core model

FileHop uses Flutter/Dart as the shared product engine, Kotlin for Android OS integration, and Swift for iOS OS integration. Rust is reserved for a future narrow Noise/crypto boundary only.

The primary architectural rule is **one product engine, multiple thin native/transport adapters**.

### Dart owns

- product/domain state machines
- peer/trust/session semantics
- transfer semantics and checkpoints
- persistence rules
- transport candidate registry/selection
- UI-facing state and navigation decisions

### Kotlin / Swift own

- OS discovery/network APIs
- platform key storage
- platform permissions/callbacks
- resource creation and release
- platform-specific background/capture behavior

Native code reports capability and lifecycle truth to Dart; it does not become another product coordinator.

## Repository implementation map

- `lib/domain/` — peer, trust, session, transfer and transport domain types/state machines
- `lib/identity/` — identity/trust orchestration and native secret-store abstraction
- `lib/persistence/` — SQLite schema, migrations, records and stores
- `lib/native_bridge/` — typed Dart/native command/event contracts
- `lib/transport/` — adapters, LAN discovery, registry, manager and selector
- `android/app/src/main/kotlin/.../filehop/` — Android identity/LAN/native plugin implementation
- `ios/Runner/` — iOS identity/LAN/native plugin implementation

## Identity vs connectivity

A stable peer is identified by its authenticated public-key fingerprint. Network addresses, Bonjour/NSD service names, network handles, endpoints and discovery instance IDs are temporary transport locators only.

Authentication binds a temporary connection to a stable identity. Never derive trust from IP address, device name or service name.

## Native lifecycle rule

Every asynchronous native subsystem must have:

- one named resource owner
- an explicit lifecycle (`STOPPED/CREATED`, `STARTING`, `ACTIVE`, `STOPPING`, `DISPOSED/TERMINAL` as applicable)
- a generation/epoch identifier
- idempotent stop and dispose
- rejection of callbacks belonging to an older generation

Do not hold global locks across blocking/framework calls. Stale callbacks must not resurrect disposed sessions or resources.

## Connection/reconnect model

V1 intentionally avoids seamless live transport migration.

If a transport dies:

1. dispose the old transport connection;
2. dispose the old peer session;
3. retain only verified transfer checkpoint state;
4. acquire a fresh transport;
5. perform a fresh authenticated peer session;
6. confirm the same stable peer identity;
7. resume from the verified checkpoint.

## Frozen platform/toolchain direction

Current project pins recorded by the supplied source state:

- Flutter 3.47.0 / Dart 3.13.0
- Android minSdk 24, compile/target 36, AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0, JDK 17
- iOS deployment target 15.0; planned shipping toolchain recorded as Xcode 26 / iOS 26 SDK
- SQLite schema v1
- native bridge version 1

Verify exact installed versions before using platform APIs or changing these pins.
