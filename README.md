<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
  <img src="docs/logo-light.png" alt="OctoMac" width="360">
</picture>

**A friendly Mac app for your OctoPrint 3D printers.**

OctoMac puts all of your [OctoPrint](https://octoprint.org) printers in one place, with a design built for watching and running prints rather than a web page squeezed into a window. Keep an eye on every printer at a glance, start a print in a couple of clicks, and watch it build up in 3D as it goes.

![OctoMac showing a print in progress](docs/screenshots/overview.png)

## What it does

- **All your printers, side by side.** Add as many OctoPrint servers as you like. Each one shows its status, temperatures and print progress in the sidebar, and switching between them is instant.
- **Live updates.** OctoMac listens to OctoPrint's live connection, so temperatures, progress and events appear the moment they happen. No waiting, no refreshing.
- **A clear overview.** See the webcam (with a cinema mode and one-click snapshots), the current print with time left and when it'll finish, and a temperature chart you can hover over and export as PNG or SVG.
- **Print in a couple of clicks.** Browse your files as thumbnails, filter by name, open one to check its print time, filament and history, then press Print.
- **Easy uploads.** Drag G-code onto the Files tab and watch the progress as it uploads.
- **G-code preview.** See exactly what will be printed, layer by layer or as a 3D model you can spin around.
- **Watch prints live.** While printing, the 3D preview follows along, with a little animated nozzle laying down the current layer.
- **Full control.** Heat up with your saved presets, move the print head, extrude filament, adjust fan and speed, send G-code from the console, and manage the connection and the Raspberry Pi.
- **Safe by design.** Stopping a print asks you to confirm and shows what you'd lose, and there's a separate emergency stop for when something goes wrong.
- **A menu bar helper.** Check on every printer from the menu bar without opening the main window.

![The 3D G-code preview following a live print](docs/screenshots/live-preview.png)

## Getting started

### What you need

- A Mac running **macOS 15 Sequoia** or newer
- One or more printers running **OctoPrint** (for example on an OctoPi Raspberry Pi)
- **Xcode 16** or newer, to build the app from source

### Build and run

```sh
git clone https://github.com/Dad-and-Ben/OctoMac.git
cd OctoMac
scripts/build-app.sh
open build/OctoMac.app
```

The finished app is at `build/OctoMac.app`. Drag it into your Applications folder to keep it.

You can also open `Package.swift` in Xcode and press Run.

### Add your first printer

1. Click **Add your first printer**.
2. Type the printer's address, such as `octopi.local` or `http://192.168.1.50`.
3. Choose **Request access**. Your browser opens OctoPrint, where you approve OctoMac with one click. (Prefer to paste an API key instead? Choose **Paste a key**.)
4. That's it. Your printer appears in the sidebar.

Your API keys are stored encrypted on your Mac, in your own user folder.

### Just looking?

Try OctoMac without a printer:

```sh
open build/OctoMac.app --args --demo
```

Demo mode shows three pretend printers, including one that's busy printing, so you can explore every screen safely.

## Plugin support

OctoMac works with a standard OctoPrint install, and it gets better with a few popular plugins.

| Plugin | What OctoMac does with it | Status |
| --- | --- | --- |
| [Slicer Thumbnails](https://plugins.octoprint.org/plugins/prusaslicerthumbnails/) | Shows the picture your slicer embeds in each G-code file, in the file list, the file browser, the file info panel and while printing. Works with PrusaSlicer, SuperSlicer, OrcaSlicer, Cura and others. | Supported |
| Application Keys (built in) | Lets you connect a printer by approving OctoMac in your browser, with no copying and pasting of API keys. | Supported |
| Classic Webcam (built in) | Shows your camera stream, including your flip and rotate settings. | Supported |
| Logging (built in) | Used for log file access. | Supported |
| [Prusa MMU](https://plugins.octoprint.org/plugins/prusammu/) | Asks which filament slot to use when you start a print on a printer with a Prusa Multi Material Unit, just like OctoPrint's own prompt. | Coming soon |

Don't have a plugin installed? No problem. OctoMac simply skips that feature. For example, without Slicer Thumbnails your files show a tidy icon instead of a picture.

Want OctoMac to support a plugin you use? Open an issue and tell us about it.

## Good to know

- **Your data stays with you.** OctoMac only talks to the OctoPrint servers you add. There are no accounts, no tracking and no cloud service.
- **Live preview is an estimate.** The animated nozzle follows the part of the file OctoPrint has sent to the printer. Printers keep a few moves in a small buffer, so on short moves the on-screen nozzle can run a fraction of a second ahead of the real one.
- **G-code preview downloads the file.** To show a preview, OctoMac downloads the G-code from your printer. Files are kept in memory while the app is open, so opening the same preview again is instant.

## For developers

OctoMac is written in Swift with SwiftUI, and the 3D preview uses Metal.

| Folder | What's inside |
| --- | --- |
| `Sources/OctoPrintKit` | A standalone Swift library for the OctoPrint REST API, live updates, the Application Keys sign-in flow, and a fast G-code reader |
| `Sources/OctoMac` | The Mac app: printers, screens, the 3D preview and the design system |
| `Tests/OctoPrintKitTests` | Tests for the library. Run them with `swift test` |
| `scripts/` | Build the app, and draw the app icon and logo |

Handy commands:

```sh
swift build                    # build everything
swift test                     # run the tests
scripts/build-app.sh debug     # build a debug copy of the app
```

The OctoPrint API is documented at [docs.octoprint.org](https://docs.octoprint.org/en/main/api/index.html).

## Thanks

OctoMac stands on the shoulders of the wonderful [OctoPrint](https://octoprint.org) project and its community of plugin authors. OctoMac is an independent project and isn't affiliated with OctoPrint.

## Licence

OctoMac is open source under the [MIT Licence](LICENSE).
