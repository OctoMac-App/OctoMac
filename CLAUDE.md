# OctoMac

A SwiftUI Mac app for OctoPrint 3D printers. This is a public repository: never commit personal details, printer addresses, API keys, signing identities, team IDs or anything from `scripts/release.local`.

## Build and test

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # swift test needs Xcode's toolchain, not just the Command Line Tools
swift build
swift test                     # Swift Testing; all tests must pass
scripts/build-app.sh debug     # assembles build/OctoMac.app (with the widget extension and Sparkle)
open build/OctoMac.app --args --demo            # demo mode: four pretend printers, no network
open build/OctoMac.app --args --demo --select 2 # start on the second demo printer
```

Use demo mode to check UI changes. It never touches the network, saved printers or stored keys.

Each new build is a new binary to macOS, which can silently block its local network access (`URLError -1009`) until the user switches OctoMac off and on in System Settings → Privacy & Security → Local Network. The app explains this when it happens. Don't change privacy settings for the user.

## Layout

- `Sources/OctoPrintKit`: a standalone client library for OctoPrint, with no app or UI code. Covers the REST API (`Endpoints/`), push updates over the websocket (`Push.swift`), Application Keys (`AppKeys.swift`), self-signed certificate pinning (`CertificateTrust.swift`), plugin APIs (`Plugins/`) and a fast G-code parser (`GCode/`). Anything that talks to OctoPrint belongs here, with tests in `Tests/OctoPrintKitTests`.
- `Sources/OctoMac/Model`: app state. `PrinterSession` holds everything live for one printer, `InstanceStore` the list of printers. API keys and proxy sign-ins live in `CredentialStore` (an encrypted file by default, the Keychain if the user chooses), never in `UserDefaults`.
- `Sources/OctoMac/Views`: one file per tab or panel. `Sources/OctoMac/Design` holds the palette, fonts and shared controls; use them rather than system defaults.
- `Sources/OctoMacWidgets` and `Sources/WidgetData`: the widget extension, which reads a status file the app writes. It's linked with `NSExtensionMain` (see `Package.swift`); without that, macOS's extension loader crashes it.
- `docs/`: README images and the website (`docs/index.html`, published by GitHub Pages from `master`). The site deliberately looks like the app: reuse the palette and fonts from `Sources/OctoMac/Design/Theme.swift`, and update its feature text and screenshots along with the README.
- `scripts/`: `build-app.sh` and `assemble.sh` package the app; `release.sh` makes notarised releases, updates `appcast.xml` and the Homebrew cask in `OctoMac-App/homebrew-tap` (maintainers only; signing settings come from the untracked `scripts/release.local`, see `release.local.example`).

## Conventions

- Match the surrounding code: its naming, comment density and SwiftUI style.
- Text in the app, README and comments is plain, friendly British English, written for people rather than programmers. Never use long (em) dashes; use a comma, colon or full stop. CI fails if one appears.
- Bug reports are GitHub issues only. Help → Report a Problem builds a diagnostics file that must never include printer names, addresses, API keys, proxy sign-ins, user names or file names; `DiagnosticsPrivacyTests` enforces this.
- OctoPrint plugins are optional: check a plugin is present before using it, and fall back gracefully when it isn't.
- Out of scope unless the maintainer asks: power control and smart plugs, Spoolman, and accounts with limited OctoPrint permissions (OctoMac expects an admin account).
- Keep pull requests focused, and update the README, `PRIVACY.md` or `CONTRIBUTING.md` when a change affects them. After editing any of those or this file, run `scripts/make-llms-full.sh` to rebuild `llms-full.txt` (CI checks it's current).
