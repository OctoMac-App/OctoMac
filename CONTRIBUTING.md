# Contributing to OctoMac

Thanks for wanting to help! OctoMac is a small, friendly project, and bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Bug reports live in [GitHub issues](https://github.com/OctoMac-App/OctoMac/issues), and only there. Please don't send reports by email or anywhere else.

1. In OctoMac, choose **Help → Report a Problem…**. OctoMac writes a short diagnostics file and opens a new issue for you.
2. Describe what you did, what you expected, and what happened instead. Screenshots help a lot.
3. Attach the diagnostics file if you're happy to. Read it first: it's plain text, and OctoMac leaves out anything personal (printer addresses, API keys, user names and file names), but it's your call.

Please don't paste API keys, passwords, printer addresses or anything else private into an issue. Issues are public.

## Suggesting a feature

Open an issue and tell us what you'd like and why. If it's about an OctoPrint plugin, a link to the plugin helps.

## Building OctoMac

You'll need a Mac running macOS 15 or newer and Xcode 16 or newer.

```sh
git clone https://github.com/OctoMac-App/OctoMac.git
cd OctoMac
scripts/build-app.sh debug     # builds build/OctoMac.app
open build/OctoMac.app
swift test                     # runs the tests
```

No printer handy? Start OctoMac with `--demo`, or choose **Help → Try Demo Mode**. You get four pretend printers to try every screen on.

## Making a change

- Keep pull requests focused: one fix or feature each.
- Match the style of the code around your change. The app is SwiftUI, and the colours, fonts and shared controls live in `Sources/OctoMac/Design`.
- `Sources/OctoPrintKit` is a standalone library for the OctoPrint API. Anything that talks to OctoPrint belongs there, with a test in `Tests/OctoPrintKitTests` where it makes sense.
- Every piece of text people can see must be translatable. In SwiftUI, a string literal in `Text`, `Button`, `Label` and the like already is; text built in code uses `String(localized:)`. Data from OctoPrint or the printer (names, file names, its own messages) is shown as it is with `Text(verbatim:)`. Then run `scripts/extract-strings.sh` to add new text to `Support/Localization/Localizable.xcstrings`, and translate it into every language: `scripts/translations.py export DIR` lists what's missing, and `scripts/translations.py import DIR` merges translation files back in. GitHub Actions fails if any text isn't in the catalog or isn't translated into every language. OctoMac is translated into everything or nothing.
- Write for people, not programmers. Text in the app and the README should be plain, friendly English. Please don't use long dashes; a comma, colon or full stop reads better.
- Run `swift test` and try your change in the app (demo mode is fine) before opening the pull request.
- Every push and pull request is built and tested on GitHub Actions. One of the tests checks that **Help → Report a Problem…** never includes printer names, addresses, API keys, user names or file names, so please keep it passing.

## Releases

Releases are tagged `vMAJOR.MINOR.PATCH` (for example `v0.2.0`), and the version number lives in the `VERSION` file. Maintainers build them with `scripts/release.sh`, which makes a universal app (Apple silicon and Intel) and a disk image. Signing details are kept in a local, untracked `scripts/release.local` file and never committed; copy `scripts/release.local.example` to start one. Updates reach people through Sparkle: `scripts/release.sh --notarize --publish --notes notes.md` signs the disk image with the maintainer's update key (kept in their Keychain, never in the repository), publishes the GitHub release, adds it to `appcast.xml`, and points the Homebrew cask in [OctoMac-App/homebrew-tap](https://github.com/OctoMac-App/homebrew-tap) at the new version.

The website's source is in `website/`, and it uses the screenshots in `docs/screenshots`. `scripts/publish-site.sh` copies it to [OctoMac-App/octomac-app.github.io](https://github.com/OctoMac-App/octomac-app.github.io), which GitHub Pages serves at https://octomac-app.github.io/; run it after changing the site or its screenshots. The site is styled to look like the app, so it uses the same colours, fonts and shapes as `Sources/OctoMac/Design`. (`docs/index.html` only forwards the old address, https://octomac-app.github.io/OctoMac/, to the new one.)

## Code of conduct

Be kind and assume good intent. We're all here because we like making things.
