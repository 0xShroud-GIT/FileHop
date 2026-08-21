# Protocol and Security

## Security model

FileHop separates stable peer identity, authenticated control sessions and transfer authorization. Network reachability alone never establishes trust.

Security failures fail closed: unknown protocol major versions, malformed/oversized secure frames, identity mismatches, invalid/replayed authorization, unsafe paths and integrity failures must not downgrade into compatibility behavior.

## Identity

- Peer security identity is the canonical public-key fingerprint.
- The existing domain uses a canonical 52-character Base32 fingerprint representation.
- Logical session/transfer/item IDs are opaque cryptographically random identifiers, not secrets.
- Transport/discovery locators are never identity.

### At-rest identity storage

- Android: AES-256-GCM wrapping with a key in Android Keystore; wrapped blobs are device-local and excluded from backup.
- iOS: Keychain with `AfterFirstUnlockThisDeviceOnly` semantics.
- Database state stores opaque protected-key references/metadata, never plaintext identity secrets.

## Secure PeerSession

The pinned design uses `Noise_XX_25519_ChaChaPoly_SHA256` via the reviewed `snow` 0.10.0 implementation behind a future narrow Rust FFI boundary.

The Rust boundary should expose cryptographic mechanics only (handshake/read/write/encrypt/decrypt/close). Dart retains identity/trust/session/network/retry/transfer/database ownership.

Before relying on the wrapper, test successful two-peer handshake plus wrong keys/prologue, truncated/oversized handshake data, corrupted/truncated ciphertext, replay, ordering errors, binding mismatch, malformed FFI input and closed-context reuse.

## Control and transfer planes

- Control messages travel over the authenticated peer session.
- Transfer data is streamed; whole-file buffering is prohibited.
- Final item completion requires SHA-256 verification.
- Transfer authorization tokens are scoped, revocable and never persisted as resumable secrets.
- Resume requires validation of source/destination identity and a verified checkpoint.

The recorded iOS transfer-plane design uses a short-lived self-signed P-256 TLS identity per peer session, fingerprint-pinned over the authenticated control channel, with Network.framework handling TLS and a loopback Dart HTTP server behind the native adapter. Do not substitute global certificate acceptance.

## Logging

Diagnostics must be structured, bounded and secret-safe. Never log private keys, Noise secrets, raw SAS material, transfer authorization tokens or file contents.
