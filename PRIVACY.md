# Privacy

OctoMac is built to keep your data on your own Mac and your own network.

## What OctoMac talks to

- **Your OctoPrint servers, and nothing else.** OctoMac only connects to the printers you add. There are no accounts, no analytics, no tracking, no adverts and no OctoMac servers.
- **GitHub, to check for updates**, once a day unless you turn it off in Settings → General. OctoMac fetches the list of versions (`appcast.xml`) and, if you choose to update, downloads the new version from GitHub Releases. Sparkle, the updater, doesn't send any information about you or your Mac.
- **Links you choose to open**, such as a plugin's guide or GitHub, open in your web browser.

## What OctoMac stores

All of this stays on your Mac:

- **Your printers' names and addresses**, in OctoMac's preferences.
- **Your API keys**, in the macOS Keychain, protected by your login password and readable only by OctoMac. If you switch off **Settings → Printers → Keep API keys in the Keychain**, they're kept in `~/Library/Application Support/OctoMac/api-keys.dat` instead, readable only by your user account and encrypted with a key built into the app. Because OctoMac is open source, that built-in key is public, so the file stops a casual look rather than a determined attacker. A proxy sign-in (user name, password or headers) you add for a printer is stored the same way, alongside its API key, and is only ever sent to that printer's address. (If you build OctoMac yourself without a Developer ID, it uses the file by default, as macOS would otherwise ask for Keychain permission after every rebuild.)
- **A small status file for the widgets** in `~/Library/Application Support/OctoMac/Widgets/`: printer names, states, progress, temperatures and a small camera picture. Only OctoMac's own widgets read it.
- **A list of the prints OctoMac has seen finish or fail** in `~/Library/Application Support/OctoMac/History/`: file names, dates, how long they took and how much filament they used, for the statistics in the History tab. It's deleted when you remove the printer.
- **Your plans and notes for each printer** in `~/Library/Application Support/OctoMac/Printers/`: a scheduled print, the print queue, your ratings and notes on files, and earlier bed level measurements. It's deleted when you remove the printer.
- **Your choices**, such as console filters, highlights and notification settings.
- **G-code previews and thumbnails** are kept in memory while OctoMac is open, and are not saved.
- **The last few seconds of each camera** are kept in memory, so you can make a clip of something that just happened. Clips you record are made on your Mac and kept in a temporary folder until you save, copy or share them, or close the clip window; nothing is uploaded.
- **A printer list you export** (File → Export Printers…) holds your printers' names, addresses, colours and any certificate you chose to trust. It never includes API keys or proxy sign-ins.
- **Backups of OctoPrint** stay on the Raspberry Pi, where OctoPrint makes them. When you save one to your Mac, it goes straight to the place you choose. A backup holds OctoPrint's settings, including its own users and API keys, so keep saved copies somewhere safe.

## Notifications

Notifications are shown by macOS on your Mac only. They aren't sent anywhere else. Finished, failed and paused prints, the first layer and your layer alerts include a picture from the printer's camera, which macOS keeps with the notification until you clear it. You can turn the pictures off in **Settings → Notifications**.

## Bug reports

**Help → Report a Problem…** writes a diagnostics file that you can read before sharing. It includes the OctoMac and macOS versions, your Mac's chip, and each printer's OctoPrint version, plugins, firmware and connection state. It leaves out printer names and addresses, API keys, proxy sign-ins, user names and file names. Nothing is sent automatically: you choose whether to attach it to a public [GitHub issue](https://github.com/OctoMac-App/OctoMac/issues), which is the only place we take bug reports.
