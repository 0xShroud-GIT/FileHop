# FileHop

FileHop is a local-first peer-to-peer sharing app for Android and iOS. The product is being built around direct device communication, authenticated peers, transport-independent sessions, streaming transfers, integrity verification, interruption recovery, and optional screen sharing.

The repository is the canonical development workspace. Source code, tests, durable architecture documentation, and the current project checkpoint live here; historical Arena handoff/evidence packets do not.

## Status

FileHop is under active development. The foundation through LAN discovery is implemented, but the complete authenticated end-to-end transfer path is **not finished yet**.

For the exact current state, last verification, blockers, and next scope, read [`CHECKPOINT.md`](CHECKPOINT.md).

## Stack

- Flutter 3.47.0 / Dart 3.13.0
- Kotlin for Android native adapters
- Swift for iOS native adapters
- SQLite through `sqflite`
- SHA-256 through `package:crypto`
- Planned narrow Rust boundary for the pinned Noise implementation when secure `PeerSession` work begins

Pinned platform/dependency details that matter to architecture are summarized in [`docs/architecture.md`](docs/architecture.md) and [`docs/protocol-security.md`](docs/protocol-security.md).

## Repository map

```text
lib/                 shared Flutter/Dart product engine and UI
android/             Android app and Kotlin platform adapters
ios/                 iOS app and Swift platform adapters
test/                Dart/Flutter automated tests
docs/                durable engineering documentation
scripts/             small repository verification utilities
AGENTS.md             permanent instructions for AI coding agents
CHECKPOINT.md         current project state and continuation point
```

## Development

Install the pinned Flutter toolchain, then from the repository root:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
python3 scripts/validate_android_manifest.py
```

Platform-specific build/runtime validation additionally requires the appropriate Android SDK/JDK or macOS/Xcode environment. Do not treat static or headless checks as physical-device proof.

## Engineering model

- Dart owns product/session/transfer semantics and persistent product state.
- Kotlin and Swift own OS resources and platform lifecycle.
- Transport adapters are thin and transport-independent above their boundary.
- A transport locator is not a peer identity; authentication binds temporary connectivity to a stable peer fingerprint.
- A broken transport is disposed and replaced with a fresh authenticated session; V1 does not perform seamless live transport migration.
- Security failures fail closed.

See [`docs/architecture.md`](docs/architecture.md) for the complete durable ownership model.

## AI contributors

Before changing the repository, read [`AGENTS.md`](AGENTS.md) and then [`CHECKPOINT.md`](CHECKPOINT.md). `AGENTS.md` is permanent operating guidance; `CHECKPOINT.md` is the changing continuation record.
