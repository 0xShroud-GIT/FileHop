# FileHop Agent Instructions

This is the single authoritative instruction file for AI coding agents working in FileHop.

## Start here

Before modifying the repository:

1. Read `CHECKPOINT.md` completely.
2. Inspect the implementation and tests relevant to the task.
3. Read only the focused document(s) under `docs/` that apply.
4. Treat source code and executable tests as ground truth when documentation disagrees.
5. Do not start unrelated roadmap work.

After materially advancing the project, update `CHECKPOINT.md` with what changed, what was verified, what remains unverified, and the next safe continuation point.

## Repository authority

- This GitHub repository is the canonical working source of truth.
- Keep it lightweight and directly buildable; do not recreate Arena/handoff/evidence packet machinery.
- Do not create competing agent instruction files such as `AGENT.md`, `CLAUDE.md`, `GEMINI.md`, or nested agent rule trees. Shared agent guidance belongs here.
- Durable architectural knowledge belongs in `docs/`; temporary/current status belongs in `CHECKPOINT.md`.
- Prefer Git history over accumulating mission logs or generated evidence archives in the repository.

## Stack and ownership

- Keep Flutter/Dart + Kotlin + Swift. Do not rewrite frameworks without a proven blocker.
- Dart owns peer/session/transfer semantics, persistence rules, transport selection, and UI-facing state.
- Kotlin/Swift own OS APIs, native resource lifetime, and platform callbacks.
- Rust, when introduced for Noise, must remain a narrow cryptographic boundary; it must not own product state, networking policy, trust, retries, persistence, or transfer semantics.
- Native adapters stay thin. They report capability/resources/events; they do not become alternate session coordinators.

## Critical invariants

- `PeerIdentity` is the stable authenticated fingerprint. Temporary addresses, service names, network handles, endpoints, and other locators are never identity.
- Transports produce/own a usable ordered connection and do not own trust, filenames, transfer semantics, UI state, or navigation.
- Preserve the existing selector/fallback architecture, but qualify LAN, Wi-Fi Direct, and Wi-Fi Aware independently before relying on fallback as product proof.
- Every asynchronous native subsystem has one explicit owner, an explicit lifecycle, a generation/epoch, idempotent stop/dispose, and stale-callback rejection.
- If ownership of a native resource cannot be named unambiguously, do not add the implementation.
- V1 does not seamlessly migrate a live session between transports. On transport loss: dispose connection/session, retain verified checkpoint, acquire fresh transport, authenticate a fresh `PeerSession`, confirm the same peer identity, then resume.
- `COMPLETED` transfer state requires successful integrity verification.
- Never persist Noise session secrets, authorization tokens, QR invitation secrets, or captured screen content.
- No custom cryptography. Use pinned/reviewed implementations and exact installed-version documentation.
- Unknown protocol versions, malformed secure frames, identity mismatches, replay/auth failures, unsafe paths, invalid tokens, and integrity failures fail closed.

## Implementation discipline

- Build one coherent vertical slice at a time.
- Prefer the smallest change that fits the existing architecture.
- Do not scaffold future radios/features while the current reference slice is incomplete.
- Preserve backward/forward data invariants and add migrations rather than silent destructive resets.
- Stream transfer payloads; never introduce whole-file buffering into the transfer path.
- Keep diagnostics structured, bounded, and secret-safe.
- Use official documentation matching the repository's pinned versions before community answers or copied fixes.
- Do not copy proprietary source, assets, keys, private endpoints, or reverse-engineered protocol material from products used as behavioral references.

## Validation

Run the smallest relevant checks during development and the full available gate before handing off material changes:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
python3 scripts/validate_android_manifest.py
```

When native code changes, also perform the strongest Android/iOS build or device validation available in the current environment. Record limitations truthfully in `CHECKPOINT.md`.

Never describe static/build evidence as physical-device PASS. Hardware-dependent discovery, connectivity, lifecycle, background behavior, capture, and cross-platform radio interoperability remain unproven until observed on real devices.

## Documentation map

Read only what is relevant:

- `docs/architecture.md` — ownership, layers, lifecycles, stack, connection model
- `docs/product.md` — product scope and release priorities
- `docs/transport.md` — transport abstraction, LAN/Direct/Aware policy and LAN discovery invariants
- `docs/protocol-security.md` — identity, trust, Noise/control/data security model
- `docs/platform-native.md` — Android/iOS native ownership and platform rules
- `docs/data-testing.md` — persistence invariants, evidence classes, validation expectations

Keep these documents concise. If the code already says something clearly, do not duplicate it here.
