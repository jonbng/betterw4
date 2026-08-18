# BetterW4 iOS — file inventory & disposition

Status: research output. No Swift file was modified by this task.
Evidence date: 2026-08-15. Author agent read every file listed and ran a real build.

> **Snapshot warning — the tree moved while this was being written.**
> Everything below describes the tree as of **2026-08-15 22:36–22:44** (a byte-exact copy was
> taken at 22:44 and is what the build evidence in §A was produced from). Between **22:54 and
> 23:02** a parallel agent began applying changes that overlap §C Step 2. Observed by mtime at
> 23:02: 19 app files edited (`AbsenceViewModel`, `BetterW4App`, `ContentView`, `CookieManager`,
> `HomeworkViewModel`, `KeychainManager`, `MessageThreadView`, `MessageThreadViewModel`,
> `MessagesViewModel`, `ReviewPromptCoordinator`, `ScheduleView`, `ScheduleViewModel`,
> `SettingsStore`, `SettingsView`, `StudentModels`, `StudentProfile`, `StudentProfileView`,
> `StudentSearchView`, `SubjectColorSettingsView`); 2 app files added (`W4DeviceID.swift`,
> `W4Routes.swift` — these overlap §5.1 `W4Urls.swift`/`W4DeviceIdStore.swift`, reconcile names);
> 9 of the 10 test files deleted and replaced by a single `W4FixtureTests.swift`; and
> `BetterW4Tests/Fixtures/` replaced with `Fixtures/W4/{home,academics-menu,extraacademics-menu,school-menu,documents}.html`
> (i.e. §5.6 was started). **Re-verify line numbers before acting on §A and §B** — the
> *classification* stands, the *coordinates* may not.

---

## 0. Method, and one correction to the brief

The brief says "95 Swift files". The actual tree is:

```
$ ls /Users/johannes/Projects/betterw4/ios/BetterW4/*.swift        →  94 files, 30 090 LOC
$ ls /Users/johannes/Projects/betterw4/ios/BetterW4Tests/*.swift   →  10 files,    752 LOC
                                                                    104 files, 30 842 LOC
```

Plus non-Swift members of the two targets:
`BetterW4/Info.plist`, `BetterW4/BetterW4.entitlements`, `BetterW4/en.lproj/Localizable.strings`,
`BetterW4Tests/Fixtures/` (7 HTML + 1 JSON at top level, 4 HTML under `Fixtures/Absence/`).

The Xcode project is `objectVersion = 77` and uses **`PBXFileSystemSynchronizedRootGroup`**
(`BetterW4.xcodeproj/project.pbxproj:41-55`) — there is **no file list in the pbxproj**
(`grep -c '\.swift' project.pbxproj` → `0`). Adding or deleting a `.swift` file under
`ios/BetterW4/` or `ios/BetterW4Tests/` changes the build with no project edit. Only one SPM
dependency is declared: SwiftSoup (`project.pbxproj:505-514`, `repositoryURL = "https://github.com/scinfu/SwiftSoup.git"`).
There is **no Supabase package**, which is why `import Supabase` is a hard compile error today.

**How the disposition was verified.** Beyond reading the files, I copied the tree to a scratch
directory, added one throw-away `_DeadStubs.swift` declaring every missing symbol, and iterated
`xcodebuild … build` until it reported **BUILD SUCCEEDED**, then `build-for-testing` until that
also succeeded. Section A below is therefore the *complete and closed* dead-reference list: the
stub file's final contents are exactly the set of symbols the tree references but does not define.
Two additional genuine compile errors surfaced that are unrelated to any deleted subsystem
(§A.14, §A.15).

**Footgun for the next agent:** `/Users/johannes/Projects/betterw4/ios/.gitignore` exists, `ios/`
is untracked in the parent repo, and the harness `grep`/`rg` wrappers run with `--ignore-files`.
Every ripgrep-style search over `ios/BetterW4` silently returns **zero hits**. Use
`command grep -rn …` (the real binary) or you will conclude the tree is already clean. It is not.

Columns in the table: **LOC** = `wc -l`. **DA** = number of string literals containing Danish
(`æøå` or a Danish UI word — see the detector note under §B.4); 62 of 104 files contain at least
one, 521 literals total. **Coupling** = none / cosmetic (Danish strings & naming only) /
structural (shape follows Lectio's data model or endpoint set, but the mechanism is reusable) /
total (body is Lectio selectors or `.aspx` URLs end to end).

---

## 1. Disposition table — app target (`ios/BetterW4/`, 94 files)

### 1.1 Networking, session, auth

| file | LOC | DA | coupling | disposition | notes |
|---|---|---|---|---|---|
| `W4HTTPClient.swift` | 703 | 0 | structural | **ADAPT** | Best asset in the repo. Keep `PriorityRequestLimiter` (l.606-703, serial + 100 ms cooldown — README §5.5 asks for exactly this), `W4RequestLog` (l.10-32), `W4URLSessionTaskCookieRegistry` (l.75-97), the per-hop `Set-Cookie` merge in `W4URLSessionDelegate` (l.121-168), the 3-attempt retry loop (l.215-251). Must change: hardcoded `Referer: https://www.lectio.dk` (l.380, l.442); `compactPath` special-cases `lectio.dk` (l.27-29); `isW4UniLoginURL` (l.116-118, l.145, l.399, l.481, l.506) → delete, replace with "final URL/`Location` contains `r=site/login`" per README §4.5; `isRobotDetectionPage` (l.579-583, Danish, `RobotDetection.aspx`) → delete, W4 has no robot page; the change-detection compares `autologinkey`/`sessionId` (l.228-230, l.344-346) → single `PHPSESSID`. The class currently follows redirects **twice** (URLSession delegate *and* the manual `case 301,302,…` loop at l.491-512) — README §5.4 wants manual only. |
| `CookieManager.swift` | 449 | 2 | total | **RENAME+ADAPT** → `W4SessionCookieStore.swift` | Whole file is the two-primary-cookie model: `primaryCookieNames = ["ASP.NET_SessionId", "autologinkeyV2"]` (l.52), `extractW4Credentials` requires both (l.82-86), seeds `isloggedin3=Y` (l.103-106), `cookieHeader` orders those three (l.124-140), `makeW4ASPNETSessionCookie` (l.339), `makeW4AutologinkeyV2Cookie` (l.411). W4 has exactly one cookie (README §4.1). Keep only the *shape*: WKWebView-store enumeration and the "ignore empty `Set-Cookie` values" rule. `W4ActiveWebViewRegistry` (l.12-46) exists only for the login WebView → delete with `W4WebView.swift`. |
| `KeychainManager.swift` | 258 | 0 | cosmetic | **KEEP** | Generic `kSecClassGenericPassword` wrapper, `kSecAttrAccessibleAfterFirstUnlock`. Only edits: `service = "dk.elliottf.betterw4"` (l.17) should become the real bundle id, and 6 Danish error strings. See §A.16 — the app currently gets `errSecMissingEntitlement (-34018)` from `wipeAll` in the simulator. |
| `StudentModels.swift` | 326 | 12 | total | **REWRITE** | Defines the four things that must change first: `Student` with `gymId: Int` (l.12-23), `School` (l.51-54), `W4Credentials` with `autologinkey`/`sessionId`/`autologinkeyExpiresAt` + the four `withASPNETSessionId` / `withAutologinkeyV2` mutators (l.59-172), `W4Error` (l.206-239, all Danish, includes `.robotDetection`). Also `DropdownEntityType` `S/T/HE/RO/GE` (l.254-272) which are Lectio dropdown prefixes. Keep verbatim: `AuthState` (l.176-194), `Notification.Name.w4SessionExpired` + `notifyIfSessionExpired()` (l.198-250) — that contract is exactly README §4.5. |
| `AuthenticationService.swift` | 186 | 0 | total | **REWRITE** | `import Supabase` (l.10); login URL is `lectio.dk/lectio/{id}/login.aspx` (l.22); callback detection is MitID `integration/unilogin.aspx` + `forside.aspx` (l.28-39); step 6 mints a Supabase session (l.83-88). Replace with the native flow from README §4.4: GET `index.php?r=site/login` → POST `LoginForm[username|password|deviceId]`+`yt0=Login` → OTP at `r=site/verify2fa` → confirm `r=site/index`. Keep `enterDemoSession()` (l.98-103) and `coldStartValidate` (l.173-185). |
| `AuthenticationViewModel.swift` | 441 | 8 | total | **REWRITE** | School list hardcoded to 8 Danish gymnasiums (l.96-107); `loadSchoolsFromSupabase` (l.112-133); `ensureSupabaseSession` (l.242-254); `LastSchoolStore`/`LastSchoolHint` (14 call sites); 17 `Analytics.*` calls; `loginWithMitID(source:)`. Only the `.w4SessionExpired` observer (l.52-58) and `handleSessionExpired` shape survive. |
| `LoginView.swift` | 336 | 9 | total | **REWRITE** | School picker sheet (l.25-27, 125, 184), "Log ind med MitID" (l.36, 174, 239), `"MitID & W4"` footer (l.298), `LastSchoolReason` switch (l.313-329). Replace with username + password + OTP + "Forgot password" (`r=site/forgotpass`). |
| `W4WebView.swift` | 188 | 1 | total | **DELETE** | `WKWebView` wrapper whose only job is MitID: `isCallbackURL`, `/forside.aspx` special case (l.76-82), preview loads `lectio.dk/lectio/504/login.aspx` (l.156). README §4.4 explicitly recommends **no WebView** for W4. Delete `W4ActiveWebViewRegistry` with it. |
| `W4HTTPClient+Schedule.swift` | 160 | 0 | total | **RENAME+ADAPT** → `W4Client+Timetable.swift` | `SkemaNy.aspx?elevid=` / `?laererid=` / `?type=lokale` (l.34-38), `aktivitet/aktivitetforside2.aspx?absid=` (l.99), `FindSkemaAdv.aspx` (l.122). W4 routes: `academics/timetable/mytimetable`, `extraacademics/timetable/mytimetable`, `academics/timetable/room`. Keep the `absId(from:)` id-extraction idea and the week-parameter plumbing. |
| `W4HTTPClient+Messages.swift` | 1048 | 17 | total | **RENAME+ADAPT** → `W4Client+Mailer.swift` | Largest single Lectio surface: `beskeder2.aspx` ×8, `dokumentupload.aspx` (l.857), `s$m$Content$Content$ListGridSelectionTree$folders` (l.526), `NewThreadBtn` (l.962), `a[href*=W4FileHandler]` (l.732 — corrupted, see §B.2), full `__doPostBack` machinery. W4 mailer is `mailer/inbox` / `mailer/archive` / `mailer/view` / `mailer/send&type=freeform` with `MailerForm[subject|message|attachment][]|sendCC|attachmentSource]` (README §5.2), TinyMCE HTML body, ≤5 × 2 MB multipart. Keep only the multipart-upload-from-disk plumbing (l.840-900) and `OutgoingAttachmentUploadError` (l.1042). Reactions / edit / flag / read-toggle have **no W4 analog** → drop. **Contains a hard compile error at l.221-222 — see §A.14.** |
| `W4HTTPClient+Student.swift` | 147 | 1 | total | **RENAME+ADAPT** → `W4Client+Identity.swift` | `SkemaNy.aspx` identity probe (l.27), `forside.aspx` (l.56), `subnav/members.aspx?holdelementid=` (l.80), `digitaltStudiekort.aspx` (l.104). W4: identity is `Welcome, {name}` in `#user-panel` on `r=site/index`; profile is `site/profile`; public profile `people/students/student&uwc_id=`. |
| `W4HTTPClient+Absence.swift` | 116 | 1 | total | **RENAME+ADAPT** → `W4Client+Absences.swift` | `fravaer_aarsag.aspx` (l.11), `subnav/fravaerelev_fravaersaarsager.aspx?elevid=` (l.30), `Origin: https://www.lectio.dk` (l.100). W4: `people/students/absences` (AC), `people/students/eaabsences` (EA), and `people/students/absences/register` with `StudentAbsenceForm[absence_date]` in `dd-M-yy`. |
| `W4HTTPClient+Assignments.swift` | 143 | 0 | total | **RENAME+ADAPT** → `W4Client+Assessments.swift` | `grades/grade_report.aspx` (l.20), `OpgaverElev.aspx` (l.43, l.70), `ElevAflevering.aspx?exerciseid=` (l.128). W4: `academics/deadlines` (student assessments, Confirm done / Revert to pending) and `academics/grades/grades`. Split grades out of this file. |
| `W4HTTPClient+Homework.swift` | 32 | 0 | total | **DELETE** | Only `material_lektieoversigt.aspx?elevid=` (l.17). W4 has no "lektieoversigt"; homework folds into assessments (README §7). |
| `W4HTTPClient+PrivateEvents.swift` | 109 | 0 | total | **DELETE** | `privat_aftale.aspx` (l.23). W4 has no private-calendar POST. Android's answer is a **local-only** overlay (`android/…/feature/schedule/LocalPrivateEvents.kt`) — mirror that instead. |
| `W4ImageLoader.swift` | 155 | 0 | structural | **ADAPT** | Good actor with NSCache + in-flight dedup + credential guard. `isW4URL` allow-lists `lectio.dk` (l.129-132), `Referer` header is lectio (l.58), placeholder `defaultfoto_small.jpg` (l.29). Change host to `w4.uwcrcn.no`; W4 avatars are `…_thumb.jpg` on people pages (README §5.5). |
| `PublicProfileImage.swift` | 217 | 0 | structural | **DELETE** | Exists solely to load *moderated BetterLectio profile pictures* over a cookie-free session (l.10-28 strips `Cookie`/`Authorization`). That subsystem is removed by decision 2. Its three view types (`PublicProfileAvatarView`, `ProfileAvatarView`, `PublicProfilePreviewImage`) are used at 7 sites — replace with `W4AvatarView` from `RateLimitedAvatarImage.swift`. |
| `RateLimitedAvatarImage.swift` | 134 | 0 | none | **KEEP** | `RateLimitedAvatarImage`, `W4AvatarView`, `RateLimitedPreviewImage`. Host-agnostic; becomes the single avatar view once `PublicProfileImage.swift` is gone. |

### 1.2 Parsers

| file | LOC | DA | coupling | disposition | notes |
|---|---|---|---|---|---|
| `BaseParser.swift` | 74 | 0 | structural | **ADAPT** | `parseAllFormFields` (l.23-63) is directly reusable for Yii forms — it already skips submit buttons and checkboxes, which is exactly the `yt0` handling README §3 describes. Delete `isRobotDetectionPage` (l.15-19, Danish + `RobotDetection`). Keep `String.nilIfEmpty`. Rename the doc comment away from "ASP.NET postback". |
| `ScheduleParser.swift` | 743 | 30 | total | **REWRITE** | Selectors are Lectio-only: `table.s2skema` (l.21), `td[data-date]` (l.26), `a.s2skemabrik.s2brik` (l.44), `#s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv` (l.342), `article.lc-display-fragment` (l.371), plus `"Ændret!"`, `"Lærer:"`, `"Øvrigt indhold:"`, `"Hele dagen"`, `"læs. 11-18"`. W4 grid is `#timetable`, hours `tt_start_hour`…`tt_end_hour`, days `Day 1–5` + `Weekend` + an EA row (README §5.6). Guides the new `W4TimetableParser`. |
| `MessageParser.swift` | 405 | 2 | total | **REWRITE** | `table[id*=threadGV]` (l.26), `a[onclick*=$LB2$]` (l.71), `div.message-list-thread-container` (l.43). W4 mailer inbox columns are Received / From / Subject. |
| `StudentParser.swift` | 693 | 23 | total | **REWRITE** | 13 `s_m_Content_Content_*` ids (l.204, 225, 242, 274, 307, 338, 391, 392, 402 …), `Autocomplete.registerDataSetUrl('AvanceretSkema_…')` (l.87), `/lectio/94/GetImage.aspx?pictureid=` (l.208), `SkemaNy.aspx?type=holdelement` (l.314). Split into `W4IdentityParser` (`Welcome,` / `#user-panel`) and `W4PeopleParser` (`people/students/*`). |
| `GradeParser.swift` | 220 | 5 | total | **REWRITE** | `#s_m_Content_Content_karakterView_KarakterGV` (l.36), `…WrittenProtokolBlockLit` (l.19), `span[data-w4contextcard]` (l.65 — corrupted, §B.2). W4 grades are IB 1-7 / predicted, route `academics/grades/grades`. |
| `AssignmentParser.swift` | 290 | 1 | total | **REWRITE** → `W4AssessmentParser.swift` | `table#s_m_Content_Content_ExerciseGV` (l.18), `#m_Content_registerAfl_pa` (l.136), `span.exercisewait` (l.70). W4 assessments are a month calendar with add / Confirm done / Revert to pending. |
| `DirectoryParser.swift` | 541 | 6 | total | **REWRITE** | `table#s_m_Content_Content_laerereleverpanel_alm_gv` (l.132), `td[data-w4contextcard]` (l.137), `img[src*=pictureid]` (l.159), `case "SC": return .classW4` (l.229). W4 directory is `people/students/all|firstyear|secondyear`, `people/students/staff&type=teachers|leaders`, `academics/timetable/room`. |
| `AbsenceEditFormParser.swift` | 107 | 4 | total | **REWRITE** | `select[name*=StudentReasonDD]` (l.17), literal control ids `s$m$Content$Content$cancelStudentNote$tb` (l.39) and `…$savecancelapplyBtn$svbtn` (l.55). W4's analog is `people/students/absences/register` with `StudentAbsenceForm[absence_date]` + JS-added per-slot checkboxes (README §5.2). |
| `MessageEditAudit.swift` | 127 | 0 | total | **DELETE** | Parses Lectio's "message was edited" audit line and formats `MessageEditedTimeLabel`. W4's mailer has no edit-after-send. Delete `MessageEditAuditTests.swift` with it. |
| `MessageReactionProtocol.swift` | 276 | 0 | total | **DELETE** | Lectio emoji reactions (`MessageReactionEmoji`, `MessageLocator`, `MessageReactionEnvelope`) parsed out of postback HTML. No W4 analog anywhere in the captured menus. Delete `MessageReactionTests.swift` with it. |
| `MessageContentRenderer.swift` | 158 | 0 | none | **KEEP** | Pure SwiftSoup → `AttributedString` with bold/italic/underline/link and HTML whitespace collapsing. Exactly what a TinyMCE mail body needs. |

### 1.3 Models

| file | LOC | DA | coupling | disposition | notes |
|---|---|---|---|---|---|
| `ScheduleModels.swift` | 293 | 2 | structural | **ADAPT** | `ScheduleEvent` (l.12-56) is clean and host-agnostic; `EventStatus .normal/.changed/.moved/.cancelled` maps onto W4's grid. `LessonContent` / `ContentBlock` / `InlineElement` (l.100-282) model Lectio's lesson-note rich text — keep the codec, re-source it from W4 subject/activity pages. |
| `AbsenceModels.swift` | 77 | 3 | structural | **ADAPT** | Field comments are Lectio (`fravaer_aarsag.aspx` l.21, "Almindeligt/Skriftligt fravær" l.14-15). W4 splits AC vs EA absences and adds **latenesses** (README §6 Home). Needs an `AbsenceKind { academic, extraAcademic }` and a lateness count. |
| `AssignmentModels.swift` | 111 | 2 | structural | **RENAME+ADAPT** → `AssessmentModels.swift` | `Assignment`/`AssignmentStatus`/`AssignmentSubmission` are Lectio afleveringer. W4 items are `assessment_id` / `student_assessment_id` / `student_deadline_date` / `student_assessment_title` with a done/pending flag (README §5.2). `HomeworkEntry`/`HomeworkItem` (l.93-121) fold in here. |
| `GradeModels.swift` | 70 | 3 | structural | **ADAPT** | `GradeColumn.shortLabel` hardcodes Danish term keys `1.standpunkt`, `afsluttende`, `årskarakter`, `eksamenskarakter` (l.29-37). Replace with W4/IB columns; the dynamic-column design (identity by key, not position) is right and should stay. |
| `MessageModels.swift` | 255 | 2 | structural | **ADAPT** | `MessageFolder` is Lectio `mappeid` (`Ulæst = -40`); `MessageThreadDetail`, `MessageReplyForm`, `NotifyOption`, `MessageRecipient.w4RecipientID` (`"T123"`/`"S123"` prefixes) all mirror Lectio. W4 has Inbox + Sent/Archive only, and recipients come from `mailer/extra&type=freeform`. Delete `MessageEditDraft` (l.136) with the edit feature. |
| `DirectoryModels.swift` | 257 | 11 | structural | **ADAPT** | `DirectoryEntityKind` includes `.classW4` (l.12 — corrupted identifier, §B.2) and `.hold`; `displayName` is Danish (l.22-32). W4 entity kinds: student, staff (teacher / EA leader / on-duty), room, resource, house, EA group, subject page. |
| `StudentProfile.swift` | 187 | 0 | total | **DELETE** | Pure Supabase RPC DTO: `custom_pfp_url` / `w4_pfp_url` coding keys (l.59-60), `extensionInstalledAt` / `extensionUninstalledAt` (browser-extension telemetry, l.21-23), `hasBetterW4(at:)` "is this classmate an active BetterLectio user" (l.85-92). All three removed subsystems in one file. `InstagramProfileLink` (l.145-186) is standalone and could be salvaged if W4 profiles ever expose socials — today they do not. Delete `StudentProfileTests.swift` with it. |

### 1.4 Stores, caches, services

| file | LOC | DA | coupling | disposition | notes |
|---|---|---|---|---|---|
| `ScheduleStore.swift` | 650 | 1 | structural | **ADAPT** | SwiftData `@Model LessonRecord`. Field `teacherId` doc says "from `data-w4contextcard`" (l.23 — corrupted, §B.2). Keep the store; re-key off W4 ids. |
| `HomeworkStore.swift` | 460 | 0 | structural | **ADAPT** | `@Model HomeworkRecord` with local done-state + `mergeRemoteDoneStates(…: [String: HomeworkSyncStatus])` (l.319, l.338). `HomeworkSyncStatus` was a Supabase type (§A.9) — W4 stores done-state natively (`Confirm done`), so the local/remote merge collapses to "W4 is truth, local is optimistic". |
| `StudentStore.swift` | 468 | 0 | structural | **ADAPT** | `@Model StudentRecord` carries `gymId: Int` (l.16) and `rawEntityType` from `DropdownEntityType`. Drop `gymId`, re-key on `uwc_id`. |
| `DirectoryStore.swift` | 974 | 0 | structural | **ADAPT** | Two `@Model`s + picture-id resolution that builds `GetImage.aspx?pictureid=` URLs (2 `lectio.dk`, 2 `.aspx` hits). Largest single file; the caching/membership design is sound, the URL builder and `gymId` scoping are not. |
| `MessageCacheManager.swift` | 167 | 0 | structural | **ADAPT** | File-based JSON cache in Caches/. `unreadMessageCountDidChange` notification (l.8-12) drives the tab badge — keep. `gymId` parameters throughout → drop. |
| `MessageListPrefetcher.swift` | 78 | 0 | structural | **ADAPT** | Correct pattern (`.opportunistic` priority, actor-guarded). Danish doc "Nyeste/Ulæst" (l.8-9), `gymId` params (l.16, 34). |
| `StudentManager.swift` | 174 | 0 | structural | **ADAPT** | Background student sync via `W4HTTPClient`. Mechanically fine; depends on the rewritten client + parser. |
| `DirectorySyncService.swift` | 142 | 0 | structural | **ADAPT** | Same — demo short-circuit at l.24-29 is a good pattern to keep. |
| `SettingsStore.swift` | 539 | 2 | structural | **ADAPT** | Keep appearance/calendar-style/notifications/subject-colour prefs and the `betterW4CachesDidClear` notification (l.520-523). Delete: App Group `"group.dk.elliottf.betterw4"` + `UserDefaults(suiteName:)` (l.66, l.97 — §A.13), `liveActivityVariant` (l.83, 123, 154), `syncWithSupabase` (l.315-355) and the two `pushMapping*` Supabase writers (l.450-500), `SharedScheduleData.clear()` (l.365). `Color.lessonMappingHue(_:)` is called at l.226/231 but is **not defined anywhere** — §A.12. |
| `SubjectMapper.swift` | 373 | 25 | total | **REWRITE** | Entirely Danish gymnasium subjects and class-code regexes (`locale = da_DK` l.51, `classLetter = "A-ZÆØÅ…"` l.56, ignore-list `kostelever`, `alumneråd`, `samarbejdsudvalg` l.68-82). W4 needs IB subjects (Biology, TOK, Visual Art, EE, Learning Support …) and IB class shapes. Mirror `android/…/feature/settings/SubjectMapper.kt` + `SubjectIcons.kt`. |
| `TimeProvider.swift` | 42 | 0 | none | **KEEP** | `SIMULATED_DATE` env override. |
| `ScheduleIdentity.swift` | 62 | 0 | structural | **ADAPT** | ISO week keys + SHA-256 lesson key. `w4WeekParameter` returns `WWYYYY` (l.24-28) — that is Lectio's `SkemaNy.aspx?week=` format; W4's timetable pagination parameter is **UNKNOWN — needs live capture** of `academics/timetable/mytimetable` with a non-current week. |
| `ScheduleLayoutUtils.swift` | 48 | 0 | none | **KEEP** | Pure overlap/column maths. |
| `ScheduleEvent+Extensions.swift` | 62 | 0 | none | **KEEP** | Pure time arithmetic + `timed`/`allDay` partitions. |
| `OutgoingMessageAttachment.swift` | 228 | 4 | structural | **ADAPT** | Photo/file picking, size + UTType validation, temp-dir staging, `purgeStaleTemporaryFiles`. Limits must change to W4's **5 files × 2 MB** (README §5.2); dir name `BetterW4MessageAttachments` (l.107, 137) is fine. |
| `MessageSignature.swift` | 33 | 0 | total | **REWRITE** | BBCode signature `[url=…]Sendt med BetterW4[/url]` (l.4); teacher detection by `id.hasPrefix("T")` (l.8) is a Lectio recipient-id convention. W4 mail is TinyMCE HTML and has no `T`/`S` id prefixes. |
| `BetterW4Links.swift` | 5 | 0 | cosmetic | **KEEP** | One constant, currently `https://betterlectio.dk/download` (l.4) — must be re-pointed. See §B.3 (it disagrees with a regex in `W4HTTPClient+Messages.swift:392`). |
| `AppStoreReviewLauncher.swift` | 20 | 0 | none | **KEEP** | |
| `ReviewEligibility.swift` | 94 | 0 | none | **KEEP** | Pure date/threshold logic, mirrors `android/…/feature/review/ReviewEligibility.kt`. |
| `ReviewPromptStore.swift` | 80 | 0 | none | **KEEP** | `UserDefaults.standard`, prefix `bl_review_prompt.` (l.11) — rename the prefix only if you are willing to reset users' counters. |
| `ReviewPromptSheet.swift` | 58 | 2 | cosmetic | **ADAPT** | Three-button soft prompt. Danish `defaultValue`s at l.16, 23, 31, 38, 45 (keys `review_prompt.*` already exist in English in `Localizable.strings`). Its `onNegative` callback currently routes to the deleted feedback sheet via `ReviewPromptCoordinator.swift:131` — re-wire to a plain dismiss, or drop the negative button. |
| `ReviewPromptCoordinator.swift` | 157 | 0 | structural | **ADAPT** | 6 `Analytics.capture` + 2 `FeedbackLogBuffer.record` + `FeedbackCoordinator.shared` (l.131, 154) + `ReferralCoordinator.shared.nudgeVisible` (l.153). Also an **Android leftover**: event `"review_play_flow_requested"` with property `"play_accepted"` (l.111-117) — Google Play naming in an iOS StoreKit path. |
| `DemoDataProvider.swift` | 576 | 47 | total | **REWRITE** | Highest Danish density in the repo. Fabricates Lectio schedules, `ElevAflevering.aspx?exerciseid=demo` detail URLs (l.440), "Velkommen til BetterW4" (l.144). Needs a full UWCRCN-flavoured demo: Day 1-5 timetable, EA row, assessments, campus status, mailer inbox. |
| `TabBarSameTabReselectDetector.swift` | 105 | 0 | cosmetic | **ADAPT** | Hardcodes `LektierTabBarIndex.value = 2` (l.13-15) and its doc comment names the Lektier tab. Re-point at whatever the W4 tab order becomes (README §7 suggests Timetable / Mailer / Assessments / More). |

### 1.5 Views

| file | LOC | DA | coupling | disposition | notes |
|---|---|---|---|---|---|
| `ContentView.swift` | 639 | 27 | total | **REWRITE** | The app shell, and the single densest concentration of dead code: 4 `FeedbackLogBuffer`, `FeedbackCoordinator`/`FeedbackSheet`/`FeedbackPresentation`, 6 `ReferralCoordinator` + `ReferralView` + `ReferralNudgeView` + `ReferralProgress`, `ProfilePictureReviewMonitor`/`ProfilePictureState`/`ProfilePictureEditorView`/`SupabaseProfilePictureService`, `BrowserExtensionInviteView`, `ShakeListener`, `LiveActivityManager`, `Analytics`, `settingsStore.syncWithSupabase`. Tabs are `Skema / Beskeder / Lektier / Opgaver / Mere` (l.130-173); `MoreView` lists Elever / Karakterer / Fravær / Lærere / Klasser / Hold / Lokaler / Grupper / Ressourcer / Studiekort (l.397-451). New IA per README §7 + the Android `ui/navigation/AppDestination.kt`. |
| `ScheduleView.swift` | 933 | 10 | structural | **ADAPT** | Visual polish worth keeping (paged day view, now-line, detail sheet). Strip 4 `LiveActivityManager.updateLiveActivity` blocks (l.603, 624, 634, 644), the `ReferralCoordinator` nudge gate (l.608-609), `PublicProfileAvatarView` (l.267). Add the EA row and the AC/EA combined week the README calls for. |
| `MessagesView.swift` | 297 | 7 | structural | **ADAPT** | Thread list + folder switcher. W4 has fewer folders (Inbox / Sent). |
| `MessageThreadView.swift` | 1099 | 10 | structural | **ADAPT** | Largest view. Delete the reaction bar, `MessageEditSheet` (l.717-799), `ReactionParticipantsSheet` (l.800-822), `ReactionFlowLayout` (l.823-862) — all Lectio-only. Keep `AttachmentRow`, `QuickLookPreview`, `AuthenticatedImageView`, the bubble layout. Owns 20 of the 52 live localisation keys. |
| `ComposeMessageView.swift` | 491 | 15 | structural | **ADAPT** | Recipient chips + picker + `FlowLayout` are reusable; recipient source becomes `mailer/extra&type=freeform`. |
| `HomeworkView.swift` | 840 | 8 | structural | **REWRITE** | The Lektier tab. W4's analog is the assessments calendar with native done-state — different screen, same swipe-to-done affordance. `https://www.lectio.dk\(urlString)` at l.617. |
| `AssignmentsView.swift` | 711 | 7 | structural | **DELETE** | Opgaver tab. README §7 is explicit: "Do not port lektier/opgaver as two tabs… fold into assessments". Salvage `AssignmentDetailSheet`'s layout into the assessments detail. `https://www.lectio.dk\(path)` at l.706. |
| `AbsenceView.swift` | 768 | 27 | structural | **ADAPT** | Donut + per-subject breakdown + edit sheet. W4 needs two meters (AC and EA) plus latenesses, and "Register absences" instead of "edit reason". |
| `GradesView.swift` | 562 | 6 | structural | **ADAPT** | Dynamic column rendering survives; term labels do not. |
| `SubjectGradeDetailView.swift` | 136 | 2 | none | **KEEP** | Swift Charts detail; only the axis labels are Danish. |
| `StudentSearchView.swift` | 842 | 37 | structural | **ADAPT** | Directory browser (`DirectoryPresentation` full/teachers/classes/holds/rooms/groups/resources). Strip `SupabaseStudentProfileService` (l.99), `betterW4URL` (l.49-105), `PublicProfilePreviewImage` (l.68), `.profilePictureDidChange` (l.78). Re-map presentations to W4's lists (all / 1st year / 2nd year / by country / by house / staff / staff-on-leave / visitors). |
| `StudentProfileView.swift` | 561 | 13 | total | **REWRITE** | Built around the deleted rich-profile system: `RichProfileState`, `SupabaseStudentProfileService.profile` (l.405), `fetched.hasBetterW4` (l.413), `StudentProfileServiceError` (l.420), Instagram row, pin/unpin. W4's public profile is `people/students/student&uwc_id=` (uwc id, year, names, pronouns, country, email, NC/SO, photo). Owns 20 live localisation keys, **all of which are missing from `Localizable.strings`** (§D). |
| `StudentCardView.swift` | 250 | 6 | total | **REWRITE** | Flip card whose back is `GetImage.aspx?type=studiekortqr` (l.24) — a Lectio-generated QR. W4's closest artefact is the **Letter of Attendance** at `people/students/letter/attendance` (a ~600 KB generated HTML document), not a QR card. Mirror `android/…/feature/studiekort/StudiekortRepository.kt`, whose `StudentCard` carries `photoUrl / qrUrl / birthday / email / house / country / pronouns`. |
| `SettingsView.swift` | 375 | 32 | total | **REWRITE** | Live Activity section (l.92-122), Browser-extension button (l.154-157), Send-feedback button (l.159-166), and three developer alerts that read and write `ASP.NET_SessionId` / `autologinkeyV2` by hand (l.181-311). Replace the cookie section with a single `PHPSESSID` inspector, or drop it. |
| `SubjectColorSettingsView.swift` | 302 | 7 | structural | **ADAPT** | Per-subject colour/icon/name overrides. Delete `syncWithSupabase` (l.79). |
| `AddPrivateEventView.swift` | 123 | 3 | structural | **ADAPT** | Form is fine; its `W4HTTPClient.createPrivateEvent` backend is being deleted. Re-point at a local-only overlay (Android `LocalPrivateEvents.kt`). |
| `TimelineListView.swift` | 418 | 1 | none | **KEEP** | Timeline + `ScheduleCard`; one `lectio.dk`/`aspx` hit is inside a comment. |
| `ModernScheduleComponents.swift` | 276 | 1 | none | **KEEP** | Alternate timeline style driven by `CalendarStyle`. |
| `CalendarStripView.swift` | 133 | 0 | none | **KEEP** | Date strip + `ScaleButtonStyle`. |
| `AllDayEventsView.swift` | 92 | 2 | cosmetic | **KEEP** | Only the literal `"Hele dagen"` (l.19). Reusable as the W4 EA/all-day row. |
| `ScheduleHeaderView.swift` | 73 | 0 | cosmetic | **KEEP** | `"om \(n) min"` (l.40). |
| `LessonContentItemView.swift` | 146 | 0 | structural | **ADAPT** | Renders `LessonContentItem`; 3 `lectio.dk` hits are link-resolution. |
| `BBCodeRichEditor.swift` | 222 | 0 | total | **REWRITE** | `BBCodeCodec` (l.141) round-trips Lectio BBCode. W4 mail bodies are TinyMCE **HTML** (README §5.2). Note `android/…/feature/messages/Bbcode*.kt` + `ui/components/bbcode/BbcodeEditor.kt` still exist in the Android port — treat those as not-yet-migrated, not as evidence W4 uses BBCode. Confirming the on-wire format is **UNKNOWN — needs live capture** of a `POST index.php?r=mailer/send&type=freeform`. |
| `AbsenceViewModel.swift` | 338 | 9 | structural | **ADAPT** | One `Analytics.capture` (l.163); Danish warning copy (l.322-326) encodes Danish absence policy — W4's thresholds differ. |
| `AssignmentsViewModel.swift` | 343 | 6 | structural | **DELETE** | Goes with `AssignmentsView.swift`. |
| `HomeworkViewModel.swift` | 328 | 1 | structural | **REWRITE** | `SupabaseHomeworkService` (l.29, 72, 160, 167), `HomeworkSyncStatus` (l.32, 278). The optimistic-write + `PendingHomeworkWrite` reconciliation pattern (l.10-14) is worth keeping against W4's own Confirm-done POST. |
| `ScheduleViewModel.swift` | 525 | 5 | structural | **ADAPT** | `SupabaseScheduleService` (l.37, 254, 410). Otherwise a good week-cache + generation-token view model. |
| `MessagesViewModel.swift` | 389 | 1 | structural | **ADAPT** | `SupabaseStudentProfileService.profiles` avatar enrichment (l.367-375) → delete. |
| `MessageThreadViewModel.swift` | 657 | 9 | structural | **ADAPT** | Same enrichment at l.591-599; plus reaction/edit paths that die with §1.2. |
| `ComposeMessageViewModel.swift` | 183 | 2 | structural | **ADAPT** | |
| `GradesViewModel.swift` | 81 | 1 | structural | **ADAPT** | Clean generation-token pattern; only the client call and error copy change. |
| `DirectoryViewModel.swift` | 525 | 6 | structural | **ADAPT** | Search/sectioning; `.classW4` reference at l.263, 321. |
| `StudentSearchViewModel.swift` | 324 | 0 | structural | **ADAPT** | Builds `GetImage.aspx?pictureid=` URLs (l.197) and is `gymId`-scoped throughout. |
| `BetterW4App.swift` | 72 | 0 | total | **ADAPT** | 5 dead calls in 40 lines: `Analytics.configure()` (l.16), `LiveActivityBackgroundRefresh.register` (l.24-28), `LiveActivityManager` ×2 (l.26, 32), `FeedbackLogBuffer` (l.54). What remains — notification permission + attachment purge + `CookieManager.logKeychainW4Cookies` — is 20 lines. |

### 1.6 Test target (`ios/BetterW4Tests/`, 10 files)

| file | LOC | DA | coupling | disposition | notes |
|---|---|---|---|---|---|
| `AbsenceEditingTests.swift` | 74 | 4 | total | **REWRITE** | Drives `AbsenceEditFormParser` against `Fixtures/Absence/*.html` (Lectio `fravaer_aarsag.aspx` captures). Same *shape* of test, new fixtures from `people/students/absences`. |
| `GradeParserTests.swift` | 94 | 9 | total | **REWRITE** | Inline Lectio `karakterView` HTML. |
| `LessonContentParserTests.swift` | 372 | 8 | total | **REWRITE** | 16 ASP.NET-control references in inline fixtures. Largest test file; the assertions about block/inline structure are reusable once re-sourced. |
| `MessageAttachmentUploadTests.swift` | 151 | 5 | total | **REWRITE** | Exercises `dokumentupload.aspx` postback parsing against `Fixtures/message-*.html`. W4 uses plain multipart `MailerForm[attachment][]` — much simpler, still worth a test. |
| `MessageEditAuditTests.swift` | 53 | 2 | total | **DELETE** | With `MessageEditAudit.swift`. |
| `MessageReactionTests.swift` | 183 | 3 | total | **DELETE** | With `MessageReactionProtocol.swift`. **Contains a hard compile error at l.126 — see §A.15.** |
| `MessageSignatureTests.swift` | 89 | 0 | total | **REWRITE** | Asserts BBCode signature bytes; rewrite for HTML. |
| `StudentParserClassTests.swift` | 23 | 3 | total | **REWRITE** | Danish class-label parsing. |
| `StudentProfileTests.swift` | 97 | 0 | total | **DELETE** | Tests `hasBetterW4(at:)` and the pfp-URL allow-list — both from the deleted Supabase profile system. |
| `SubjectMapperTests.swift` | 25 | 0 | total | **REWRITE** | Danish subject codes. |

Fixtures: all 11 files under `BetterW4Tests/Fixtures/` are Lectio HTML — **DELETE**, replace with
extracts from `references/pages/*.html` and `references/w4.uwcrcn.no.har`.

### 1.7 Roll-up

| disposition | app | tests | total |
|---|---:|---:|---:|
| KEEP | 16 | 0 | 16 |
| ADAPT | 41 | 0 | 41 |
| REWRITE | 21 | 7 | 28 |
| RENAME+ADAPT | 7 | 0 | 7 |
| DELETE | 9 | 3 | 12 |
| **total** | **94** | **10** | **104** |

Nothing is KEEP-with-zero-edits in the strict sense — the 16 KEEPs still need their Danish
literals translated where they have any (`AllDayEventsView` 2, `ScheduleHeaderView` 1,
`SubjectGradeDetailView` 2, `TimelineListView` 1, `ModernScheduleComponents` 1); "KEEP" means the
*body* is correct for W4 as written.

Eight files carry a rename:

| current | new name |
|---|---|
| `CookieManager.swift` | `W4SessionCookieStore.swift` |
| `W4HTTPClient+Schedule.swift` | `W4Client+Timetable.swift` |
| `W4HTTPClient+Messages.swift` | `W4Client+Mailer.swift` |
| `W4HTTPClient+Student.swift` | `W4Client+Identity.swift` |
| `W4HTTPClient+Absence.swift` | `W4Client+Absences.swift` |
| `W4HTTPClient+Assignments.swift` | `W4Client+Assessments.swift` |
| `AssignmentModels.swift` | `AssessmentModels.swift` |
| `AssignmentParser.swift` | `W4AssessmentParser.swift` *(row disposition is REWRITE — the body does not survive, only the filename slot)* |

---

## A. Dead-reference list (complete; closed by a green build)

This list is exhaustive. Method: stub every unresolved symbol in a scratch copy until
`xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=latest" CODE_SIGNING_ALLOWED=NO build`
reported **BUILD SUCCEEDED**, then `build-for-testing` likewise. Nothing else is missing.

### A.1 `import Supabase` — the module does not exist
| site | fix |
|---|---|
| `BetterW4/AuthenticationService.swift:10` | delete the line |
| `BetterW4/AuthenticationViewModel.swift:12` | delete the line |

Only SwiftSoup is declared in `project.pbxproj:505-514`. This one error masks every other error
in the project — the compiler aborts at module-interface emit, which is why a naive `xcodebuild`
run reports exactly one problem.

### A.2 `SupabaseAuthService`
`AuthenticationService.swift:84` · `AuthenticationViewModel.swift:251`
→ delete the `await SupabaseAuthService.shared.authenticateWithW4(…)` call (5 lines each) and the
`ensureSupabaseSession(for:)` method that wraps the second (`AuthenticationViewModel.swift:242-254`,
called from `:182`).

### A.3 `SupabaseManager`
`AuthenticationService.swift:119` (`try? await SupabaseManager.shared.client?.auth.signOut(scope: .local)`) ·
`AuthenticationViewModel.swift:243` (`guard let client = SupabaseManager.shared.client else { return }`)
→ delete both lines; in `wipeAuthState()` the remaining keychain + WebKit wipe is sufficient.

### A.4 `SupabaseStudentProfileService`
`AuthenticationService.swift:114` (`.clearCache()`) ·
`StudentProfileView.swift:405-409` (`.profile(studentID:viewer:forceRefresh:)`) ·
`StudentSearchView.swift:99-103` (same) ·
`MessagesViewModel.swift:367-372` (`.profiles(studentIDs:viewerStudentID:gymID:forceRefresh:)`) ·
`MessageThreadViewModel.swift:591-596` (same)
→ delete each `await` block and the local it assigns. In `MessagesViewModel` / `MessageThreadViewModel`
the whole avatar-enrichment `for` loop that follows (`:373-375`, `:597-599`) goes with it.

### A.5 `SupabaseSubjectService`
`SettingsStore.swift:321-324` (`.fetchMappings`) · `:458-462` and `:490-494` (`.resetMappingOverride`) ·
`:464-471` (`.upsertMappingOverride`)
→ delete `syncWithSupabase(studentId:schoolId:)` (`:315-355`) entirely and the two `Task { … }`
bodies in `pushMapping…`/`pushMappingReset` (`:455-478`, `:487-499`). Callers of the deleted method:
`ContentView.swift:184`, `SubjectColorSettingsView.swift:79`, `SettingsStore.swift:475`, `:497`.

### A.6 `SupabaseSchoolService`
`AuthenticationViewModel.swift:121` → delete `loadSchoolsFromSupabase(force:)` (`:112-133`),
`hasLoadedSchoolsFromSupabase` (`:28`, `:113`, `:127`), `isLoadingSchools`/`schoolLoadError` (`:26-27`),
and — per decision 4 — `schools`/`selectedSchool`/`loadSchools()` (`:20-21`, `:96-107`) too.

### A.7 `SupabaseHomeworkService`
`HomeworkViewModel.swift:29` (property), `:72-75`, `:160-165`, `:167-170`
→ delete the property and the three call sites; W4 owns done-state natively.

### A.8 `SupabaseScheduleService`
`ScheduleViewModel.swift:37` (property), `:253-259` (`syncWeek`), `:409-415` (`syncLessonContent`)
→ delete the property and both `if target.kind == .student { Task { … } }` blocks.

### A.9 `HomeworkSyncStatus` (type lived with the Supabase homework service)
`HomeworkStore.swift:319` and `:338` (signatures of `mergeRemoteDoneStates` /
`mergeRemoteDoneStatesAsync`) · `HomeworkViewModel.swift:32` (`remoteStatusByEntryId`), `:278`
(`applyRemoteStatuses`), `:284`, `:310`, `:311`, `:314` (uses `.isDone` / `.clientUpdatedAt`)
→ delete both `HomeworkStore` methods and `applyRemoteStatuses` + `remoteStatusByEntryId`.

### A.10 `SupabaseProfilePictureService` / `ProfilePictureState` / `ProfilePictureEditorView` / `ProfilePictureReviewMonitor` / `.profilePictureDidChange`
`ContentView.swift:16` (`ProfilePictureReviewMonitor.shared`), `:62-69` (`.refresh(for:)` ×2),
`:70-80` (the review-outcome `.alert`), `:324` (`ProfilePictureState?`), `:325`, `:334-340`
(`PublicProfileAvatarView` branch), `:378-386` (edit button), `:500-503`, `:504-512` (`.sheet` +
`ProfilePictureEditorView`), `:519-525` (`.onReceive(.profilePictureDidChange)`) ·
`StudentProfileView.swift:99` (`.onReceive(.profilePictureDidChange)`) ·
`StudentSearchView.swift:78-84` (same)
→ delete every block; in `ContentView.MoreView` the avatar collapses to the `studentInfo.pictureId`
branch, which itself becomes a W4 `…_thumb.jpg` URL.

### A.11 Referral / feedback / browser-extension / shake / Live Activity / school picker

| symbol | sites | fix |
|---|---|---|
| `Analytics.` | `BetterW4App.swift:16`; `AbsenceViewModel.swift:163`; `ContentView.swift:456`; `ReviewPromptCoordinator.swift:90,104,111,128,142`; `AuthenticationViewModel.swift:71,77,155,165,171,183,202,208,222,228,295,312,346,347,370,371,379,380,401,403` | delete every call (28 total). Decision 2 forbids an analytics shim. |
| `FeedbackLogBuffer` | `BetterW4App.swift:54`; `ContentView.swift:33,47,177,196`; `ReviewPromptCoordinator.swift:71,81` | delete the calls; in `BetterW4App` and `ContentView` this empties the surrounding `.onAppear`/`.onChange`, which should then go too |
| `FeedbackCoordinator` | `ContentView.swift:120,186-188,214,222,256,269-270`; `SettingsView.swift:159-166`; `ReviewPromptCoordinator.swift:131,154` | delete property, the "Send feedback" button, both `setExternalPromptBlocking("feedback")` hooks, and the `.feedback` case of `AuthenticatedSheet` |
| `FeedbackSheet` | `ContentView.swift:222` | delete with the sheet case |
| `FeedbackPresentation` | `ContentView.swift:100,106` | delete the `case feedback(FeedbackPresentation)` from `AuthenticatedSheet` (`:99-111`) |
| `ShakeListener` | `ContentView.swift:210-218` | delete the whole `.background { … }` modifier |
| `ReferralCoordinator` | `ContentView.swift:15,43-45,51,57,62,121,189-194,211-213,224,259,271,323,461-467,499`; `ScheduleView.swift:608-612`; `ReviewPromptCoordinator.swift:153` | delete. `ContentView.onOpenURL` (`:49-53`) and `.onContinueUserActivity` (`:54-59`) exist **only** for referral deep links — delete both |
| `ReferralView`, `ReferralNudgeView`, `ReferralProgress` | `ContentView.swift:455-473` (nav row), `:224`, `:462` | delete the "Inviter venner" section outright |
| `BrowserExtensionInviteView` | `ContentView.swift:326,475,513-515`; `SettingsView.swift:23,154-157,259-261` | delete both buttons and both `.sheet`s |
| `LiveActivityManager` | `BetterW4App.swift:26,32`; `ContentView.swift:488`; `SettingsView.swift:108,336`; `ScheduleView.swift:603-606,624-627,634-637,644-647` | delete every call. In `ScheduleView` the four blocks are inside `.task`, `.onReceive(.betterW4CachesDidClear)`, `.onReceive(minuteTimer)`, `.onChange(of: scenePhase)` — keep the surrounding modifiers, drop the bodies that only fed the Live Activity |
| `LiveActivityBackgroundRefresh` | `BetterW4App.swift:24-28` | delete the whole `#if os(iOS)` block |
| `LiveActivityVariant` | `SettingsStore.swift:83,123,154`; `SettingsView.swift:94,106` | delete the published property, its load/save, and the entire Live-Activity `Section` (`SettingsView.swift:91-122`) plus `testLiveActivity()` / `makeTestLiveActivitySchedule()` (`:332-372`) |
| `SharedScheduleData` | `SettingsStore.swift:365` | delete the line (it was the widget's App-Group payload) |
| `SchoolPickerView` | `LoginView.swift:12,25-27,125,184` | delete with the school picker (decision 4) |
| `LastSchoolStore` | `AuthenticationViewModel.swift:45,67,68,146,162,163,199,200,219,220,349,354,397,398` | delete; a per-install `deviceId` (README §4.4) replaces the "resume last school" idea |
| `LastSchoolHint` | `AuthenticationViewModel.swift:30,348` | delete the published property and `LastSchoolHint.from(school:)` call |
| `LastSchoolReason` | `LoginView.swift:313,322` | delete `resumeTitle(for:)` / `resumeSubtitle(for:)` and the whole `resumeContent` branch (`:19-21`, `:52-145`) |
| `StudentProfileServiceError` | `StudentProfileView.swift:420` | delete with the rich-profile fetch |

### A.12 `Color.lessonMappingHue(_:)` — never defined anywhere in the tree
`SubjectMapper.swift:199`, `:218` · `SettingsStore.swift:226`, `:231`.
`SettingsStore.swift:526` defines the *inverse* (`Color.lessonMappingHueValue() -> Int?`) but the
forward `static func lessonMappingHue(_ hue: Int) -> Color` was in a file that no longer exists
(it was shared with the widget/Live-Activity target). **Minimal fix:** add it to the existing
`extension Color` at `SettingsStore.swift:525-539`, e.g.
`static func lessonMappingHue(_ hue: Int) -> Color { Color(hue: Double(hue)/360, saturation: …, brightness: …) }`.
This is the only dead reference that is *not* a removed feature — it is a genuinely missing
utility and must be restored, not deleted.

### A.13 App Group access
`SettingsStore.swift:66` `static let appGroupIdentifier = "group.dk.elliottf.betterw4"` ·
`SettingsStore.swift:97` `self.userDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)`.
This is the only App Group use in the tree. `BetterW4/BetterW4.entitlements` is an **empty
`<dict/>`** — there is no `com.apple.security.application-groups` entitlement, so
`UserDefaults(suiteName:)` returns `nil` at runtime and **every preference is silently discarded**
(`userDefaults` is `UserDefaults?` and every read/write is optional-chained). Minimal fix: replace
line 97 with `UserDefaults.standard` and delete line 66.

### A.14 Genuine compile error, unrelated to any removed feature
`BetterW4/W4HTTPClient+Messages.swift:221-222`:
```swift
let title = formFields.filter { $0.name == fields.titleField }.first?.value
    .flatMap { $0.isEmpty ? nil : $0 } ?? "Re: \(initial.detail.title)"
```
Optional chaining binds `.flatMap` to the **non-optional** `String`, so it resolves to
`Sequence.flatMap` over `Character`s: `error: value of type 'String.Element' has no member 'isEmpty'`
and `error: binary operator '??' cannot be applied to operands of type '[String.Element]?' and 'String'`.
Minimal fix: parenthesise the optional — `let title = (formFields.filter { … }.first?.value).flatMap { … } ?? "…"`.
Inherited verbatim from `references/betterlectio/ios/BetterLectio/LectioHTTPClient+Messages.swift:221`,
so it is not rename damage.

### A.15 Genuine compile error in the test target
`BetterW4Tests/MessageReactionTests.swift:126` — `  anden linje</textarea>` is indented 2 spaces
while the closing `"""` of the multi-line literal is at 8:
`error: insufficient indentation of line in multi-line string literal`.
Minimal fix: indent that line to 8 spaces (it does not change the parsed value, since the
delimiter indentation is stripped uniformly). Also present in
`references/betterlectio/ios/BetterLectioTests/MessageReactionTests.swift:126`. Moot if
`MessageReactionTests.swift` is deleted as recommended.

### A.16 Runtime (not compile) — recorded so it is not rediscovered
With A.1-A.15 stubbed the app builds and the test bundle links, but `test-without-building`
fails: `BetterW4 … Early unexpected exit … (Underlying Error: Crash: BetterW4 … <external symbol>)`,
immediately after `⚠️ [Keychain] wipeAll status: -34018` (`errSecMissingEntitlement`) and a
Main Thread Checker violation: `CookieManager.clearAllWebViewData` calls
`-[WKWebsiteDataStore removeDataOfTypes:…]` off the main thread
(`CookieManager.swift`, reached from `AuthenticationService.wipeAuthState():118`).
Both need fixing when `CookieManager` is rewritten: keychain items need either a
`keychain-access-groups` entitlement or `kSecUseDataProtectionKeychain`, and the WebKit wipe must
be `@MainActor`.

---

## B. Rename-damage audit

An earlier mechanical `sed` replaced `Lectio→W4` and `BetterLectio→BetterW4` case-sensitively
across the tree. Findings, classified **(a) must-rewrite for W4**, **(b) harmless comment**,
**(c) corrupted identifier to fix**.

### B.1 What the sed got right
`grep -c 'Lectio'` over `ios/BetterW4` and `ios/BetterW4Tests` returns **0** — no `Lectio`-cased
identifier survived. All 91 files were renamed on disk. The damage is entirely in (i) strings and
selectors the sed *should not* have touched, and (ii) lowercase `lectio` inside real Lectio URLs
and HTML attributes, which it left alone.

### B.2 Corrupted identifiers and strings — class (c), fix mechanically

| what | sites | was | verdict |
|---|---|---|---|
| `data-w4contextcard` | **23 sites**: `StudentParser.swift:343`; `GradeParser.swift:65`; `DirectoryParser.swift:137`; `ScheduleStore.swift:23` (doc); plus `BetterW4Tests/LessonContentParserTests.swift`, `GradeParserTests.swift`, `MessageAttachmentUploadTests.swift`, `StudentParserClassTests.swift` fixtures | `data-lectiocontextcard` (a real Lectio HTML attribute) | **(c) → then (a)**: as written it matches nothing on either server. Do not "restore" it — delete with the parser rewrite. Recorded here so nobody mistakes it for a live W4 attribute. |
| `a[href*=W4FileHandler]` | `W4HTTPClient+Messages.swift:732` | `LectioFileHandler` | **(c) → then (a)**: attachment hrefs on W4 are ordinary `index.php?r=…` links. |
| `"profile_picture.invalid_sew4n"` | `BetterW4/en.lproj/Localizable.strings:49` | `invalid_selection` — the sed hit the `lectio` inside `se·lectio·n` | **(c)**, but the whole `profile_picture.*` block is deleted anyway (§D). |
| `enum DirectoryEntityKind { case classW4 }` + `"W4-klasse"` | `DirectoryModels.swift:12,24,37,46,59,143,171,194`; `DirectoryParser.swift:65,205,229,384`; `DirectoryViewModel.swift:263,321`; `StudentSearchView.swift:28` | `classLectio` / `"Lectio-klasse"` — Lectio's own "school class" entity vs the app's synthetic one | **(c)**: the name now reads as "a W4 class", which is misleading since W4 has years/houses, not Danish klasser. Rename during the `DirectoryModels` ADAPT. |
| `makeW4ASPNETSessionCookie`, `makeW4AutologinkeyV2Cookie` | `CookieManager.swift:325,339,397,411` | `makeLectio…` | **(c) → then (a)**: both cookies are gone in W4. |
| `isW4UniLoginURL` | `W4HTTPClient.swift:116,145,399,481,506` | `isLectioUniLoginURL` | **(c) → then (a)**: `broker.unilogin.dk` has no meaning for W4; replace with the `r=site/login` test (README §4.5). |
| `"Beskeden overskrider W4s tegnbegrænsning"` | `W4HTTPClient+Messages.swift:368` | `"Lectios tegnbegrænsning"` | **(c)+(a)+Danish**: reads as "W4s" (possessive-s glued to a brand); rewrite in English. |
| `"MitID & W4"` | `LoginView.swift:298` | `"MitID & Lectio"` | **(a)**: W4 has no MitID. |
| Notification names `"dk.elliottf.betterw4.sessionExpired"` (`StudentModels.swift:203`), `"dk.elliottf.betterw4.cachesDidClear"` (`SettingsStore.swift:522`), keychain service `"dk.elliottf.betterw4"` (`KeychainManager.swift:17`), App Group `"group.dk.elliottf.betterw4"` (`SettingsStore.swift:66`) | 4 sites | `dk.elliottf.betterlectio…` | **(c)**: reverse-DNS prefix `dk.elliottf` does not match the shipping bundle id `dk.jonathanb.w4` (`project.pbxproj:377`). Harmless functionally, wrong as identifiers. |
| `ReviewPromptStore` key prefix `"bl_review_prompt."` | `ReviewPromptStore.swift:11` | `bl` = BetterLectio | **(b)**, but note changing it resets users' prompt counters. |

**False positives the sed correctly skipped** (do *not* "fix" these): every `selection`,
`selectionKey`, `selectedPhotos`, `maxSelectionCount`, `OutgoingAttachmentSelectionError`,
`selectionLabel`, `.sensoryFeedback(.selection, …)` — the substring `lectio` inside `selection`.
There are ~40 such hits; a naive `grep -i lectio` will surface them.

### B.3 Leftover Lectio protocol, class (a) — must rewrite for W4

Counts over `ios/BetterW4` + `ios/BetterW4Tests` (via `command grep -rn -i -F`):

| pattern | hits | where the mass is |
|---|---:|---|
| `lectio.dk` (URL host) | 61 | `W4HTTPClient+Messages.swift` (16), `W4HTTPClient+Schedule.swift` (6), `W4HTTPClient+Assignments.swift` (6), `W4HTTPClient+Student.swift` (5), `W4HTTPClient.swift` (4), `W4ImageLoader.swift` (4), `CookieManager.swift` (9), `AuthenticationService.swift` (2), `W4WebView.swift` (2), `StudentCardView.swift` (2), `ContentView.swift` (2), `DirectoryStore.swift` (2), `MessageReactionProtocol.swift` (2), `W4HTTPClient+PrivateEvents.swift` (2), `W4HTTPClient+Absence.swift` (3), `W4HTTPClient+Homework.swift` (1), `BetterW4Links.swift` (1), `StudentModels.swift` (1), `StudentSearchViewModel.swift` (1), `StudentParser.swift` (1), `HomeworkView.swift` (1), `AssignmentsView.swift` (1), `TimelineListView.swift` (1), `DemoDataProvider.swift` (1), `LessonContentItemView.swift` (3), tests (9) |
| `.aspx` | 90 | same files; `W4HTTPClient+Messages.swift` (13), `W4HTTPClient+Schedule.swift` (8), `StudentParser.swift` (8), `W4HTTPClient+Assignments.swift` (7) |
| `ASP.NET_SessionId` | 87 | `CookieManager.swift`, `StudentModels.swift`, `SettingsView.swift`, `W4HTTPClient.swift` |
| `autologinkey` / `autologinkeyV2` | 87 | same |
| ASP.NET postback controls (`s$m$Content…`, `s_m_Content_Content_…`, `__doPostBack`, `__EVENTTARGET`) | ~130 | parsers + `W4HTTPClient+Messages.swift` (30) + tests (37) |
| `__VIEWSTATE` | 10 | comments and `BaseParser.swift:22` doc |
| `UniLogin` | 23 | `W4HTTPClient.swift`, `AuthenticationService.swift`, `CookieManager.swift` |
| `MitID` | 31 | `LoginView.swift`, `AuthenticationService.swift`, `AuthenticationViewModel.swift`, `W4WebView.swift` |
| `gymId` | 324 | pervasive — it is a stored property on `Student`, `StudentEntry`, `StudentRecord`, `DirectoryEntity`, and a parameter on ~40 client/store methods. **This is the single widest mechanical change in the port.** W4 is one host; `gymId` must be deleted, not renamed. |

Two concrete inconsistencies introduced by the sed touching one occurrence and not its twin:

* `BetterW4Links.downloadURL = "https://betterlectio.dk/download"` (`BetterW4Links.swift:4`) vs the
  regex `#"\[url=https://betterw4\.dk/download\]…"#` in `W4HTTPClient+Messages.swift:392`. They can
  never match. Both are wrong for W4. **(a)**
* `MessageSignature.bbcode` builds `"Sendt med BetterW4"` from `BetterW4Links.downloadURL`
  (`MessageSignature.swift:4`), and `MessageReactionProtocol.swift:130` searches for the literal
  `"Sendt med BetterW4"`. Danish + BBCode + a URL that no longer resolves. **(a)**

### B.4 Danish text — class (a), the decision-3 workload

Detector: a string literal containing `æøåÆØÅ`, **or** one of ~45 Danish UI words
(`Skema|Beskeder|Lektier|Opgaver|Mere|Elever|Klasse|Hold|Lokale|Gruppe|Karakterer|Fravær|
Annuller|Gem|Slet|Send|Emne|Ingen|Alle|Fag|Note|Uge|Skriv|Profil|Tilbage|Skole|Tema|Udseende|
Notifikationer|Version|Hele|Ukendt|…`). Result: **521 literals across 62 of 101 files.** Because
the detector is word-list based it under-counts; treat 521 as a floor.

Worst 15 (file — count): `DemoDataProvider.swift` 47 · `StudentSearchView.swift` 37 ·
`SettingsView.swift` 32 · `ScheduleParser.swift` 30 · `AbsenceView.swift` 27 · `ContentView.swift` 27 ·
`SubjectMapper.swift` 25 · `StudentParser.swift` 23 · `W4HTTPClient+Messages.swift` 17 ·
`ComposeMessageView.swift` 15 · `StudentProfileView.swift` 13 · `StudentModels.swift` 12 ·
`DirectoryModels.swift` 11 · `MessageThreadView.swift` 10 · `ScheduleView.swift` 10.

Three sub-classes, because they need different treatment:

1. **User-visible UI copy** — must become English, ideally via `Localizable.strings`.
   Highest-value: `ContentView.swift:130-172` (the five tab labels), `SettingsView.swift`,
   `AbsenceView.swift`, `StudentSearchView.swift`, `StudentModels.swift:217-238` (`W4Error`
   descriptions, the strings users actually hit when something breaks).
2. **Danish used as parser input** — `ScheduleParser.swift` matches `"Ændret!"`, `"Lærer:"`,
   `"Øvrigt indhold:"`, `"Hele dagen"`; `BaseParser.swift:17` matches `"Du er blevet logget ud"`;
   `W4HTTPClient.swift:580-581` matches `"ikke er en robot"`. These are **not** translations —
   they are Lectio page content. Deleting the Danish here is the same edit as the parser rewrite.
   Do not "translate" them.
3. **Danish domain vocabulary baked into models** — `hold`, `fravær`, `standpunkt`, `elev`,
   `lærer`, `studiekort` as *field and case names* (`GradeEntry.hold`, `GradeColumn.shortLabel`
   cases, `DirectoryEntityKind.hold`, `AbsenceSummary.regularAbsence` comments). Renaming these
   is part of each model's ADAPT/REWRITE, not a string sweep.

`ios/BetterW4/en.lproj/Localizable.strings` is already English (86 keys), but only 52 keys are
referenced from code and 21 referenced keys are missing — see §D. Everything else in the UI is a
raw Danish literal.

---

## C. Dependency-ordered build plan

Verified command:
```
xcodebuild -project ios/BetterW4.xcodeproj -scheme BetterW4 \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=latest" \
  CODE_SIGNING_ALLOWED=NO build
```
Because the project uses filesystem-synchronized groups, deleting a `.swift` file is a complete
removal — no project edit needed. Steps 1-4 are what the next agent should do; they are what I
proved sufficient for a green build.

**Step 1 — two one-line compile fixes (independent of everything else).**
`W4HTTPClient+Messages.swift:221` (parenthesise the optional, §A.14) and
`BetterW4Tests/MessageReactionTests.swift:126` (indent to 8 spaces, §A.15).
Verify: nothing yet — step 1 alone still fails on §A.1.

**Step 2 — delete the removed subsystems in one pass.** This is the whole of §A.1-A.11 plus §A.12
and §A.13. Order inside the step does not matter (all are deletions), but do it as one commit
because half-deleting `ContentView` leaves it uncompilable either way.
- Delete files: `StudentProfile.swift`, `PublicProfileImage.swift`,
  `BetterW4Tests/StudentProfileTests.swift`.
  (`MessageEditAudit.swift`, `MessageReactionProtocol.swift` and their two tests are also DELETE,
  but they are self-consistent today — defer to step 6 if you want a smaller diff.)
- Edit files, in descending pain order: `ContentView.swift` (≈25 blocks), `AuthenticationViewModel.swift`
  (≈35 lines), `SettingsView.swift` (≈4 sections), `SettingsStore.swift` (≈100 lines),
  `ScheduleView.swift` (4 blocks), `BetterW4App.swift` (5 calls), `ReviewPromptCoordinator.swift`
  (8 calls), `HomeworkViewModel.swift` + `HomeworkStore.swift` (`HomeworkSyncStatus`),
  `ScheduleViewModel.swift`, `MessagesViewModel.swift`, `MessageThreadViewModel.swift`,
  `StudentSearchView.swift`, `StudentProfileView.swift`, `SubjectColorSettingsView.swift`,
  `AuthenticationService.swift`, `AbsenceViewModel.swift`, `LoginView.swift`.
- Add `Color.lessonMappingHue(_:)` to `SettingsStore.swift` (§A.12); swap App Group for
  `UserDefaults.standard` (§A.13).
- Replace the 7 `PublicProfileAvatarView` / `PublicProfilePreviewImage` uses with `W4AvatarView`
  / `RateLimitedPreviewImage`.
**Verify: BUILD SUCCEEDED.** ← the project now compiles against Lectio. This is the checkpoint;
do not start protocol work before hitting it.

**Step 3 — foundation types (nothing above them compiles until they change).**
`StudentModels.swift` first: `Student` loses `gymId`, gains `uwcId`; `School` is deleted;
`W4Credentials` becomes `{ phpSessionId: String, deviceId: String }`; `W4Error` loses
`.robotDetection` and becomes English. Then the mechanical fallout: every `gymId:` parameter
(324 hits) and `schoolId: Int` argument across the client, stores and view models.
Delete `W4WebView.swift`, `W4HTTPClient+Homework.swift`, `W4HTTPClient+PrivateEvents.swift`.
Verify after each sub-edit; this step *will* be red for a while — it is the one unavoidable
big-bang.

**Step 4 — transport.** New: `W4Urls.swift` (+`Routes`), `YiiForm.swift`, `W4Form.swift`,
`W4DeviceIdStore.swift`. Rewrite `CookieManager.swift` → `W4SessionCookieStore.swift` (one
cookie, merge non-empty `Set-Cookie` per hop). Adapt `W4HTTPClient.swift`: host,
manual-redirects-only, `r=site/login` session-expiry detection, drop UniLogin + robot detection.
Adapt `BaseParser.swift`. Verify.

**Step 5 — auth vertical.** `W4LoginClient.swift` (password → `verify2fa` → home),
`AuthenticationService`, `AuthenticationViewModel`, `LoginView` + new `OTPView`,
`W4IdentityParser` (`Welcome,` / `#user-panel`). At the end of this step you can log in for real
and capture live HTML for step 6. Verify + manual login.

**Step 6 — one feature vertical at a time**, each = client extension + parser + models + store +
view model + view + fixtures + tests. Suggested order (cheapest evidence first, matching README §7
v1 MVP): campus status → timetable (AC+EA) → assessments → mailer → absences → documents →
directory → grades → trips/travel → SafetyNet/EA activities. Delete `AssignmentsView.swift` +
`AssignmentsViewModel.swift`, `MessageEditAudit*`, `MessageReaction*` here. Verify after each
vertical.

**Step 7 — shell and IA.** `ContentView` tab set, `MoreView` catalogue, `TabBarSameTabReselectDetector`
index, `DemoDataProvider`. Verify.

**Step 8 — English sweep.** All 521 literals; `Localizable.strings` per §D. Verify.

**Step 9 — tests.** Replace `BetterW4Tests/Fixtures/**` from `references/pages/*.html` and
`references/w4.uwcrcn.no.har`; rewrite the 6 REWRITE test files; delete the 3 DELETE ones.
Verify with `build-for-testing` **and** `test` — note §A.16, the host app currently crashes on
launch under the test runner.

---

## D. `ios/BetterW4/en.lproj/Localizable.strings`

Current state: **86 keys defined, 52 referenced from Swift, 21 referenced keys missing.**
Every reference uses `String(localized:defaultValue:)` with a **Danish** `defaultValue`, so the
file is the only English surface in the app and a missing key silently ships Danish.

### D.1 Delete — 55 keys belonging to removed features

`browser_extension.body`, `browser_extension.copied`, `browser_extension.copy`,
`browser_extension.copy_announcement`, `browser_extension.navigation_title`,
`browser_extension.share`, `browser_extension.share_message`, `browser_extension.share_subject`,
`browser_extension.title` — 9 keys (browser extension, decision 1).

All 45 `profile_picture.*` keys: `choose`, `compression_error`, `cooldown_error`,
`crop_accessibility`, `crop_title`, `current`, `demo_success`, `disabled`, `format_help`,
`invalid_file`, `invalid_payload`, `invalid_sew4n` *(also a corrupted key, §B.2)*, `invite`,
`invite_message`, `loading`, `locked`, `next_change`, `not_unlocked`, `pending`, `pending_body`,
`pending_exists`, `preparing`, `preview`, `progress`, `ready`, `reason_inappropriate`,
`reason_other`, `reason_privacy`, `reason_unsuitable`, `refresh`, `rejected`,
`rejection_fallback`, `review_approved`, `review_rejected`, `review_title`, `safety_help`,
`status_error`, `status_unavailable`, `student`, `submit`, `submit_error`, `submit_success`,
`title`, `unauthorized`, `upload_error`, `use_image`, `zoom`, `zoom_accessibility`
(moderated profile pictures + referral unlock, decision 2).

Reconsider, don't auto-delete: the 5 `review_prompt.*` keys — the App Store rating pre-filter is
KEEP (`ReviewEligibility`/`ReviewPromptStore`/`ReviewPromptSheet`), but its *negative* branch
currently opens the deleted feedback sheet (`ReviewPromptCoordinator.swift:131`). Keep the keys,
re-wire the negative branch to a plain dismiss.

Also delete the 13 `message.*` keys tied to reactions/editing —
`message.add_reaction`, `message.react_with`, `message.reacted_with`, `message.reaction_you`,
`message.reaction_error_title`, `message.edit_action`, `message.edit_body`,
`message.edit_error_title`, `message.edit_signature_preserved`, `message.edit_subject`,
`message.edit_subject_placeholder`, `message.edit_title`, `message.edited_just_now`,
`message.edited_at` — once `MessageReactionProtocol.swift` / `MessageEditAudit.swift` go.
Keep `message.actions`, `message.edit_link_*` (the link button survives in the compose editor).

### D.2 Add — 21 keys already referenced but undefined

All from `StudentProfileView.swift` (and therefore also candidates for deletion if that view is
rewritten from scratch, but they must exist while it does):
`student_profile.birthday`, `.class`, `.class_short`, `.demo_bio`, `.inactive`, `.loading`,
`.missing`, `.photo`, `.photo_hint`, `.pin`, `.retry`, `.schedule`, `.schedule_description`,
`.show_less`, `.show_more`, `.student_badge`, `.title`, `.unavailable`, `.unpin`, `.write`,
`.write_short`.
Plus `common.retry` is defined but unreferenced while `student_profile.retry` is referenced and
missing — collapse to `common.retry`.

### D.3 Add — the new English UI surface

The 521 Danish literals need keys. Minimum namespaces to create, matching the new IA:

`tab.*` (timetable, mailer, assessments, more) ·
`login.*` (username, password, sign_in, otp_title, otp_code, otp_verify, forgot_password,
error_invalid_credentials, error_session_expired) ·
`timetable.*` (today, week, day_1…day_5, weekend, extra_academics, no_ea, now, all_day, cancelled,
changed, room, teacher) ·
`assessments.*` (title, add, confirm_done, revert_to_pending, due, overdue, done, no_items) ·
`mailer.*` (inbox, sent, compose, subject, message, recipients, attach, send, cc_me, received, from) ·
`absences.*` (academic, extra_academic, latenesses, register, percentage, no_records) ·
`campus.*` (on_campus, off_campus, location, other, set_status) ·
`trips.*`, `documents.*`, `directory.*` (students, staff, rooms, houses, countries, birthdays),
`grades.*`, `safetynet.*` (wellness, sleep, exercise, weekly_report),
`settings.*` (appearance, theme, calendar_style, subject_colours, notifications, clear_cache,
sign_out, version) ·
`error.*` (network, session_expired, not_authorized, server, parse) — mirroring the six W4 session
states in README §4.5 and `android/…/core/i18n/AppErrorUi.kt`.

Keep the file as one `en.lproj/Localizable.strings`; decision 3 means no second `.lproj`.

---

## 5. NEW — files that do not exist yet

Named to match the Android blueprint (`android/app/src/main/java/dk/betterw4/android/**`) so the
two ports stay legible side by side. Paths are all `ios/BetterW4/`.

### 5.1 Transport & session (blocking; step 4)
| new file | purpose | Android counterpart |
|---|---|---|
| `W4Urls.swift` | Yii route builder for `https://w4.uwcrcn.no/index.php?r={route}&k=v`, plus a `Routes` enum of the ~45 captured routes; `routeOf(url:)` for redirect classification | `core/w4/W4Urls.kt` (already enumerates `site/login`, `site/verify2fa`, `academics/deadlines`, `mailer/inbox`, …) |
| `W4Hosts.swift` | `HOST = "w4.uwcrcn.no"`, `ORIGIN`, a stable desktop User-Agent | `core/w4/W4Hosts.kt`, `core/w4/http/W4UserAgent.kt` |
| `YiiForm.swift` | `fieldsForSubmit(html:extra:submitName:submitValue:formSelector:)` — collect a Yii form's inputs and add the clicked `yt0` | `core/w4/YiiForm.kt` |
| `W4Form.swift` | parse a `<form>` (action, method, submit name/value) + urlencode | `core/w4/scrape/W4Form.kt` |
| `W4SessionCookieStore.swift` | single `PHPSESSID`; merge non-empty `Set-Cookie` per hop; never wipe on empty | `core/w4/cookie/{W4CookieJar,SetCookieParser,CookieHeaderBuilder}.kt` |
| `W4DeviceIdStore.swift` | stable per-install UUID for `LoginForm[deviceId]`, in Keychain | `core/w4/auth/W4DeviceIdStore.kt` |
| `W4SessionEvents.swift` | the six session-death signals of README §4.5 as one classifier (302→login, 200 login body, AJAX 403 + `Login Required`, 403 other, 409, missing `Welcome,`) | `core/w4/session/{SessionController,SessionEvents}.kt` |

### 5.2 Auth (step 5)
| new file | purpose |
|---|---|
| `W4LoginClient.swift` | `submitPassword(username:password:) -> .authenticated / .needsOtp(challenge) / .failed`; `submitOtp(challenge:code:)`. Mirrors `core/w4/auth/W4LoginClient.kt` including `W4OtpChallenge { formAction, hiddenFields, otpFieldName, submitName, submitValue }`. The OTP **field names are UNKNOWN — needs live capture** of one full login (password → `r=site/verify2fa` → home). |
| `OTPView.swift` | native code entry (`.oneTimeCode` content type) |
| `ForgotPasswordView.swift` | `r=site/forgotpass`, `ForgotPassForm[username]` + `yt0=Reset` |
| `W4IdentityParser.swift` | `Welcome, {name}` from `#user-panel`, `uwc_id` from profile links |

### 5.3 Chrome present on every page (step 6, first)
| new file | purpose |
|---|---|
| `W4Chrome.swift` | one pass over `#header` / `#main_menu` / `#user-panel` / `.sdmenu` / `#content_inner` so every page fetch also refreshes identity, notification count and campus status |
| `CampusStatusParser.swift` + `CampusStatusStore.swift` + `CampusStatusView.swift` | `POST index.php?r=site/setstatus` with `status=on\|off` and `location=<label>` (`maxlength=20` for "other"); locations come from the page. Android: `feature/campus/*` |
| `W4NotificationParser.swift` + `W4NotificationPoller.swift` | 60 s poll of `notifications/refresh`; `read` / `readGroup` / `readAll` / `readAllEmails` / `clear*` with `notification_id` / `notification_type`. Android: `feature/notifications/*` |

### 5.4 Feature parsers/repositories (step 6, per vertical)
`W4TimetableParser.swift` (AC + EA, `#timetable`, `tt_start_hour`/`tt_end_hour`, Day 1-5 + Weekend) ·
`W4AssessmentParser.swift` (month calendar, add item, Confirm done / Revert to pending) ·
`W4MailerParser.swift` (inbox/archive/view; Received/From/Subject) ·
`W4PeopleParser.swift` (students all / 1st / 2nd / country / house; staff current + on leave; visitors) ·
`W4AbsenceParser.swift` (AC + EA + latenesses; the `register` form) ·
`W4GradeParser.swift` (`academics/grades/grades`, `…/sat`, transcripts) ·
`W4TripsParser.swift` + `W4TravelFormsParser.swift` (`academics/trips`, `academics/travel/travel.list`) ·
`W4DocumentsParser.swift` (`documents/index&folder_id=`/`page_id=`) ·
`W4EAActivitiesParser.swift` (`extraacademics/activities/*`, diary `EAGroupStudentModel[outcomes][]`, portfolio, CAS interviews) ·
`SafetyNetParser.swift` (weekly wellness/sleep/exercise, Graph/Table) ·
`W4ResourceBookingParser.swift` (`academics/resources/resources`; POST `day, month, year, reservation_id, time_start, time_end, description, resource_id`) ·
`RoomScheduleParser.swift` (`academics/timetable/room`) ·
`LetterOfAttendanceLoader.swift` (`people/students/letter/attendance`, ~600 KB HTML — stream, don't parse into a model).
Each has a direct Android counterpart under `android/…/feature/*`.

### 5.5 Supporting
| new file | purpose |
|---|---|
| `IcsCalendarParser.swift` | optional fast path over the personal feeds in `academics/feeds` (`acttical`/`eattical`/`combottical`/`sassttical`). Token is a secret — Keychain only, never logged. Android: `feature/schedule/IcsCalendarParser.kt` |
| `LocalPrivateEvents.swift` | local-only calendar overlay replacing the deleted `privat_aftale.aspx` path. Android: `feature/schedule/LocalPrivateEvents.kt` |
| `W4Dates.swift` | `dd-M-yy` (`14-Aug-2026`) + `en-GB` datepicker formats. Android: `core/w4/W4Dates.kt` |
| `SubjectIcons.swift` | IB subject → SF Symbol + hue, replacing the Danish table in `SubjectMapper.swift`. Android: `feature/settings/SubjectIcons.kt` |
| `HomeLinksView.swift` | the configurable Home "Links" block (Trip Form, ManageBac, kitchen form, policies Drive, document pages) — data, not code |

### 5.6 Tests
`BetterW4Tests/Fixtures/w4/` sourced from `references/pages/*.html`
(`UWCRCN W4.html`, Academics, Extra Academics, School info, Documents, Current applicants) and
`references/w4.uwcrcn.no.har`, plus `W4UrlsTests.swift`, `YiiFormTests.swift`,
`W4SessionExpiryTests.swift` (the six README §4.5 signals), and one parser test per §5.4 file.

### 5.7 Open captures blocking `NEW` work
1. One full login HAR (password → `r=site/verify2fa` → home): exact OTP field names, whether
   `PHPSESSID` rotates, whether `deviceId` is stored server-side. Blocks `W4LoginClient.swift`.
2. `academics/timetable/mytimetable` for a **non-current** week: the week/pagination query
   parameter. Blocks `ScheduleIdentity.w4WeekParameter`.
3. A `POST index.php?r=mailer/send&type=freeform` body: confirms TinyMCE HTML vs anything else.
   Blocks `BBCodeRichEditor.swift`'s replacement.
4. A `notifications/refresh` response body. Blocks `W4NotificationParser.swift`.
5. An assessments Confirm-done POST body. Blocks `W4AssessmentParser.swift`'s write path.
