# stashy

Native **Stash**-App für **iOS** und **tvOS** mit **SwiftUI** — schnell, ohne eingebautes Tracking und direkt mit deinem Stash-Server verbunden.

## Funktionen (Stand Repo)

- **Home & Katalog** — konfigurierbares Dashboard (Zeilen, Statistiken, Listen), Szenen, Darsteller, Studios, Galerien, Bilder, Tags, Gruppen, Marker.
- **Feeds** — vertikaler, swipebarer Feed (Clips/Previews); optional „Social“ von Darsteller-Details aus.
- **StashLine** — Bild-Timeline mit Filtern, Set-Gruppierung (u. a. nach Datum bzw. Name) und optional nach Bildausrichtung.
- **Downloads** — Szenen für Offline-Wiedergabe laden.
- **Wiedergabe** — Streaming mit wählbarer Qualität (pro Server / für Reels).
- **Geräte** — TheHandy, **Intiface** / Buttplug inkl. **FunScript** im Player.
- **Tools** — optional **Hot or Not** (Duell/Charts), abgestimmt auf das Stash-Plugin; in den Server-Einstellungen: **HTTPS-Zertifikat vertrauen** für Self-Signed-Zertifikate im Heimnetz.
- **Suche** — übergreifende Suche.
- **Einstellungen** — mehrere Server, API-Schlüssel (iOS: Keychain), Erscheinungsbild, Standard-Sortierung und -filter je Bereich, Sichtbarkeit und Reihenfolge der Tabs.

## Datenschutz

Es werden **keine** Nutzerdaten für Analytics oder Tracking erhoben — keine eingebauten Drittanbieter-Tracker, keine app-internen Nutzer-IDs.

## Voraussetzungen

- Ein laufender **[Stash](https://github.com/stashapp/stash)**-Server (GraphQL-API wie von der App genutzt).
- **Xcode** (empfohlen: aktuelle stabile Version).

## Lokal bauen

```bash
# iOS
xcodebuild -project stashy.xcodeproj -scheme stashy -destination 'generic/platform=iOS' build

# tvOS
xcodebuild -project stashy.xcodeproj -scheme stashyTV -destination 'generic/platform=tvOS' build
```

GraphQL liegt unter `graphql/` und wird zur Laufzeit eingebunden.

## Plattformen & Installation

| Plattform | App Store | TestFlight |
|-----------|-----------|------------|
| **iOS** | [stashy](https://apps.apple.com/us/app/stashy/id6754876029) | [Einladung](https://testflight.apple.com/join/KBYqHCuD) |
| **tvOS** | — | Early Alpha (gleicher TestFlight-Link) |

## Community

- **Discord**: [stashy](https://discord.gg/NBkUpUYJ)

## Roadmap (Auszug)

- tvOS näher an den iOS-Funktionsumfang bringen
- Performance und Speicher bei sehr großen Bibliotheken
- Feintuning von Filtern, Katalogen und Detailansichten

## Bekannte Einschränkungen

- Auf **tvOS** fehlen nicht alle iOS-Features (z. B. Keychain, manche UI-Komponenten/Gesten).
- **Hot or Not** und ähnliche Tools setzen das **passende Stash-Plugin** bzw. Server-Daten voraus.
