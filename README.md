# OctoMac

A Mac app for controlling [OctoPrint](https://octoprint.org) printers, with a layout and look built for the job rather than standard Mac chrome.

- Any number of OctoPrint servers, each with live status in the sidebar and the menu bar
- Live updates over OctoPrint's push connection (no polling), camera streams kept warm for instant switching
- Overview: camera with cinema mode and snapshots, layer-stack progress, opened file with thumbnail, temperature presets, and a chart with hover readouts, event markers and PNG/SVG export
- Move, Files (folders, upload by drag and drop, thumbnails), Console and Machine (connection, profile, system commands) tabs
- Stop with a clear confirmation, plus a separate emergency stop (M112)

## Requirements

- macOS 15 or later
- Xcode 16 or later (the Swift toolchain that ships with Xcode; the Command Line Tools alone can't expand SwiftUI's macros)

## Build and run

```sh
scripts/build-app.sh            # release build → build/OctoMac.app
scripts/build-app.sh debug      # debug build
open build/OctoMac.app
```

Or open `Package.swift` in Xcode and run the `OctoMac` scheme.

`open build/OctoMac.app --args --demo` shows canned printers without touching the network or saved settings (`--select N` picks the Nth printer).

## Adding a printer

Use **Add a printer**, enter the address, then either **Request access** (approve the request in the OctoPrint page that opens; uses OctoPrint's Application Keys plugin) or paste an API key. Keys are stored encrypted in `~/Library/Application Support/OctoMac/api-keys.dat`, readable only by your user account.

## Layout

| Path | What's there |
| --- | --- |
| `Sources/OctoPrintKit` | Client for the OctoPrint REST API, push (websocket) updates and the Application Keys flow |
| `Sources/OctoMac/Model` | Configured printers, credentials, and the live `PrinterSession` per printer |
| `Sources/OctoMac/Design` | Palette, type, shared components (layer stack, heat tiles, thumbnails) |
| `Sources/OctoMac/Views` | Window, rail, stage and its tabs, chart, editor, menu bar |
| `Tests/OctoPrintKitTests` | Decoding tests against OctoPrint-shaped fixtures (`swift test`) |

OctoPrint API reference: https://docs.octoprint.org/en/main/api/index.html
