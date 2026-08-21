# Product

FileHop is a local-first device-to-device sharing product for Android and iOS. Native peer sharing should not require accounts, cloud infrastructure, advertising, tracking or Internet connectivity.

## Core release path

The core product should become reliable in this order:

1. identity and trust
2. discovery and connection
3. authenticated peer session
4. file offer/accept
5. bounded-memory streaming transfer
6. SHA-256 integrity verification
7. interruption/checkpoint/reconnect/resume
8. background/lifecycle recovery

Only after this path is stable should broad folder-sharing, WebShare, UI polish or optional transports become release-critical.

Screen sharing remains part of the architecture, but it must not block a reliable core file-transfer release unless an explicit later product decision changes that priority.

## Intended sharing capabilities

The broader design includes files, folders, photos, videos, text, links and live screen content. Not all of these are implemented in the current source state.

## Trust/security defaults

- No auto-accept from unknown peers.
- Trust is bound to cryptographic peer identity, not names or network addresses.
- Blocking survives restart.
- Trust does not imply automatic transfer acceptance.
- No remote-control behavior is implied by screen sharing.
- Captured screen frames/audio are not persisted as a side effect of sharing.

## UI rule

UI controls should map to explicit engine commands/events rather than hiding product state inside widgets. The UI should display engine/native truth rather than infer success from connection attempts.
