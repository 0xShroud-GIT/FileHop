# Data and Testing

## Persistence invariants

FileHop production persistence currently starts at schema v1. Preserve these invariants:

- peer fingerprint is unique security identity;
- blocked and trusted are mutually exclusive;
- forgetting a peer removes trust without rewriting history;
- blocking survives restart;
- trust does not imply auto-accept;
- checkpoints belong to exactly one transfer item;
- checkpoint offsets cannot exceed source/partial-destination truth;
- resume validates source and destination identity/version before requesting bytes;
- completed items retain no active authorization token;
- `COMPLETED` requires successful hash verification;
- peer-provided paths are sanitized before persistence/use;
- history deletion does not silently delete files;
- file deletion does not rewrite historical result truth.

Schema changes require a monotonic version, explicit forward migration, deterministic previous-version fixtures and migration tests. Do not silently reset production data to escape a migration failure.

## Evidence language

Use four distinct evidence levels:

- **A — executable/shared proof:** directly observed tests in the current environment.
- **B — build/contract proof:** compilation/static/source-contract validation without real hardware runtime.
- **C — physical-device proof required:** OS/radio/device behavior.
- **D — human/store proof required:** UX, accessibility, store/policy/release signoff.

Never report B as C.

## Routine checks

From repository root, when the pinned Flutter toolchain is available:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
python3 scripts/validate_android_manifest.py
```

Add focused tests with each implementation change. Prefer deterministic tests for state transitions, malformed input, persistence/reload/migration, transport selection/lifecycle, identity/trust, protocol boundaries, interruption/recovery and resource cleanup.

## Transfer test expectations

The transfer engine must prove bounded-memory streaming and backpressure; large logical fixtures should be generated/streamed rather than loaded wholly into memory.

Resume tests must cover interruption at arbitrary offsets, stale/invalid checkpoints, source changes, partial-file mismatch, invalid Range requests and final hash mismatch.

## Native/device qualification

For native radios and lifecycle systems, maintain a real-device compatibility record outside transient prose. Record device/OS pair, transport, operation performed, result and observed failures. Do not fabricate untested matrix rows.
