# BetterW4

Unofficial iOS and Android apps for [W4](https://w4.uwcrcn.no/), the student system at
[UWC Red Cross Nordic](https://uwcrcn.no/).

W4 itself is a website. These apps sign in the same way a browser does, then show timetable, mail,
assessments and the rest on a phone. There is no BetterW4 server — the apps talk to `w4.uwcrcn.no`
and store everything on the device.

Not made by, endorsed by, or affiliated with the college.

## Features

- Native login with 2FA
- Combined academics + extra-academics timetable, plus custom events stored on the device
- Mail, assessments, grades, absences
- Student / staff directory, houses, on duty
- Campus status
- Offline cache, plus a demo mode that needs no account

## Repo

| Path | |
|---|---|
| [`ios/`](ios/) | SwiftUI app. See [`ios/README.md`](ios/README.md), and [`IOSGuide.md`](IOSGuide.md) to ship it. |
| [`android/`](android/) | Kotlin + Compose app. See [`android/README.md`](android/README.md). |
| [`extension/`](extension/) | Browser extension (WXT + Preact) for `w4.uwcrcn.no`. See [`extension/README.md`](extension/README.md). |
| [`PROTOCOL.md`](PROTOCOL.md) | How W4's login, cookies and pages actually work. |
| [`PRIVACY.md`](PRIVACY.md) | What the apps store and what they don't. |
| `references/` | Saved W4 pages, and the BetterLectio client these apps were ported from. |

Both apps use the application id `dk.jonathanb.w4`.

## Run it

**iOS** — Xcode 16.4+, iOS 18.5:

```bash
open ios/BetterW4.xcodeproj
```

**Android** — Android Studio, JDK 17+, SDK 36. Open the `android/` folder (not the repo root), then:

```bash
cd android
./gradlew :app:assembleDebug
```

Log in with a real W4 account, or tap demo on the login screen.

**Browser extension** — [Bun](https://bun.sh/), then:

```bash
cd extension
bun install
bun run dev          # Chrome
# bun run dev:firefox
```

## Privacy

No backend, no analytics, no ads. Session cookie and cached pages live on the device. Details in
[PRIVACY.md](PRIVACY.md).
