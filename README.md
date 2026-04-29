# stashy

A native **Stash** client for **iOS** and **tvOS** built with **SwiftUI** — fast, no built-in tracking, and wired directly to your Stash server.

## Features (current repo)

- **Home & catalogue** — configurable dashboard (rows, statistics, lists), scenes, performers, studios, galleries, images, tags, groups, markers.
- **Feeds** — vertical, swipeable feed (clips/previews); optional “Social” entry from performer detail.
- **Feeds** — image and video timelines with filters.
- **Downloads** — download scenes for offline playback.
- **Playback** — streaming with selectable quality (per server / for Reels); scene detail on iOS uses [KSPlayer](#third-party-ksplayer) (AV engine) for device sync compatibility.
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

## Third-party: KSPlayer

[KSPlayer](https://github.com/kingslay/KSPlayer) is pulled in via **Swift Package Manager** (see the `stashy` target in `stashy.xcodeproj`). It powers **inline scene playback** on iOS (replacing the previous `AVPlayerViewController`-based view in the scene detail card).

**Engine:** The app sets `KSOptions.secondPlayerType` to **`KSAVPlayer`** at launch. That keeps playback on **`AVPlayer` / `AVPlayerItem`**, so **StashVideoSync** (video analysis and toy sync) continues to use the same AVFoundation hooks.

**Note:** Upstream KSPlayer defaults to **GPL-3.0**. If you ship or fork the app, review license obligations; the author also offers a paid **LGPL** build and other terms.

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
- **Hot or Not** and similar tools assume the **matching Stash plugin** and server data.
