# Building and running BetterW4 for iOS

Clone to running app. No backend, no API keys, no service accounts — the app talks to
`w4.uwcrcn.no` and nothing else.

## Requirements

| | |
|---|---|
| Xcode | 16.4 or newer (the project is `objectVersion = 77`, which needs Xcode 16+) |
| iOS SDK | 18.5 |
| Simulator | any iPhone on iOS 18.5+ |
| Dependencies | SwiftSoup only, resolved automatically by Xcode |

There is no CocoaPods, no Carthage and no `Package.swift` to bootstrap. Open the project and build.

## Run it

```bash
open ios/BetterW4.xcodeproj
```

Select the **BetterW4** scheme and an iPhone simulator, then ⌘R. The first build spends a few
seconds resolving SwiftSoup.

You land on the login screen. Two ways in:

- **Try demo** — a complete offline session with invented UWC data. No network traffic of any kind.
  This is also the App Review path: a reviewer needs no test account.
- **A real W4 account** — your UWC id (`nc26abcd` shape) and password, then the 2FA code W4 sends.
  The first login on a fresh install always prompts for 2FA because the device id is new.

## Command line

```bash
cd ios

# build
xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO build

# test
xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  test

# just the errors
xcodebuild ... build 2>&1 | grep error:
```

**Do not pass `CODE_SIGNING_ALLOWED=NO` when running tests.** The Keychain needs the
`keychain-access-groups` entitlement, which is only applied to a signed build; without it every
`SecItemAdd` fails with `-34018` and the Keychain tests fail for a reason that has nothing to do with
the code under test.

## The two gates

Both are plain shell, both exit non-zero on failure, and both are cheap enough to run before pushing.

```bash
ios/scripts/check-legacy.sh    # no Lectio hosts or ASP.NET protocol in Swift code
ios/scripts/check-english.sh   # no Danish user-facing text
```

`check-legacy.sh` is the important one. BetterW4 is a port of BetterLectio, and a surviving
`lectio.dk` URL is not a harmless leftover: it would send a W4 session cookie to a third party and
hit a server that cannot answer it. The app also enforces this at runtime — `W4HTTPClient` throws
`W4Error.notPortedToW4` for any host that is not `w4.uwcrcn.no`, so a missed URL fails loudly in
development instead of leaking quietly in production.

Both gates exempt comment lines. A note saying "W4 is Yii, so there is no `__VIEWSTATE` here" is
what stops someone reintroducing it; a gate that forces you to delete your own explanation is a gate
people learn to ignore.

## Signing

`DEVELOPMENT_TEAM` is set to `9ULRK8DH95`. Simulator builds sign ad-hoc and need nothing from you.
For a device build, set your own team on the BetterW4 target — automatic signing handles the rest,
and the only entitlement in play is `keychain-access-groups`.

## Regenerating test fixtures

```bash
python3 ios/scripts/make-fixtures.py
```

This rebuilds `BetterW4Tests/Fixtures/W4/` from the captures in `references/`, replacing every real
UWC id and name with placeholders and refusing to write if anything real survives.

Fixture provenance is marked in each test file and matters when you read a green suite:

- `[V]` — a real capture. Home, the three side-menus and Documents. These assertions are evidence.
- `[I]` — synthesized by us from the Android port and the specs. These verify **our parser**, not
  what W4 emits. Mail, assessments, grades, trips and absence lists are all in this category.

The captured week is a holiday week containing zero lesson blocks, so the timetable's block-level
selectors remain unverified. `testCapturedHolidayWeekHasNoEvents` asserts the empty case deliberately:
if it ever fails, the parser has started inventing events out of grid furniture.

## Project layout

```
ios/
├── BetterW4/              app target — one flat folder, filesystem-synchronized
│   ├── W4Routes, W4HTTPClient, W4LoginClient, CookieManager, KeychainManager   transport + auth
│   ├── W4*Parser.swift                                                          HTML parsers, pure
│   ├── *Repository.swift, W4PageCache, CachePolicy                              data layer
│   └── *View.swift, *ViewModel.swift                                            UI
├── BetterW4Tests/         unit tests + Fixtures/W4/
├── docs/                  the port plan and per-area specs
└── scripts/               the two gates + the fixture generator
```

Xcode uses a `PBXFileSystemSynchronizedRootGroup`, so **adding a file to `BetterW4/` adds it to the
target automatically** — there is no `project.pbxproj` edit and no merge conflict when two people add
files at once.

## Where to look first

- `docs/W4_PORT_PLAN.md` — the master plan, including section 2 where the specs disagreed and how
  each conflict was resolved.
- `docs/spec/parsers.md` — every selector, with a bug register of places the Android port is wrong.
- `docs/spec/reviewer-notes.md` — what is verified against a real capture versus assumed.
- `../README.md` — the W4 protocol brief: routes, the login flow, session-death rules.
