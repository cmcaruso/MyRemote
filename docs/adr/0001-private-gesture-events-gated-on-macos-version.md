# Private gesture events, gated on the macOS version

Gestures should feel like the Mac's own trackpad, and a real trackpad's zoom, rotate and dock swipes follow the fingers. No public API can post them, so the Host posts undocumented `CGEvent` gesture events (types 29 and 30 with numbered private fields, the recipe Mac Mouse Fix uses), which were tested on macOS 26.

Dock swipes (Mission Control, App Exposé, Spaces, Show Desktop, Apps) are known to break on macOS 27. They are posted only on macOS 26.x; on any other version the Host falls back to one-shot Dock calls or fn-flagged shortcuts. Supporting a new macOS means testing it and widening that check, not detecting failure at runtime, since the Host can't tell whether the Dock reacted.

## Considered Options

- **One-shot only** (Dock calls and shortcuts everywhere): stable, but nothing follows the fingers, which is the point of the feature.
- **Detect failure and fall back:** not practical, because a posted dock swipe gives no feedback.
