# Privacy

OctoMac is built to keep your data on your own Mac and your own network.

## What OctoMac talks to

- **Your OctoPrint servers, and nothing else.** OctoMac only connects to the printers you add. There are no accounts, no analytics, no tracking, no adverts and no OctoMac servers.
- **Links you choose to open**, such as a plugin's guide or GitHub, open in your web browser.

## What OctoMac stores

All of this stays on your Mac:

- **Your printers' names and addresses**, in OctoMac's preferences.
- **Your API keys.** By default they're kept in `~/Library/Application Support/OctoMac/api-keys.dat`, readable only by your user account and encrypted with a key built into the app. Because OctoMac is open source, that built-in key is public, so this stops a casual look at the file rather than a determined attacker. If you'd prefer, turn on **Settings → Printers → Keep API keys in the Keychain** to store them in the macOS Keychain instead.
- **Your choices**, such as console filters, highlights and notification settings.
- **G-code previews and thumbnails** are kept in memory while OctoMac is open, and are not saved.

## Notifications

Notifications are shown by macOS on your Mac only. They aren't sent anywhere else.

## Bug reports

**Help → Report a Problem…** writes a diagnostics file that you can read before sharing. It includes the OctoMac and macOS versions, your Mac's chip, and each printer's OctoPrint version, plugins, firmware and connection state. It leaves out printer names and addresses, API keys, user names and file names. Nothing is sent automatically: you choose whether to attach it to a public [GitHub issue](https://github.com/Dad-and-Ben/OctoMac/issues), which is the only place we take bug reports.
