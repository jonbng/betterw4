# BetterW4 for iOS — master implementation plan

Status: authoritative execution plan. Supersedes the five specs in `ios/docs/spec/` **only where it
says so explicitly** (§2); everywhere else the specs remain the detail reference and this document
tells you which section to follow.

Inputs read in full: `/Users/johannes/Projects/betterw4/README.md` (the W4 protocol brief) and
`/Users/johannes/Projects/betterw4/ios/docs/spec/{client,parsers,features,ui,inventory,reviewer-notes}.md`.

Ground truth re-verified against the working tree on 2026-08-15 23:15 (§1.4) — the tree moved while
the specs were being written, and three of them are already partly stale.

> **Read §0 first.** The plan below is what we intended to build. §0 is what is actually on disk,
> wave by wave, measured on 2026-08-16. Where they disagree, §0 is right and the plan is history.

---

## 0. Reality against this plan — measured 2026-08-16

Everything in this section was checked against the working tree, not remembered. Baseline on the
day of writing:

```
xcodebuild … test        Executed 743 tests, with 0 failures       ** TEST SUCCEEDED **
scripts/check-legacy.sh  clean — 160 Swift files                   exit 0
scripts/check-english.sh clean — 129 Swift files                   exit 0
```

129 app Swift files · 33 test files · 743 tests · 13 parsers · 16 repositories · 21 fixtures, of
which **5 are real captures** and 16 are synthesized.

### 0.1 Wave status

| Wave | Verdict | Evidence (one line) |
|---|---|---|
| **1** Make the tree compile | **PARTIAL** | 1.1/1.2/1.4 done — zero `Supabase`, `Analytics.`, `HomeworkSyncStatus`, `LastSchoolStore`, `SchoolPickerView` references survive and both gate scripts exist and *fail* rather than report. **1.3 did not land for preferences:** `SettingsStore.swift:82,123` still opens `UserDefaults(suiteName: "group.dk.elliottf.betterw4")` against an entitlements file that declares no app group (§0.3, D-1). |
| **2** W4 transport core | **PARTIAL / DIVERGED** | The transport is real, live and host-gated (`W4HTTPClient.swift:248` refuses any host but `w4.uwcrcn.no`), but it is a **rewritten `W4HTTPClient.swift` + `CookieManager.swift`**, not the planned 12-file split — none of `W4HTTPEngine`, `W4Client`, `W4CookieJar`, `W4Chrome`, `W4Multipart`, `W4Errors`, `W4SessionEvents`, `W4SessionController`, `W4LastLoginStore` exists as a file, and `W4Html`/`YiiForm`/`W4Form` are still inside `W4LoginClient.swift` rather than split out per 2.4. The six named suites in 2.8 (`W4RoutesTests`, `W4CookieJarTests`, `W4SessionClassificationTests`, `PriorityRequestLimiterTests`, `YiiFormTests`, `W4DatesTests`) were never written; transport behaviour is covered indirectly by `W4HostGateTests` (4 tests), `RememberMeTests` (11) and the repository suites against stubs. |
| **3** Auth vertical | **PARTIAL — works, built differently** | Login + 2FA succeed against the real server, and the session survives relaunch. But `W4AuthService.swift`, `W4CredentialStore.swift`, `W4ChromeParser.swift`, `OTPView.swift` and `ForgotPasswordView.swift` were never created: `AuthenticationService` survived instead of being deleted, the OTP card is inline in `LoginView`, and identity parsing lives in `W4LoginClient` + `ChromeObserver`. **Forgot password has a route constant (`W4Routes.swift:164`) and no screen.** `W4LoginFlowTests` / `W4ChromeParserTests` and the `login.html` / `verify2fa.html` fixtures do not exist — the whole login state machine is untested. |
| **4** Parsers and domain models | **DONE** | 13 parsers on disk, each `nonisolated`, each with its own fixture-tested suite (`W4TimetableParserTests` … `ICSCalendarParserTests`), and every fixture carries a provenance header. Diverged on one name (§0.2, D-2). |
| **5** Repositories, stores, caches | **DONE** | 16 `*Repository.swift` files, `W4PageCache` + `CachePolicy` with real TTLs, `AttachmentCache` (LRU 50 MB / 100 files) and `MessageCacheManager`; all three cache roots set `isExcludedFromBackup`; each repository has a demo branch. |
| **6** View models + death of the Lectio stack | **PARTIAL / DIVERGED** | Every `W4HTTPClient+*.swift` extension, `ScheduleParser`, `AssignmentParser`, `GradeParser`, `DirectoryParser`, `StudentParser`, `MessageParser`, `MessageSignature`, `BetterW4Links`, `HomeworkStore`/`HomeworkViewModel` and `StudentStore` are gone, and `check-legacy.sh` is clean. **6.7's headline deletion deliberately did not happen** — see §0.2, D-1. |
| **7** Core tab screens | **DONE** | Four tabs (`ContentView.swift:79`): Timetable · Mail · Assessments · More, each in its own `NavigationStack`, with the campus capsule and notifications bell as toolbar items. `AddPrivateEventView` is gone per D-32. Two writes ship disabled behind flags (§0.4). |
| **8** More-tab screens | **PARTIAL — folded into the verticals** | 8.x was never run as its own wave; each screen landed with the vertical that owned its parser and repository. Present: `AbsenceView`, `GradesView` + `SubjectGradeDetailView`, `StudentSearchView` + `StudentProfileView`, `DocumentsView`, `TripsView`, `ExtraAcademicsView`, `StudentCardView`, and `HomeView` (birthdays, announcements and the 10 Links inline). Absent, with no "Coming soon" row either — the IA simply omits them: register-absences, SAT/transcripts/RoP/EE/testimonial, quick links, travel forms, resource bookings, the EA diary/portfolio/CAS/SafetyNet suite, the Letter of Attendance screen, and standalone birthdays/announcements/personal-feeds screens. `FeedsRepository` exists with no UI consumer. |
| **9** App shell, settings, demo, notifications | **PARTIAL** | 9.1 settings structure landed (Appearance · Notifications · Data · Privacy · About · Sign out, including the "What BetterW4 stores" screen that resolves OQ-7) but its own Done criterion — *every preference persists across relaunch* — is **not met**, because of the Wave-1.3 app-group bug. 9.2 demo mode is **DONE** and proven offline by `DemoDataTests.testCatalogueCarriesNoFetchableURLs`. 9.4 review prompt is **DONE** (no feedback sheet, no Play-store events, `ReviewTrigger.privateEventCreated` removed). **9.3 is NOT DONE** and **9.5 is NOT DONE** (§0.3). |
| **10** Sweep, shims, captures, docs | **PARTIAL — this pass** | 10.1 **DONE** (`check-english.sh` exits 0 and fails the build on Danish). 10.2 **DONE** — `gymId` and `PORTSHIM` are at 0 in code (312 at the time this plan was written; 32 by the time the shim-removal pass ran), and the gate now bans them plus `schoolName`. Eight explanatory *comments* still mention `gymId` to record why there is no gym id; the gate exempts comments on purpose. 10.3 **NOT DONE** — no new captures were taken, so 16 of 21 fixtures are still `[I]`. 10.4 **PARTIAL** — `ScreenRenderSmokeTests` renders 16 screens in light *and* dark, but no `.accessibility5` audit and no contrast measurement was performed. 10.5 **DONE** by this pass (this section, `RELEASE.md`, `ios/README.md`, the repo front page). 10.6 **PARTIAL** — `docs/RELEASE.md` is written; no archive has been built or validated. |

### 0.2 Deliberate divergences — what we did instead, and why

**D-1. Plan item 6.7 said delete `W4HTTPClient.swift` and `CookieManager.swift`. They were rewritten
for W4 instead, and they are the live transport.**

The plan treated both as Lectio corpses to be deleted once Wave 2's new engine had taken over. Wave 2's
engine was never written under those names; the port went the other way, gutting the two existing files
and rebuilding them against W4. `W4HTTPClient.swift` (996 lines) is now the W4 request path — the
`W4UserAgent` constants, the redacted request log, the per-task cookie context, the manual redirect
loop, and the host gate that throws `W4Error.notPortedToW4` for anything that is not `w4.uwcrcn.no`.
`CookieManager.swift` is now the `PHPSESSID` jar plus a `WKWebView` cookie-store bridge, because
`W4WebView` needs the session injected to render authenticated CMS pages.

Deleting them today would tear out working authentication. **The names are the only thing left that is
Lectio-era; the contents are not.** If someone renames them later, `W4HTTPClient` → `W4Client` and
`CookieManager` → `W4CookieJar` is the mapping the plan intended — but it is a rename, not a deletion.

**D-2. The grades models needed a `W4` prefix, against rule D-5.**

D-5 says the `W4` prefix is for wire/protocol types only and domain models are unprefixed. The grades
vertical could not follow it: the legacy Lectio grade types occupied the plain names `GradeColumn`,
`GradeCell`, `GradeRow` and `GradesReport`, and `GradesView` was still compiling against them at the
moment the new models had to land. Renaming the old ones first would have broken the build for the
duration; landing the new ones under the same names was a redeclaration error.

So the W4 grades models were prefixed — `W4GradeColumn`, `W4GradeCell`, `W4GradeRow`,
`W4GradesReport`, `W4EffortGrade`, all in `W4GradesModels.swift` — and the legacy types were deleted
afterwards. The prefix is now vestigial: nothing occupies the plain names any more. It is a safe
rename whenever someone wants it, and not worth a red build on its own.

**Smaller divergences, recorded so they are not mistaken for oversights:**

| Plan said | Reality | Why it is fine (or not) |
|---|---|---|
| D-17: demo student id `nc00demo` | `Student.demoStudentId == "demo"`, `classLabel: "3a"` | Works, but the `3a` label is a Lectio-shaped class code on the demo student. Cosmetic; visible in demo mode. |
| D-15: Keychain service `dk.jonathanb.w4` | `dk.elliottf.betterw4` | Bundle id *is* `dk.jonathanb.w4`; only the Keychain service string kept the old name. Renaming it strands existing sessions, so it needs a migration, not an edit. |
| 1.3: add `kSecUseDataProtectionKeychain: true` to every query | not present anywhere | The Keychain works because the `keychain-access-groups` entitlement is applied. Tests pass signed and fail with `-34018` unsigned, which is the same symptom the plan blamed on this flag. |
| 8.4/D-25: new `W4HTMLViewer.swift`, `W4WebView.swift` deleted | `W4WebView.swift` survives, rewritten | Same job, older name: it renders an authenticated W4 page in a `WKWebView` and has no auth role. Used by `HomeView`, `ScheduleView`, `StudentCardView`. |
| 7.5: `MoreView.swift` (new file) | `MoreView` lives inside `ContentView.swift:201` | No behavioural difference. |
| 7.2: `MailboxView.swift`, `MessagesView.swift` deleted | `MessagesView.swift` kept as the mail list | Name only. |

### 0.3 Known defects — five of six fixed in the App Store readiness pass (2026-08-18)

These were written down on 2026-08-16 rather than repaired, because that pass was documentation-only.
Items 1–5 were fixed on 2026-08-18 while preparing the App Store submission — each was a blocker or a
review risk, not just a tidiness point. Item 6 is still open. The original text of each is kept so the
diagnosis is not lost.

1. ~~**Every user preference is silently discarded on a real device.**~~ **FIXED 2026-08-18** —
   `SettingsStore` now opens `UserDefaults.standard`; `appGroupIdentifier` is gone. Original: `SettingsStore.swift:82` declares
   `appGroupIdentifier = "group.dk.elliottf.betterw4"` and line 123 opens
   `UserDefaults(suiteName:)` on it; all 15 preference writes go through that optional. The app has
   **no app-group entitlement** — `BetterW4/BetterW4.entitlements` contains only
   `keychain-access-groups`. This is landmine **G-5**, which Wave 1.3 existed to fix. Theme, calendar
   style, subject colours and every notification toggle are affected. The one-line fix is
   `UserDefaults.standard`; it is one line because the plan already decided it, and it is left undone
   only because this pass does not touch Swift.
2. ~~**The four notification toggles are write-only.**~~ **FIXED 2026-08-18, completed 2026-08-20**
   — Wave 9.3 landed upstream (`NotificationRefresh` / `NotificationDiff` /
   `NotificationBackgroundRefresh`), so timetable-change, assessment and trip alerts are now real
   diff-based notifications on a `BGAppRefreshTask`. Alongside them, `NotificationScheduler.swift`
   schedules `UNCalendarNotificationTrigger` reminders for lessons and assessment due dates from data
   already on disk, so no background refresh is needed. `notifyNewMail` and `notifyTimetableChanges`
   were **removed** rather than backed: both need a scheduled fetch-and-diff the app does not do. The
   Settings footer now says what actually happens. `NotificationPlannerTests` covers the rules.
   Original:
   `notifyNewMail`, `notifyAssessments`, `notifyTimetableChanges`, `notifyLessonReminder` and
   `lessonReminderMinutes` have zero readers outside `SettingsView`/`SettingsStore`. Wave 9.3 never
   landed: there is no `BackgroundRefresh.swift`, no `NotificationScheduler.swift`, no
   `NotificationDiff.swift`, and no `BGTaskScheduler` call anywhere. Meanwhile
   `SettingsView.swift:189` tells the student "BetterW4 checks W4 in the background and notifies you
   on this device only." It does not. Either build 9.3 or delete the section.
3. ~~**The app asks for notification permission on first launch.**~~ **FIXED 2026-08-18** — the
   request moved out of `BetterW4App` entirely; `SettingsView` asks on first opt-in, as 9.3 wanted.
   Original:
   `BetterW4App.swift:28` requests authorisation from `.task` on the root view. The plan wanted it
   requested lazily on first toggle (9.3). Combined with (2), this is a permission prompt with
   nothing behind it — and an App Review question waiting to happen.
4. ~~**`UIBackgroundModes = fetch` is declared and unused.**~~ **RESOLVED 2026-08-20** — removed on
   2026-08-18 when nothing implemented background work, then **restored** when Wave 9.3 landed:
   `BGTaskScheduler` requires the background mode *and* `BGTaskSchedulerPermittedIdentifiers`, and
   with only one of the two `NotificationRefresh` never runs. Declared and used is the state
   Guideline 2.5.4 asks for. Original: `project.pbxproj:367,405` sets
   `INFOPLIST_KEY_UIBackgroundModes = fetch` with no background work to justify it. Remove it or
   implement 9.3 before submitting.
5. ~~**`Localizable.strings` is dead.**~~ **FIXED 2026-08-18** — `BetterW4/en.lproj/` deleted. Every
   `String(localized:)` call site already carried a `defaultValue`, so nothing changed on screen.
   Original: The file is 86
   lines of Lectio-era keys — `browser_extension.*`, `profile_picture.*`, and the `message.*`
   reaction/edit keys Wave 9.5 said to delete — while the whole app has exactly **4**
   `NSLocalizedString` / `String(localized:)` call sites across 129 files. Every string the user
   reads is a hardcoded English literal. That is a defensible choice for an English-only app, but
   then the strings file should go; as it stands it is a stale artefact that will mislead the next
   person. Note also that `check-english.sh` scans Swift only, so it would not catch Danish here.
6. **STILL OPEN — the login state machine has no tests.** `W4LoginClient.swift` is 729 lines carrying the ordering
   bug that matters most — a `verify2fa` page also renders `Welcome,`, so OTP must be classified
   before authenticated — and nothing asserts it. The plan's `W4LoginFlowTests` and its two synthetic
   fixtures were never written. This is the largest untested surface in the app and it is the one
   that gates every other surface.

### 0.4 Writes that ship disabled, on purpose

| Flag | Value | Where | Unblocked by |
|---|---|---|---|
| `AssessmentFeatureFlags.writesEnabled` | `false` | `AssessmentModels.swift:292` | C-3 — one real *Confirm done* round trip |
| `MailFeatureFlags.composeEnabled` | `false` | `ComposeMessageViewModel.swift:39` | C-4 — one real `mailer/send&type=freeform` round trip |
| School-calendar ICS overlay | off, hook only | `TimetableRepository.swift:201` | OQ-8 / C-7 |
| Week paging (`&year=&week=`) | self-verifying probe, `TimetableWeekParamSupport` | `TimetableRepository.swift:151,396` | C-2 |

The plan named a single `W4Feature` namespace for these; no wave owned that type, so each vertical
kept its own flag with the same meaning. Folding them together is a rename.

### 0.5 What is still unbuilt from §1.4's own feature list

v1 ship-blocking items that are **not** in the tree: local notifications for mail / assessments /
timetable changes / lesson reminders (§0.3 item 2), and register-absences. v1.5 items not in the
tree: SAT, transcripts, RoP, EE and testimonial screens; travel forms; resource bookings; the Letter
of Attendance; the personal-feeds screen; the rooms screen. Everything under "Later" in §1.4 remains
later, and none of it has the "Coming soon" placeholder row that 7.5 specified.

---

## 1. What BetterW4 for iOS is

### 1.1 One paragraph

BetterW4 is a single native iPhone/iPad app (bundle id `dk.jonathanb.w4`) that gives a UWC Red Cross
Nordic student their W4 life — timetable, assessments, mail, attendance, campus status — without the
2016-era jQuery website. It logs in natively with username + password + 2FA, holds exactly one cookie
(`PHPSESSID`), scrapes HTML from `https://w4.uwcrcn.no/index.php?r=…`, posts Yii forms and jQuery
`$.post` payloads, caches everything locally, and works offline against that cache. It talks to
nothing else: no backend, no analytics, no account. W4 is the single source of truth.

### 1.2 Locked product decisions (restated, not up for debate)

1. **One shipping target.** iPhone/iPad app `BetterW4`, bundle id `dk.jonathanb.w4`, plus the
   `BetterW4Tests` unit-test target. No Live Activities, no widget extension, no Mac app, no Safari
   extension, no App Clip.
2. **Local-only.** No Supabase, no PostHog/analytics, no in-app feedback, no referrals, no moderated
   profile pictures. Nothing leaves the device except requests to `w4.uwcrcn.no` (plus the public
   school Google-Calendar ICS, if §2 OQ-8 resolves in favour of enabling it).
3. **English only.** One `ios/BetterW4/en.lproj/Localizable.strings`. Every user-visible Danish
   string dies. Dates and week numbering are `en_GB` / ISO, matching W4.
4. **No school picker, no MitID, no ASP.NET postbacks, no `__VIEWSTATE`, no `gymId`.** W4 is one
   host, one school.
5. **Feature scope = the Android BetterW4 app**, delivered with the iOS app's architecture,
   navigation and visual polish. Nothing in this plan adds a feature the Android port does not have;
   several Lectio features are removed because W4 has no analogue.

### 1.3 Tab IA (from `spec/ui.md` §1, adopted)

Four tabs plus a persistent toolbar cluster:

| # | Tab | Root view | Primary routes |
|---|---|---|---|
| 1 | **Timetable** | `ScheduleView` | `site/index`, `academics/timetable/mytimetable`, `extraacademics/timetable/mytimetable` |
| 2 | **Mail** | `MailboxView` | `mailer/inbox`, `mailer/archive`, `mailer/view&id=`, `mailer/send&type=freeform` |
| 3 | **Assessments** | `AssessmentsView` | `academics/deadlines` |
| 4 | **More** | `MoreView` | everything else |

Toolbar (W4 page chrome, so it is app chrome — not a tab): **campus-status capsule**
(`site/setstatus`) and **notifications bell** (`notifications/refresh` + 7 write routes).
There is deliberately **no Home tab**: `site/index` is fetched once and its parts are distributed —
week grid → Timetable, meters → Attendance, birthdays/announcements/links → More, campus → toolbar —
with a compact "Today digest" card at the top of the Timetable tab.

### 1.4 Feature list

**v1 (ship-blocking).** Native login + 2FA + demo mode · combined AC+EA week timetable with rotation
days and the now-line · assessments list/month with Confirm done / Revert to pending · mail inbox +
sent + read + compose with attachments · AC/EA attendance meters and registration lists · campus
status set/read · notifications bell (empty state is normal) · documents CMS browser · Home digest
(greeting, links, birthdays, announcements) · people directory + profiles · settings (theme, calendar
style, subject colours, notifications, clear cache, sign out) · local notifications for mail /
assessments / timetable changes / lesson reminders.

**v1.5.** Grades + SAT + transcripts · trips and travel forms (read-only, then write) · register
absences · resource bookings (read) · school-calendar ICS overlay · personal feeds (copy/add to
calendar) · birthdays screen · announcements + `site/rss` · Letter of Attendance · rooms.

**Later.** EA activities / diary / portfolio / CAS interviews / SafetyNet · subject pages · EE · RoP ·
testimonial · on duty · visitors · admissions. These get "Coming soon" rows in More from Wave 8 so
the IA is stable, and are built when a capture exists.

**Never.** ManageBac scraping (link only, README §7 line 388), staff/administrative surfaces,
message threads/replies/reactions/edits/BBCode/signatures, private calendar events on the server,
absence-percentage maths, the Danish 7-step grade scale, student-card QR.

---

## 2. Reconciliation — where the five specs disagree

Every row is a decision. **D** = decided, binding. **OQ** = genuinely open, with the default to ship
until a capture settles it. Where a spec loses, the reason is one line.

### 2.0 Ground-truth corrections to the specs (verified, not argued)

| # | Correction | Evidence |
|---|---|---|
| G-1 | The tree is **97 app Swift files + 2 test files**, not 94+10. `W4Routes.swift`, `W4DeviceID.swift`, `W4LoginClient.swift` already exist; `BetterW4Tests/` is now `W4FixtureTests.swift` + `SubjectMapperTests.swift` with 5 sanitized fixtures under `BetterW4Tests/Fixtures/W4/`. | `ls`, 2026-08-15 23:15 |
| G-2 | **The only remaining dead-reference cluster is the auth trio.** A probe build with stubs for `Supabase*`, `Analytics`, `HomeworkSyncStatus`, `LastSchool*`, `SchoolPickerView` compiles the whole app. `inventory.md` §A.11's 60+ call sites (LiveActivity, Feedback, Referral, ProfilePicture, BrowserExtension, ShakeListener) are **already gone**. | probe `xcodebuild build` |
| G-3 | `inventory.md` §A.12 (`Color.lessonMappingHue` missing) is **already fixed** — defined at `SettingsStore.swift:438`. | grep |
| G-4 | `inventory.md` §A.14 (`W4HTTPClient+Messages.swift:221` optional-chaining error) **is not a compile error in this tree**; the code type-checks. Do not "fix" it — delete the file with the mailer port. | probe build |
| G-5 | `inventory.md` §A.13 (App Group) is **still live**: `SettingsStore.swift:69,99` uses `UserDefaults(suiteName: "group.dk.elliottf.betterw4")` against an empty entitlements file ⇒ every preference is silently discarded at runtime. Wave 1 fixes it. | grep + `BetterW4.entitlements` |
| G-6 | **New, in no spec:** the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`project.pbxproj:380-381`), Swift 5 language mode, deployment target **iOS 18.5**. Every type is `@MainActor` by default. Parsers, the engine, the gate and the stores must be explicitly `nonisolated` / `actor` or "parse off the main actor" is a lie. | `project.pbxproj` |
| G-7 | `gymId` is down to **312 references in 40 files** and `Student` still carries `gymId`/`pictureId`/`classLabel`/`schoolName`; `School` still exists; `W4Credentials` is already single-`sessionId`; `W4Error` already has `.forbidden`/`.serverConflict` and no `.robotDetection`. | `StudentModels.swift` |
| G-8 | Fixture placeholders are already fixed by `ios/scripts/make-fixtures.py`: signed-in student `nc26abcd` / **"Alex Andersen"**; staff `nc16efgh`, `nc19ijkl`; students `nc25mnop`, `nc25qrst`; unmapped ids → `ncNNzzzz`. `parsers.md`'s `nc00aaa` / "Test Student" assertions are wrong. | `scripts/make-fixtures.py` |

### 2.1 Naming and type-identity conflicts

| # | Conflict | Decision | Reason |
|---|---|---|---|
| D-1 | `client.md` names the URL builder `W4URLs`; `inventory.md` §5.1 names it `W4Urls.swift`; the tree already ships **`W4Routes`** (`W4Routes.swift`, 321 lines, includes host + session-URL classification). | **`W4Routes`** wins. Absorb `client.md` §3's `Route` constant list and encoding rules into it; there is no `W4URLs`, no `W4Hosts.swift`, no `W4Session.swift`. | Code on disk that compiles beats spec prose; the fixture tests already reference it. |
| D-2 | `client.md` `W4HTML` / `W4DeviceIDStore` / `W4LoginForm` vs landed `W4Html` / `W4DeviceID` / `W4Form`. | Landed names win: **`W4Html`, `W4DeviceID`, `W4Form`, `YiiForm`, `W4LoginClient`**. | Same reason; zero behavioural difference. |
| D-3 | `features.md` §1.1 declares `struct W4Session { phpsessid, updatedAt }` while `client.md` §7.3 declares `enum W4Session` for URL classification. Direct collision. | **No type named `W4Session` exists.** URL classification lives on `W4Routes` (`isLoginURL` / `isOTPURL` / `isHomeURL`); the credential type is `W4Credentials { sessionID, additionalCookies }` (`client.md` §4.1). | One name, two meanings, in one module = a compile error waiting to happen. `client.md` is the transport authority. |
| D-4 | `client.md` `W4Student` + `uwcID` vs `features.md` `Student` + `uwcId`. | **`Student`** with **`uwcId`**. | `features.md` defines every downstream model and SwiftData column with that spelling; `Student` already exists in 40 files. |
| D-5 | Domain-model prefixing: `parsers.md` returns `W4Assessment`, `W4Person`, `W4Trip`, `W4MailSummary`, `W4AbsenceMeter`; `features.md` uses `Assessment`, `Person`, `Trip`, `MailMessage`, `AttendanceMeter`. | **Rule:** the `W4` prefix is for wire/protocol types only (`W4Client`, `W4Routes`, `W4Credentials`, `W4Error`, `W4Html`, `W4Form`, `W4Dates`, and every parser `W4XParser`). Domain models the UI consumes are unprefixed (`features.md` naming). **Exception: `W4Notification*` keeps the prefix** because `Notification` is a Foundation type. | Two competing vocabularies in one module is the single largest source of merge pain; one mechanical rule ends it. |
| D-6 | `parsers.md` `W4EventSource {academic, extraAcademic, …}` vs `features.md` `EventSource {academics, extraAcademics, …}`. | **`EventSource { academics, extraAcademics, schoolCalendar, local }`.** | Matches `AttendanceSource` and the W4 menu labels ("Academics", "Extra Academics"). |
| D-7 | Fixture identities: `parsers.md` asserts `nc00aaa` / "Test Student"; the landed sanitizer produces `nc26abcd` / "Alex Andersen". | **Landed sanitizer wins**; all assertions use `nc26abcd` / "Alex Andersen" / `nc16efgh` / `nc19ijkl` / `nc25mnop` / `nc25qrst`. | Fixtures exist; rewriting them to satisfy prose is pure churn. |

### 2.2 Data-model conflicts

| # | Conflict | Decision | Reason |
|---|---|---|---|
| D-8 | `ScheduleEvent` field set: `parsers.md` (`subtitle`, `attendance`, `route`, `rawTooltip`) vs `features.md` (`subject`, `teacherUwcId`, `href`, `notes`). | Union on `features.md`'s spelling **plus** `attendance: LessonAttendance?` and `rawTooltip: String?` from `parsers.md`. Drop `subtitle`/`route` (shims until Wave 10). | `rawTooltip` is bug B3 — `div.period[title]` is proven to exist (`UWCRCN W4.html:279`) and is the likeliest home of teacher/room/notes. Losing it would waste the first term-time capture. |
| D-9 | Event id scheme: `features.md` `"w4-<id>"` vs `parsers.md` B20 source-prefixed `"ac-w4-42"`. | **Source-prefixed.** | AC class 42 and EA group 42 genuinely collide after merge. |
| D-10 | `features.md` `ScheduleWeek.nowMinutesFromStart` parsed from `#current_time top:NNNpx`; `parsers.md` B22 says the attribute was written by JS before the page was saved and the server sends it hidden. | **Never parse `#current_time`.** Delete the field; compute the now-line from `TimeProvider.now` in `Europe/Oslo` against `tt_start_hour`. | B22 is right; parsing it would produce a now-line frozen at 13:34 forever. |
| D-11 | Timezone: `parsers.md` §0.1 proves W4 renders `Europe/Oslo` wall clock; `client.md` §2's `W4Dates` says only "en_GB, calendar day". | **One `W4Dates`** with `zone = TimeZone(identifier: "Europe/Oslo")!`, `locale = en_GB_POSIX`, fixed Gregorian calendar, and the union of both format lists (`d-MMM-yyyy`, `dd-MMM-yyyy`, `d-MMM-yy`, `dd-MMM-yy`, `yyyy-MM-dd`, `d/M/yyyy`, `dd/MM/yyyy`, + `dd-MMM-yyyy HH:mm`). | The 900px/15h ⇒ 1px=1min proof cross-checked against the HAR `Date:` header is the strongest piece of evidence in the whole research set. Never `TimeZone.current`. |
| D-12 | Campus option model: `parsers.md` `{id: DOM id, value: POST value, label}` vs `features.md` `{id: input value, label}`. | **`parsers.md`'s three-field version.** | Bug B6: posting the *label* breaks 2 of 11 options ("On campus" must post `status=on` with no `location`; "Other" must post the free text). |
| D-13 | Absence taxonomy: `parsers.md` `W4AbsenceCategory {absence, lateness, prearranged, medical, present}` vs `features.md` `AttendanceKind {absence, lateness}` + raw `status` string. | **One enum `AttendanceKind { absence, lateness, prearranged, medical, present, unknown }`, plus the raw `status: String` rendered verbatim.** Meter counts come from the meter prose, never from row classification. | Row classes (`tr.prearranged_1`, `tr.medical_1`) are [V] in `css/tables.css`, so they must be representable; but no absence list has been captured, so the raw string is the only thing we can show honestly. |
| D-14 | Grades cell: `parsers.md` `{value, effort}` vs `features.md` `{value, weight}`. | **`{value: String, effort: EffortGrade?}`**, plus `GradeColumn.isAnticipated`. | `.effort-grade-*` and `th.anticipated` are [V] in `css/main.css`; "weight" is Lectio's *Vægt* with zero W4 evidence. |
| D-15 | Credentials storage key: `client.md` `w4.credentials.<studentID>` vs `features.md` `w4.session.<uwcId>`. | **`w4.credentials.<uwcId>`**, service `dk.jonathanb.w4`. Device id is a *separate* item `w4.deviceId` (both specs agree it must never live inside the credentials blob). | Keeps `KeychainManager`'s existing account scheme; one-word edit instead of a migration. |
| D-16 | `features.md` deletes `W4Credentials` wholesale; `inventory.md` §C step 3 says it becomes `{phpSessionId, deviceId}`. | **`W4Credentials { sessionID: String, additionalCookies: [String: String] }`** per `client.md` §4.1, no expiry fields, deny-list on `autologinkeyV2`/`isloggedin3`/`ASP.NET_SessionId`. | `PHPSESSID` has no `Max-Age`/`Expires`; any client-side expiry check is a lie. `additionalCookies` is defensive, not load-bearing. |
| D-17 | Demo student id: `client.md` `"demo"` vs `features.md` `"nc00demo"`. | **`nc00demo`**, `displayName = "Demo Student"`. | Matches the `nc\d{2}[a-z]+` pattern the whole app keys on, including the fixture sanitizer. |

### 2.3 Behavioural conflicts

| # | Conflict | Decision | Reason |
|---|---|---|---|
| D-18 | Timetable week paging: `features.md` §1.2 fetches `?year=&week=`; `parsers.md` §4 marks both params **[U]** and says fetch the bare route and read the week out of the HTML; `inventory.md` says `w4WeekParameter` is unknown. | **v1 fetches the bare route** and derives `(year, week)` from the header `dd-MMM-yyyy` cells (bug B5). Week navigation ships behind a runtime probe: request `&year=&week=`, compare the returned header dates against the requested ISO week; on mismatch, disable prev/next and show only the current week. | Trusting an unverified param silently mislabels every event; the probe is 15 lines and self-verifying. |
| D-19 | Redirects: today the app auto-follows in the delegate *and* has a dead manual branch. | **Delegate returns `completionHandler(nil)`; the engine drives the chain**, max 5 hops, merging `Set-Cookie` per hop. 302/303 after POST → GET without body; 307/308 keep method+body. | README §4.5 line 140: auto-following turns a dead session into 200 login HTML and parsers throw garbage. |
| D-20 | `reviewer-notes.md` §2 says merge cookies *in* `willPerformHTTPRedirection` then decide; `client.md` §6.2 says return `nil` always and let the engine merge. | **`client.md`.** Return `nil` unconditionally; the engine merges from the 3xx response it receives. | One mechanism, no delegate/engine split brain. The 3xx response carries its own `Set-Cookie`. |
| D-21 | `.forbidden` handling. | 401/403 **with** `Login Required` ⇒ `.sessionExpired`; 403 **without** ⇒ `.forbidden`, inline message, **stay signed in**. 409 ⇒ `.serverConflict(body)`. | W4's own `init_ajax.js` does exactly this; a student opening a staff page must not be logged out. |
| D-22 | `ScheduleStore.markMissingAsCancelled`. | **Becomes delete-on-successful-parse**, and only when the fetch produced a real grid (`div.column` count ≥ 8). | The one captured week is a holiday week with zero `.period`; synthesising "cancelled" lessons for every holiday is worse than useless. |
| D-23 | Where chrome (campus status, notification count, identity) is refreshed. | **In `W4Client`**, not in each repository: a single `chromeObserver` hook fires on every HTML response containing `id="user-panel"`, dispatched to a detached `nonisolated` task, feeding `ChromeObserver` → `CampusStatusRepository` / `NotificationRepository`. | `features.md` wants every page fetch to feed it; if that lives in repositories, one forgotten call site silently freezes the campus chip forever. |
| D-24 | ui.md uses `SFSafariViewController` as the fallback for un-parsed W4 pages (trip create, travel forms, resource booking). | **Never for authenticated W4 pages.** `SFSafariViewController` has its own cookie store and will show a login screen. Fallback is: fetch with `W4Client`, render the returned HTML in a `WKWebView` via `loadHTMLString(_:baseURL:)` with JavaScript disabled. `SFSafariViewController` is only for genuinely external links (ManageBac, Google Drive, the college site). | Nobody flagged this; it would have shipped a broken "Plan new trip" button. |
| D-25 | `ui.md` §3.4 deletes `W4WebView.swift`; §4.14 wants a `WKWebView` for the HTML Letter of Attendance. | Both: delete `W4WebView.swift` (a MitID login shell) in Wave 1; add a new, tiny `W4HTMLViewer.swift` in Wave 8 that only does `loadHTMLString` with JS off, no navigation delegate, no cookies. | README §4.4 bans a WebView *for auth*, not for rendering bytes we already fetched. |
| D-26 | Attachment limits: code says 10 × 25 MB. | **5 files × 2 MB** (README §5.2), enforced in the picker and again before upload. | Server limit. |
| D-27 | Where per-wave tests live. | Every wave writes the unit tests for what it lands; **Wave 10 is fixture completion + CI gates**, not "write all the tests at the end". | A parser landed without its fixture test is not done. |
| D-28 | Migration mechanics across waves. | **No file is deleted until its last caller is gone**, and every model change in Waves 4–6 is *additive with a deprecated compatibility shim* marked `// PORTSHIM` (e.g. `var subtitle: String { subject }`). Wave 10 removes every `PORTSHIM` and a CI grep fails the build if any survive. | This is what makes the build gate green at every wave boundary while 8 people work in parallel. Without it, Waves 4–6 are one giant red interval. |
| D-29 | The old Lectio HTTP stack. | `W4HTTPClient.swift`, `CookieManager.swift` and the seven `W4HTTPClient+*.swift` extensions **stay, frozen and unedited**, until the last caller is ported (Wave 6). The new engine is added alongside in Wave 2. Nobody edits the frozen files. | They are dead at runtime the moment Wave 3 lands (no Lectio session can exist), so double stacks cost nothing and buy a green build every wave. |
| D-30 | Concurrency posture (G-6). | Parsers are `nonisolated enum`s over `String`; domain models are `Sendable` value types; the engine/gate/caches are `actor`s; stores are actors or `@ModelActor`; only view models and views are `@MainActor`. Do **not** change `SWIFT_DEFAULT_ACTOR_ISOLATION`. | Flipping the build setting would silently move 90 files off the main actor. Explicit `nonisolated` is auditable. |
| D-31 | `MessageSignature` ("Sent with BetterW4"). | **Deleted**, with `BetterW4Links.swift`. | Decision 2 killed the growth loop; W4 mail goes to real staff inboxes. |
| D-32 | `AddPrivateEventView` / local private events. | **Deleted in Wave 7** and *not* replaced by a device-local overlay in v1. | `features.md` keeps the model "labelled honestly"; `ui.md` deletes it. Deleting is right for v1: a calendar entry that exists only on one phone, in an app whose whole promise is "W4 is the truth", is a support burden. Revisit post-v1. |
| D-33 | Review prompt. | **Keep** `ReviewEligibility` / `ReviewPromptStore` / `ReviewPromptSheet` / `AppStoreReviewLauncher`; rewire `onNegative` to dismiss + suppress 90 days (it currently opens the deleted feedback sheet). Keep the `bl_review_prompt.` key prefix. | Cheapest retained feature in the tree; renaming the prefix only resets counters. |
| D-34 | `TabBarSameTabReselectDetector` hardcodes index 2. | Keep the constant, rename it `AssessmentsTabBarIndex` — Assessments is still index 2 in the new 4-tab order. | Happy accident; no logic change. |

### 2.4 Open questions (ship the default, replace on capture)

| # | Question | Default we ship | Capture that settles it |
|---|---|---|---|
| OQ-1 | OTP field name / form action / submit button on `site/verify2fa`; does `PHPSESSID` rotate; is there a "trust this device" control? | Dynamic discovery, already implemented in `W4LoginClient` (`W4Form` picks the first non-hidden, non-`LoginForm` input whose name matches `/otp\|totp\|2fa\|code\|token\|pin\|sms\|verify\|authenticator\|one[-_]?time/`, else the sole candidate). | C-1: HAR of one full login. |
| OQ-2 | Timetable `&year=&week=` paging. | D-18's self-verifying probe; current week only if it fails. | C-2: `academics/timetable/mytimetable` for a non-current week. |
| OQ-3 | Every `data-assessment-*` attribute name (all invented by the Android port; the Android fixture is hand-written). | Parse what matches, render nothing when nothing matches, **writes disabled behind `W4Feature.assessmentWrites = false`** until C-3 lands. | C-3: `academics/deadlines` in term time + one *Confirm done* request/response. |
| OQ-4 | Mailer grid columns, unread marker, attachment marker, `mailer/view` body container, pagination. | Header-driven column matching (never positional); `#content_inner` minus breadcrumb for the body; `div.pager` present ⇒ show "More on W4" instead of silently truncating. | C-4: `mailer/inbox` with >1 page + one `mailer/view`. |
| OQ-5 | Letter of Attendance: `%PDF-` bytes or ~600 KB HTML? README says HTML; the Android port hard-fails without `%PDF-`. | Sniff `Content-Type` **and** magic bytes; PDF → QuickLook + share, HTML → `W4HTMLViewer` + "Save as PDF" via `UIPrintPageRenderer`. | C-5: `people/students/letter/attendance` headers + first bytes. |
| OQ-6 | `notifications/refresh` fragment markup. | Parse defensively; **an empty `div.notifications` is the normal state**, not a failure; accept a full container, a bare `.btn-group`, or an anonymous wrapper. | C-6: one refresh response with a non-zero badge. |
| OQ-7 | Privacy-policy URL (Android's is a Danish page for a Danish product). | Ship an in-app **"What BetterW4 stores"** screen only; no external link. App Store submission needs a real URL from the owner. | Owner decision, not a capture. |
| OQ-8 | Is `calendar@uwcrcn.no` really the Home `#calendar` iframe source? The saved `embed.html` is blank. | School-calendar ICS overlay ships **off by default** with a Settings toggle; on = one 6 h-cached fetch to `calendar.google.com`. | C-7: the Home iframe `src` attribute. |
| OQ-9 | Does opening `mailer/view` clear the email notification server-side? | After a successful open, POST `notifications/read` when a matching `notification_id` is known; refetch the bell. Never guess the id. | C-6 / C-4. |
| OQ-10 | Absence-register per-slot checkbox names. | Screen ships as a "Coming soon" row; the generic `YiiForm` scraper is written and tested against a synthetic Yii form so the screen is a 1-day job once captured. | C-8: `people/students/absences/register` on a real timetable day. |
| OQ-11 | Trip create / travel form / resource booking / EA diary outcome / SafetyNet report POST payloads. | Read-only screens; write affordances render the fetched W4 page in `W4HTMLViewer` (D-24) with an explanatory note. | C-9…C-12. |
| OQ-12 | Grades table shape (`table.grades` + `th.anticipated` + `.effort-grade-*` are [V] in CSS, the rest is guessed). | Selector ladder `#content_inner table.grades` → `.grid-view table.items` → `table`, dynamic header-slug columns, degrade to "No grades found". | C-13: `academics/grades/grades`. |

---

## 3. The wave plan

**How to read this.** Waves are sequential; the build gate (§4) must pass at the end of each wave.
Inside a wave, items are parallel-safe: **no file is owned by two items in the same wave**, so each
item can be a separate engineer and a separate branch. A file may be owned by different items in
*different* waves — that is expected. Where an item must land after a sibling (deletions that orphan
callers), it says "lands last".

Path prefix for everything below: `/Users/johannes/Projects/betterw4/ios/`.
`(new)` = create, `(delete)` = remove from disk (no project edit needed — the target uses
`PBXFileSystemSynchronizedRootGroup`).

**Deletion rule (applies to every wave).** A file may only be deleted by the item that owns *every*
remaining caller, or by an item in a later wave. If your deletion would orphan a caller that no item
in your wave owns, **do not delete it** — leave the file, and move the deletion into the next wave's
teardown item. The gate is green code, not a completed checklist. The file lists below were derived
from a real caller graph on 2026-08-15; re-run `command grep -rl '\bTypeName\b' BetterW4/*.swift`
before deleting anything, because the graph moves as waves land.

---

### Wave 1 — Make the tree compile (excision only, no W4 work)

Goal: `build`, `build-for-testing` and `test` all green. Nothing here is W4 protocol work; it removes
the last of the pruned-subsystem references and the two runtime landmines.

**1.1 — Auth-surface excision** · spec: `inventory.md` §A.1–A.6, §A.11; `client.md` §8.7
Files: `BetterW4/AuthenticationService.swift`, `BetterW4/AuthenticationViewModel.swift`,
`BetterW4/LoginView.swift`, `BetterW4/W4WebView.swift` *(delete)*.
Delete `import Supabase`, `SupabaseAuthService`/`SupabaseManager`/`SupabaseStudentProfileService`/
`SupabaseSchoolService`, all 28 `Analytics.*` calls, `LastSchoolStore`/`LastSchoolHint`/
`LastSchoolReason`, `SchoolPickerView`, the MitID sheet, the resume branch, the `.robotDetection`
case reference at `AuthenticationViewModel.swift:430`, and the off-main
`CookieManager.clearAllWebViewData()` call in `wipeAuthState()`. `LoginView` becomes a plain
username/password form whose submit throws `W4Error.parsingError("Not ported yet")` — Wave 3 wires it.
**Done:** no reference to any of those symbols survives (`command grep`), `build` green.

**1.2 — Homework sync excision** · spec: `inventory.md` §A.7, §A.9
Files: `BetterW4/HomeworkStore.swift`, `BetterW4/HomeworkViewModel.swift`.
Delete `mergeRemoteDoneStates` / `mergeRemoteDoneStatesAsync` (the `HomeworkSyncStatus` type does not
exist) and any caller.
**Done:** `HomeworkSyncStatus` returns zero grep hits; `build` green.

**1.3 — Preferences, Keychain and plist hygiene** · spec: `inventory.md` §A.13, §A.16; `features.md` §2.2–2.3
Files: `BetterW4/SettingsStore.swift`, `BetterW4/KeychainManager.swift`, `BetterW4/Info.plist`,
`BetterW4/BetterW4.entitlements`.
Replace `UserDefaults(suiteName: "group.dk.elliottf.betterw4")` with `UserDefaults.standard` and
delete `appGroupIdentifier`; set the Keychain `service` to `dk.jonathanb.w4`; add
`kSecUseDataProtectionKeychain: true` to every Keychain query (this is what causes
`errSecMissingEntitlement (-34018)` and the test-host crash); delete the `isloggedin3` migration.
**Done:** a preference written then re-read survives a relaunch in the simulator; `test` no longer
crashes on launch.

**1.4 — Build gates and CI scripts** · spec: this document §4
Files (all new): `scripts/build.sh`, `scripts/test.sh`, `scripts/check-legacy.sh`,
`scripts/check-english.sh`, `docs/BUILD.md`.
`check-legacy.sh` greps with `command grep` (never `rg` — `ios/.gitignore` makes ripgrep return zero
hits, `inventory.md` §0) for `lectio.dk`, `.aspx`, `ASP.NET_SessionId`, `autologinkey`, `__VIEWSTATE`,
`gymId`, `MitID`, `PORTSHIM` and prints counts; it **reports** in Waves 1–9 and **fails** in Wave 10.
`check-english.sh` greps string literals for `[æøåÆØÅ]` plus the Danish word list in `ui.md` §5.2.
**Done:** `./scripts/build.sh` and `./scripts/test.sh` exit 0; the two check scripts run and print a
baseline (expect ~312 `gymId`, ~39 files with `æøå`).

> **Gate G1:** `build` + `build-for-testing` + `test` green. *This is the checkpoint the whole plan
> hangs from — do not start Wave 2 before it.*

---

### Wave 2 — The W4 transport core (additive; the Lectio stack stays frozen)

Goal: a complete, tested W4 client that nothing calls yet. Per D-29 nothing in
`W4HTTPClient.swift` / `CookieManager.swift` / `W4HTTPClient+*.swift` is touched.

**2.1 — Engine, gate, logging, request/response models** · spec: `client.md` §6, §9
Files (new): `BetterW4/W4HTTPEngine.swift`, `BetterW4/W4RequestGate.swift`,
`BetterW4/W4RequestLog.swift`, `BetterW4/W4Models.swift`.
Port `PriorityRequestLimiter` (copy from `W4HTTPClient.swift:606-703`, keep the cancellation
handshake and 100 ms gap, add Android's 90 s acquire timeout), the 3-attempt loop with jitter, the
redirect loop per D-19/D-20, the status classification table (`client.md` §6.5), the `URLSession`
config with cookies fully disabled, `W4Request`/`W4Response`/`FetchPriority`/`W4Credentials`.
Delete nothing; add `nonisolated`/`actor` annotations per D-30. No manual `Accept-Encoding`.
**Done:** engine drives a scripted `URLProtocol` through 302→302→200 with per-hop cookie merge.

**2.2 — Cookie jar** · spec: `client.md` §5
Files (new): `BetterW4/W4CookieJar.swift`.
Host gate, `PHPSESSID`-only with the empty-value guard, `nil`-on-unchanged, Lectio-cookie deny-list,
redacted preview.
**Done:** the 9 `W4CookieJarTests` in §5 pass.

**2.3 — Client façade, chrome writes, multipart** · spec: `client.md` §7, §7.5
Files (new): `BetterW4/W4Client.swift`, `BetterW4/W4Chrome.swift`, `BetterW4/W4Multipart.swift`.
`get` / `postForm` / `postAjax` / `postMultipart(bodyFile:)` / `postYiiForm` / `getData` / `url`;
credential resolution (`client.md` §7 steps 1–3); the demo hard gate; the D-23 `chromeObserver` hook;
campus + 8 notification helpers; streaming multipart from a temp file with the 256 KB chunk loop,
generalised to repeated `MailerForm[attachment][]` parts.
**Done:** `postAjax` sets `X-Requested-With`; `setCampusStatus(onCampus: true)` sends no `location` key.

**2.4 — HTML + form toolkit (split the landed monolith)** · spec: `client.md` §7.1–7.4; `parsers.md` §9
Files: `BetterW4/W4Html.swift` *(new)*, `BetterW4/YiiForm.swift` *(new)*, `BetterW4/W4Form.swift`
*(new)*, `BetterW4/W4LoginClient.swift` *(trim to the state machine)*, `BetterW4/BaseParser.swift`.
Move `W4Html`, `YiiForm`, `W4Form` out of `W4LoginClient.swift` into their own files (Wave 3 and
Wave 4 both need them and must not fight over one file). Extend `YiiForm` with the checkbox/datepicker
metadata `parsers.md` §9 needs. Strip `isRobotDetectionPage` and the Danish strings from `BaseParser`.
**Done:** the three types are in their own files; `W4LoginClient.swift` is < 200 lines; grep for
`RobotDetection` is empty.

**2.5 — Routes and dates** · spec: `client.md` §3, §2; `parsers.md` §0.1–0.2
Files: `BetterW4/W4Routes.swift`, `BetterW4/W4Dates.swift` *(new)*.
Add the full `Route` constant list (`client.md` §3.3), assert the encoding quirks (literal `/` inside
`r`, `%20` never `+`, deterministic key order, `r` first, inline sibling splitting). `W4Dates` per D-11.
**Done:** the 11 `W4RoutesTests` and the `W4DatesTests` in §5 pass, including under a forced `da_DK`
locale and an `America/New_York` default timezone.

**2.6 — Identity, session and error types** · spec: `client.md` §4.4, §8.3–8.4; `features.md` §1.1
Files: `BetterW4/StudentModels.swift`, `BetterW4/W4Errors.swift` *(new)*,
`BetterW4/W4SessionEvents.swift` *(new)*, `BetterW4/W4SessionController.swift` *(new)*,
`BetterW4/W4LastLoginStore.swift` *(new)*.
`Student` gains `uwcId`, `year`, `house`, `photoURL`; `gymId` becomes a **`// PORTSHIM` computed
`var gymId: Int { W4School.id }`** and `School` becomes `enum W4School { static let id = 1; static let
name = "UWC Red Cross Nordic" }` with a `// PORTSHIM` `School` typealias — this is what stops the 312
`gymId` references from becoming one big-bang edit (D-28). `W4Error` moves out, English only, keeps
`.forbidden`/`.serverConflict`, gains `.invalidOTP`/`.keychain(OSStatus)`.
**Done:** `build` green with `gymId` still referenced everywhere but no longer meaningful; the
session-expired notification name is `dk.jonathanb.w4.sessionExpired`.

**2.7 — Avatar loading retarget** · spec: `client.md` §9.6
Files: `BetterW4/W4ImageLoader.swift`, `BetterW4/RateLimitedAvatarImage.swift`.
Host → `w4.uwcrcn.no`, UA/Referer → `W4UserAgent`, avatars → `/files/user_photos/{uwcId}_thumb.jpg`,
`/images/user.png` ⇒ `nil`, drop the Lectio `defaultfoto_small.jpg` retry, keep the opportunistic gate,
NSCache, in-flight dedup and downsampling.
**Done:** no `lectio.dk` reference; `isW4URL` requires https + `W4Routes.isW4Host`; **and
`W4ImageLoader` no longer references `CookieManager`** (it reads `W4Credentials` through
`W4CredentialStore`) — that is the last non-frozen consumer, which is what lets 6.7 delete
`CookieManager.swift`.

**2.8 — Transport tests + URLProtocol harness** · spec: `client.md` §10 tests 1–45
Files (new): `BetterW4Tests/W4URLProtocolStub.swift`, `BetterW4Tests/W4RoutesTests.swift`,
`BetterW4Tests/W4CookieJarTests.swift`, `BetterW4Tests/W4SessionClassificationTests.swift`,
`BetterW4Tests/PriorityRequestLimiterTests.swift`, `BetterW4Tests/YiiFormTests.swift`,
`BetterW4Tests/W4DatesTests.swift`.
**Done:** all pass; the 403-without-`Login Required` test asserts **no** session-expired notification.

> **Gate G2:** `build` + `test` green. Two HTTP stacks coexist; only the new one is tested.

---

### Wave 3 — Auth vertical (this wave unblocks every capture)

Goal: a real login against `w4.uwcrcn.no`, so the team can take captures C-1…C-13.

**3.1 — Login client, device id, auth service** · spec: `client.md` §8.2, §8.5, §8.6
Files: `BetterW4/W4LoginClient.swift`, `BetterW4/W4DeviceID.swift`, `BetterW4/W4AuthService.swift`
*(new)*, `BetterW4/AuthenticationService.swift` *(delete, lands last)*.
GET `site/login` with `allowLoginPage` → parse the real form → POST
`LoginForm[username|password|deviceId]` + `yt0` → classify **OTP before authenticated**
(`W4LoginClient.kt:138`; the 2FA page renders `Welcome,` too) → OTP POST → `finishLogin` (identity,
save credentials *before* the confirmation GET, confirm with `site/index`). Device id: Keychain,
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never logged, never `identifierForVendor`.
`coldStartValidate`: only `.sessionExpired`/`.invalidCredentials`/`.missingCookies` log out.
Logout: fire-and-forget `site/logout` with `allowLoginPage: true`, then `wipeAll()`.
**Done:** a real student account logs in on device, survives app relaunch, and `Log out` returns to
the login screen with the username prefilled.

**3.2 — Login UI** · spec: `ui.md` §4.0; `client.md` §8.7
Files: `BetterW4/LoginView.swift`, `BetterW4/OTPView.swift` *(new)*,
`BetterW4/ForgotPasswordView.swift` *(new)*, `BetterW4/AuthenticationViewModel.swift`.
Username (`maxlength 16`, `.username`, no autocaps), password (`.password`, show/hide), **Log in**,
**Try the demo**, **Forgot password** (`site/forgotpass`, `ForgotPassForm[username]`, `yt0=Reset`);
OTP screen with `.oneTimeCode` + number pad. Server error text shown verbatim from
`.errorSummary li` → `.errorSummary` → `.errorMessage` → generic. Never auto-retry a failed login.
**Done:** all three screens are English, VoiceOver-labelled, and behave on a wrong password, a wrong
OTP and offline.

**3.3 — Credential store protocol** · spec: `client.md` §8.1
Files: `BetterW4/KeychainManager.swift`, `BetterW4/W4CredentialStore.swift` *(new)*.
Protocol + `KeychainManager` conformance + `InMemoryCredentialStore` for tests. Keys per D-15.
**Done:** `InMemoryCredentialStore` drives the login-flow tests with zero Keychain access.

**3.4 — Chrome/identity parser** · spec: `parsers.md` §1
Files (new): `BetterW4/W4ChromeParser.swift`.
`parseIdentity` (`#user-panel .right` ownText → `/Welcome,\s*([^|<]+)/`; uwc id from
`#content_inner a[href*=people/students/student][href*=uwc_id]` whose text contains "profile" — **not**
the first `nc\d{2}[a-z]+` in the document, bug B17), `parseSideMenu`, `parseServerVersion`,
`contentInner`.
**Done:** against `Fixtures/W4/home.html`: `("nc26abcd", "Alex Andersen")`, version `25.9.1`,
`parseSideMenu` = `[]` on Home; against `academics-menu.html`: 4 sections, 13 items in section 0,
`items[1].route == "academics/timetable/mytimetable"`.

**3.5 — Auth tests** · spec: `client.md` §10 tests 46–62
Files (new): `BetterW4Tests/W4LoginFlowTests.swift`, `BetterW4Tests/W4ChromeParserTests.swift`,
`BetterW4Tests/Fixtures/W4/login.html`, `BetterW4Tests/Fixtures/W4/verify2fa.html` *(both synthetic,
each with a leading `<!-- SYNTHESIZED, not a capture -->` comment)*.
**Done:** the ordering-bug guard passes — a page that is on `site/verify2fa` **and** contains
`Welcome,` classifies as `.needsOTP`, not `.authenticated`.

> **Gate G3:** `build` + `test` green **and** a manual login on a real device/simulator reaches Home.
> **Immediately after G3, take captures C-1…C-13 (§5.1).** Waves 4+ are materially better with them.

---

### Wave 4 — Parsers and domain models (purely additive; maximum parallelism)

Goal: every v1/v1.5 parser exists, is `nonisolated`, is fixture-tested, and returns final domain
models. Nothing here calls the network or SwiftData. Legacy parsers/models stay until Wave 6/7 orphans
them (D-28/D-29); new domain types live in new files, and where a name is reused the legacy type gains
`// PORTSHIM` bridging members instead of being renamed.

**4.1 — Timetable** · spec: `parsers.md` §4; `features.md` §1.2; D-8/D-9/D-10/D-18
Files (new): `BetterW4/W4TimetableParser.swift`, `BetterW4/HTMLContentRenderer.swift`;
edit: `BetterW4/ScheduleModels.swift`.
Inner-grid selection via `select("div#timetable").last()` (bug B1 — Home has **two** `id="timetable"`),
day columns = `.column` without `.cell` descendants, header `dd-MMM-yyyy` is the truth (B5), pixel
geometry `1px = 1min` from `tt_start_hour`, `.period[title]` captured raw into `rawTooltip` (B3),
`no-classes` by **class** not text (B4), source-prefixed ids (B20), em dash U+2014/U+2013/`-` all
accepted. `HTMLContentRenderer` is the salvaged `parseLessonContent`/`parseInlines` renderer, reused by
mail and documents.
**Done:** against the real Home capture — 7 days, `days[0].date == 2026-08-10` Oslo, `Day 1`,
`days[5].rotationDay == "Weekend"`, `eaNote == "No EA"`, **zero events**, week 33/2026, hours 7–22,
exactly one `isToday`; and the same assertions hold with the device timezone forced to
`America/New_York`.

**4.2 — Assessments** · spec: `parsers.md` §6; `features.md` §1.3; OQ-3
Files (new): `BetterW4/W4AssessmentParser.swift`, `BetterW4/AssessmentModels.swift`.
`a.assessment-link[data-assessment-*]`, both `month=` regex forms (B11), `parseAjaxURLs`,
`statusFields` keyed by kind (`assessment_id` vs `student_assessment_id`).
**Done:** synthetic fixture parses 2 items with the documented values; the empty-calendar fixture
returns `[]` without throwing; the test file carries the "verifies the parser, not W4" comment.

**4.3 — Mailer** · spec: `parsers.md` §7; `features.md` §1.4; OQ-4
Files (new): `BetterW4/W4MailerParser.swift`, `BetterW4/W4MailDetailParser.swift`,
`BetterW4/MailModels.swift`.
Header-driven columns, id from `[?&]id=(\d+)` (never `tr[id]`, never `subject.hashCode()` — B18),
`td.empty`/`span.empty`/`No results found.`/`div.note` empty states (B9), pager detection (B10).
**Done:** archive fixture with no `From` header yields `from == nil` and still column-matches the
subject.

**4.4 — Attendance** · spec: `parsers.md` §8; `features.md` §1.5; D-13
Files (new): `BetterW4/W4AbsenceParser.swift`, `BetterW4/AttendanceModels.swift`.
Meters via `/You have (\d+) absences? and (\d+) latenesse?s? so far/i`; list via header-driven columns
plus `tr.prearranged_*`/`tr.medical_*` row classes (B14); content-hash ids, never the row index (B19).
**Done:** Home capture yields `(0, 0)` for both meters — assert the zero case, it is what we have.

**4.5 — Campus status + notifications** · spec: `parsers.md` §2–§3; `ui.md` §2.2–2.3; D-12
Files (new): `BetterW4/W4CampusStatusParser.swift`, `BetterW4/W4NotificationParser.swift`,
`BetterW4/CampusModels.swift`, `BetterW4/NotificationModels.swift`.
All 11 options verbatim with separate `value`/`label`; `setStatusBody` per D-12; `(…)` stripping (B7);
empty `div.notifications` ⇒ explicit `.empty` snapshot (B8); accepts wrapper/`.btn-group`/full container.
**Done:** `setStatusBody(onCampus) == ["status": "on"]` — no `location` key at all.

**4.6 — Home aggregate** · spec: `parsers.md` §13; `features.md` §1.16
Files (new): `BetterW4/W4HomeParser.swift`, `BetterW4/HomeModels.swift`.
Greeting, public-profile route, birthdays (photo + uwc id only — the capture has **no names**),
announcements (`No announcements...` is the captured empty state), the 10-entry `#links` block parsed
dynamically, never hardcoded.
**Done:** `links.count == 10`; `academics/trips` link `isInternalRoute == true`; ManageBac `false`.

**4.7 — People and profiles** · spec: `parsers.md` §11; `features.md` §1.12
Files (new): `BetterW4/W4PeopleParser.swift`, `BetterW4/PeopleModels.swift`.
Kind from the href (`people/staff/staff` vs `people/students/student`) — never a document-wide
substring sniff; merge the two anchors per `<li>`; `/images/user.png` ⇒ `nil`; supports both
`ul.user-list` and the `CGridView` variant (`td.student-name`, `td.entry-name`, `td.status`).
**Done:** `people-empty` fixture (`div.note` "No users found", real markup) yields `[]`.

**4.8 — Documents CMS** · spec: `parsers.md` §12; `features.md` §1.10
Files (new): `BetterW4/W4DocumentsParser.swift`, `BetterW4/DocumentModels.swift`.
`ul.folder-list > a.folder|a.page`, `.page-title`/`.page-details`/`.page-content` for a leaf (B16),
`div.up > a`, breadcrumbs from `#breadcrumb .crumbs a`.
**Done:** the real `documents.html` fixture yields title `Documents`, folder ids `27` and `34`,
`page == nil`.

**4.9 — Grades** · spec: `parsers.md` §10; D-14; OQ-12
Files (new): `BetterW4/W4GradeParser.swift`, `BetterW4/GradesModels.swift`.
Selector ladder per OQ-12 (B13), dynamic header-slug columns with `-2` de-duplication, `th.anticipated`,
`.effort-grade-*`, alerts from `div.errorMessage|error|warning|note`, `–`/`-` ⇒ no grade (never `""`).
**Done:** the "missing known columns do not shift values" test survives, retargeted at W4 markup.

**4.10 — Trips and travel** · spec: `parsers.md` §14; `features.md` §1.9
Files (new): `BetterW4/W4TripsParser.swift`, `BetterW4/TripModels.swift`.
Header-driven (never positional), raw `statusLabel` always retained alongside the enum.
**Done:** the header-shuffle test (Status and Participants swapped) still yields `.planning`.

**4.11 — ICS overlay** · spec: `parsers.md` §5; OQ-8
Files (new): `BetterW4/ICSCalendarParser.swift`, `BetterW4/SchoolCalendar.swift`;
`BetterW4Tests/Fixtures/W4/school-calendar.ics`.
Line unfolding, `VALUE=DATE`, exclusive all-day `DTEND`, `DURATION`, RRULE with caps,
`EXDATE`, `STATUS:CANCELLED`, `\n`/`\,` unescaping; thread the zone properly (B21).
**Done:** the 7-VEVENT fixture assertions in `parsers.md` §5 pass.

**4.12 — IB subject mapping** · spec: `features.md` §6; `inventory.md` §1.4
Files: `BetterW4/SubjectMapper.swift`, `BetterW4/SubjectIcons.swift` *(new)*,
`BetterW4Tests/SubjectMapperTests.swift`.
Replace 55 Danish gymnasium subjects, the Danish class-code regex and the 17 Danish ignore patterns
with IB groups keyed on the English name with HL/SL stripping; keep the machinery (canonical key →
override → default, hue→RGB at S 0.62 / V 0.88, unmapped hue 215); unknown subjects fall back to a
stable hash-of-name hue.
**Done:** `Mathematics HL`, `English A HL`, `Biology SL`, `TOK`, `Visual Arts` all map; no `æøå`.

**4.13 — Parser test suite + fixture generator** · spec: §5 of this document
Files: `scripts/make-fixtures.py`, `BetterW4Tests/W4FixtureTests.swift`, and one
`BetterW4Tests/<Parser>Tests.swift` per item above *(each item owns its own test file; this item owns
only the generator, the shared fixture list and the capture-pinning file)*.
**Done:** `python3 scripts/make-fixtures.py` regenerates every fixture from `references/` and the
suite is green.

> **Gate G4:** `build` + `test` green. Every parser has a fixture test and every fixture states its
> provenance ([V] real capture / [I] synthesized / [U] placeholder) in a leading comment.

---

### Wave 5 — Repositories, stores and caches

Goal: the layer that owns cache policy, TTL, demo branching and write actions. View models still call
the old client; nothing here is wired into the UI yet.

**5.1 — Timetable repository + store** · spec: `features.md` §0.2, §2.1, §2.5; D-22
Files: `BetterW4/TimetableRepository.swift` *(new)*, `BetterW4/ScheduleStore.swift`,
`BetterW4/ScheduleIdentity.swift`.
Parallel AC (`.important`) + EA (`.opportunistic`) fetch, merge, optional ICS overlay (OQ-8),
`LessonRecord` columns per `features.md` §2.1, delete-on-successful-parse with the `div.column ≥ 8`
guard, `w4WeekParameter` deleted in favour of D-18.
**Done:** cache-first + always-fetch; a cold store renders from network; a warm store renders offline.

**5.2 — Assessments repository + store** · spec: `features.md` §1.3, §2.1
Files: `BetterW4/AssessmentRepository.swift` *(new)*, `BetterW4/AssessmentStore.swift` *(new)*.
Optimistic `localStatus` overlay dropped as soon as the server status is newer; writes gated by
`W4Feature.assessmentWrites` (OQ-3); write invalidates the cache immediately.
**Done:** confirm-done round-trips in a stubbed client and reverts on failure.

**5.3 — Mail repository + caches** · spec: `features.md` §1.4, §2.4
Files: `BetterW4/MailRepository.swift` *(new)*, `BetterW4/MessageCacheManager.swift`,
`BetterW4/MessageListPrefetcher.swift`, `BetterW4/AttachmentCache.swift` *(new)*.
`Caches/MailCache/<b64(uwcId)>/`, base64 filename encoding kept, message bodies immutable/never
expiring, attachments LRU 50 MB / 100 files, unread badge notification retargeted to the W4 inbox.
**Done:** list + body survive relaunch; `Clear cache` empties them.

**5.4 — Attendance repository** · spec: `features.md` §1.5, §2.5
Files: `BetterW4/AttendanceRepository.swift` *(new)*.
Three cache keys (AC list, EA list, Home meters), 30 min TTL.
**Done:** meters render from the Home snapshot without a second request.

**5.5 — Directory, profile and people stores** · spec: `features.md` §1.12, §2.1
Files: `BetterW4/DirectoryRepository.swift` *(new)*, `BetterW4/DirectoryStore.swift`,
`BetterW4/StudentStore.swift` *(emptied of Lectio usage; **deleted in 6.5**, because
`SettingsStore` and `StudentSearchViewModel` still reference it at G5)*,
`BetterW4/DirectorySyncService.swift`, `BetterW4/StudentManager.swift`,
`BetterW4/ProfileRepository.swift` *(new)*.
`PersonRecord`/`RoomRecord` keyed on `uwcId`; delete `DirectoryMembershipRecord`, `pictureID`, the
`GetImage.aspx` URL builder, the 9-case entity kind and every `gymId` scope; search tokens become a
computed normalized string; serial sweep, 7-day TTL, pinning scoped to the signed-in uwc id.
**Done:** ~200 people sync serially without saturating the gate; the duplicate `Students.store` is gone.

**5.6 — Chrome repositories** · spec: `features.md` §1.7–1.8; D-23
Files: `BetterW4/CampusStatusRepository.swift` *(new)*, `BetterW4/NotificationRepository.swift` *(new)*,
`BetterW4/ChromeObserver.swift` *(new)*.
`apply(html:)` fed by the `W4Client` hook; 60 s foreground poll only while the sheet is closed; every
mutation re-parses the returned fragment and replaces the snapshot.
**Done:** opening any screen updates the campus chip with zero extra requests.

**5.7 — Page cache + TTL policy** · spec: `features.md` §2.4–2.5
Files: `BetterW4/W4PageCache.swift` *(new)*, `BetterW4/CachePolicy.swift` *(new)*.
`Caches/W4Pages/<b64(uwcId)>/<sha256(key)>.html` + `.meta.json` with `{fetchedAt, finalURL,
contentType}` — a real TTL, unlike Android's `SimpleCache` which never expires (do not port that bug).
**Done:** the TTL table in `features.md` §2.5 is expressed once, in this file, and unit-tested.

**5.8 — Secondary repositories** · spec: `features.md` §0.2
Files (all new): `BetterW4/DocumentRepository.swift`, `BetterW4/TripRepository.swift`,
`BetterW4/TravelRepository.swift`, `BetterW4/GradeRepository.swift`, `BetterW4/HomeRepository.swift`,
`BetterW4/FeedsRepository.swift`, `BetterW4/ExtraAcademicsRepository.swift`,
`BetterW4/ResourceRepository.swift`.
`HomeRepository` returns one `HomeSnapshot` from a single `site/index` fetch. `FeedsRepository` stores
feed tokens in the Keychain, never in `UserDefaults`, never in a log line.
**Done:** each has a demo branch and a TTL entry; `AssignmentRepository`, `PlanRepository`,
`ModuleStatRepository`, `TermRepository`, `RoomScheduleRepository` are **not** created (Android's are
empty stubs).

> **Gate G5:** `build` + `test` green; repository unit tests run against stubbed clients and fixtures.

---

### Wave 6 — View models (and the death of the Lectio stack)

Goal: every view model reads from a repository, never from an HTTP client (`features.md` §0 rule 2 —
today four of them call the client directly). Generation guards, cache-first, spinner-only-when-empty
and the `.forbidden`-is-not-logout rule are preserved verbatim (`features.md` §3).

**6.1 — Timetable VM** · files: `BetterW4/ScheduleViewModel.swift`,
`BetterW4/W4HTTPClient+Schedule.swift` *(delete)*.
**6.2 — Mail VMs** · files: `BetterW4/MessagesViewModel.swift`,
`BetterW4/MailMessageViewModel.swift` *(new)*, `BetterW4/MessageThreadViewModel.swift` *(delete)*,
`BetterW4/ComposeMessageViewModel.swift`, `BetterW4/MessageParser.swift` *(delete)*,
`BetterW4/MessageSignature.swift` *(delete)*, `BetterW4/BetterW4Links.swift` *(delete)*,
`BetterW4/W4HTTPClient+Messages.swift` *(delete)*.
**6.3 — Assessments VM** · files: `BetterW4/AssessmentsViewModel.swift` *(new)*,
`BetterW4/HomeworkViewModel.swift` *(delete)*, `BetterW4/AssignmentsViewModel.swift` *(delete)*,
`BetterW4/AssignmentParser.swift` *(delete)*, `BetterW4/AssignmentModels.swift` *(delete)*,
`BetterW4/HomeworkStore.swift` *(delete)*, `BetterW4/W4HTTPClient+Assignments.swift` *(delete)*,
`BetterW4/W4HTTPClient+Homework.swift` *(delete)*.
**6.4 — Attendance VM** · files: `BetterW4/AbsenceViewModel.swift`,
`BetterW4/AbsenceEditFormParser.swift` *(delete)*, `BetterW4/AbsenceModels.swift`,
`BetterW4/W4HTTPClient+Absence.swift` *(delete)*.
**6.5 — Grades + directory VMs** · files: `BetterW4/GradesViewModel.swift`,
`BetterW4/GradeParser.swift` *(delete)*, `BetterW4/GradeModels.swift`,
`BetterW4/DirectoryViewModel.swift`, `BetterW4/StudentSearchViewModel.swift`,
`BetterW4/DirectoryParser.swift` *(delete)*, `BetterW4/DirectoryModels.swift`,
`BetterW4/StudentParser.swift` *(delete)*, `BetterW4/W4HTTPClient+Student.swift` *(delete)*,
`BetterW4/StudentStore.swift` *(delete — deferred here from 5.5)*, plus the three surgical
call-site files those deletions orphan: `BetterW4/SettingsStore.swift`,
`BetterW4/ContentView.swift`, `BetterW4/DemoDataProvider.swift` (drop the `StudentParser` /
`DirectoryParser` / `StudentStore` references only; the real rewrites are 7.5 and 9.2).
**6.6 — New VMs** · files (all new): `BetterW4/HomeViewModel.swift`,
`BetterW4/CampusStatusViewModel.swift`, `BetterW4/NotificationsViewModel.swift`,
`BetterW4/DocumentsViewModel.swift`, `BetterW4/TripsViewModel.swift`,
`BetterW4/ExtraAcademicsViewModel.swift`.
**6.7 — Legacy transport teardown** *(lands last in the wave)* · files:
`BetterW4/W4HTTPClient.swift` *(delete)*, `BetterW4/CookieManager.swift` *(delete)*,
`BetterW4/W4HTTPClient+PrivateEvents.swift` *(delete)*, `BetterW4/ScheduleParser.swift` *(delete)*.
Preconditions, verified by grep before deleting: `CookieManager`'s only remaining callers were
`AuthenticationService` (gone in 3.1), `W4WebView` (gone in 1.1), `W4ImageLoader` (fixed in 2.7) and
`W4HTTPClient` itself; `ScheduleParser`'s were `ScheduleViewModel` (6.1) and `HomeworkViewModel` (6.3).

**Done, all items:** no view model imports or references `W4HTTPClient`; every published mutation is
generation-guarded; `command grep -rn "lectio.dk\|\.aspx\|__doPostBack" BetterW4/` returns **0**.
Spec: `features.md` §3 for the twelve preserved rules; `inventory.md` §1.5 for per-file notes.

> **Gate G6:** `build` + `test` green; `scripts/check-legacy.sh` reports 0 for `lectio.dk`, `.aspx`,
> `ASP.NET_SessionId`, `autologinkey`, `__VIEWSTATE`, `MitID`.

---

### Wave 7 — Core tab screens

Goal: the four tabs work end to end against W4.

**7.1 — Timetable screens** · spec: `ui.md` §4.1, §3.1–3.2
Files: `BetterW4/ScheduleView.swift`, `BetterW4/ScheduleHeaderView.swift`,
`BetterW4/TimelineListView.swift`, `BetterW4/ModernScheduleComponents.swift`,
`BetterW4/AllDayEventsView.swift`, `BetterW4/CalendarStripView.swift`,
`BetterW4/LessonContentItemView.swift`, `BetterW4/ScheduleEvent+Extensions.swift`,
`BetterW4/ScheduleLayoutUtils.swift`, `BetterW4/AddPrivateEventView.swift` *(delete, D-32)*,
`BetterW4/PublicProfileImage.swift` *(delete)*.
Start/end hour from `tt_start_hour`/`tt_end_hour` (not hardcoded 8/16), `en_GB` locale, Today digest,
toolbar cluster, no FAB, no Live Activity hooks.
**Done:** a real week renders with rotation days, weekend markers, the now-line and the digest;
at `.accessibility3`+ the day page auto-collapses to list style instead of clipping the grid.

**7.2 — Mail list + message** · spec: `ui.md` §4.2–4.3
Files: `BetterW4/MailboxView.swift` *(new)*, `BetterW4/MailMessageView.swift` *(new)*,
`BetterW4/MessagesView.swift` *(delete)*, `BetterW4/MessageThreadView.swift` *(delete)*,
`BetterW4/MessageReactionProtocol.swift` *(delete)*, `BetterW4/MessageEditAudit.swift` *(delete)*,
`BetterW4/MessageModels.swift`.
Two folders only; salvage `AttachmentRow`, `QuickLookPreview`, `AuthenticatedImageView` into
`MailMessageView.swift`; no threads, replies-in-place, reactions, edits or flags.
**Done:** inbox → message → attachment preview works; empty / no-search-results / error / offline
states all use `ContentUnavailableView`.

**7.3 — Compose** · spec: `ui.md` §4.4; D-26
Files: `BetterW4/ComposeMessageView.swift`, `BetterW4/OutgoingMessageAttachment.swift`,
`BetterW4/MessageContentRenderer.swift`, `BetterW4/BBCodeRichEditor.swift` *(delete)*.
`MailerForm[subject|message|attachment[]|sendCC|attachmentSource]`, recipients from
`mailer/extra&type=freeform`, HTML body (bold/italic/underline/link/lists), 5 × 2 MB.
**Done:** a real message sends; a 3 MB attachment is rejected in the picker with an English message.

**7.4 — Assessments screen** · spec: `ui.md` §4.5
Files: `BetterW4/AssessmentsView.swift` *(new)*, `BetterW4/HomeworkView.swift` *(delete)*,
`BetterW4/AssignmentsView.swift` *(delete)*.
List/Month segmented, date sections, swipe **and** context-menu Confirm done / Revert to pending
(swipe alone is not accessible), `+` add student assessment when writes are enabled (OQ-3).
**Done:** done-state comes from the server; a failed write reverts the row and shows a toast.

**7.5 — Shell and More root** · spec: `ui.md` §2.1, §4.6
Files: `BetterW4/ContentView.swift`, `BetterW4/MoreView.swift` *(new)*,
`BetterW4/TabBarSameTabReselectDetector.swift`.
4-tab `TabView`, per-tab `NavigationStack`, bound path on More and Mail, reselect-to-top /
reselect-to-root, rows not yet backed by a parser render as "Coming soon" (stable IA).
**Done:** every More row navigates or says "Coming soon"; no Lectio catalogue entries remain.

**7.6 — Chrome controls** · spec: `ui.md` §2.2–2.3
Files (all new): `BetterW4/CampusStatusControl.swift`, `BetterW4/NotificationsBell.swift`,
`BetterW4/NotificationsListView.swift`.
Capsule with a coloured dot **and** text (colour is never the only signal), `Other` alert with a
20-char limit, optimistic update with revert; bell sheet with Tasks/Emails sections, severity words
not just colours, mark-read/clear per item/group/all, tap routes into the app.
**Done:** setting status off-campus updates the chip everywhere without a refetch; an empty bell shows
no badge and is not an error.

> **Gate G7:** `build` + `test` green **and** a manual pass on device: log in → timetable → mail →
> read → compose draft → assessments → set campus status → sign out.

---

### Wave 8 — More-tab screens and the new W4 surfaces

All items are independent screens; maximum parallelism.

**8.1 — Attendance screens** · `ui.md` §4.7–4.8 · files: `BetterW4/AbsenceView.swift`,
`BetterW4/RegisterAbsenceView.swift` *(new)*.
**8.2 — Grades screens** · `ui.md` §4.x, `parsers.md` §10 · files: `BetterW4/GradesView.swift`,
`BetterW4/SubjectGradeDetailView.swift`, `BetterW4/AcademicRecordsView.swift` *(new — SAT,
transcripts, RoP, EE, testimonial as sanitized HTML)*.
**8.3 — Directory + profile** · `ui.md` §4.9 · files: `BetterW4/DirectoryView.swift` *(new)*,
`BetterW4/StudentSearchView.swift` *(delete)*, `BetterW4/StudentProfileView.swift`,
`BetterW4/StudentProfile.swift`.
**8.4 — Documents + quick links** · `ui.md` §4.15, §4.24 · files:
`BetterW4/DocumentsBrowserView.swift` *(new)*, `BetterW4/QuickLinksView.swift` *(new)*,
`BetterW4/W4HTMLViewer.swift` *(new — D-24/D-25: `loadHTMLString`, JS off, no cookies)*.
**8.5 — Boarding** · `ui.md` §4.12–4.13, §4.23 · files: `BetterW4/TripsView.swift` *(new)*,
`BetterW4/TravelFormsView.swift` *(new)*, `BetterW4/ResourceBookingsView.swift` *(new)*.
**8.6 — Extra Academics suite** · `ui.md` §4.16–4.20 · files (all new):
`BetterW4/EAActivitiesView.swift`, `BetterW4/EADiaryView.swift`, `BetterW4/EAPortfolioView.swift`,
`BetterW4/CASInterviewsView.swift`, `BetterW4/SafetyNetView.swift`.
SafetyNet is pastoral: no badge, no notification, no shared-container cache.
**8.7 — ID & Attendance** · `ui.md` §4.14, `features.md` §1.13, OQ-5 · files:
`BetterW4/IDAttendanceView.swift` *(new)*, `BetterW4/AttendanceLetterView.swift` *(new)*,
`BetterW4/StudentCardView.swift` *(delete)*.
**8.8 — Home-derived screens** · `ui.md` §4.21–4.22, §4.25 · files (all new):
`BetterW4/BirthdaysView.swift`, `BetterW4/AnnouncementsView.swift`,
`BetterW4/PersonalFeedsView.swift` *(token masked as `••••`, never rendered in full, never logged)*.

**Done, all items:** each screen has empty / error / offline states, a light+dark `#Preview` pair,
`accessibilityLabel` on every icon-only control, and `.accessibilityElement(children: .combine)` on
grouped rows.

> **Gate G8:** `build` + `test` green; no screen crashes with an empty or missing parser result.

---

### Wave 9 — App shell, settings, demo, notifications

**9.1 — Settings** · spec: `features.md` §6; `ui.md` §4.10
Files: `BetterW4/SettingsView.swift`, `BetterW4/SettingsStore.swift`,
`BetterW4/SubjectColorSettingsView.swift`.
Final list: Appearance (theme, calendar style, subject colours, Subject settings) · Notifications
(4 toggles + reminder minutes + authorisation row) · Personal feeds · Data (Clear cache, Re-sync
directory, Storage used) · Privacy ("What BetterW4 stores"; no external URL, OQ-7) · About (app
version, W4 server version linked to `site/relnotes`, acknowledgements) · Sign out. Delete the
Live-Activity, feedback, browser-extension, signature, language-picker and cookie-debug sections.
**Done:** every preference persists across relaunch (this is the G-5 regression test).

**9.2 — Demo mode** · spec: `client.md` §11; `features.md` §4
Files: `BetterW4/DemoDataProvider.swift`, `BetterW4/DemoContent.swift` *(new)*.
English, UWC-shaped, **zero network** (locally drawn initial avatars, never gravatar URLs), zero
persistence, per-screen content per `features.md` §4, "Demo data. Not connected to W4." banner.
**Done:** with the device in Airplane Mode, every v1 screen renders demo content and no request is
attempted (assert by failing the demo gate in `W4Client`).

**9.3 — Local notifications + background refresh** · spec: `features.md` §5
Files: `BetterW4/BackgroundRefresh.swift` *(new)*, `BetterW4/NotificationScheduler.swift` *(new)*,
`BetterW4/NotificationDiff.swift` *(new)*, `BetterW4/BetterW4App.swift`, `BetterW4/Info.plist`.
`BGAppRefreshTaskRequest` id `dk.jonathanb.w4.refresh` (+ `BGTaskSchedulerPermittedIdentifiers` and
`UIBackgroundModes` in `Info.plist`), ≤25 s budget, bell-first fetch order, verbatim diff keys,
5-per-category cap, `lesson.<eventId>` calendar triggers capped at 40, badge = unread inbox count,
permission requested lazily on first toggle.
**Done:** a simulated background run produces exactly one notification per genuinely new item and
none on a second run with unchanged data.

**9.4 — Review prompt rewiring** · spec: D-33
Files: `BetterW4/ReviewPromptCoordinator.swift`, `BetterW4/ReviewPromptSheet.swift`,
`BetterW4/ReviewPromptStore.swift`, `BetterW4/ReviewEligibility.swift`,
`BetterW4/AppStoreReviewLauncher.swift`.
**Done:** the negative branch dismisses and suppresses for 90 days; no Google-Play-named events.

**9.5 — Strings file** · spec: `inventory.md` §D; `ui.md` §5
Files: `BetterW4/en.lproj/Localizable.strings`.
Delete the 55 dead keys (`browser_extension.*`, `profile_picture.*`, reaction/edit `message.*`), add
the 21 referenced-but-missing `student_profile.*` keys, and create the new namespaces (`tab.*`,
`login.*`, `timetable.*`, `assessments.*`, `mailer.*`, `absences.*`, `campus.*`, `trips.*`,
`documents.*`, `directory.*`, `grades.*`, `safetynet.*`, `settings.*`, `error.*`).
**Done:** every key defined is referenced and every key referenced is defined (checked by a script).

> **Gate G9:** `build` + `test` green; manual demo-mode pass in Airplane Mode; a background refresh
> fires a notification.

---

### Wave 10 — Sweep, shims, captures, docs, release hygiene

**10.1 — English sweep** · spec: `ui.md` §5.2 (the ~180-row table)
Files: every remaining file with a Danish literal (baseline: 39 files with `æøå`, 521 literals),
plus `scripts/check-english.sh` flipped to **fail** the build.
**Done:** `check-english.sh` exits 0.

**10.2 — Shim removal** · spec: D-28
Files: every file containing `// PORTSHIM` — chiefly `BetterW4/StudentModels.swift` (`gymId`,
`School` typealias), `BetterW4/ScheduleModels.swift` (`subtitle`, `startTime`, `endTime`).
`scripts/check-legacy.sh` flipped to **fail** on `PORTSHIM` and `gymId`.
**Done:** `command grep -rn "gymId\|PORTSHIM" BetterW4/` returns 0 (from 312).

**10.3 — Capture-driven fixture completion** · spec: §5.1
Files: `scripts/make-fixtures.py`, `BetterW4Tests/Fixtures/W4/*`, and the parser test files whose
fixtures were `[I]`/`[U]`.
Replace every synthesized fixture for which a capture now exists; each replacement must flip its
provenance comment from `[I]`/`[U]` to `[V]` and tighten its assertions.
**Done:** the provenance table in §5.2 has no `[U]` rows left for v1 surfaces.

**10.4 — Accessibility, dark mode and performance pass** · spec: `ui.md` §6
Files: any view failing the audit (expected: timetable grid at accessibility sizes, tinted-surface
contrast, swipe-only actions).
**Done:** every screen at `.accessibility5` without clipping; contrast ≥ 4.5:1 for body text in both
schemes; every swipe action has a non-swipe equivalent.

**10.5 — Docs** · files: `docs/W4_PORT_PLAN.md` (this file — mark waves done),
`docs/BUILD.md`, `docs/spec/*.md` (append a "superseded by plan §2" note where §2 overrode them),
`../PROTOCOL.md` (update §10 unknowns with what the captures resolved).
**Done:** a new engineer can go from clone to running app using `docs/BUILD.md` alone.

**10.6 — Release hygiene** · files: `BetterW4/Info.plist`, `BetterW4/BetterW4.entitlements`,
`AppIcon.icon/`, `docs/RELEASE.md` *(new)*.
App Store notes: demo mode is the review path (no test account needed), privacy nutrition label =
"Data not collected", the privacy URL from OQ-7.
**Done:** an archive builds and validates.

> **Gate G10 (ship gate):** `build` + `test` + `check-legacy.sh` + `check-english.sh` all exit 0;
> archive validates; a full manual pass on a real student account and a full pass in demo mode.

---

## 4. Build gates

Verified working command (run from `/Users/johannes/Projects/betterw4/ios`; the SwiftSoup package
resolves automatically, and the project uses `PBXFileSystemSynchronizedRootGroup` so adding/removing
`.swift` files needs **no** project edit):

```sh
cd /Users/johannes/Projects/betterw4/ios

# G-BUILD
xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO build

# G-TEST (compile the test bundle, then run it)
xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO test
```

To read failures: `… build 2>&1 | command grep -E "error:|warning: .*deprecat|\*\* "`.
**Use `command grep`, never `rg`/`grep` through the harness wrappers** — `ios/.gitignore` plus
`--ignore-files` makes ripgrep-style searches silently return zero hits over `ios/BetterW4`
(`inventory.md` §0).

| Gate | After wave | Must pass | Extra |
|---|---|---|---|
| G1 | 1 | build · build-for-testing · test | preferences persist across relaunch; no `-34018` in the log |
| G2 | 2 | build · test | new transport tests green; legacy stack untouched |
| G3 | 3 | build · test | **manual login on a real account reaches Home**; captures taken |
| G4 | 4 | build · test | every parser fixture-tested; provenance comments present |
| G5 | 5 | build · test | repository tests against stubbed clients |
| G6 | 6 | build · test | `check-legacy.sh`: 0 for `lectio.dk`, `.aspx`, `autologinkey`, `__VIEWSTATE`, `MitID` |
| G7 | 7 | build · test | manual: login → timetable → mail → compose → assessments → campus → sign out |
| G8 | 8 | build · test | no screen crashes on empty/missing parser output |
| G9 | 9 | build · test | demo pass in Airplane Mode; background refresh notification |
| G10 | 10 | build · test · both check scripts | archive validates; full manual pass, real + demo |

Current state (2026-08-15 23:15): **build FAILS** with exactly one diagnostic —
`AuthenticationService.swift:10:8: error: no such module 'Supabase'`. A probe build with stubs for
`Supabase*`, `Analytics`, `HomeworkSyncStatus`, `LastSchool*` and `SchoolPickerView` compiles the
entire app, which is why Wave 1 is only four items.

---

## 5. Test plan for `BetterW4Tests`

### 5.1 Captures to take (all immediately after G3, ranked)

| # | Capture | Unblocks | Fixture it becomes |
|---|---|---|---|
| C-1 | HAR of one full login: `GET site/login` → `POST site/login` → 2FA page → `POST` OTP → home | OQ-1, `W4LoginClient` assertions, whether `PHPSESSID` rotates | `login.html`, `verify2fa.html` (replacing the synthetic pair) |
| C-2 | `GET academics/timetable/mytimetable` **in term time**, plus one non-current week | B2/B3/B4, OQ-2, every `.period` assertion | `timetable-mytimetable-termtime.html` |
| C-3 | `GET academics/deadlines` + the `$.post` for **Confirm done** | OQ-3, all assessment writes | `assessments-calendar.html`, `assessments-confirm.txt` |
| C-4 | `GET mailer/inbox` with >1 page + one `mailer/view&id=` + the `mailer/send` form | OQ-4, pagination, compose field names | `mailer-inbox.html`, `mailer-view.html`, `mailer-send-form.html` |
| C-5 | `people/students/letter/attendance` response headers + first 16 bytes | OQ-5 | (headers recorded in the test, no fixture) |
| C-6 | One `notifications/refresh` response with a non-zero badge | OQ-6, OQ-9, background notifications | `notifications-refresh.html` |
| C-7 | The Home `#calendar` iframe `src` | OQ-8 | (constant in `SchoolCalendar.swift`) |
| C-8 | `people/students/absences` + `people/students/absences/register` | OQ-10, §4.4/§8.1 | `absences-ac.html`, `absences-register.html` |
| C-9 | `academics/grades/grades` (+ `/sat`) | OQ-12 | `grades.html` |
| C-10 | `people/students/all` | photo path, grid vs `ul.user-list` | `people-all.html` |
| C-11 | `academics/trips` + "Plan new trip" | OQ-11 | `trips.html`, `trip-create-form.html` |
| C-12 | One `documents/index&folder_id=` and one `&page_id=` | `a.page` markup | `documents-folder.html`, `documents-page.html` |
| C-13 | An authenticated-but-unauthorised page (403 body) | the `.forbidden` branch | (assertion only) |

**Hygiene, non-negotiable** (`reviewer-notes.md` §8): everything goes through
`scripts/make-fixtures.py` — uwc ids mapped to the existing placeholders (`nc26abcd`, `nc16efgh`,
`nc19ijkl`, `nc25mnop`, `nc25qrst`, unmapped → `ncNNzzzz`), names replaced, image binaries dropped,
`token=` → `REDACTED`, `PHPSESSID=` → `REDACTED`. **Never commit a live session cookie or a feed token.**

### 5.2 Fixtures and their provenance

Already generated from `references/pages/` (all **[V]**, real markup):
`home.html` (from `UWCRCN W4.html`), `academics-menu.html`, `extraacademics-menu.html`,
`school-menu.html`, `documents.html`. Add from the HAR: nothing new — HAR entry 0 is the same
Documents body. Add synthesized **[I]** fixtures, each with a
`<!-- SYNTHESIZED, not a capture. Verifies the parser, not W4. -->` header:
`login.html`, `verify2fa.html`, `assessments-calendar.html`, `assessments-empty.html`,
`mailer-inbox.html`, `mailer-inbox-empty.html`, `mailer-archive.html`, `absences-ac.html`,
`absences-ea-empty.html`, `grades.html`, `grades-tablegrades.html`, `people-all.html`,
`trips.html`, `trips-empty.html`, `documents-page.html`, `notifications-refresh.html`,
`yii-form-generic.html`, `school-calendar.ics`. Plus **[V]** extracts trimmed from the real Home
capture: `campus-chrome-oncampus.html`, `notifications-empty.html`, `people-empty.html`
(the real `div.note` "No users found" body from `Current applicants at UWCRCN.html`).

### 5.3 Assertions per parser (the ones that must exist)

| Suite | Assertions |
|---|---|
| `W4RoutesTests` | literal `/` inside `r`; sibling keys not inside `r`; inline siblings split out; explicit query beats inline; a key named `r` is dropped; `"On a walk + back & forth"` round-trips as `%2B`/`%20`/`%26` and never a bare `+`; `routeOf` decodes `%2F` first; all four `resolve` spellings agree; two calls with the same dictionary produce byte-identical URLs |
| `W4CookieJarTests` | merge sets `PHPSESSID`; **empty value does not clear a live session**; regeneration replaces; foreign host merges nothing; extras add/remove; unchanged ⇒ `nil`; empty jar ⇒ empty header; `autologinkeyV2`/`isloggedin3`/`ASP.NET_SessionId` never emitted; redaction never leaks the value |
| `W4SessionClassificationTests` | 302→`site/login` ⇒ `.sessionExpired` + exactly one notification; same with `allowLoginPage` ⇒ followed; 200 with `LoginForm[username]` ⇒ `.sessionExpired`; 403 + `Login Required` ⇒ `.sessionExpired`; 403 without ⇒ `.forbidden` **and no notification**; 409 ⇒ `.serverConflict(body)`; 6 hops ⇒ `.sessionExpired`; per-hop cookie carried forward; 302-after-POST ⇒ GET without body, 307 keeps both; 404 ⇒ `.http(404)`; `ajax` sets `X-Requested-With`; every request carries the exact UA + `Referer: https://w4.uwcrcn.no` and **no** `Accept-Encoding` |
| `PriorityRequestLimiterTests` | no overlap; `.important` jumps `.opportunistic`; cancelling a queued waiter does not deadlock; cancelling a just-served waiter releases the slot; ≥100 ms spacing; acquire timeout fires |
| `YiiFormTests` | last `option[selected]`; unchecked checkboxes skipped, checked included with `value` or `"on"`; `input[type=file]` skipped; submits routed to `submitButtons`; `yt0` from the form, explicit value wins; encoder emits `%20`/`%2B`, keys sorted, `[`/`]` percent-encoded; **never** `__VIEWSTATE` |
| `W4LoginFlowTests` | cookie from `GET site/login` is sent on the POST; body carries all four fields incl. the Keychain device id; 302→`verify2fa` ⇒ `.needsOTP` with the OTP field excluded from `hiddenFields`; OTP→`site/index` ⇒ `.authenticated`; **a `verify2fa` page containing `Welcome,` is `.needsOTP`, not `.authenticated`**; `.errorSummary` text surfaced; no `Set-Cookie` + empty jar ⇒ `.failed`; wrong OTP ⇒ `.failed(invalidOTP: true)` |
| `W4ChromeParserTests` | `("nc26abcd", "Alex Andersen")` — and specifically **not** `nc25mnop`/`nc25qrst` (the birthday classmates, bug B17); version `25.9.1`; Home and Documents have no sdmenu; academics menu = 4 sections / 13 items / `travel.list` at `[2][1]` |
| `W4TimetableParserTests` | 7 days on the **unmodified** two-`#timetable` markup (bug B1); `2026-08-10` Oslo Monday; `Day 1`; `Weekend` + `isNoClasses` on Sat/Sun; `No EA`; **zero events** (holiday week — do not fake lessons); week 33/2026; hours 7–22; exactly one `isToday`; `—`/`–`/`-` all parse; timezone forced to `America/New_York` changes nothing |
| `W4CampusStatusParserTests` | 11 options in order; `options[0].value == "oncampus"`, `[10] == "other"`, `[2].label == "At Raudbua"`; `selectedOptionID == "location_0"`; `setStatusBody(onCampus) == ["status":"on"]` (no `location` key); `("At Raudbua")` parens stripped |
| `W4NotificationParserTests` | empty container ⇒ `.empty`, no throw; refresh fixture ⇒ count 3, one task group + one email group, overdue severity; a bare `<div><div class="btn-group">…` wrapper parses identically |
| `W4AbsenceParserTests` | Home ⇒ `(0,0)` and `(0,0)`; list rows carry `.lateness`; `class="prearranged_1"` wins over a "Type" column saying `Absence`; empty page ⇒ `[]` not an error |
| `W4AssessmentParserTests` | 2 items with kind/status/date/subject/teacher; `parseAjaxURLs().confirm` contains `academics/deadlines/confirm`; `statusFields` picks the right key per kind; empty ⇒ `[]`; **test file states it verifies the parser, not W4** |
| `W4MailerParserTests` | 2 inbox rows with id/subject/from/received; order preserved; archive without a `From` header ⇒ `from == nil` and the subject still column-matched; empty ⇒ `[]`; pager detected |
| `W4DocumentsParserTests` | index ⇒ 2 folders, ids 27/34, `page == nil`; page fixture ⇒ `.page-title`/`.page-content` populated, `items.isEmpty` |
| `W4HomeParserTests` | greeting "Alex Andersen"; profile route contains `uwc_id=`; birthdays today 3 / tomorrow 1 with photos and **no names**; `announcements.isEmpty`; `links.count == 10`; internal vs external classification |
| `W4PeopleParserTests` | 3 people, 2 students + 1 staff; each appears once despite two anchors; `/images/user.png` ⇒ `nil`; `profileRoute` differs by kind; empty page ⇒ `[]` |
| `W4GradeParserTests` | dynamic columns in server order; blank cell ⇒ `nil` not `""`; duplicate headers de-duplicated; `th.anticipated` flagged; `.effort-grade-*` parsed; missing known columns do not shift values |
| `W4TripsParserTests` | 1 trip with parsed dates; `.planning` + verbatim label; **header-shuffle test**; empty ⇒ `[]` |
| `ICSCalendarParserTests` | all-day exclusive `DTEND`; folded lines; weekly `BYDAY` expansion; `\,` unescaping; `STATUS:CANCELLED` skipped; UTC → Oslo |
| `W4DatesTests` | `14-Aug-2026`, `4-Aug-26`, `2026-08-14`, `14/08/2026` all parse under a `da_DK` device locale; `format` round-trips |
| `SubjectMapperTests` | IB names map; HL/SL stripped; unknown subject gets a stable hue; no Danish subject survives |
| `W4FixtureTests` (existing) | keeps pinning the captures themselves; extended, never deleted |

---

## 6. Risk list

Ordered by expected cost × likelihood.

| # | Risk | Why it is likely | Blast radius | Mitigation | Settled by |
|---|---|---|---|---|---|
| R-1 | **2FA field names are unverified.** No login page, no `LoginForm` string, no `verify2fa` string and no ClientJS exists anywhere in `references/` — it is README prose only. | Nothing in the capture set touches auth. | Total: no login ⇒ no app. | Discovery-based parsing already implemented (OQ-1): parse whatever form is on the page, pick the OTP input by name pattern then by elimination; surface the server's own error text; log an `inputInventory` in DEBUG when discovery fails. | C-1 |
| R-2 | **`deviceId` may not actually suppress 2FA**, so every launch prompts for an OTP. | README says "almost certainly" and nothing confirms it. | UX-fatal; the app feels broken. | Keep the id stable in the Keychain (`…ThisDeviceOnly`, never `identifierForVendor`); if C-1 shows a "trust this device" control, post it. If OTP-every-launch is real, the fallback is Face ID-gated credential re-submit — design it only if confirmed. | C-1 |
| R-3 | **Every assessment `data-*` attribute is invented** — the Android fixture is hand-written, not a capture, and assessments are a whole tab. | `parsers.md` B12 proves it. | Tab 3 shows nothing; writes could 409 or silently no-op. | Parser degrades to `[]` and logs; writes behind `W4Feature.assessmentWrites = false`; the empty state is honest ("Nothing due"); ship the tab read-only if C-3 slips. | C-3 |
| R-4 | **The only timetable capture is a holiday week with zero `.period` elements**, so the entire lesson-block parser is unverified. | Verified: `class="period"` × 0 in all captures. | Tab 1 renders an empty grid for a real student. | Pixel geometry (1px = 1min) *is* verified and is the primary path; every `.period` sub-node optional; capture `title` raw (B3); the fixture test asserts "7 days, right dates, **zero** events" rather than faking lessons. | C-2 |
| R-5 | **Mailer HTML is unknown** (grid columns, unread marker, attachments, body container, pagination). | No mailer page captured. | Tab 2 lists nothing or mis-assigns columns. | Header-driven matching everywhere (never positional); id from the href not from `tr[id]`; four empty-state signals; `div.pager` ⇒ "More on W4" instead of silent truncation. | C-4 |
| R-6 | **Session-death misclassification logs students out mid-lesson** (or, worse, keeps a dead session and feeds parsers login HTML). | Six distinct signals, three of which look alike. | Trust-destroying. | The full classification table with a dedicated test per row (§5.3), manual redirects only, `.forbidden` never logs out, one idempotent notification. | C-13 |
| R-7 | **`SFSafariViewController` fallbacks would show a login screen** because it has its own cookie store (D-24). | Two specs proposed it for authenticated pages. | Every "not yet parsed" surface appears broken. | D-24: fetch with `W4Client`, render via `W4HTMLViewer` (`loadHTMLString`, JS off). `SFSafariViewController` only for genuinely external links. | none needed |
| R-8 | **MainActor-by-default (G-6)** silently pins parsers and stores to the main thread; the 600 KB Letter of Attendance and the 200-person directory then hitch the UI. | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set and no spec noticed. | Jank, watchdog kills on older devices. | D-30: parsers `nonisolated`, engine/gate/caches `actor`, stores actor-isolated, only VMs/views `@MainActor`; add a debug assertion that parse entry points are off-main. | none needed |
| R-9 | **The `gymId` big bang** (312 refs / 40 files) turns one wave red for days. | It is a stored property on four models and a parameter on ~40 methods. | Schedule slip, merge hell. | D-28 shim: `gymId` becomes a computed `W4School.id` in Wave 2; call sites die per-vertical; Wave 10 removes the shim with a CI gate. | none needed |
| R-10 | **Rate-limiting a tiny Apache box.** Avatars for 200 people plus a directory sweep plus a 60 s bell poll. | README §5.5 exists precisely because of this. | The school blocks the app. | One process-global serial gate with a 100 ms floor that avatars also pass through; directory sweep serial and 7-day TTL; bell polls only while foregrounded and the sheet is closed; demo mode makes zero requests. | none needed |
| R-11 | **Letter of Attendance is PDF or 600 KB HTML** — README and the Android port disagree. | Documented contradiction. | A crash or an empty screen on a document students actually need. | OQ-5: sniff `Content-Type` **and** magic bytes; handle both; stream, never parse into a model. | C-5 |
| R-12 | **Notification fragment markup is unknown** and drives both the bell and background notifications. | The captured `div.notifications` is empty. | Silent notifications, or false positives waking students. | Empty is an explicit tested state; diff keys are set-difference so a still-present item never re-notifies; 5-per-category cap; nothing fires in demo or signed-out. | C-6 |
| R-13 | **Fixture leakage of real people.** The captures contain real UWC ids, names and photo filenames. | The fixtures are committed. | Privacy incident at a 200-student school. | Everything passes through `make-fixtures.py`; the sanitizer redacts unmapped ids, `token=` and `PHPSESSID=`; a CI grep in Wave 10 fails on `nc26jban`, `Bangert`, `PHPSESSID=[A-Za-z0-9]` in `BetterW4Tests/`. | none needed |
| R-14 | **Feed tokens are password-equivalent** and appear in a screen we intend to build. | README §4.8. | Account takeover of a personal calendar. | Keychain only, masked as `••••` in the UI, excluded from logs and screenshots, never in a fixture, never in `UserDefaults`. | none needed |
| R-15 | **App Review rejects a login-walled app.** | Standard 2.1/5.1.1 pattern. | Ship blocked. | Demo mode is the review path (Wave 9.2), reachable in one tap from the login screen, fully functional offline, labelled "Demo data. Not connected to W4."; privacy label = "Data not collected"; OQ-7 needs a real privacy URL before submission. | owner decision |
| R-16 | **Spec drift** — five specs, a moving tree, and this plan overriding parts of all five. | Already happened once (three specs are partly stale: G-1…G-5). | Two engineers implement two vocabularies. | §2 is binding; every wave item cites the spec section it follows; Wave 10.5 back-annotates the specs. Anyone finding a contradiction files it as a new `D-` row here rather than choosing. | none needed |

---

## 7. Scope discipline — what is explicitly *not* being built

Live Activities · widgets · Mac/Safari/App Clip targets · any backend · analytics of any kind ·
in-app feedback · referrals · profile-picture upload or moderation · message threads, replies,
reactions, edits, BBCode, signatures, flags, folders beyond Inbox/Sent · assignment hand-ins and
submission history · absence percentages, causes and "Godskrevet" · the Danish 7-step grade scale and
XPRS · holds, synthetic classes and `S`/`T`/`HE`/`RO` prefixes · the studiekort QR · a second language ·
a school picker · MitID · ManageBac scraping · staff/administrative surfaces · admissions CRM ·
device-local private calendar events (D-32) · a WebView anywhere in the auth path.

Anything on this list that a future capture makes tempting gets a new `D-` row in §2 first.
