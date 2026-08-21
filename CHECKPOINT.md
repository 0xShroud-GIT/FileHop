# FileHop Checkpoint

Updated: 2026-08-21

## Current state

- Source basis: FileHop workspace packet v0.2, through Mission 07.
- Mission 07 LAN discovery remains the current completed subsystem scope, with audit remediation pending owner review on `audit-fixes-2026-08-21`.
- Mission 08 Wi-Fi Direct: **NOT STARTED / deferred** until the LAN reference vertical slice is proven.
- Mission 09 Wi-Fi Aware: **NOT STARTED / deferred** until the LAN reference vertical slice is proven.
- Mission 10 implementation has **not started**. Production app composition remains the local shell until that reference connection slice is deliberately integrated.
- Next executable product scope after audit remediation: **Mission 10 — LAN reference control/data viability**.

## Latest engineering

The 2026-08-21 repository audit identified and remediated integration/lifecycle defects without starting Mission 10:

- iOS native plugin now implements the missing event-emission bridge and marshals discovery events onto the main queue.
- iOS LAN discovery mutable state now has one serialized queue authority; public start/stop and native callbacks converge there, and stale browser-failure callbacks are generation-guarded before mutation or emission.
- `NativeBridge` now shares one EventChannel stream per bridge instance so multiple Dart listeners do not create competing native listen/cancel lifecycles.
- `TransportManager.close()` serializes against acquisition, rejects new work during shutdown, disconnects its active connection, and tears down event subscriptions/capability observation deterministically.
- transport candidate discovery generation is preserved across state-machine transitions.
- capability permission changes are published to capability observers without inventing an availability state.
- persisted transfer-item relative paths are validated on decode as well as write, so corrupted/tampered rows fail closed.
- local identity creation treats the successful metadata insert as the commit point; a transient post-commit protected-store/read failure no longer deletes the committed identity secret and strand metadata.
- Android engine detach retains a bounded main-thread NSD stop retry window so an asynchronous stop failure can be retried after Flutter drops the plugin reference.
- native `connectionChanged` events now carry an explicit connected/disconnected boolean, and the shared transport adapter preserves that state for future Mission 10 use.

Regression tests/source contracts were added for each changed behavior.

## Verification state

The branch was reviewed statically against the existing source-contract tests and repository invariants. The branch diff is intentionally limited to the audited lifecycle/bridge/persistence/identity defects and regression coverage; no Mission 10 sockets, Noise, Wi-Fi Direct/Aware, or UI/product-engine integration was introduced.

The current execution environment does **not** provide Flutter or Dart, so the required `dart format`, `flutter analyze`, and `flutter test --concurrency=1` gates have not been executed here. Xcode/iOS SDK and Android SDK are also unavailable, so the Swift/Kotlin platform changes have not been compiled in this environment. Do not describe these changes as build/runtime PASS until those gates are run in an appropriate toolchain.

Historical supplied evidence remains historical only:

- final recorded Flutter suite before this audit branch: **545 tests passing**.
- Android production Kotlin was previously compiled in the recorded Mission 07 environment.
- iOS Swift compile/runtime was not previously executed because Xcode was unavailable.
- Android/iOS LAN behavior on physical devices remains unverified.

## Review / continuation point

`audit-fixes-2026-08-21` is awaiting owner review and must not be merged without explicit approval. After approval and merge, run the full repository validation gate in a Flutter/native-capable environment before treating the remediation as verified.

Once the audit remediation is accepted, continue with Mission 10 only:

1. Implement reliable ordinary-LAN control/data viability using the existing transport abstractions.
2. Produce the common ordered connection surface for the upper engine.
3. Keep LAN free of identity/trust/transfer semantics.
4. Then implement the fresh authenticated `PeerSession` / Noise layer and the end-to-end transfer vertical slice.

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

- audit-branch Flutter formatting/analyzer/test gates.
- audit-branch Android and iOS native compilation.
- Android NSD/multicast real-device behavior, including detach/stop-failure recovery.
- iOS Bonjour/local-network-permission real-device behavior and rapid stop/start lifecycle.
- Android↔iOS LAN discovery/connectivity.
- Wi-Fi Direct and Wi-Fi Aware implementation/qualification.
- background ownership, pickers, screen capture, WebRTC first-frame behavior, and future iOS transfer TLS listener/pump.

## Continuation rule

Any agent materially advancing FileHop must update this file before handing off. Keep only the current state, latest meaningful verification, active blockers/risks, and next safe work; move durable rules into `AGENTS.md` or `docs/` rather than letting this become a historical log.
