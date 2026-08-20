# BetterW4 for iOS

A native iPhone and iPad client for **W4**, the student information system at
[UWC Red Cross Nordic](https://uwcrcn.no/). It gives a student their timetable, assessments, mail,
attendance and campus status without the college's 2016-era jQuery website.

BetterW4 is a port of [BetterLectio](https://github.com/) — same architecture, different school
system. Lectio's ASP.NET postbacks, school picker and MitID login are gone; W4 is one Yii 1 PHP host
with one cookie.

**It is unofficial.** It is not made by, endorsed by or affiliated with UWC Red Cross Nordic. The
About screen says so.

**It has no backend.** No server of ours, no account, no analytics, no telemetry. The app talks to
`w4.uwcrcn.no` and nothing else, and a runtime host gate makes sure of it. Everything it knows lives
in the app sandbox on the phone.

---

## The four tabs

| Tab | What it is |
|---|---|
| **Timetable** | The combined Academics + Extra Academics week, with rotation days (Day 1–5 / Weekend), the "now" line in `Europe/Oslo`, and a Today digest at the top. |
| **Mail** | The W4 mailer — inbox and archive, message bodies, attachment preview. Compose exists but is disabled (see Status). |
| **Assessments** | W4's assessments calendar, list or month. This is the app's homework surface; W4 has no separate homework/assignments split. Confirm done / Revert to pending exist but are disabled (see Status). |
| **More** | Everything else: Home (birthdays, announcements, the college's configured links), notifications, grades, absence, Extra Academics, the student and teacher directories, trips, documents, the ID card, and settings. |

The campus-status capsule and the notifications bell are toolbar items on every screen, because they
are W4's page chrome rather than a destination.

## Features

- **Native login with 2FA.** Username, password and the one-time code are plain fields posted to
  W4's own Yii form. No WebView anywhere in the auth path. A per-install device id (Keychain, not
  `identifierForVendor`) is what lets W4 skip the code on later launches.
- **Demo mode**, one tap from the login screen. A complete offline session with invented data, zero
  network requests. It is also the App Review path — no test account changes hands.
- **Offline-first.** Every surface is cache-first with a real per-surface TTL. A warm cache renders
  in Airplane Mode; a cold one fetches.
- **Timetable** with subject colours, IB subject mapping (HL/SL aware), an optional school-calendar
  overlay, and week paging behind a self-verifying probe.
- **Attendance** — the Academics and Extra Academics meters from Home, plus the absence and lateness
  lists.
- **Grades** with W4's effort grades and anticipated-grade columns.
- **Directory** of students and staff, with profiles and rate-limited avatars.
- **Trips**, **documents** (the W4 CMS), **campus status**, **notifications bell**.
- **Settings**: theme, calendar style, subject colours and renames, cache controls, and a plain
  "What BetterW4 stores" screen.

**Deliberately not built:** no widgets, no Live Activities, no Mac or Safari target, no ManageBac
scraping, no staff or admissions surfaces, no second language, no school picker. See
`docs/W4_PORT_PLAN.md` §7.

## Build it

Xcode 16.4+, iOS 18.5 SDK, one SPM dependency (SwiftSoup) that Xcode resolves for you. No pods, no
API keys, no service accounts.

```bash
open ios/BetterW4.xcodeproj    # pick the BetterW4 scheme and an iPhone simulator, then ⌘R
```

**`docs/BUILD.md` is the real instructions** — command-line build and test, the fixture generator,
the project layout, and the `-34018` trap that makes Keychain tests fail if you pass
`CODE_SIGNING_ALLOWED=NO` to `test`.

## The gates

Two shell scripts, both cheap, both exit non-zero on failure. Run them before pushing.

```bash
ios/scripts/check-legacy.sh     # no Lectio host, protocol or model concept in Swift code
ios/scripts/check-english.sh    # no Danish user-facing text
```

`check-legacy.sh` is the one that matters. A surviving `lectio.dk` URL would send a W4 session cookie
to a third party; a surviving `gymId` would put a school scope into a cache key at a one-school
college. Both scripts exempt comment lines — a note explaining *why* there is no `__VIEWSTATE` is
what stops someone reintroducing it.

Current state: **759 tests passing, both gates clean.**

---

## Status — read this before you trust a screen

The app builds, launches and renders every screen, in light and dark. That is not the same as being
verified against the real server, and the difference is not evenly distributed.

**We have five real captures**, all taken from a student account in **August 2026 — a holiday week.**
Everything else in the test suite is markup we wrote ourselves.

### Verified against real W4 markup `[V]`

| Surface | Evidence |
|---|---|
| **Home** (`site/index`) | `Fixtures/W4/home.html` — the week grid, greeting, birthdays, announcements, attendance meters, campus dropdown and all 10 configured links. |
| **Documents** (`documents`) | `Fixtures/W4/documents.html` — folder list, ids, breadcrumbs. |
| **The three side-menus** | `academics-menu.html`, `extraacademics-menu.html`, `school-menu.html` — every route the app navigates to came from these. |
| **The login form** | Fetched live on 16 Aug 2026. Four inputs, no CSRF token, no "remember me" checkbox. Asserted inline in `RememberMeTests.testRealLoginFormHasNoRememberField`. |
| **Page chrome** | Identity (`Welcome, …`), the server version, the campus-status option list and the empty notifications container — all extracted from the Home capture. |

### Resting on synthesized fixtures `[I]`

These parsers are tested, and their tests pass. **The tests verify our parser, not W4.** Every one of
these fixtures is markup we invented from the protocol brief and the Android port; each carries a
`SYNTHESIZED — NOT A CAPTURE` header saying so.

- **Mail** — inbox, archive, message body, empty states, pagination. No mailer page has ever been
  captured. Columns are matched by header text rather than position precisely because we are
  guessing at the grid.
- **Assessments** — every `data-assessment-*` attribute name is invented. This is a whole tab resting
  on a hand-written fixture.
- **Grades** — the CSS proves `table.grades`, `th.anticipated` and `.effort-grade-*` exist; the table
  shape around them is assumed.
- **Trips**, **absence and lateness lists**, **people lists**, **document leaf pages**, **the
  notifications fragment with content** — same story.
- **Every lesson block.** This is the big one: **the one captured timetable week is a holiday week
  containing zero lessons.** `.period`, `.inner`, `.datetime`, `.room` and the attendance-marker
  classes have never been seen. The grid *geometry* is proven (900px over 15 hours ⇒ 1px = 1 minute,
  cross-checked against the capture's `Date:` header), and that is the parser's primary path — but
  the blocks that sit on that grid are unverified. `W4TimetableParserTests.testCapturedHolidayWeekHasNoEvents`
  asserts the empty case on purpose: if it ever fails, the parser has started inventing lessons out
  of grid furniture.
- **The 2FA page.** The login form is captured; `site/verify2fa` cannot be fetched without being
  mid-login, so its markup is uncaptured. The app discovers the one-time-code field from the rendered
  form rather than hardcoding a name — a mitigation, not knowledge. There are no tests over the login
  state machine at all.

### Writes are behind feature flags, and off

Nothing in the app POSTs to W4 except campus status. Two write surfaces are built, tested against our
own fixtures, and **disabled**, because their payloads have never been sent to the live server and a
wrong POST to a college SIS is not a bug you get to take back:

| Flag | Where | Turn it on when |
|---|---|---|
| `AssessmentFeatureFlags.writesEnabled` | `AssessmentModels.swift` | one real *Confirm done* round trip has been captured |
| `MailFeatureFlags.composeEnabled` | `ComposeMessageViewModel.swift` | one real `mailer/send&type=freeform` round trip has been captured |

The compose screen and the assessment swipe actions render and behave; they simply have no transport
behind them yet.

### Known defects

The App Store readiness pass on 2026-08-18 closed five of the six: preferences now persist
(`UserDefaults.standard`, not a phantom app-group suite), notifications actually fire
(`NotificationScheduler` schedules lesson and assessment reminders locally; the two toggles that
needed background refresh were removed), permission is asked on first opt-in rather than at launch,
the unused `UIBackgroundModes` is gone, and the stale Lectio-era `Localizable.strings` is deleted.

**Still open:** the login state machine has no tests — 729 lines carrying the ordering bug that
matters most, with nothing asserting it. Full list with file and line references in
**`docs/W4_PORT_PLAN.md` §0.3**.

---

## Where to look next

| | |
|---|---|
| `docs/BUILD.md` | Clone to running app. Start here. |
| `docs/W4_PORT_PLAN.md` | The master plan. **§0 is the current state, wave by wave**, including what diverged from the plan and why. §2 is where the five specs disagreed and how each conflict was settled. |
| `docs/RELEASE.md` | App Store reference: the review path, the privacy answer, entitlements, and what still blocks a submission. |
| `../IOSGuide.md` | **The ordered App Store walkthrough** — what was fixed, what you still have to do, and every App Store Connect field. Start here for a submission. |
| `docs/spec/parsers.md` | Every selector, with a bug register of places the Android port is wrong. |
| `docs/spec/reviewer-notes.md` | Verified versus assumed, in more detail than this page. |
| `../PROTOCOL.md` | The W4 protocol brief — routes, the login flow, cookies, session-death rules. Shared with the Android app. |
