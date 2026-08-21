# Platform Native Boundaries

## Android

Current custom Kotlin sources live under `android/app/src/main/kotlin/app/filehop/filehop/`:

- `FileHopIdentitySecretStore.kt`
- `FileHopLanDiscovery.kt`
- `FileHopNativePlugin.kt`
- `MainActivity.kt`

Android native code owns Android OS resources only. Existing identity storage uses Android Keystore wrapping; LAN discovery uses NSD and generation-scoped lifecycle/resource ownership.

Future Wi-Fi Direct, Wi-Fi Aware, background-transfer and MediaProjection resources must follow the same owner/generation/idempotent-dispose/stale-callback rules.

For long-running user-initiated transfers, use the platform mechanism selected for the exact Android version/toolchain rather than creating an application-level substitute.

## iOS

Current custom Swift sources under `ios/Runner/` include:

- `FileHopIdentitySecretStore.swift`
- `FileHopLanDiscovery.swift`
- `FileHopNativePlugin.swift`

`ios/RunnerTests/` contains native contract tests for identity allocation and LAN discovery/TXT behavior.

Identity secrets use Keychain device-only accessibility. LAN discovery uses Network.framework Bonjour browsing and remains passive until the connection stage owns an endpoint.

Future Apple background work, Wi-Fi Aware, capture and transfer TLS listener resources must use explicit native owners and deterministic cleanup.

## Bridge

The shared/native bridge is versioned and typed. Preserve current channel/codec semantics and bounded validation. Platform additions should surface capability/state/events to Dart instead of embedding product policy in native code.

## Device truth

Compilation and source-contract tests cannot prove platform callback behavior. Permission flows, discovery, connection, background execution, screen capture and cross-platform radio interoperability require real-device validation.
