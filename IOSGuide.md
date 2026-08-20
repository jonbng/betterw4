# BetterW4 for iOS — the App Store guide

Everything between the tree as it stands today and BetterW4 being live on the App Store, in the
order you have to do it.

This guide was written alongside an App Store readiness pass on **2026-08-18** that fixed six
submission blockers in the code. **§2 is what changed and how it was verified**; everything from §3
onwards is work only you can do — it needs an Apple account, a decision, or a person at the college.

Two companion documents, both still current:

| | |
|---|---|
| `ios/docs/RELEASE.md` | The *reference*: why each privacy answer is what it is, the exact review-note wording, the entitlement trap. This guide tells you what to do; that one tells you why. |
| `ios/docs/W4_PORT_PLAN.md` §0 | What is actually built, wave by wave, including what is verified against the real server and what is not. Read §0.3 before you promise anyone a date. |

---

## Status at a glance

| | |
|---|---|
| Builds | ✅ Debug simulator and Release `generic/platform=iOS`, both clean — after fixing six compile/test breakages that came in with `origin/main` (§2.7) |
| Tests | ✅ 828 passing, 0 failures |
| Gates | ✅ `check-legacy.sh` and `check-english.sh` both exit 0 |
| App icon | ✅ ships (was missing entirely — §2.1) |
| Privacy manifest | ✅ ships (was missing entirely — §2.2) |
| Signed archive | ⛔️ never produced — needs disk space and an SDK check (§0) |
| Permission from the college | ⛔️ not obtained — **the real blocker** (§1) |

---

## 1. Start here: the thing no code change can fix

**BetterW4 is an unofficial client for somebody else's system, and that is the most likely reason
it gets rejected.**

App Store Review Guideline **5.2.1** (Intellectual Property) and **5.2.2** (Third-Party Sites) both
bear on this. Apple's stated position on 5.2.2 is direct:

> *"If your app displays content from a third-party service, make sure you have permission from the
> service to do so."*

BetterW4 scrapes `w4.uwcrcn.no`, an internal system belonging to UWC Red Cross Nordic, renders the
college's data, and is named after the college's product. Every one of those is a fact a reviewer
can establish from the screenshots alone. The mitigations already in the app — an About screen
stating it is unofficial, a single host, no backend, no analytics — are good and worth keeping, but
none of them is permission.

**What to do, in order of how much it helps:**

1. **Get it in writing from the college.** An email from someone at UWC Red Cross Nordic with the
   authority to say it — IT, the head of school, whoever owns W4 — saying they are aware of
   BetterW4, that it is a student-built client for their own students, and that they do not object
   to it being distributed on the App Store. A PDF or a screenshot of that email is what you attach
   in App Store Connect ▸ *App Review Information* ▸ *Attachment*, and reference in the notes.
2. **If they will not put it in writing, ask why.** If the answer is "we would rather you didn't",
   that is the answer — a rejection is the cheaper way to find out, but the relationship is not.
3. **Consider whether the name has to be "BetterW4".** "W4" is the college's system name. A name
   that does not lead with someone else's trademark is a smaller target under 5.2.1. This is a
   judgement call, not a rule; the App Store has plenty of "unofficial client for X" apps.

**The app icon now makes this sharper.** As of `origin/main`, the icon vector is the UWC
twin-globes mark with "W4" — visually very close to UWC's own logo — rather than the abstract owl it
was. That is a branding decision, but it moves an unofficial client closer to the line under 4.1
(impersonation) as well as 5.2.1. Written permission matters more, not less, because of it.

**Do not skip this and hope.** A 5.2.1 rejection is resolved by producing documentation, so you will
end up doing it anyway — just after a rejection is on the record and with the clock restarted.

Be deliberate about the marks you put on the product page as well as in the binary — `logo.png`,
`logo-512.png` and `uwc.svg` at the repository root are all UWC-derived.

---

## 2. What was fixed on 2026-08-18

Six things. Two of them would have failed the upload outright, before a human ever looked at the
app.

### 2.1 The app had no icon at all ⛔️→✅

`ios/AppIcon.icon` is an **Icon Composer** document, and Icon Composer shipped with **Xcode 26**.
This project builds with **Xcode 16.4**, which does not understand the format — it copied the
folder into the app bundle verbatim as an inert resource. The built `.app` contained no
`Assets.car`, no `CFBundleIcons`, and no icon file of any size. The simulator showed a grey
placeholder; App Store Connect would have rejected the upload with **ITMS-90022**, *"missing
required icon file"*.

Fixed by generating a real asset catalogue from the same vector:

- **`ios/scripts/make-appicon.swift`** — renders `AppIcon.icon/Assets/logo 1.svg` onto the light
  gradient background specified in `icon.json`, measures the glyph's actual ink so the mark is
  optically centred rather than centred on its `viewBox`, and writes an opaque 1024×1024 PNG. Uses
  AppKit's native SVG support, so it needs no third-party rasteriser.
- **`ios/BetterW4/Assets.xcassets/AppIcon.appiconset/`** — the catalogue that actually ships.
- `AppIcon.icon` was removed from the Resources build phase but kept in the repository, so the
  vector and its layer recipe survive until the project moves to Xcode 26.

Verified in a Release `.app` built for device:

```
AppIcon60x60@2x.png     120×120   hasAlpha: no
AppIcon76x76@2x~ipad.png 152×152  hasAlpha: no
Assets.car              present
CFBundleIcons           present   (and CFBundleIcons~ipad)
```

The "no alpha" line matters: the App Store rejects an icon with an alpha channel even when it is
fully opaque.

To regenerate after changing the artwork: `ios/scripts/make-appicon.swift`

### 2.2 No privacy manifest ⛔️→✅

Apple has required `PrivacyInfo.xcprivacy` since **1 May 2024** for any app calling a
"required reason" API. There was none. Uploading without it earns an **ITMS-91053**
*"Missing API declaration"* notice and, for a new app, a rejection.

**`ios/BetterW4/PrivacyInfo.xcprivacy`** now declares no tracking, no collected data, and the two
categories the code actually uses — each checked against the tree, not copied from a template:

| Category | Reason | Where |
|---|---|---|
| `…CategoryUserDefaults` | `CA92.1` | `SettingsStore`, `ReviewPromptStore`, `DirectoryRepository`, `DirectoryStore`, `ScheduleStore` |
| `…CategoryFileTimestamp` | `C617.1` | `AttachmentCache` LRU eviction, `OutgoingMessageAttachment` purge, `ReviewEligibility` install age, cache-size reporting |

Disk space, system boot time and active keyboards are deliberately absent — nothing calls them. The
caches measure themselves with `NSURLFileSizeKey`, which is a *file* size and is not in Apple's
disk-space category. Declaring a category you do not use is its own kind of wrong answer.

`CA92.1` is the "app's own defaults only" reason, and it is correct **because** of the next fix.

### 2.3 Every preference was silently discarded on device ⛔️→✅

`SettingsStore` opened `UserDefaults(suiteName: "group.dk.elliottf.betterw4")` against an
entitlements file that declares no app group. The suite was therefore always `nil`, and all fifteen
preference writes went nowhere: theme, calendar style, subject colours and renames, every
notification toggle. On a real device the Settings screen forgot everything on relaunch.

This is a bug a reviewer finds by changing the theme and killing the app, and it had been known
since 2026-08-16 (`W4_PORT_PLAN.md` §0.3 item 1).

Now `UserDefaults.standard`. Nothing shares these preferences with an extension, so the app's own
defaults are the right home; adding the entitlement instead would also have moved the privacy
manifest's reason off `CA92.1`.

### 2.4 The notification feature promised something it did not do ⛔️→✅

> **Updated 2026-08-20 after merging `origin/main`.** Upstream landed the background-refresh work
> (`NotificationRefresh`, `NotificationDiff`, `NotificationBackgroundRefresh`) that this section
> said did not exist. The app now runs **two** notification systems and both are real:
>
> * **Change alerts** — `NotificationRefresh` fetches on a `BGAppRefreshTask`, diffs against the
>   last snapshot and posts when the server disagrees. Covers timetable changes, new/overdue
>   assessments and trips.
> * **Time reminders** — `NotificationScheduler` pre-schedules lesson reminders and "due tomorrow"
>   from cached data, needing no background execution.
>
> Consequently `UIBackgroundModes = fetch` has been **restored** — `BGTaskScheduler` requires it
> alongside `BGTaskSchedulerPermittedIdentifiers`, and with only one of the two the background
> refresh fails at runtime. It is now declared *and* implemented, which is what Guideline 2.5.4
> actually asks for. Only `notifyNewMail` stayed deleted: nothing polls the mailer.
>
> The rest of this section is the original diagnosis, kept because it explains why the toggles
> were audited in the first place.

The old state was, in one sentence: the app asked for notification permission on first launch, told
the student in Settings that *"BetterW4 checks W4 in the background and notifies you on this device
only"*, declared `UIBackgroundModes = fetch`, and never sent a single notification. There was no
`BGTaskScheduler` call anywhere in the codebase. That is a Guideline **2.5.4** problem (declaring a
background mode without implementing it) sitting on top of a **5.1.1** problem (asking for a
permission you do not use).

Rather than delete the feature, it was made real within what the app can honestly do:

- **`ios/BetterW4/NotificationScheduler.swift`** — a pure `NotificationPlanner` plus a thin
  `UNUserNotificationCenter` adapter. Reminders are scheduled *ahead of time* with
  `UNCalendarNotificationTrigger`, from timetable and assessment data the app has already fetched
  and cached. These fire while the app is not running, so **no background mode is needed at all**.
  - **Lesson reminders** fire the configured lead (5/10/15/30 min) before a lesson starts.
    Cancelled, all-day and unplaceable blocks are skipped.
  - **Assessment reminders** fire at 18:00 Oslo the evening before the due day. Items already marked
    done are skipped.
  - The plan is deduplicated, sorted by fire date and capped at 60 — iOS keeps only the 64 soonest
    pending requests and silently discards the rest, so the truncation is done deliberately and
    keeps the soonest.
- **"New mail" and "Timetable changes" were removed**, not fixed. Answering either question means
  fetching W4 on a schedule and diffing the result, which needs background refresh this app does not
  implement. They were write-only switches over nothing. *(Superseded: `Timetable changes` came back
  with upstream's diff engine. `New mail` is still gone.)*
- `UIBackgroundModes` is gone from both build configurations. *(Superseded: restored — see the note
  above.)*
- Permission is now requested **lazily, on first opt-in** in Settings, instead of from the root
  view's `.task` at launch. Verified: the app launches to the login screen with no system prompt.
- The Settings footer now says what actually happens, including *"the app does not check W4 in the
  background."*
- Sign-out clears pending reminders, for the same reason the caches are cleared.
- **`ios/BetterW4Tests/NotificationPlannerTests.swift`** — 16 tests over the rules that would
  otherwise embarrass the app on a lock screen.

### 2.5 Two build settings that would have cost you time ⛔️→✅

- **`DEVELOPMENT_TEAM` disagreed between targets.** The app carried `5L74RXWG44`; the test target
  and `RELEASE.md` carried `9ULRK8DH95`. A mismatch surfaces at archive time as a signing error that
  never mentions the mismatch. Both per-target values are gone; the team is now set once in
  **`ios/Signing.xcconfig`**, applied at project level. **You still have to confirm the value — §3.1.**
- **`ITSAppUsesNonExemptEncryption = false`** added to `Info.plist`, so export compliance is
  answered in the build instead of by hand on every single upload. `false` is correct here: the only
  cryptography is HTTPS via `URLSession` and the Keychain, both Apple-provided and exempt.

### 2.6 A stale Lectio-era strings file was shipping ✅

`BetterW4/en.lproj/Localizable.strings` was 86 lines of keys from the BetterLectio ancestor —
`browser_extension.*`, message reaction keys — for features this app does not have. It shipped in
the bundle. Every `String(localized:)` call site in the app already carries a `defaultValue`, so
deleting it changed nothing on screen.

### 2.7 Six breakages that arrived with `origin/main` (merged 2026-08-20) ⛔️→✅

`origin/main` did not compile. This was verified in isolation — a clean worktree at `6276bd0`, built
on its own, fails — so none of it came from the merge. All six are fixed:

| Where | What | Fix |
|---|---|---|
| `PeopleModels.swift:198` | `DirectoryPersonProfile: Codable` holds `[PersonClass]`, and `PersonClass` was not `Codable`. | Added `Codable` — every stored property is already a `String`/`String?`. |
| `StudentProfile.swift:256` | `String.nilIfEmpty` declared a second time; `BaseParser.swift:70` already has it. Swift rejects it as a redeclaration rather than treating it as a shadow. | Removed the duplicate. The surviving one trims before testing for empty, which is what the rest of that file already does by hand. |
| `W4HouseParser.swift:259` | `item.clone()` — that is jsoup's name; SwiftSoup spells it `copy(with:)` and returns `Any`. The error-typed result produced four further "cannot infer contextual base" errors further down the same function. | `guard let clone = item.copy() as? Element`. |
| `OnDutyView.swift:41` | A `Section` with a `header:`, containing a `ForEach`, nested in another `ForEach`, inside an `if`/`else` in a `List` — the type checker gave up and reported against Charts' `ChartContentBuilder`, a framework that file does not import. | Extracted `OnDutyRoleSection` so the section has a concrete type. |
| `ScreenRenderSmokeTests.swift:64` | `TimetableEvent.init` takes `room` before `teacher`; the call passed them the other way round. | Swapped. |
| `DirectoryViewModelTests.swift:545` | `testSwitchingYearFilterHidesTheOtherYear` failed. Its stub returned every person regardless of which list was requested, but W4 pre-filters server-side — `people/students/firstyear` answers with first years and nobody else. | Made the stub honour the route. The production code was right; the stub was modelling a server that does not exist. |

One more, caught by the gate rather than the compiler: `HouseFlag.swift` folded a literal `å`, which
`check-english.sh` flags as Danish UI text. It is a folding table for Norwegian house names, not
something anyone reads, so it is now written as `\u{00E5}` with a comment saying why.

### Verification, if you want to re-run it

```bash
cd ios

# Gates
./scripts/check-legacy.sh && ./scripts/check-english.sh

# Tests — never pass CODE_SIGNING_ALLOWED=NO to `test`; the Keychain tests
# need the entitlement and fail with -34018 without it. Expect 828 passing.
xcodebuild test -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'

# Release build for device
xcodebuild build -project BetterW4.xcodeproj -scheme BetterW4 \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

---

## 3. Before you can build an archive

### 3.1 Confirm the development team ⛔️

Open **`ios/Signing.xcconfig`** and check the value:

```
DEVELOPMENT_TEAM = 5L74RXWG44
```

That is the team the app target already carried. It is **not** a verified fact — the docs said
`9ULRK8DH95`, and only one can be right. Find yours in **Xcode ▸ Settings ▸ Accounts ▸** your
account (the 10-character Team ID), or at **developer.apple.com/account ▸ Membership details**.

Setting it through the Xcode UI instead is fine — Xcode writes `DEVELOPMENT_TEAM` onto the target,
which overrides the file — but then do it on **both** targets, or you have recreated the bug.

### 3.2 Apple Developer Program membership ⛔️

$99/year, at [developer.apple.com/programs](https://developer.apple.com/programs/). Enrolment can
take a day or two, and an organisation enrolment needs a D-U-N-S number and takes longer. Do this
first if it is not already done.

An individual enrolment publishes under your own legal name, which will be visible on the product
page as the seller. For an app aimed at one college's students that is usually fine; decide
deliberately rather than discovering it at launch.

### 3.3 Register the bundle id

**developer.apple.com/account ▸ Certificates, Identifiers & Profiles ▸ Identifiers ▸ +**

- Bundle ID: **`dk.jonathanb.w4`** (explicit, not wildcard)
- Capabilities: **none**. The app's only entitlement is `keychain-access-groups`, which needs no
  capability toggle. No push, no app groups, no associated domains, no iCloud, no Sign in with Apple.

### 3.4 Two URLs you must supply ⛔️

App Store Connect will not let you submit without them.

- **Privacy policy URL** — required on the product page for every app, including one that collects
  nothing. The app ships an in-app *Settings ▸ Privacy ▸ "What BetterW4 stores"* screen; the
  simplest honest path is to publish that same text as a page (a GitHub Pages file is fine) and use
  its URL. It must state that no data is collected or transmitted to you, and name what is stored
  on the device.
- **Support URL** — a page where a student can reach you. A GitHub repository's issues page counts.

---

## 4. App Store Connect: create the app record

**appstoreconnect.apple.com ▸ My Apps ▸ + ▸ New App**

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `BetterW4` — 30 characters max, must be unique across the whole App Store. Have a fallback ready. |
| Primary language | English (U.K.) or English (U.S.) — the app is English-only by design |
| Bundle ID | `dk.jonathanb.w4` |
| SKU | Any internal string, e.g. `betterw4-ios` — never shown to anyone |
| User access | Full |

Then fill in the product page.

### Category

Primary **Education**. This matches `LSApplicationCategoryType = public.app-category.education`
already in the build. Leave the secondary category empty, or **Productivity**.

### Age rating

Answer the questionnaire honestly and expect **4+**. The app has no objectionable content of its
own. Two questions deserve thought:

- **User-generated content / messaging.** The app *displays* W4 mail between students and staff, but
  it cannot send anything — compose is built and disabled behind `MailFeatureFlags.composeEnabled`
  (`false`). If you ever enable it, revisit this answer, because a messaging surface with no
  moderation or reporting is a Guideline **1.2** problem.
- **Unrestricted web access.** The app opens ManageBac, Google Drive and the college website in
  Safari as ordinary links, and renders some W4 CMS pages in a `WKWebView` scoped to `w4.uwcrcn.no`.
  This is not a browser. Answer "no".

### Description, keywords, subtitle

Say plainly what it is and who it is for. Being explicit about "unofficial" in the description helps
you with Guideline 5.2.1 rather than hurting you — it is what the About screen already says.

A starting point, adjust to taste:

> BetterW4 is a fast, native iPhone and iPad client for W4, the student information system used at
> UWC Red Cross Nordic.
>
> See your timetable, assessments, mail, attendance, grades and campus status without waiting on a
> desktop website that was not built for a phone. Everything is cached, so your week is on screen
> the moment you open the app — even with no signal.
>
> • Timetable — Academics and Extra Academics in one week view, with rotation days and subject
>   colours you can rename and recolour
> • Assessments — calendar or list, with local reminders the evening before something is due
> • Mail — inbox, archive and attachments
> • Attendance, grades, absence and lateness
> • Student and staff directory, trips, documents and your ID card
> • Lesson reminders that fire before class, scheduled on your device
>
> BetterW4 has no server. There is no account to create and no analytics of any kind — the app talks
> to your college's W4 server and nothing else, and everything it knows stays on your phone.
>
> Not sure? Tap "Try demo" on the sign-in screen to explore the whole app with sample data, without
> an account.
>
> BetterW4 is an unofficial app. It is not made by, endorsed by or affiliated with UWC Red Cross
> Nordic.

**Subtitle** (30 chars): `Your W4 timetable, natively` — or similar.

**Keywords** (100 chars total, comma-separated, no spaces after commas, do not repeat the app name
or the category):
`w4,uwc,timetable,school,student,assessments,attendance,schedule,rcn`

### App Privacy ⛔️

**App Store Connect ▸ your app ▸ App Privacy ▸ Get Started.**

Answer **"No, we do not collect data from this app"**, then publish. Every subsequent question
disappears.

This is literally true and the argument is in `ios/docs/RELEASE.md` §2: no backend, no analytics SDK,
one dependency (SwiftSoup 2.11.3) that is a pure HTML parser with no network code, no IDFA, no
`ATTrackingManager`. Apple's definition of "collect" is *transmit off the device*; nothing the app
stores leaves the phone.

Note this answer is separate from `PrivacyInfo.xcprivacy` and they must agree. They do.

---

## 5. Screenshots

⚠️ **Take every screenshot in demo mode.** Never screenshot a real account. The timetable, mail
list, directory and birthdays all show real students' names at a 200-person boarding college, and
those screenshots become a public web page.

Tap **"Try demo"** on the login screen (`LoginView.swift:173`) and work from there.

**Required sizes** — App Store Connect scales down from the largest, so these two sets cover
everything:

| Device class | Simulator | Pixels |
|---|---|---|
| 6.9" iPhone | iPhone 16 Pro Max | 1320 × 2868 |
| 13" iPad | iPad Pro 13-inch (M4) | 2064 × 2752 |

The iPad set is required **because the app ships `TARGETED_DEVICE_FAMILY = "1,2"`**. If you would
rather not do iPad screenshots for 1.0, that is a decision to make now, not later — see §9.

Up to 10 per size; 4–6 good ones beat 10 mediocre ones. Suggested order, which is also roughly the
order a reviewer will explore:

1. **Timetable** — the week view with subject colours. The app's whole reason to exist.
2. **Today digest / day view** — what a student actually looks at between lessons.
3. **Assessments** — month view with items.
4. **Mail** — inbox with a message open.
5. **Grades** or **Attendance** — the meters read well as an image.
6. **Settings ▸ What BetterW4 stores** — quietly reinforces the privacy answer for anyone reading.

Capture from a booted simulator:

```bash
xcrun simctl boot "iPhone 16 Pro Max"
xcrun simctl install booted /path/to/BetterW4.app
xcrun simctl launch booted dk.jonathanb.w4
# tap through to the screen you want, then:
xcrun simctl io booted screenshot ~/Desktop/betterw4-01-timetable.png
```

Take them in **light mode**; the app renders in both, but a consistent set looks deliberate.

---

## 6. Archive, validate, upload

Once §3.1 is confirmed:

1. **Xcode ▸ scheme selector ▸ "Any iOS Device (arm64)"** — you cannot archive to a simulator.
2. Bump the build number if you have uploaded before. `CURRENT_PROJECT_VERSION` is `1` and
   `MARKETING_VERSION` is `1.0`. Every upload needs a **unique** build number for a given version
   string; the marketing version only changes when you want the public version to change.
3. **Product ▸ Archive.**
4. In the Organizer window that opens: **Validate App** first. It runs Apple's checks — icon,
   privacy manifest, entitlements, bitcode-era leftovers — locally, and it is much faster to fix a
   problem here than after an upload.
5. **Distribute App ▸ App Store Connect ▸ Upload.**
6. Wait for processing (usually 5–30 minutes). You will get an email if it fails. Watch for
   **ITMS-90022** (icon) and **ITMS-91053** (privacy manifest) — both are fixed in §2, and both
   reappearing would mean something got reverted.

From the command line, if you prefer:

```bash
cd ios
xcodebuild archive \
  -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'generic/platform=iOS' \
  -archivePath build/BetterW4.xcarchive

xcodebuild -exportArchive \
  -archivePath build/BetterW4.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

You will need to write `ExportOptions.plist` yourself (`method` = `app-store-connect`, `teamID` =
your team). The Xcode Organizer path is less fuss for a first submission.

---

## 7. App Review Information — copy this in

**App Store Connect ▸ your version ▸ App Review Information.**

Leave **Sign-in required** *unchecked*. Do not send Apple a real W4 account: every account is a
named student's identity, mail and attendance record, and its 2FA code goes to that student's phone.
There is nothing to hand over that is both working and safe.

Paste into **Notes**:

> No account is required to review this app.
>
> On the first screen, tap "Try demo" — the button directly below "Log in". That opens a full
> offline session with invented data (timetable, mail, assessments, attendance, grades, trips,
> documents, campus status). Every screen in the app is reachable from it.
>
> Demo mode performs no network requests at all. You can review the entire app in Airplane Mode.
>
> The sign-in form above it is for students of UWC Red Cross Nordic and authenticates against the
> college's own server. We cannot supply a shared account because each one is a named student's
> personal record and is protected by two-factor authentication.
>
> BetterW4 is an unofficial client for W4, the student information system used by UWC Red Cross
> Nordic. It has no backend of its own: no server, no account, no analytics, no telemetry. It talks
> to w4.uwcrcn.no over HTTPS and nothing else, and a runtime host check enforces that before any
> request leaves the device. Everything the app stores stays in the app sandbox.
>
> Notifications are local only. Lesson and assessment reminders are scheduled ahead of time from
> data already on the device; the app performs no background refresh and declares no background
> modes.
>
> [If you have it:] Attached is written confirmation from UWC Red Cross Nordic that they are aware
> of this app and do not object to its distribution.

**Attachment:** the college's written permission from §1, if you have it. This is the single most
valuable thing you can attach.

---

## 8. What review is most likely to ask, and what to say

| Guideline | The question | The answer |
|---|---|---|
| **5.2.1 / 5.2.2** | "Do you have permission to use this third-party service and its content?" | §1. Attach the college's confirmation. Without it, expect this one. |
| **2.1** | "We were unable to sign in." | The reviewer missed "Try demo". Point at it by name and position, and note it needs no network. |
| **5.1.1** | "Why do you ask for notification permission?" | It is asked only when the student turns reminders on in Settings, and it schedules local lesson and assessment reminders. Nothing is sent to a server. |
| **2.5.4** | "You declare a background mode you do not use." | No longer true — `UIBackgroundModes` was removed. If this comes back, something was reverted. |
| **1.2** | "This app has user-generated content with no moderation." | The app cannot send anything. Compose is disabled behind a feature flag; it is a read-only view of the college's own mail system. |
| **4.1** | "Does this impersonate UWC Red Cross Nordic?" | The About screen states it is unofficial and not made by the college; the description says the same; the icon is the app's own artwork, not the college crest. |
| **2.3** | "Your screenshots do not match the app." | Only a risk if you screenshot a real account and then submit demo mode, or vice versa. Be consistent. |

If you are rejected, reply in Resolution Center with specifics rather than resubmitting blindly —
a reply that answers the question is usually faster than a new build.

---

## 9. Decisions worth making before you submit, not after

**iPad.** The app ships for iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) but the UI has only
been smoke-tested at iPhone size — `ScreenRenderSmokeTests` renders 16 screens in light and dark,
which is not the same as somebody looking at them on a 13" canvas. Shipping iPad means a second
screenshot set and a second surface review will exercise. Either spend an hour actually looking at
the app on an iPad simulator, or set `TARGETED_DEVICE_FAMILY = 1` for 1.0 and add iPad in 1.1. The
app still runs on iPad in compatibility mode either way.

**The parsers are largely unverified against the real server.** This is the thing to be honest with
yourself about. `ios/docs/W4_PORT_PLAN.md` §0 and `ios/README.md` say it plainly: there are five real
captures, all from a **holiday week in August 2026 containing zero lessons**. Mail, assessments,
grades, trips, absence lists and **every lesson block** rest on fixtures the team wrote by hand. The
tests verify the parser, not W4.

Nothing about that blocks an App Store submission — the app renders, and empty states are handled.
But the first time a student opens BetterW4 in term time is the first time anyone finds out whether
the timetable parser works on a real timetable, and that is a bad moment to discover in production.
**Strongly consider a TestFlight round with two or three students during a normal school week before
you release publicly.** TestFlight is in the same App Store Connect record and needs no extra
review for internal testers.

**Two write surfaces ship disabled**, and should stay that way until a real round trip is captured:
`AssessmentFeatureFlags.writesEnabled` and `MailFeatureFlags.composeEnabled`, both `false`. A wrong
POST to a college SIS is not a bug you get to take back.

**The login state machine has no tests** (`W4_PORT_PLAN.md` §0.3 item 6). It is 729 lines gating
every other surface. Not a submission blocker; the largest untested risk in the app.

---

## 10. After it is approved

- **Release manually, not automatically.** Choose "Manually release this version" so approval does
  not put it live at 03:00 on a day you cannot answer questions.
- **Phased release** is on by default for updates and is worth keeping.
- **Watch Xcode Organizer ▸ Crashes** for the first week. There is no crash reporter in the app by
  design, so Apple's own is all you have — which is fine, and it is the reason to keep it that way.
- **Availability.** The app is useful to about 200 people in one Norwegian college. Consider
  restricting availability to Norway (and wherever students are over holidays) rather than all 175
  storefronts — it reduces the odds of a reviewer in an unrelated market wondering what W4 is.
- **When you next change the artwork**, re-run `ios/scripts/make-appicon.swift`. When you next add a
  dependency or an Apple API, re-check `PrivacyInfo.xcprivacy` in the same pass — the check is
  static analysis over the binary, so an undeclared call is found every time.

---

## Appendix: the files this pass added or changed

| File | What |
|---|---|
| `ios/BetterW4/Assets.xcassets/AppIcon.appiconset/` | **New.** The icon that actually ships. |
| `ios/scripts/make-appicon.swift` | **New.** Regenerates the icon from the vector. |
| `ios/BetterW4/PrivacyInfo.xcprivacy` | **New.** Required-reason API declarations. |
| `ios/BetterW4/NotificationScheduler.swift` | **New.** Local lesson and assessment reminders. |
| `ios/BetterW4Tests/NotificationPlannerTests.swift` | **New.** 16 tests over the planner's rules. |
| `ios/Signing.xcconfig` | **New.** One team, set once. **Confirm the value.** |
| `ios/BetterW4/Info.plist` | `ITSAppUsesNonExemptEncryption = false`. |
| `ios/BetterW4/SettingsStore.swift` | `UserDefaults.standard`; two dead toggles removed. |
| `ios/BetterW4/SettingsView.swift` | Two toggles removed, footer made true, reschedule on change. |
| `ios/BetterW4/BetterW4App.swift` | Launch-time permission request removed. |
| `ios/BetterW4/ScheduleViewModel.swift` | Schedules lesson reminders after a week loads. |
| `ios/BetterW4/AssessmentsViewModel.swift` | Schedules due-date reminders after a month loads. |
| `ios/BetterW4/AuthenticationViewModel.swift` | Clears pending reminders on sign-out. |
| `ios/BetterW4.xcodeproj/project.pbxproj` | `UIBackgroundModes` removed, icon wired, team unified. |
| `ios/BetterW4/en.lproj/Localizable.strings` | **Deleted.** Stale Lectio-era file. |
| `ios/docs/RELEASE.md`, `ios/docs/W4_PORT_PLAN.md`, `ios/README.md` | Brought in line with the tree. |
