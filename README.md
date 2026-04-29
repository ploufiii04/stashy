# stashy

A native **Stash** client for **iOS** and **tvOS** built with **SwiftUI** — fast, no built-in tracking, and wired directly to your Stash server.

## Features (current repo)

- **Home & catalogue** — configurable dashboard (rows, statistics, lists), scenes, performers, studios, galleries, images, tags, groups, markers.
- **Feeds** — vertical swipeable clip feed, optional “Social” from performer detail; image/video timelines with filters.
- **Downloads** — download scenes for offline playback.
- **Playback** — streaming with selectable quality (per server / for Reels); iOS scene detail uses KSPlayer (AV-backed) for device sync.
- **Devices** — TheHandy, **Intiface** / Buttplug including **FunScript** in the player.
- **Search** — global search across server content.
- **Settings** — multiple servers, API keys (Keychain on iOS), appearance, default sort/filter per area, tab visibility and order.

## Privacy

**No** analytics or tracking user data — no third-party trackers in the app, no app-assigned user IDs.

## Requirements

- A running **[Stash](https://github.com/stashapp/stash)** server (GraphQL API as used by the app).
- **Xcode** (recommended: current stable release).

## Build locally

```bash
# iOS
xcodebuild -project stashy.xcodeproj -scheme stashy -destination 'generic/platform=iOS' build

# tvOS
xcodebuild -project stashy.xcodeproj -scheme stashyTV -destination 'generic/platform=tvOS' build
```

GraphQL documents live under `graphql/` and are loaded at runtime.

## Platforms & distribution

| Platform | App Store | TestFlight |
|----------|-----------|------------|
| **iOS** | [stashy](https://apps.apple.com/us/app/stashy/id6754876029) | [Join](https://testflight.apple.com/join/KBYqHCuD) |
| **tvOS** | — | Early alpha (same TestFlight link) |

## Community

- **Discord**: [stashy](https://discord.gg/NBkUpUYJ)

## Roadmap (excerpt)

- Bring tvOS closer to iOS feature parity
- Performance and memory for very large libraries
- Tuning filters, catalogues, and detail views

## Known limitations

- **tvOS** does not include every iOS feature (e.g. Keychain, some UI components/gestures).


## Third-party

**[KSPlayer](https://github.com/kingslay/KSPlayer)** (SPM, `stashy` target) — iOS inline scene playback; app uses **`KSAVPlayer`** so **`AVPlayer`/`AVPlayerItem`** and StashVideoSync stay on AVFoundation. Upstream **GPL-3.0**; author offers **LGPL** / commercial builds.

**Match** (Hot-or-Not–style rating function) is **inspired by** **[Ascension](https://github.com/Servbot91/Ascension/tree/main)** — the Sakoto fork of Hot or Not for Stash. Stashy aims to stay **compatible with the same custom-field / DB entries** used by that plugin ecosystem, but **matchmaking and scoring algorithms** in the app **differ** from Ascension’s server-side behaviour.
