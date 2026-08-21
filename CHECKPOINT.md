# FileHop Checkpoint

Updated: 2026-08-21

## Current state

- Source basis: FileHop workspace packet v0.2, through Mission 07.
- Mission 07 LAN discovery: **PASS / FROZEN** in the supplied project history.
- Mission 08 Wi-Fi Direct: **NOT STARTED / deferred** until the LAN reference vertical slice is proven.
- Mission 09 Wi-Fi Aware: **NOT STARTED / deferred** until the LAN reference vertical slice is proven.
- Next executable scope: **Mission 10 — LAN reference control/data viability**.
- Mission 10 implementation has **not started** in this checkpoint.

## Last completed engineering

Mission 07 hardened LAN discovery and native lifecycle behavior, including:

- Android NSD generation/entry guards and single serialized state authority.
- bounded loss correlation and per-path ownership tracking.
- generation-owned multicast cleanup and fail-closed lifecycle behavior.
- iOS passive Bonjour discovery with retained native endpoint references.
- strict TXT/address/native-service locator validation.
- transport locator kept separate from peer identity.

The LAN discovery service type remains `_filehop._tcp`, with TXT schema `v=1` and ephemeral instance ID `i=<32 lowercase hex>`.

## Last recorded verification

The supplied Mission 07 history records:

- `flutter analyze`: PASS / no issues.
- final recorded Flutter suite: **545 tests passing** after the same-generation entry-guard pass.
- Android production Kotlin: compiled with pinned Kotlin 2.4.0 against the recorded Android/Flutter contract environment.
- iOS Swift compile/runtime: not executed in that environment because Xcode was unavailable.
- Android/iOS LAN discovery behavior on physical devices: still requires device validation.

Repository cleanup on 2026-08-21 did **not** modify the application source/config/test/native files. A SHA-256 inventory verified **234/234 original app files unchanged** after flattening. Repository-only changes are the root documentation/ignore rules plus two small verification/export scripts required by existing immutable tests. The current cleanup environment does not contain Flutter/Dart, so the historical test result above has not been re-run here.

## Next implementation target

Prove ordinary LAN as the reference transport before adding more radio complexity:

1. Implement the existing Mission 10 scope over LAN only: reliable local control/data viability.
2. Produce a common ordered `TransportConnection` abstraction suitable for the upper engine.
3. Keep the LAN implementation free of identity/trust/transfer semantics.
4. Then implement Mission 11 secure `PeerSession` / Noise over that common connection.
5. Then Mission 12: discovery → connection → fresh authenticated peer session → offer → accept → stream binary → full SHA-256 verification.
6. Exercise interruption/checkpoint/dispose/fresh reconnect/fresh authentication/resume over LAN before returning to Wi-Fi Direct and Wi-Fi Aware.

## Locked risk-reduction rules

- Preserve Flutter/Dart + Kotlin + Swift; no framework rewrite without a proven blocker.
- LAN is the reference vertical slice.
- Mission 06 selector/fallback behavior remains architecturally valid; fallback must not hide a broken transport during qualification.
- One explicit owner per native resource; generation/epoch + stale-callback rejection for asynchronous native systems.
- `TransportLocator != PeerIdentity`.
- No seamless V1 live transport migration.
- Screen sharing remains planned but must not block a reliable core file-transfer release.
- Wi-Fi Aware is an enhancement that must not become a core availability dependency without physical evidence.

## Current hardware/build gaps

Do not claim these as PASS until verified in an appropriate environment:

- Android NSD/multicast real-device behavior.
- iOS Bonjour/local-network-permission real-device behavior.
- Android↔iOS LAN discovery/connectivity.
- Wi-Fi Direct and Wi-Fi Aware implementation/qualification.
- iOS native build/XCTest execution.
- background ownership, pickers, screen capture, WebRTC first-frame behavior, and future iOS transfer TLS listener/pump.

## Continuation rule

Any agent materially advancing FileHop must update this file before handing off. Keep only the current state, latest meaningful verification, active blockers/risks, and next safe work; move durable rules into `AGENTS.md` or `docs/` rather than letting this become a historical log.
