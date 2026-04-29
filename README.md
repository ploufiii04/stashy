# stashy

A native **Stash** client for **iOS** and **tvOS** built with **SwiftUI** — fast, no built-in tracking, and wired directly to your Stash server.

## Features (current repo)

- **Home & catalogue** — configurable dashboard (rows, statistics, lists), scenes, performers, studios, galleries, images, tags, groups, markers.
- **Feeds** — vertical, swipeable feed (clips/previews); optional “Social” entry from performer detail.
- **StashLine** — image timeline with filters, set grouping (e.g. by date or name), optionally by image orientation.
- **Downloads** — download scenes for offline playback.
- **Playback** — streaming with selectable quality (per server / for Reels).
- **Devices** — TheHandy, **Intiface** / Buttplug including **FunScript** in the player.
- **Tools** — optional **Hot or Not** (duel/charts), aligned with the Stash plugin; in server settings: **Trust HTTPS certificate** for self-signed certs on a home network.
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
- **Hot or Not** and similar tools assume the **matching Stash plugin** and server data.
