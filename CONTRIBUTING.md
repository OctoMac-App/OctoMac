# Contributing to OctoMac

Thanks for wanting to help! OctoMac is a small, friendly project, and bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Bug reports live in [GitHub issues](https://github.com/Dad-and-Ben/OctoMac/issues), and only there. Please don't send reports by email or anywhere else.

1. In OctoMac, choose **Help → Report a Problem…**. OctoMac writes a short diagnostics file and opens a new issue for you.
2. Describe what you did, what you expected, and what happened instead. Screenshots help a lot.
3. Attach the diagnostics file if you're happy to. Read it first: it's plain text, and OctoMac leaves out anything personal (printer addresses, API keys, user names and file names), but it's your call.

Please don't paste API keys, passwords, printer addresses or anything else private into an issue. Issues are public.

## Suggesting a feature

Open an issue and tell us what you'd like and why. If it's about an OctoPrint plugin, a link to the plugin helps.

## Building OctoMac

You'll need a Mac running macOS 15 or newer and Xcode 16 or newer.

```sh
git clone https://github.com/Dad-and-Ben/OctoMac.git
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
- Write for people, not programmers. Text in the app and the README should be plain, friendly English. Please don't use long dashes; a comma, colon or full stop reads better.
- Run `swift test` and try your change in the app (demo mode is fine) before opening the pull request.

## Releases

Releases are tagged `vMAJOR.MINOR.PATCH` (for example `v0.2.0`), and the version number lives in the `VERSION` file. Maintainers build them with `scripts/release.sh`, which makes a universal app (Apple silicon and Intel) and a disk image. Signing details are kept in a local, untracked `scripts/release.local` file and never committed.

## Code of conduct

Be kind and assume good intent. We're all here because we like making things.
