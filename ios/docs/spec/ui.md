# BetterW4 iOS — Information Architecture & Screen-by-Screen UI Plan

Status: spec, not yet implemented. Authoritative inputs: `/README.md` (the W4 protocol brief),
the completed Android port under `android/app/src/main/java/dk/betterw4/android/**`, the saved
W4 pages under `references/pages/`, and the existing SwiftUI code in `ios/BetterW4/`.

Sibling specs in this directory own auth, HTTP/session, and the per-page parsers. This document
owns **navigation, screens, view files, states, and copy**. Where it names a route or a selector it
cites the file it was read from. Anything not observed is marked `UNKNOWN — needs live capture`.

---

## 0. Starting condition (read this before planning work)

`ios/BetterW4/` is a *pruned copy* of the BetterLectio iOS app. The prune deleted the Supabase /
PostHog / feedback / referral / profile-picture / Live-Activity / browser-extension **implementation
files but not their call sites**. The app in the repo today does not compile. Symbols referenced
with no definition left in the target:

| Missing symbol | References | Example call site |
|---|---|---|
| `Analytics` | 28 | `BetterW4App.swift:15` `Analytics.configure()` |
| `LiveActivityManager` | 9 | `ScheduleView.swift:603`, `SettingsView.swift:108,336` |
| `FeedbackLogBuffer` | 7 | `ContentView.swift:33,47` |
| `ReferralCoordinator` | 6 | `ContentView.swift:15,51`, `ScheduleView.swift:608` |
| `LiveActivityVariant` | 4 | `SettingsView.swift:93-101` |
| `FeedbackCoordinator` / `FeedbackSheet` / `FeedbackPresentation` | 4 / 1 / 1 | `ContentView.swift:120,222`, `SettingsView.swift:161` |
| `SupabaseProfilePictureService`, `ProfilePictureReviewMonitor`, `ProfilePictureEditorView`, `ProfilePictureState` | 3/1/1/1 | `ContentView.swift:16,63,502,511` |
| `BrowserExtensionInviteView` | 2 | `ContentView.swift:514`, `SettingsView.swift:260` |
| `ShakeListener` | 1 | `ContentView.swift:210` |
| `SchoolPickerView` | 1 | `LoginView.swift:26` |
| `ReferralView` / `ReferralNudgeView` / `ReferralProgress` | 1 each | `ContentView.swift:224,455,462` |
| `LiveActivityBackgroundRefresh` | 1 | `BetterW4App.swift:21` |

Also live in the tree: 112 `lectio.dk` / `.aspx` references across 32 files. **The first UI commit is
therefore a demolition commit** (section 3), not a feature commit. Everything below assumes it landed.

---

## 1. The tab bar

### 1.1 Recommendation

**Four tabs, plus a persistent toolbar cluster.**

| # | Tab | SF Symbol (selected / plain) | Root view |
|---|---|---|---|
| 1 | **Timetable** | `calendar` | `ScheduleView` |
| 2 | **Mail** | `envelope.fill` / `envelope` (+ unread badge) | `MailboxView` |
| 3 | **Assessments** | `checklist` / `checklist.unchecked` | `AssessmentsView` |
| 4 | **More** | `ellipsis.circle` | `MoreView` |

Toolbar on the Timetable tab (and mirrored into `MoreView`'s header): **campus-status control**
(leading-ish, a `Menu`-backed capsule) and **notifications bell** (trailing, badged). These are W4
page chrome, present on every W4 page (`references/pages/UWCRCN W4.html:37-49`), so they belong in
app chrome, not in a tab.

### 1.2 Justification

* README §7 (`README.md:370-388`) maps BetterLectio's five tabs onto W4 as: Skema → combined AC+EA
  timetable; Beskeder → Mailer; Lektier → **assessments calendar**; Opgaver → *"fold into assessments
  + EE later"*; Mere → everything else. That is literally four tabs. `README.md:22` repeats the rule
  as a hard instruction: *"Do not port lektier/opgaver as two tabs."*
* The Android port already shipped exactly this shape:
  `AppDestination.kt:19-53` declares `Schedule`, `Messages`, `Homework`, `More` and
  `bottomBarItems = entries` (`AppDestination.kt:51`); `BetterW4Root.kt:214-258` wires those four
  `composable` destinations and nothing else. Feature scope is locked to the Android app, so iOS
  ships the same four.
* `AppDestination.kt:18` even documents the direction of travel — *"Primary bottom tabs — mirrors iOS
  AuthenticatedTabShell"* — so converging back on four tabs restores parity rather than breaking it.

### 1.3 What happens to the 5th Lectio tab

`ContentView.swift:86-92` currently declares five tabs (`schedule, messages, homework, assignments,
more`) and `ContentView.swift:149-155` renders `AssignmentsView` as tab 4 ("Opgaver").

**The `assignments` tab is deleted.** W4 has one student-authored deadline surface —
`academics/deadlines` (`W4Urls.kt:89`), the month calendar with *add item* / *Confirm done* /
*Revert to pending* (`README.md:316`, `W4AssessmentParser.kt:66-79`). Lectio's separate "Opgaver"
(assignment hand-ins with submission history and per-assignment grading) has **no W4 analogue**:
there is no `assignments` route in the captured Academics sdmenu (`references/pages/Academics.html:77`).
The `Homework` tab is renamed **Assessments** and becomes the single deadline surface. Anything
Lectio-`Opgaver`-shaped that W4 *does* have — Extended Essay (`academics/ee`), Records of Progress
(`academics/rop`), transcripts — goes to **More ▸ Academics**, not to a tab.

### 1.4 Alternatives considered and rejected

* **A "Home" tab** mirroring `site/index`. Rejected: the Home page is a *composite* of things that
  each belong somewhere better (week grid → Timetable; meters → Absence; birthdays/announcements →
  their own More screens; Links → More). Its unique value — "what is happening today" — is delivered
  by the Today digest on the Timetable tab (§4.1) at zero navigation cost.
* **A "Campus" tab** for status + trips + travel forms. Rejected: setting status is a two-tap action
  that must be reachable from anywhere; a tab that you visit to press one button is a wasted tab.
  The control lives in the toolbar (`campusstatusdropdown.js` shows W4 itself treats it as chrome).
  Trips/travel forms are visited a handful of times a year → More.
* **Five tabs with EA split out**. Rejected: `README.md:19` lists the daily path as "Timetable,
  assessments, mail, campus status, extra-academics", but EA's *daily* surface is the EA timetable,
  which is merged into the Timetable tab as a second data source
  (`W4TimetableParser.mergeWeeks`, `W4TimetableParser.kt:56-64`). EA's non-daily surfaces (activities,
  diary, portfolio, CAS interviews, SafetyNet) go to More ▸ Extra Academics.

---

## 2. Global chrome and navigation model

### 2.1 Shell

`ContentView.swift` keeps its three-state root (`.loading` → `LoadingView`, `.unauthenticated` →
`LoginView`, `.authenticated` → tab shell; `ContentView.swift:19-30`). Everything else in that file
goes (§3).

Each tab owns a `NavigationStack`. Only **More** needs a bound `NavigationPath` (it is the deep tab);
Mail needs one too because compose-then-open-sent must push after the sheet dismisses (existing
pattern, `MessagesView.swift:89-94`). Preserve `TabBarSameTabReselectDetector.swift` — reselecting a
tab scrolls it to top; reselecting **More** additionally pops to root (Android does the same,
`BetterW4Root.kt:142-145`).

### 2.2 Campus status control — `CampusStatusControl.swift` (new)

*Evidence.* `references/pages/UWCRCN W4.html:38-49`:

```html
<div class="status-dropdown"><div class="status oncampus">
  <div class="status-value">on campus</div><div class="location"></div></div></div>
<div class="selection-box"><p>I am currently:</p>
  <span id="location"><input value="oncampus" id="location_0" checked type="radio" name="location">
  <label for="location_0">On campus</label> … <input value="other" id="location_10" …></span>
  <input maxlength="20" type="text" value="" name="other" id="other">
  <input id="submit-campus-status" name="yt0" type="button" value="Set status"></div>
```

Eleven options, verbatim, in order: `On campus`, `On a walk`, `At Raudbua`, `On Jarstadheia`,
`On the island`, `In Flekke`, `In Dale`, `In A building (after 10:30pm)`,
`In K building (after 10:30pm)`, `In Library/Study room (after 10:30pm)`, `Other`.
Mirrored in `CampusStatusParser.kt:22-31`.

*Write path.* `POST index.php?r=site/setstatus` with `status=on|off` and `location` omitted for
on-campus, else the option label or the free-text `other` value (`campusstatusdropdown.js:17-22`,
`README.md:225-234`, `W4Chrome.kt:11-29`).

*iOS shape.* A capsule button in `.toolbar` showing the current label — "On campus" (green dot) or
the location string (amber dot) — opening a `Menu`. `Other` opens a small alert with a `TextField`
(`.maxLength 20`). Optimistic update, revert + inline error on failure. Read state from the parsed
chrome of any loaded page (`CampusStatusParser.parse`, selectors `.status-dropdown .status`,
`.status-value`, `.location`, `#location input[type=radio]`, `CampusStatusParser.kt:35-45`), so it
costs no extra request.

### 2.3 Notifications bell — `NotificationsBell.swift` + `NotificationsListView.swift` (new)

*Evidence.* Chrome container is `div.notifications` (`UWCRCN W4.html:37`, empty in that capture).
`notifications.js:1-58` gives the full interaction contract; `notifications.css:1-60` gives the DOM:

* count badge: `div.notifications .btn-group div.alert`, with severity classes `normal` (blue),
  `new` (green `rgb(150,200,82)`), `overdue` (red `rgb(218,79,73)`)
* task groups: `h3.tasks a.read` (mark all), `dt a.read[data-notification-type]` (mark group),
  `dd li a.read[data-notification-id]` (mark one); `a.clear` variants for clearing
* email groups: `dl.email-list dt` / `dd`, `h3.emails a.read`
* polling: `setInterval(… notification_urls.refresh …, 60000)` **only while the dropdown is closed**
  (`notifications.js:51-57`)
* the response is an HTML fragment swapped in via `$('#header div.notifications').html($(data).children())`
  (`notifications.js:64`) — so the parser must tolerate a wrapper element
  (`W4NotificationParser.kt:41-51`)

Routes: `notifications/{read,readgroup,readall,readallemails,clear,cleargroup,clearall,refresh}`
(`UWCRCN W4.html:24`, `W4Urls.kt:141-148`, `W4Chrome.kt:31-72`).

*iOS shape.* `Image(systemName: "bell")` with `.badge()`; tap presents a `.sheet` with
`.presentationDetents([.medium, .large])` containing two sections — **Tasks** and **Emails** —
each a `List` of rows with a leading severity dot, a "Mark all read" section-trailing button, and
swipe-to-clear. Tapping a row marks it read and routes by `href`: `mailer*` → Mail tab,
`deadline|assessment` → Assessments tab (Android does exactly this in
`ScheduleScreen.kt:113-121`). Poll every 60 s while the app is foreground and the sheet is closed.

---

## 3. Disposition of every existing SwiftUI file

Decisive. `KEEP` = compiles after string/locale swap. `ADAPT` = same view, new data source or
trimmed features. `GUT` = keep the filename, replace the body. `DELETE` = remove from target.

### 3.1 KEEP (near-as-is; strings and locale only)

| File | Change |
|---|---|
| `ScheduleHeaderView.swift` | `"om \(minutesValue) min"` → `"in \(m) min"` (line 40). Nothing else. |
| `AllDayEventsView.swift` | `"Hele dagen"` → `"All day"` (line 19). |
| `LessonContentItemView.swift` | none (renders `LessonContentItem` blocks/links generically). |
| `TimelineListView.swift` | `"Ingen lektioner i dag"` → `"No lessons today"` (line 31). Keep the 8:10 reference-time layout (line 15-17) but make it configurable — W4 grids start at `tt_start_hour = 7` (`UWCRCN W4.html:22`). |
| `ModernScheduleComponents.swift` | same: `startHour`/`endHour` (lines 37-38) must come from `tt_start_hour`/`tt_end_hour`, not hardcoded 8/16. |
| `MessageContentRenderer.swift` | **keep verbatim.** It renders HTML → `AttributedString` via SwiftSoup — exactly what W4's TinyMCE mail bodies need (`README.md:219, 351`). This is the single most reusable message file. |
| `SubjectColorSettingsView.swift` | strings only; the per-subject rename+colour model survives. |
| `SubjectGradeDetailView.swift` | strings; re-point at the W4 grade row model. |
| `PublicProfileImage.swift`, `RateLimitedAvatarImage.swift`, `W4ImageLoader.swift` | keep; re-point base URL at `/…_thumb.jpg` on `w4.uwcrcn.no` (`UWCRCN W4.html:201-203`) and keep the rate limiter (`README.md:259`). |
| `CalendarStripView.swift` | one line: `Locale(identifier: "da_DK")` → `Locale(identifier: "en_GB")` (line 6). W4 is `en-GB` (`README.md:407`). |
| `TabBarSameTabReselectDetector.swift`, `TimeProvider.swift`, `ScheduleLayoutUtils.swift`, `ScheduleIdentity.swift`, `ScheduleEvent+Extensions.swift` | keep. |
| `ReviewPromptSheet.swift` | keep the sheet; rewire `onNegative` (§3.4). |

### 3.2 ADAPT

| File | What changes |
|---|---|
| `ScheduleView.swift` | Remove all four `LiveActivityManager` calls (603, 624, 634, 644), the `ReferralCoordinator`/`ReviewPromptCoordinator` block (607-614), the FAB (`fabLayer`, 545-567) and its `AddPrivateEventView` sheet (679-696). Add the toolbar cluster (§2.2/2.3) and the Today digest (§4.1). Keep the whole layered layout: `headerLayer` / `mainScrollLayer` / pinned `calendarStripHeader` / `weekNumberBadge` / lazy day pager (`ScheduleView.swift:400-478, 569-581`). Keep the multi-target `SchedulableTarget` init (71-84) — it powers "see this person's timetable" from the directory. |
| `MessagesView.swift` | Folder menu becomes exactly two: **Inbox** (`mailer/inbox`) and **Sent** (`mailer/archive`) (`W4Urls.kt:131-133`). Keep search, keep the read/unread swipe, **remove the flag swipe** (lines 183-189) unless a capture proves W4 mail has a flag — mark `UNKNOWN — needs live capture of mailer/inbox row markup`. Row subtitle changes from Lectio's `recipients` to W4's `From` column (`W4MailerParser.kt:23-24, 40`). |
| `ComposeMessageView.swift` | Recipient picker sources from `mailer/extra&type=freeform` (`W4Urls.kt:136`, `README.md:351`). Body editor swaps `BBCodeRichEditor` for a plain multiline editor that emits HTML (`MailerForm[message]` is TinyMCE HTML, `README.md:214`). Fields become `MailerForm[subject]`, `[message]`, `[attachment][]` (multipart, ≤5 × 2 MB), `[sendCC]`, `[attachmentSource]=upload`. Keep `FlowLayout` + `RecipientChip` (lines 241-270, 439+). |
| `AbsenceView.swift` | Keep the two-tab shape (Overview / Registrations) and the donut (`DonutSlice`, line 735) but re-source: AC meter and EA meter, each `You have N absences and M latenesses` (`UWCRCN W4.html:243, 247`; `W4AbsenceParser.kt:23-26, 39-44`). Two rings instead of Lectio's "Almindeligt / Skriftligt". Registrations table from `people/students/absences` / `eaabsences` `table.items` (`W4AbsenceParser.kt:54`). |
| `GradesView.swift` | Re-source from `academics/grades/grades` (`W4Urls.kt:95`). Note `W4GradeParser.kt:8-11` says *"No captured live HTML"* — the grades screen must render a **generic column table** (subject / teacher / level + N grade columns keyed by header slug) and degrade to "no grades" rather than assuming Lectio's SP1/SP2/årskarakter axes. Mark `UNKNOWN — needs live capture of academics/grades/grades`. |
| `SettingsView.swift` | Delete the Live-Activity section (92-122), the feedback + browser-extension section (151-171), and every ASP.NET/autologinkey debug row (181-216). Keep Appearance (Theme / Calendar style / Subject colours / Subject settings, 41-89), Notifications toggle (125-137), Clear cache, About. Add: **Personal feeds** (§4.13), **Log out**. |
| `StudentSearchView.swift` | Rename → `DirectoryView.swift`. `DirectoryPresentation` (line 9-18) loses `.holds`, `.classes`, `.groups`, `.resources` (Lectio concepts) and gains `.allStudents`, `.firstYear`, `.secondYear`, `.byCountry`, `.byHouse`, `.staff`, `.staffOnLeave`, `.rooms` — one case per captured `dynamic_menu_people` link (`School info @ UWCRCN.html:77`). |
| `StudentProfileView.swift` | Re-source from `people/students/student&uwc_id=…` (`W4Urls.kt:121`, `W4PeopleParser.parseProfile`, selector `table.detail-view` at `W4PeopleParser.kt:37`). Fields per `README.md:365`: UWC id, year, names, pronouns, country, email `{uwc_id}@uwcrcn.no`, NC/SO, last login, photo. Keep the embedded week-schedule pane and the `dynamicTypeSize.isAccessibilitySize` branch (line 206). |
| `HomeworkView.swift` | Rename → `AssessmentsView.swift`; see §4.9 — this is a heavy adapt bordering on a rewrite, but the swipe row (`HomeworkSwipeRow`, 202), card (417), status badge (586) and detail sheet (648) all survive. |
| `ContentView.swift` | GUT (below) but the file stays. |

### 3.3 GUT AND REWRITE (filename kept, body replaced)

| File | Why |
|---|---|
| `ContentView.swift` | Every non-tab concern in it is deleted product surface: `ReferralCoordinator` (15, 45-58), `ProfilePictureReviewMonitor` (16, 62-80), `FeedbackCoordinator` + `ShakeListener` + `AuthenticatedSheet` (99-111, 209-232), `.onOpenURL`/`.onContinueUserActivity` referral deep links (49-59), Supabase settings sync (`ContentView.swift:184`), and the `MoreView` body (317-616) which is 300 lines of Lectio catalog grid + profile-picture editor + referral row + browser-extension row. Rebuild as: 4-tab `TabView` + `LoadingView` only. `MoreView` moves to its own file. |
| `LoginView.swift` | It is a MitID/WebView/school-picker screen: `SchoolPickerView` sheet (25-27), `W4WebView` sheet titled "Log ind med MitID" (28-47), `viewModel.lastSchoolHint` resume flow (63-73). W4 needs native username + password → OTP. Target shape is the Android one: single screen, `needsOtp` swaps the field set, "Forgot password" link, demo entry (`LoginScreen.kt:72-251`). See §4.0. |
| `AbsenceView.swift` | listed as ADAPT above; if the W4 meter model lands first, the Overview tab body is a rewrite. |
| `StudentCardView.swift` | It renders a *Lectio* studiekort: `GetImage.aspx?type=studiekortqr&studentid=…` (line 24) and `GetImage.aspx?pictureid=` (line 18). W4 has no QR student card. Rebuild as **ID & Attendance**: photo + name + UWC id + year + house from `site/profile`, and a button that fetches **Letter of Attendance** (§4.14). Keep the flip animation and the card chrome (39-50) — it is good, and the "front = identity / back = document" metaphor survives. |
| `MessageThreadView.swift` | 1000+ lines built on Lectio's thread model: `MessageBubble` (443), reply composer, `MessageEditSheet` (717), `ReactionParticipantsSheet` (800), `ReactionFlowLayout` (823). W4 mail is **one message, no thread, no reply, no reactions** (`README.md:351`: Inbox columns Received/From/Subject; compose is `mailer/send&type=freeform`). Replace with a much smaller `MailMessageView.swift`: header (from / date / subject), body via `MessageContentRenderer`, attachment rows, and a "Reply" button that opens Compose pre-filled with the sender. Salvage into the new file: `AttachmentRow` (863), `QuickLookPreview` (948), `AuthenticatedImageView` (996). |

### 3.4 DELETE

| File | Reason |
|---|---|
| `AddPrivateEventView.swift` | **No W4 analogue.** The captured Home page has no private-event affordance (`UWCRCN W4.html:83-266`); no Academics/EA/School sdmenu link creates a calendar item (`Academics.html:77`, `Extra Academics.html:76`, `School info @ UWCRCN.html:77`); the only student-authored dated item on W4 is a **student assessment** (`README.md:216, 316`). Delete this and `W4HTTPClient+PrivateEvents.swift`, the FAB in `ScheduleView.swift:545-567`, and `ScheduleView.swift:679-696`. |
| `BBCodeRichEditor.swift` | Lectio BBCode. W4 mail is TinyMCE HTML (`README.md:219`). |
| `MessageReactionProtocol.swift` | Lectio reactions. No reaction surface in any captured W4 page. |
| `MessageEditAudit.swift` | Lectio message editing. `mailer` has no edit-sent-mail route in the captured menu. |
| `MessageSignature.swift` | The "Sent with BetterW4" signature is a growth loop. Product decision 2 removed referrals and analytics for the same reason; W4 mail goes to real staff inboxes. Delete, and drop `settings.messageSignatureEnabled` (`SettingsView.swift:141-149`). |
| `AssignmentsView.swift`, `AssignmentsViewModel.swift`, `AssignmentParser.swift`, `AssignmentModels.swift`, `W4HTTPClient+Assignments.swift` | The 5th tab. §1.3. |
| `MessageThreadViewModel.swift` | Rewritten as `MailMessageViewModel.swift`; the old file's reply/reaction/edit state has no target. |
| `W4WebView.swift` | Only consumer was the MitID login sheet. README §4.4 (`README.md:114`) explicitly prescribes native forms, *"no WebView, no ClientJS"*. |
| `AppStoreReviewLauncher.swift` | Keep only if `ReviewPromptCoordinator` survives; the coordinator's `onNegative` currently opens feedback (removed), so rewire `onNegative` to just dismiss + suppress for 90 days, and keep the launcher. |
| Lectio-only UI already gone but still called | `SchoolPickerView`, `BrowserExtensionInviteView`, `FeedbackSheet`, `ReferralView`, `ReferralNudgeView`, `ProfilePictureEditorView` — remove the call sites listed in §0. |

Note on **school picker**: `README.md:151` — *"School picker / gym id in the URL … W4 is one host"*.
Every `gymId` parameter threaded through `ScheduleView`, `TimelineListView`, `StudentCardView`
(`ScheduleView.swift:380, 391`, `StudentCardView.swift:18`) becomes dead weight; strip it in the
same pass or leave a single constant. That is a data-layer decision — flagged here because it shows
up in view signatures.

---

## 4. Screen-by-screen

Format: **file — what it shows — data (route → parser) — navigation edges — empty / error / offline.**

Routes are `https://w4.uwcrcn.no/index.php?r={route}` (`W4Urls.kt:22-36`). Parser names refer to the
Android objects, which are the reference implementations to port; the parser spec in this directory
is authoritative for their internals.

### 4.0 `LoginView.swift` — Log in *(gutted, rewritten)*

* **Shows.** App mark; **Username** (`maxlength 16`, placeholder `e.g. nc26xxxx`) and **Password**
  with a show/hide eye; primary **Log in**; secondary **Try the demo**; footer link **Forgot password**.
  On `needsOtp`, the field set swaps to a single **One-time code** field with a back arrow, title
  "Confirm with code", subtitle "Enter the verification code from W4."
* **Data.** `GET site/login` for the cookie → `POST site/login` with `LoginForm[username]`,
  `LoginForm[password]`, `LoginForm[deviceId]` (stable per-install UUID in Keychain), `yt0=Login`
  (`README.md:92-102, 114-123`). OTP page is `site/verify2fa` (`W4Urls.kt:82`);
  **field names UNKNOWN — needs a HAR of one full login** (`README.md:112, 419`).
  Forgot password: `site/forgotpass`, `ForgotPassForm[username]`, `yt0=Reset` (`README.md:104`).
* **Edges.** Success → tab shell. Demo → tab shell with a "Demo" badge in the More header.
* **States.** Server error surfaced verbatim from Yii `.errorSummary` / `errorMessage`
  (`README.md:255`). Offline → "No internet connection. Check your connection and try again."
  Never auto-retry a failed login.

### 4.1 `ScheduleView.swift` — Timetable *(tab 1, adapted)*

* **Shows.** Live-lesson header (`ScheduleHeaderView`) → week-scrolling date strip (`CalendarStripView`,
  pinned section header) → horizontally paged day view (`TimelineListView` or
  `ModernTimelineListView` per `settingsStore.calendarStyle`) with an all-day chip strip on top.
  Floating week badge. Toolbar: campus control + notifications bell + "Today" button when off-today.
  **New: Today digest** — shown only when the selected date is today, a compact card above the strip
  carrying (a) birthday avatars for today/tomorrow, (b) the newest announcement, (c) the two absence
  meters as small rings. Tapping each pushes the corresponding More screen. Source is the one
  `site/index` fetch we already make.
* **Data.** AC: `academics/timetable/mytimetable`; EA: `extraacademics/timetable/mytimetable`;
  merged via `W4TimetableParser.mergeWeeks` (`W4Urls.kt:90, 108`; `W4TimetableParser.kt:56-64`).
  Home week grid `site/index` gives the same `#timetable` DOM plus rotation-day labels
  (`UWCRCN W4.html:86-190`). Geometry: `.column` per day, absolutely-positioned `.period` blocks at
  1 px ≈ 1 min from `tt_start_hour` (`W4TimetableParser.kt:13-15, 36-49`); `tt_start_hour = 7`,
  `tt_end_hour = 22` (`UWCRCN W4.html:22-23`). Header dates from `#timetable-header .header-cell`
  with `.day-name` + `dd-MMM-yyyy` + `.rotation-day` (`W4TimetableParser.kt:66-72`).
  Optional iCal fast path: `academics/feeds/combottical&token=…` (`README.md:169-180`) — token is a
  secret, Keychain only, never logged.
* **Edges.** Tap event → `LessonDetailSheet` (kept, `ScheduleView.swift:702-786`) with
  `.presentationDetents([.medium, .large])`. Tap a participant → `StudentProfileView`.
  Digest taps → Birthdays / Announcements / Absence.
* **States.** *Empty day*: "No lessons today" + calendar glyph (`TimelineListView.swift:26-35`).
  *Weekend*: W4 marks `.rotation-day.no-classes` → render "Weekend" rather than an empty grid.
  *Error*: keep the existing inline `authErrorBanner` (`ScheduleView.swift:480-524`), retitled
  "Could not reach W4" / "Try again. Your session is still saved." *Offline*: last cached week
  renders with a subtle "Offline — showing saved data" bar; the date strip still scrolls but new
  weeks show a skeleton and a retry.

### 4.2 `MailboxView.swift` (from `MessagesView.swift`) — Mail *(tab 2, adapted)*

* **Shows.** Folder menu in the leading toolbar (**Inbox** / **Sent**), compose button trailing,
  `.searchable` list of rows: avatar (initials fallback), From, Subject, Received, unread dot,
  paperclip when attached.
* **Data.** `mailer/inbox` and `mailer/archive` → `W4MailerParser.parseInbox`. Real selectors:
  `div.grid-view table.items` → `thead th` for column detection (`received` / `send date` / `date`,
  `from`, `subject`) → `tbody tr`, skipping `td.empty`; message id from `href` `[?&]id=(\d+)` or the
  row's `yw0_`-prefixed DOM id (`W4MailerParser.kt:20-52`).
* **Edges.** Row → `MailMessageView` (push). Compose → sheet. Sender name → `StudentProfileView`
  when the row links a `uwc_id`.
* **States.** *Empty*: `ContentUnavailableView` "No mail" / "Messages from staff and classmates show
  up here." *Empty search*: `ContentUnavailableView.search(text:)` (already used,
  `MessagesView.swift:207`). *Error*: centred glyph + message + "Try again"
  (`MessagesView.swift:134-151`). *Offline*: cached list + banner; compose disabled with
  "You are offline".

### 4.3 `MailMessageView.swift` (replaces `MessageThreadView.swift`) — one message *(new file)*

* **Shows.** Subject as inline nav title; sender row (avatar, name, `Received` timestamp); body via
  `MessageContentRenderer.render(html)`; attachment rows with QuickLook preview; a **Reply** button.
* **Data.** `mailer/view&id={id}` (`W4Urls.kt:134`, and `W4Urls.kt` doc comment cites the real
  example `r=mailer/view&id=1`). Body element selector **UNKNOWN — needs live capture of one
  `mailer/view` page**; until then parse `#content_inner` minus the breadcrumb (the pattern
  `W4DocumentsParser.kt:27-45` uses).
* **Edges.** Reply → `ComposeMessageView` pre-filled. Attachment → QuickLook. Sender → profile.
* **States.** Body-less message → "This message has no content." Attachment fetch failure →
  inline row error, per the existing attachment error vocabulary (`strings.xml:129-135`).

### 4.4 `ComposeMessageView.swift` — Compose *(adapted)*

* **Shows.** To (chips + picker), Subject, Body (multiline, emits HTML), attachment chips,
  "Send me a copy" toggle (`MailerForm[sendCC]`), Send.
* **Data.** `POST mailer/send&type=freeform`, multipart, `MailerForm[subject]`, `[message]`,
  `[attachment][]` ≤ 5 × 2 MB, `[sendCC]`, `[attachmentSource]=upload` (`README.md:214, 219`).
  Recipient list: `mailer/extra&type=freeform` (`W4Urls.kt:136`).
* **States.** Send-disabled hint "Add a subject, a recipient and a message." Per-attachment upload
  progress and per-attachment failure with retry/remove. On 403 + `Login Required` → session-expired
  path, draft preserved.

### 4.5 `AssessmentsView.swift` (from `HomeworkView.swift`) — Assessments *(tab 3)*

* **Shows.** Segmented **List** / **Month** at the top. **List** = date-sectioned rows ("Today",
  "Tomorrow", weekday + date), each row: title, subject · teacher · unit, days-left pill, done
  checkbox; swipe → Confirm done / Revert to pending; overdue rows in red. **Month** = a month grid
  with dots, tapping a day filters the list. A `+` in the toolbar adds a **student assessment**.
* **Data.** `academics/deadlines` → `W4AssessmentParser.parse`. Real selectors: `a.assessment-link`
  carrying `data-assessment-id`, `data-assessment-type` (`student` vs class), `data-status`
  (`pending`/…), `data-assessment-date`, `data-subject-name`, `data-teacher-name`, `data-unit`,
  `data-days-left`, `data-css-class` (contains `overdue`) — `W4AssessmentParser.kt:29-63`.
  Action URLs are read out of the page's inline JS as a `{confirm, revert, save, create, delete}`
  map (`W4AssessmentParser.kt:23-26, 66-79`) and POSTed as AJAX
  (`HomeworkRepository.kt:104-106`). Form fields per `README.md:216`: `assessment_id`,
  `student_assessment_id`, `student_deadline_date`, `student_assessment_title`.
  Class-wide view: `academics/classes/assessments/all` (`W4Urls.kt:94`) as a filter chip.
* **Edges.** Row → detail sheet (title, subject, teacher, unit, due date, done toggle). `+` → add
  sheet (title + date; student items only).
* **States.** *Empty*: "All clear!" / "You have nothing due in the next 14 days." (green check).
  *Error*: retry. *Offline*: cached list, done-toggles queue and replay, marked with a small
  "pending sync" glyph. **The done state is server-side on W4** (`README.md:22`) — never let a local
  toggle silently disagree; on replay failure, revert and show a toast.

### 4.6 `MoreView.swift` (extracted from `ContentView.swift`) — More *(tab 4)*

Root list. Sections and rows, in order:

* **Header card** — avatar, display name from `Welcome, {name}` in `#user-panel`
  (`UWCRCN W4.html:55`; `W4IdentityParser`), UWC id + year; tap → **ID & Attendance** (§4.14).
* **Academics** — Grades · Transcripts · SAT/ACT · Records of Progress · Extended Essay ·
  My classes · All classes · Subject pages · Testimonial form
  (`W4Urls.kt:92-102`, `Academics.html:77`)
* **Attendance** — My absences (AC) · My EA absences · Register absences
  (`W4Urls.kt:118-120`)
* **Extra Academics** — My activities · EA diary · Portfolio · CAS interviews · SafetyNet ·
  All EA / EAC / CR / PBL / Leirskule · EA documents (`W4Urls.kt:110-116`, `Extra Academics.html:76`)
* **Boarding** — Campus status · Trips · Travel forms · Resource bookings
  (`W4Urls.kt:103-105`, `README.md:318-322`)
* **School** — People (directory) · My teachers/group leaders · Rooms · Birthdays · Announcements ·
  Documents · Links (`School info @ UWCRCN.html:77`)
* **App** — Settings · Notifications · Log out

This is a superset of Android's More root (Grades, Absence, People, Documents, Trips, Settings,
Log out — `MoreScreen.kt:2252-2302`) because iOS gets the full captured menu; Android's
`MoreDestination` enum (`MoreViewModel.kt:63-66`) is the shipped-today subset and the sensible
**phase-1 cut**. Rows not yet backed by a parser render with a "Coming soon" disclosure rather than
being hidden, so the IA is stable across phases.

* **States.** No network → rows still render; each destination handles its own offline state.

### 4.7 `AbsenceView.swift` — Absence

* **Shows.** Segmented **Academics** / **Extra Academics**; two big rings (Absences, Latenesses) with
  the raw counts under them; below, the registration list grouped by date.
* **Data.** Meters from Home (`#academic-absences`, `#ea-absences`, text
  `You have N absences and M latenesses so far`, `UWCRCN W4.html:240-248`;
  `W4AbsenceParser.kt:23-26, 38-44`) or from the detail page itself. Lists from
  `people/students/absences` and `people/students/eaabsences` → `table.items`
  (`W4AbsenceParser.kt:54-58`), columns matched by header keyword sets
  (`date`, `period`, `class`, `type`, `status`, `comment`, `teacher` — `W4AbsenceParser.kt:29-35`).
* **Edges.** "Register absence" → §4.8.
* **States.** Empty → "No absence records". Error/offline standard.

### 4.8 `RegisterAbsenceView.swift` *(new)*

* **Shows.** A date field (`dd-MMM-yy` picker, W4 uses an `en-GB` jQuery datepicker) and a list of
  that day's slots with checkboxes; Submit.
* **Data.** `POST people/students/absences/register`, `StudentAbsenceForm[absence_date]` plus
  per-slot checkboxes injected by W4's own JS (`README.md:213`).
  **Checkbox field names UNKNOWN — needs live capture of the register page.**
* **States.** Until captured, this screen ships behind a "Coming soon" row.

### 4.9 `DirectoryView.swift` (from `StudentSearchView.swift`) — People

* **Shows.** `.searchable` list; scope chips **All students / 1st year / 2nd year / By country /
  By house / Staff / Staff on leave / Rooms**; pinned people float to the top (keep the existing pin
  affordance).
* **Data.** `people/students/{all,firstyear,secondyear,byname,bypreferred,bycountry,byhouse}`,
  `people/staff/{current,onleave}`, `academics/timetable/room`
  (`School info @ UWCRCN.html:77`, `W4Urls.kt:122-127, 106`).
  Parser: `W4PeopleParser.parse` — defensive, keys off any `a[href*=uwc_id]` plus
  `table.items tbody tr` (`W4PeopleParser.kt:24-31`). Avatars: `/…{uwc_id}_thumb.jpg`
  (`UWCRCN W4.html:201`), rate-limited (`README.md:259`).
* **Edges.** Person → `StudentProfileView`; room → room timetable via the multi-target `ScheduleView`.
* **States.** Empty search → "No results" / "Try another search or category."
  Offline → the cached directory (this is the one dataset worth syncing eagerly).

### 4.10 `SettingsView.swift` — Settings *(adapted)*

Sections: **Appearance** (Theme segmented System/Light/Dark; Calendar style Timeline/List; Subject
colours toggle; Subject settings) · **Notifications** (enable; which W4 notification types)
· **Personal feeds** (§4.13) · **Data** (Clear cache) · **About** (app, version, GitHub) · **Log out**.

### 4.11 `NotificationsListView.swift` *(new)* — see §2.3.

### 4.12–4.20 New screens W4 needs (sketches)

**4.12 `TripsView.swift`** — `academics/trips` (`W4Urls.kt:103`). List of cards: trip name (title),
`Outgoing → Return` dates, destination, type, participants count, and a status pill —
Planning (grey) / Pending confirmation (amber) / Approved (green) / Cancelled (strikethrough red)
per `README.md:318`. Parser `W4TripsParser.parse`: `#content_inner table` → `tbody tr`, 7 cells
in order name, outgoing, returning, destination, type, participants, status
(`W4TripsParser.kt:16-33`); skip `td.empty`. Toolbar `+` = **Plan new trip** —
**POST payload UNKNOWN — needs live capture of the trip-create form** (`README.md:421`); until then
the `+` opens the W4 trip form in `SFSafariViewController` (Home's Links list already points at
`r=academics/trips` as "Trip Form", `UWCRCN W4.html:262`). Empty: "No trips".

**4.13 `TravelFormsView.swift`** — `academics/travel/travel.list` (`W4Urls.kt:104`). Four fixed rows,
one per journey: *To school (autumn)*, *Home (winter)*, *Back after winter*, *Home (summer)*
(`README.md:320`), each with a completion checkmark, plus a fifth row **Manage my travel contacts**.
Tapping a journey pushes a read-only detail; editing is `SFSafariViewController` in v1.
**Form fields UNKNOWN — needs live capture.**

**4.14 `AttendanceLetterView.swift` / ID card** — `people/students/letter/attendance`
(`W4Urls.kt:128`, `School info @ UWCRCN.html:77`). Front: identity card (photo, name, UWC id, year,
house) from `site/profile`. Back / button: **Letter of Attendance**. Note a contradiction to resolve:
`README.md:326` describes it as *"large generated document (HTML ~600KB+)"*, but the Android
implementation fetches bytes and **requires a `%PDF-` magic prefix**, erroring otherwise
(`StudiekortRepository.kt:90-100`). iOS must handle both: if the bytes start with `%PDF-` show a
`QuickLook` preview and a share sheet; else render the HTML in a `WKWebView` and offer
"Save as PDF" via `UIPrintPageRenderer`. **Which one it actually is: UNKNOWN — needs live capture.**

**4.15 `DocumentsBrowserView.swift`** — `documents/index` (+ `&folder_id=` / `&page_id=`)
and `extraacademics/documents` (`W4Urls.kt:138, 116`). A drill-down browser: a `List` of folder rows
(folder glyph, chevron) and page rows (doc glyph); pushing a page renders its HTML body.
Real markup from the capture (`Documents.html:80-83`):
`<ul class="folder-list"><li><a class="folder" href="…&folder_id=27">Internal Information</a></li>…`.
`W4DocumentsParser` selects `#content_inner`, then `a.folder` (id from `folder_id=(\d+)`) and
`a.page` (id from `page_id=(\d+)`); when both are empty and a heading exists it treats the page as a
leaf and returns `bodyHtml` (`W4DocumentsParser.kt:27-45`). **`a.page` markup UNKNOWN — the capture
only contains the root folder listing; needs a capture of one folder.** Breadcrumb from the pushed
stack, mirroring Android's `documentsStack` (`MoreViewModel.kt:242-245`). Empty: "No documents".

**4.16 `EAActivitiesView.swift`** — `extraacademics/activities/myactivities` plus the browse routes
`extraacademics/activities/ea&type={eac|cr|pbl|leirsk}` (`W4Urls.kt:110, 115`,
`Extra Academics.html:76`). Segmented **Mine** / **All**, with filter chips *Running / Past / Future*
and a sort control *By name / By weekday* (`README.md:343`). Rows: activity name, leader, weekday +
time, type badge (EAC / Campus responsibility / PBL / Leirskule).

**4.17 `EADiaryView.swift`** — `extraacademics/activities/myactivities/diary` (`W4Urls.kt:111`).
Entry list by week; composer with a free-text field plus multi-select **learning outcomes**
(`EAGroupStudentModel[outcomes][]`, `README.md:343`). The outcome vocabulary is
**UNKNOWN — needs live capture**.

**4.18 `EAPortfolioView.swift`** — `extraacademics/activities/myportfolio` (`W4Urls.kt:112`).
Read-only sectioned summary of activities + outcomes achieved.

**4.19 `CASInterviewsView.swift`** — `extraacademics/activities/interviews` (`W4Urls.kt:113`).
Three fixed rows (interviews 1–3) with date and status; a "Export PDF" action per `README.md:338`.

**4.20 `SafetyNetView.swift`** — `extraacademics/safetynet/mysafetynet` (`W4Urls.kt:114`).
Segmented **Graph** / **Table** over weekly rows with columns Period, Status, Average wellness,
Sleep, Exercise (`README.md:217, 345`). Graph = three sparkline series (wellness / sleep / exercise).
A `+` adds a report for the current or a past week. **This screen is pastoral, not academic** —
treat the numbers as private: no badge, no notification, no widget, and no caching to a shared
container. **Create-form fields UNKNOWN — needs live capture.**

**4.21 `BirthdaysView.swift`** — `people/birthdays` (`W4Urls.kt:129`), plus Home's today/tomorrow
blocks: `#birthdays-today` / `#birthdays-tomorrow` each an `<ul><li><a href="…uwc_id=…"><img
class="photo" width="40" src="…{uwc_id}_thumb.jpg">` (`UWCRCN W4.html:197-218`). Screen: **Today**
and **Tomorrow** avatar rows at the top, then a month calendar below. Tap → profile.
Empty: "No birthdays today".

**4.22 `AnnouncementsView.swift`** — Home's `#announcements-content` (`UWCRCN W4.html:220-229`,
literal empty state in the capture is `<p>No announcements...</p>`) and the public feed
`site/rss` (`W4Urls.kt:86` — unauthenticated, so it works even with a dead session). List of
title + date + body; pull to refresh. Empty: "No announcements".

**4.23 `ResourceBookingsView.swift`** — `academics/resources/resources` (`W4Urls.kt:105`).
Month calendar of bookings + **Book resource** sheet. Fields per `README.md:216`:
`day, month, year, reservation_id, time_start, time_end, description, resource_id`.
Resources are rooms/spaces (classrooms, Auditorium, Høegh Kitchen, …, `README.md:322`).
**Resource id list UNKNOWN — needs live capture of the booking form's `<select>`.**

**4.24 `QuickLinksView.swift`** — the configurable Home `#links` list (`UWCRCN W4.html:261-262`):
UWCRCN Extra Academic Website, RCN College Policies Drive, Trip Form, Høegh Kitchen Booking Form,
**ManageBac**, Bakehus, Haugland times, Learning support, 6 Stiar, Lavvo Booking. Rows open
in-app when the href is a `documents/index&page_id=` route, and in `SFSafariViewController` otherwise.
`README.md:388`: **do not scrape ManageBac** — it is a link, full stop.

**4.25 `PersonalFeedsView.swift`** — `academics/feeds` (`W4Urls.kt:101`). Lists the per-user RSS/iCal
URLs (`acttrss`, `eattrss`, `combottrss`, `sassttrss` and the `…tical` variants, `README.md:169-178`).
UI: a row per feed with **Copy link** and **Add to Calendar**; the `token=` is masked on screen
(`••••`) and never rendered in full, never logged, never put in a screenshot
(`README.md:180, 423`).

---

## 5. English string plan

### 5.1 Policy

1. **English is the only language.** One `en.lproj/Localizable.strings`. No `da.lproj`, no
   `AppLanguage` picker (drop Android's `settings_language*`, `strings.xml:286-289`).
2. **Every user-visible string moves out of the view into `Localizable.strings`** with a dotted key
   (`schedule.empty_day`, `mail.compose_title`, …) accessed via
   `String(localized:defaultValue:)`. The existing file already uses this convention
   (`en.lproj/Localizable.strings:1-86`) — but ~90 % of its current keys are for deleted features
   (`browser_extension.*`, `profile_picture.*`) and must be purged; keep only `common.*`,
   `review_prompt.*`.
3. **Match W4's own English, not a translation of the Danish.** Where W4 has a label, use it verbatim:
   "on campus", "Set status", "Confirm done", "Revert to pending", "Letter of Attendance",
   "Academics Attendance Meter", "College Announcements", "Birthdays!"
   (`UWCRCN W4.html:40, 48, 195, 223, 241`; `README.md:216`). This keeps the app legible next to the
   website students also use.
4. **Dates and numbers use `en_GB`**, matching W4 (`dd-MMM-yyyy` e.g. `14-Aug-2026`,
   `README.md:407`; `UWCRCN W4.html:94`). Replace both `Locale(identifier: "da_DK")` occurrences
   (`CalendarStripView.swift:6`, `HomeworkView.swift:12`). Week numbering stays ISO (Monday-first) —
   already correct (`ScheduleView.swift:98`).
5. **Domain vocabulary is UWC's, not Lectio's.** "lesson" not "modul"; "assessment" not "homework"
   or "assignment"; "class" = an academic course; "house" = boarding house; "EA" = Extra Academics
   and is *never* expanded to "extracurricular".
6. **A CI check** greps the target for `[æøåÆØÅ]` in string literals and for the Danish word list in
   §5.2; the build fails if any survive outside a comment. Today there are 112 `lectio.dk`/`.aspx`
   hits and dozens of Danish literals, so the check must be added *after* the demolition commit.

### 5.2 Translation table

Recurring Danish UI strings found in `ios/BetterW4/*.swift` and
`android/app/src/main/res/values/strings.xml`, with their English replacements.

**Navigation and chrome**

| Danish | English | Seen at |
|---|---|---|
| Skema | Timetable | `ContentView.swift:130`, `strings.xml:5` |
| Beskeder | Mail | `ContentView.swift:136`, `MessagesView.swift:28`, `strings.xml:6` |
| Lektier | Assessments | `ContentView.swift:145`, `HomeworkView.swift:40` |
| Opgaver | *(tab deleted)* / Assessments | `ContentView.swift:153`, `strings.xml:7-8` |
| Mere | More | `ContentView.swift:172,496`, `strings.xml:9` |
| Studie | Academics | `ContentView.swift:414` |
| Skole | School | `strings.xml:251` |
| Legitimation | ID | `ContentView.swift:450` |
| App | App | — |
| Tilbage | Back | `strings.xml:119` |

**Auth and session**

| Danish | English |
|---|---|
| Log ind | Log in |
| Log ind med MitID | *(deleted)* |
| Log ud | Log out |
| Brugernavn | Username |
| Kodeord | Password |
| Vis / Skjul kodeord | Show / Hide password |
| Engangskode | One-time code |
| Bekræft med kode | Confirm with code |
| Indtast bekræftelseskoden fra W4. | Enter the verification code from W4. |
| Forkert brugernavn, kodeord eller kode. | Wrong username, password or code. |
| Godkender… | Signing in… |
| Din session er udløbet. Log ind igen. | Your session expired. Log in again. |
| Forbindelsen til W4 fejlede | Could not reach W4 |
| Prøv igen. Din session er stadig gemt. | Try again. Your session is still saved. |
| Prøv demo | Try the demo |

**Common actions and states**

| Danish | English |
|---|---|
| Indlæser… / Indlæser | Loading… |
| Henter dine lektier… / Henter beskeder… / Henter karakterer… | Loading assessments… / Loading mail… / Loading grades… |
| Prøv igen | Try again |
| Annuller | Cancel |
| Gem | Save |
| Luk | Close |
| Slet | Delete |
| Send | Send |
| Ryd | Clear |
| Ryd cache | Clear cache |
| Fortryd | Undo |
| Nulstil / Nulstil alle tilpasninger | Reset / Reset all customisations |
| Færdig | Done |
| Marker som færdig | Mark as done |
| Noget gik galt / Hov, der skete en fejl | Something went wrong |
| Ingen internetforbindelse | No internet connection |
| Ingen resultater | No results |

**Timetable**

| Danish | English |
|---|---|
| Ingen lektioner i dag | No lessons today |
| Ingen skemadata | No timetable data |
| Uge %d | Week %d |
| I dag / I morgen / I går | Today / Tomorrow / Yesterday |
| Hele dagen | All day |
| om %d min | in %d min |
| %d min (tilbage) | %d min left |
| Aflyst | Cancelled |
| Ændret | Changed |
| Modul | Lesson |
| Lokale | Room |
| Lærer / Lærere | Teacher / Teachers |
| Elev / Elever | Student / Students |
| Deltagere | Participants |
| Indhold / Øvrigt indhold | Content / Other content |
| Ingen indhold | No content |
| Noter / Note fra lærer | Notes / Teacher's note |
| Ressourcer | Resources |
| Ny privat aftale, Privat aftale, Gem aftale … | *(all deleted — no W4 analogue)* |
| Skolekalender | School calendar |

**Mail**

| Danish | English |
|---|---|
| Ny besked | New message |
| Emne | Subject |
| Modtagere / Vælg modtagere | Recipients / Choose recipients |
| Besked | Message |
| Indbakke / Sendt | Inbox / Sent |
| Søg i beskeder | Search mail |
| Ingen beskeder | No mail |
| Læst / Ulæst | Read / Unread |
| Marker som læst / ulæst | Mark as read / unread |
| Besked sendt | Message sent |
| Sender… | Sending… |
| Vedhæft / Vedhæftet / Fjern vedhæftning | Attach / Attachment / Remove attachment |
| Foto eller video / Fil | Photo or video / File |
| Uploader %@… | Uploading %@… |
| Højst %d vedhæftninger | Up to %d attachments |
| Skriv svar… | Write a reply… |
| Besvar | Reply |
| Tilføj reaktion, Reagerede med, Rediger besked, Flag | *(all deleted — no W4 analogue)* |
| Kunne ikke åbne filen | Could not open the file |
| Gemt i Downloads | Saved to Files |

**Assessments**

| Danish | English |
|---|---|
| Ingen opgaver | Nothing due |
| Alt klaret! | All clear! |
| Du har ingen lektier de næste 14 dage. | You have nothing due in the next 14 days. |
| Deadline | Due |
| Om %d dage | In %d days |
| %d dage forsinket | %d days overdue |
| Uden dato | No date |
| Afventer / Afventer dig | Pending |
| Status | Status |
| *(new, from W4)* | Confirm done · Revert to pending |

**Absence, grades, people**

| Danish | English |
|---|---|
| Fravær | Absence |
| Samlet fravær | Total absence |
| Fravær pr. fag | Absence by class |
| Registreringer / Fraværsregistreringer | Registrations |
| Ingen fraværsregistreringer fundet | No absence records |
| Årsag / Forklaring | Reason / Explanation |
| Rediger fravær | Edit absence |
| Mangler / Manglende fraværsårsager | Missing / Missing absence reasons |
| Almindeligt / Skriftligt | *(replaced by)* Absences / Latenesses |
| Akademisk / EA | Academics / Extra Academics |
| Karakterer / Karakteroversigt | Grades |
| Gennemsnit | Average |
| Fag | Subject |
| Vægt | Weight |
| Ingen karakterer fundet | No grades found |
| Personer | People |
| Elever / Lærere / Klasser / Hold / Lokaler / Grupper / Ressourcer | Students / Staff / Classes / *(drop)* / Rooms / *(drop)* / Resources |
| Fastgør / Fjern fastgørelse / Fastgjorte | Pin / Unpin / Pinned |
| Skriv besked | Write a message |
| Se skema | View timetable |
| Fødselsdag | Birthday |
| Studiekort | *(replaced by)* ID & Attendance |
| Fremmødebrev (PDF) | Letter of Attendance |

**Settings and app**

| Danish | English |
|---|---|
| Indstillinger | Settings |
| Udseende | Appearance |
| Tema · System / Lys / Mørk | Theme · System / Light / Dark |
| Kalenderstil · Tidslinje / Liste | Calendar style · Timeline / List |
| Fagfarver / Fagindstillinger / Farve / Visningsnavn / Tilpasset | Subject colours / Subject settings / Colour / Display name / Customised |
| Notifikationer | Notifications |
| Aflyste og ændrede moduler | Cancelled and changed lessons |
| Nye beskeder | New mail |
| W4-notifikationer | W4 notifications |
| Notifikationshistorik | Notification history |
| Data & privatliv | Data |
| Privatlivspolitik | Privacy policy |
| Version / Om | Version / About |
| Kommer snart. Under opbygning. | Coming soon. |
| Sprog · Dansk / English | *(section deleted)* |
| Inviter venner, Send feedback, Browser-udvidelse, Skift profilbillede | *(all deleted)* |

**Campus and boarding (new — use W4's own English)**

| Concept | String |
|---|---|
| Status chip, on campus | On campus |
| Status chip, off campus | *(the selected location, e.g.)* On a walk |
| Picker title | Where are you? |
| Picker submit | Set status |
| Other free text | Other · placeholder "Where? (max 20 characters)" |
| Trips empty | No trips |
| Trip statuses | Planning · Pending confirmation · Approved · Cancelled |
| Travel forms | To school (autumn) · Home (winter) · Back after winter · Home (summer) · Manage my travel contacts |
| Documents empty | No documents |
| SafetyNet columns | Period · Status · Average wellness · Sleep · Exercise |

**Do not translate** (proper nouns / W4 identifiers): `W4`, `UWCRCN`, `ManageBac`, `EA`, `EAC`, `PBL`,
`Leirskule`, `Raudbua`, `Jarstadheia`, `Flekke`, `Dale`, `Bakehus`, `Haugland`, `Lavvo`, `Høegh`,
`SafetyNet`, `CAS`, `IB`, `TOK`, `NC`/`SO`, house names, and the eleven campus-location labels.

---

## 6. Accessibility, Dynamic Type, dark mode — what to preserve and what to fix

### 6.1 Preserve

* **Theme control.** `ContentView.swift:31` applies `.preferredColorScheme(settingsStore.preferredColorScheme)`
  where `nil` follows the device (`SettingsStore.swift:52-53, 199-201`). Keep; the picker stays in
  Settings (`SettingsView.swift:42-50`).
* **Semantic colours everywhere.** The codebase already uses
  `Color(UIColor.systemBackground)` / `.systemGroupedBackground` / `.secondarySystemGroupedBackground` /
  `.tertiarySystemGroupedBackground` / `.separator` rather than literals
  (`ScheduleView.swift:444, 571`; `ContentView.swift:436, 553, 557`; `StudentCardView.swift:43`).
  Keep this rule absolutely; no hex colours in view code.
* **Scheme-aware opacity ramps** for subject-tinted surfaces, so tinted blocks stay legible on both
  backgrounds: `AllDayEventsView.swift:48-53`, `ModernScheduleComponents.swift:204-208`,
  `TimelineListView.swift:392-413`. These ramps are the reason the timetable looks right in dark
  mode; port them to every new tinted surface (assessment rows, trip status pills, EA type badges).
* **Accessibility-size branch.** `StudentProfileView.swift:24-25, 206`
  (`@Environment(\.dynamicTypeSize)` + `if dynamicTypeSize.isAccessibilitySize`) reflows the profile
  header. Copy this pattern into the new Today digest and the campus control.
* **Reduce Motion.** `StudentProfileView.swift:24` reads `accessibilityReduceMotion`. Extend it to
  the `StudentCardView` flip and the tab cross-fades.
* **Haptics.** `.sensoryFeedback(.selection, trigger: selectedDate)` on the date strip
  (`CalendarStripView.swift:123`). Add the same on campus-status change and on assessment
  confirm-done.
* **`ContentUnavailableView`** for empty and no-search-results states
  (`MessagesView.swift:207`) — make it the standard for every empty state in the app.
* **Pull to refresh** on every list (`.refreshable`, 8 existing sites).
* **`minimumScaleFactor`** on constrained labels (6 sites, e.g. `LoginView.swift:112`,
  `ContentView.swift:541`) — keep, but only as a last resort after wrapping.

### 6.2 Requirements for new and rewritten screens

1. **Dynamic Type to `.accessibility5` without clipping.** No fixed-height rows containing text.
   The timetable's absolute-positioned blocks (`TimelineListView.swift:37-45`) are the hard case: at
   accessibility sizes, collapse the day page to the **list** calendar style automatically rather
   than clipping a 1 px/min grid.
2. **Every icon-only control gets `accessibilityLabel`.** Today 18 labels exist for far more than 18
   icon buttons. New required labels: notifications bell (with count in the value —
   `"Notifications, 3 unread"`), campus status (label "Campus status", value the current location),
   compose, add assessment, confirm done, back.
3. **Grouped rows are single accessibility elements.** Timetable blocks, mail rows and assessment
   rows must use `.accessibilityElement(children: .combine)` with a composed label
   (`"Biology, 09:00 to 10:00, room A12, cancelled"`), not eight separate swipes.
4. **Colour is never the only signal.** Status today is colour-coded (cancelled red, changed amber —
   `ScheduleView.swift:805-823`). Every status must also carry text or a glyph: cancelled gets a
   strikethrough (already done in `AllDayEventsView.swift:64`), changed gets
   `exclamationmark.circle.fill` (already done, `AllDayEventsView.swift:78`), campus off-campus gets
   the location text, not just an amber dot, notification severity gets a word not just
   green/red (`notifications.css:38-46`).
5. **Contrast.** Subject-colour text at `.opacity(0.55)`/`0.6` on tinted fills
   (`TimelineListView.swift:392-395`) must be re-checked against 4.5:1 for body text in both schemes;
   raise the floor or darken the fill where it fails.
6. **Swipe actions always have a non-swipe equivalent.** Confirm-done, mark-read and delete must each
   also be reachable from the row's detail view or a context menu — swipe-only is inaccessible with
   VoiceOver's rotor on some rows.
7. **Dark mode is a first-class review gate.** Every new screen ships with a
   `#Preview` pair (light + `.preferredColorScheme(.dark)`); the pattern already exists at
   `MessageThreadView.swift:1098`.
8. **No colour-only "demo" indicator.** The demo badge must be a text badge.

---

## 7. Open questions — each needs one live capture

| # | Question | Capture that resolves it |
|---|---|---|
| 1 | OTP form field names on `site/verify2fa` | HAR of one full login: password POST → OTP page → home (`README.md:419`) |
| 2 | `mailer/view` body container selector; whether a Reply route exists; whether mail can be flagged or deleted | GET `index.php?r=mailer/view&id={id}` HTML |
| 3 | `academics/grades/grades` table shape (columns, whether HL/SL and predicted grades are separate columns) | GET the grades page (`W4GradeParser.kt:8-11` admits it is unverified) |
| 4 | Assessment create / confirm-done POST payloads | Network capture of a real "Confirm done" and "Add item" (`README.md:421`) |
| 5 | `documents/index&folder_id=` page markup — is a leaf page `a.page` or a different class? | GET one folder and one page |
| 6 | Letter of Attendance content type: PDF bytes or 600 KB HTML? | GET `people/students/letter/attendance` and inspect the first bytes + `Content-Type` |
| 7 | `people/students/absences/register` slot checkbox field names | GET the register page with a real timetable day |
| 8 | Resource booking form: `resource_id` option list and time-slot granularity | GET `academics/resources/resources` + open "Book resource" |
| 9 | EA diary outcome vocabulary (`EAGroupStudentModel[outcomes][]` values) | GET the diary composer |
| 10 | SafetyNet weekly-report create form fields | GET `extraacademics/safetynet/mysafetynet` |
| 11 | Trip create POST payload and the status vocabulary as rendered | GET "Plan new trip" |
| 12 | A `notifications/refresh` HTML sample with real items (the saved Home page has an empty `div.notifications`, `UWCRCN W4.html:37`) | POST `notifications/refresh` with a session that has unread items |
