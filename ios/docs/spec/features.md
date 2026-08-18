# BetterW4 iOS — domain, repository and persistence spec

What the app holds, where each field comes from, and how it flows from HTML to disk to screen.

Companion documents:

- `ios/docs/spec/reviewer-notes.md` — HTTP engine, cookies, redirects, session death, login/2FA, identity.
  That document wins on anything transport-shaped. This one starts *above* the client: it assumes a
  `W4Client` that returns `(body, finalUrl, statusCode, contentType, credentials)` and typed failures.
- `README.md` (repo root) — the W4 protocol brief. Route strings quoted here are re-verified against the
  saved pages in `references/pages/`, not taken from memory.

Evidence rules used throughout: every selector, route and field name is either (a) quoted from a saved page
in `references/pages/`, (b) quoted from the shipped Android port, or (c) explicitly marked
**UNKNOWN — needs live capture**. Nothing is invented.

---

## 0. Layering

```
W4Client  (reviewer-notes.md)          → HTML / bytes + typed failure
  └── Parser (pure, no I/O, testable)  → domain structs
        └── Repository (actor)          → cache policy, demo branch, write actions
              └── Store (SwiftData / file cache / Keychain / UserDefaults)
                    └── ViewModel (@MainActor, generation-guarded)
```

Rules that are not negotiable:

1. Parsers are pure functions over `String` and return domain structs. No `URLSession`, no SwiftData, no
   `MainActor`. This is what makes `BetterW4Tests` possible against fixtures.
2. Repositories own the cache/TTL policy and the demo branch. ViewModels never talk to `W4Client`.
   *(Today they do — `HomeworkViewModel.swift:88`, `AbsenceViewModel.swift:66`, `MessagesViewModel.swift:97`,
   `ScheduleViewModel.swift:191` all call `W4HTTPClient` directly. That inversion is part of this port.)*
3. Parsing runs off the main actor (`Task.detached(priority: .userInitiated)`), as it already does in
   `HomeworkViewModel.swift:94-96` and `MessagesViewModel.swift:105-109`. Keep it.

### 0.1 Result type

Android uses `AppResult` / `AppError` (`core/result/AppResult.kt:7-43`). iOS uses `throws` + typed error.
Final shape:

```swift
enum W4Failure: Error, Equatable {
    case offline                     // URLError.notConnectedToInternet / .networkConnectionLost
    case sessionExpired              // reviewer-notes.md §3 — the ONLY case that logs the user out
    case forbidden                   // 403 without "Login Required" — wrong role, stay signed in
    case serverConflict(String)      // 409, body is the message (init_ajax.js)
    case parsing(String)
    case transport(String)
}
typealias W4Result<T> = Result<T, W4Failure>
```

`AppError.RobotDetection` (`core/result/AppResult.kt:38`) and `W4Error.robotDetection`
(`ios/BetterW4/StudentModels.swift:213`) are deleted — W4 has no robot page.
`AppError.InvalidLogin` survives as a login-screen-only error, not a `W4Failure` case.

### 0.2 Final repository set

| Repository | Replaces | Primary routes |
|---|---|---|
| `TimetableRepository` | `ScheduleRepository` / `ScheduleViewModel` fetches | `academics/timetable/mytimetable`, `extraacademics/timetable/mytimetable`, `site/index` |
| `AssessmentRepository` | `HomeworkStore` + `HomeworkViewModel` + all of `assignments/` | `academics/deadlines` |
| `MailRepository` | `MessageCacheManager` + `MessagesViewModel` + `MessageThreadViewModel` | `mailer/inbox`, `mailer/archive`, `mailer/view`, `mailer/send&type=freeform`, `mailer/extra&type=freeform` |
| `AttendanceRepository` | `AbsenceViewModel` fetches | `people/students/absences`, `people/students/eaabsences`, `people/students/absences/register` |
| `GradeRepository` | `GradesViewModel` fetches | `academics/grades/grades`, `academics/grades/grades/sat`, `academics/transcripts/transcripts` |
| `CampusStatusRepository` | new | `site/setstatus`, chrome of any page |
| `NotificationRepository` | new | `notifications/refresh`, `read`, `readgroup`, `readall`, `readallemails`, `clear*` |
| `TripRepository` | new | `academics/trips` |
| `TravelRepository` | new | `academics/travel/travel.list` |
| `DocumentRepository` | new | `documents/index`, `extraacademics/documents` |
| `ExtraAcademicsRepository` | new | `extraacademics/activities/*`, `extraacademics/safetynet/mysafetynet` |
| `DirectoryRepository` | `DirectoryStore` + `StudentStore` + `DirectorySyncService` | `people/students/all`, `firstyear`, `secondyear`, `byname`, `bypreferred`, `bycountry`, `byhouse`, `people/staff/current`, `people/staff/onleave`, `people/students/staff&type=…`, `people/birthdays` |
| `ProfileRepository` | `StudiekortRepository` | `site/profile`, `people/students/student&uwc_id=`, `people/students/letter/attendance` |
| `FeedsRepository` | new | `academics/feeds`, `site/rss` |
| `ResourceRepository` | new | `academics/resources/resources` |
| `HomeRepository` | new | `site/index` (one fetch, many models) |

Deleted outright, with no successor: `AssignmentRepository` (Android's is already an empty stub —
`feature/assignments/AssignmentRepository.kt:8-11` returns `emptyList()`), `PlanRepository`
(`feature/plans/PlanRepository.kt:13-16`, demo-only), `ModuleStatRepository`
(`feature/teams/ModuleStatRepository.kt:13-16`, demo-only), `TermRepository`
(`feature/terms/TermRepository.kt:14-27`, hardcoded), `RoomScheduleRepository.loadPersonWeek`
(`feature/directory/RoomScheduleRepository.kt:17-26`, returns empty — W4 exposes no per-person timetable
to students).

---

## 1. The domain model

### 1.1 Identity and session

```swift
struct Student: Codable, Equatable, Hashable {
    let uwcId: String        // "nc26jban" — pattern nc\d{2}[a-z]+, from the profile link in chrome
    let displayName: String  // "Jonathan Bangert" — from "Welcome, {name}" in #user-panel
    var year: String?        // "Year 1" / "1st year"
    var house: String?
    var photoURL: URL?       // https://w4.uwcrcn.no/files/user_photos/{uwcId}_thumb.jpg
    let isDemo: Bool
    var id: String { uwcId }
}
```

Changes from `ios/BetterW4/StudentModels.swift:12-23`:

- `studentId: String` → `uwcId`. It is the Keychain scope key, the SwiftData scope key and the cache-key
  prefix. There is no numeric student id on W4 (reviewer-notes.md §6).
- **`gymId: Int` dies everywhere.** It is threaded through ~40 call sites today (`StudentStore`,
  `DirectoryStore`, `MessageCacheManager.threadDetailFile`, every `W4HTTPClient` method). W4 is one host,
  one school. Deleting it collapses `DirectoryEntityID.key` from `"\(gymId)|\(kind)|\(rawID)"`
  (`DirectoryModels.swift:84-86`) to just the UWC id.
- `School` / `School.demo` (`StudentModels.swift:43-54`) die with the school picker. Android's
  `W4School { ID = 1, NAME = "UWC Red Cross Nordic" }` (`core/model/Student.kt:33-37`) is the pattern:
  a constant, not a model.
- `pictureId` (Lectio `GetImage.aspx?pictureid=`) dies; W4 photos are a deterministic URL
  (`feature/directory/W4PeopleParser.kt:91-92`).

```swift
struct W4Session: Codable {              // Keychain only, never UserDefaults, never logged
    var phpsessid: String
    var updatedAt: Date
}
```

`W4Credentials` (`StudentModels.swift:59-172`) is deleted wholesale: `autologinkey`,
`autologinkeyExpiresAt`, `sessionIdExpiresAt`, `additionalCookies`, `isloggedin3`, and the four
`withASPNETSessionId` / `clearingAutologinkeyV2` helpers. One cookie, no expiry metadata (the `Set-Cookie`
carries neither `Max-Age` nor `Expires` — README §4.1), so `isValid` / `isExpiringSoon` have nothing to
compute and are deleted with it. The device id is a separate Keychain item, not part of the session.

### 1.2 Timetable — `skema` becomes AC + EA combined

**Verified markup** (`references/pages/UWCRCN W4.html`):

| Node | Line | Content |
|---|---|---|
| `#timetable > h3` | 86 | `August 2026, week 33` |
| `#timetable-header .header-row .header-cell` | 88–96 | `.day-name` `Monday`, `<div>10-Aug-2026</div>`, `.rotation-day` `Day 1`, `<div>No EA</div>` |
| `.rotation-day.no-classes` | 95 | `Weekend` on Sat/Sun |
| second `#timetable` (grid body) | 138 | `div.column[style="height: 900px"]` — hour gutter of 15 `div.cell` (`7:00 — 8:00` … `21:00 — 22:00`, em dash U+2014) then 7 day columns |
| `div.column.current > #current_time` | 180 | `style="… top: 394px;"` — the now-line |
| `var tt_start_hour = 7; var tt_end_hour = 22;` | 22 | page script |

15 hours over 900 px ⇒ **1 px = 1 minute from 07:00**. `top: 394px` = 13:34. This is the geometry the
Android parser assumes (`feature/schedule/W4TimetableParser.kt:91-96`) and it is the only *verified* way to
place a block. `.period`, `.inner`, `.datetime`, `.room` (`W4TimetableParser.kt:82-100`) are **UNKNOWN —
needs live capture** of a term-time week; the captured week is a holiday week with zero lesson blocks.

```swift
enum EventSource: String, Codable { case academics, extraAcademics, schoolCalendar, local }
enum EventStatus: String, Codable { case normal, changed, cancelled }

struct ScheduleEvent: Identifiable, Codable, Equatable {
    let id: String            // "w4-<id>" from href id=/class_id=/group_id=, else "<source>-<date>-<index>"
    let title: String
    let subject: String       // canonical-ish label used for colour/rename lookup
    let start: Date?          // nil ⇒ all-day
    let end: Date?
    let date: Date            // day the occurrence renders on
    let room: String?
    let teacher: String?
    let teacherUwcId: String?
    let status: EventStatus
    let source: EventSource
    let isAllDay: Bool
    let href: String?
    let notes: String?
}

struct ScheduleDay: Codable, Equatable {
    let date: Date
    let rotationDay: String?   // "Day 1" … "Day 5", "Weekend"
    let eaSummary: String?     // "No EA" when the header cell says so
    let events: [ScheduleEvent]
}

struct ScheduleWeek: Codable, Equatable {
    let year: Int              // ISO week-year
    let week: Int
    let days: [ScheduleDay]    // always 7, Monday-first
    let startHour: Int         // tt_start_hour, default 7
    let endHour: Int           // tt_end_hour, default 22
    let nowMinutesFromStart: Int?  // #current_time top:NNNpx, only for the current week
    let fetchedAt: Date
}
```

Changes from `ios/BetterW4/ScheduleModels.swift:12-56`:

- `startTime: String` / `endTime: String` become real `Date?`. The current string pair forces every consumer
  to re-parse and makes the all-day case a magic empty string (`ScheduleStore.swift:647`).
- `subtitle` → `subject`, `teacherId` → `teacherUwcId`.
- `EventStatus.moved` is deleted (Lectio-only). Legacy raw value `"moved"` decodes to `.changed`.
- New: `source`, `rotationDay`, `eaSummary`, `startHour`/`endHour`/`nowMinutesFromStart`.

Assembly (`feature/schedule/ScheduleRepository.kt:50-93` is the model): fetch AC
(`academics/timetable/mytimetable/index`, `.important`) and EA
(`extraacademics/timetable/mytimetable/index`, `.opportunistic`) **in parallel** with
`?year=&week=`, parse each, merge by date, then overlay:

1. the college Google Calendar (`feature/schedule/SchoolCalendar.kt:18-19`,
   `https://calendar.google.com/calendar/ical/calendar%40uwcrcn.no/public/basic.ics`) — this is the
   `#calendar` iframe on Home (`UWCRCN W4.html:255`). **The saved `embed.html` is blank**, so the calendar
   id is inherited from the Android port, not verified: **UNKNOWN — needs a live capture of the Home
   iframe `src`**;
2. local private events (`feature/schedule/LocalPrivateEvents.kt`) — W4 has **no** private-appointment
   form (`ScheduleRepository.kt:157`), so "add event" stays a device-local overlay or is cut. Keep the
   model, label the UI honestly ("Only on this device").

`ScheduleMultiDay` (`feature/schedule/ScheduleMultiDay.kt:25-136`) ports as-is: expand across covered days,
promote full middle days to all-day, clamp segments to the day for layout, dedupe by `(id, date)`.

`ScheduleIdentity.w4WeekParameter` (`ios/BetterW4/ScheduleIdentity.swift:24-28`, `WWYYYY`) is Lectio's
format and is deleted — W4 takes `year` and `week` as separate query keys.

### 1.3 Assessments — `lektier` + `opgaver` collapse into one calendar

This is the single biggest product change. `HomeworkEntry`/`HomeworkItem`
(`ios/BetterW4/AssignmentModels.swift:93-111`) and the entire `Assignment` family
(`AssignmentModels.swift:12-88`: `AssignmentStatus.submitted/waiting/notSubmitted/missing`,
`AssignmentDetail`, `AssignmentFile`, `AssignmentSubmission`, `elevTimerHours`) are replaced by:

```swift
enum AssessmentKind: String, Codable { case classAssigned = "class", studentCreated = "student" }
enum AssessmentStatus: String, Codable { case pending, done }

struct Assessment: Identifiable, Codable, Equatable {
    let id: String                 // "\(kind.rawValue):\(rawId)"
    let rawId: String              // assessment_id | student_assessment_id
    let kind: AssessmentKind
    let title: String
    let subject: String
    let teacher: String?
    let unit: String?
    let dueDate: Date?
    let daysLeft: Int?
    var status: AssessmentStatus   // server truth
    let isOverdue: Bool
    let href: String?
}

struct AssessmentDraft {           // student-created items only
    var studentAssessmentId: String?     // nil ⇒ create
    var title: String                    // student_assessment_title
    var deadline: Date                   // student_deadline_date, formatted dd-MMM-yyyy
}

struct AssessmentActionURLs: Codable {   // scraped from the page script, never hardcoded
    let confirm: String, revert: String, save: String, create: String, delete: String
}
```

Source: `academics/deadlines` (confirmed in the Academics sdmenu, `references/pages/Academics.html:77`).
Parser shape from `feature/homework/W4AssessmentParser.kt:27-58`: `a.assessment-link` carrying
`data-assessment-id`, `data-assessment-type` (`student` vs class), `data-status` (`pending` ⇒ `.pending`),
`data-assessment-date`, `data-subject-name`, `data-teacher-name`, `data-unit`, `data-days-left`,
`data-css-class` (contains `overdue`); day fallback via the enclosing `.day > .day-header` plus `month=` /
`year=` in the page URL. **All of these attribute names are UNKNOWN — needs live capture** of
`academics/deadlines`; the parser must return `[]` and log, never throw, when they are absent.

Writes (README §5.2 confirms the field names, the AJAX URLs are scraped):

| Action | Fields |
|---|---|
| Confirm done | `assessment_id=<rawId>` (class) or `student_assessment_id=<rawId>` (student) → `urls.confirm` |
| Revert to pending | same fields → `urls.revert` |
| Create / Save | `student_assessment_title`, `student_deadline_date` (+ `student_assessment_id` on save) → `urls.create` / `urls.save` |
| Delete | `student_assessment_id` → `urls.delete` |

`feature/homework/W4AssessmentParser.kt:61-80` (`parseAjaxUrls`, `fieldsForStatus`) is the reference.
Because W4 owns done-state server-side, the Lectio-era local `donePrefs`
(`feature/homework/HomeworkRepository.kt:31,110-121`) becomes an **optimistic overlay only**: write
`localStatus` + `localStatusUpdatedAt`, POST, and drop the overlay as soon as a fetch returns a server
status newer than the local write. Nothing about "homework done" is ever synced anywhere else — the
`SupabaseHomeworkService` / `HomeworkSyncStatus` merge in `HomeworkStore.swift:319-360` and
`HomeworkViewModel.swift:29,71-76,118-120` is deleted.

Also deleted: `AssignmentFilter.awaitingMe/delivered/missing` with its Danish substring matching
(`feature/assignments/AssignmentModels.kt:51-67`), `HomeworkDetailLoader`, `groupedByDate()`'s
`"Uden dato"` label (`feature/homework/HomeworkModels.kt:41`). The filter set becomes
**All / Pending / Done / Overdue**, plus a subject filter.

### 1.4 Mail — `beskeder` becomes the W4 mailer

```swift
struct MailFolder: Codable, Hashable, Identifiable {
    let id: String, displayName: String
    static let inbox   = MailFolder(id: "inbox",   displayName: "Inbox")
    static let archive = MailFolder(id: "archive", displayName: "Sent")
}

struct MailMessage: Identifiable, Codable, Equatable {
    let id: String            // id= from the row href
    let subject: String
    let from: String          // inbox only; archive has no From column
    let receivedAt: Date?
    let isUnread: Bool
    let hasAttachment: Bool
    let href: String?
}

struct MailMessageDetail: Codable, Equatable {
    let id: String
    let subject: String
    let from: String
    let recipients: [String]
    let sentAt: Date?
    let bodyHTML: String      // #content_inner, TinyMCE-authored HTML
    let attachments: [MailAttachment]
}

struct MailAttachment: Identifiable, Codable, Equatable { let id: String, name: String, url: String }

struct MailRecipient: Identifiable, Codable, Hashable {
    let id: String            // W4 recipient token from mailer/extra&type=freeform
    let name: String
    let subtitle: String?     // year / house / role
}

struct MailDraft {
    var subject: String                       // MailerForm[subject]
    var bodyHTML: String                      // MailerForm[message] — HTML, not BBCode, not Markdown
    var recipients: [MailRecipient]
    var attachments: [OutgoingMessageAttachment]  // MailerForm[attachment][], multipart
    var sendCopyToMe: Bool                    // MailerForm[sendCC]
}
```

Routes verified in `references/pages/School info @ UWCRCN.html:77`: `r=mailer/inbox`, `r=mailer/archive`,
`r=mailer/send&type=freeform`. Field names from README §5.2 (`MailerForm[subject]`, `[message]`,
`[attachment][]`, `[sendCC]`, `[attachmentSource]=upload`). List markup: Android targets the generic Yii
grid `div.grid-view table.items` with header-driven column indexes — Received / From / Subject on inbox,
Send date / Subject / Attachment on archive (`feature/messages/W4MailerParser.kt:19-52`). That defensive
shape is right; the exact markup is **UNKNOWN — needs live capture** of `mailer/inbox`.

**What dies from the Lectio message model** (`ios/BetterW4/MessageModels.swift`, `MessageThreadView.swift`,
1 099 lines, and the whole `feature/messages/` BBCode stack):

| Dies | Evidence it is Lectio-only |
|---|---|
| Threads (`MessageThreadDetail.messages: [Message]`, `MessageModels.swift:156-204`) | W4 `mailer/view&id=` renders one email; Android returns a single synthetic `ThreadEntry` (`feature/messages/MessageRepository.kt:110-123`) |
| Reply / reply-all + `NotifyOption` (`MessageModels.swift:207-218`) | no reply route in the mailer sdmenu; composing is always `mailer/send&type=freeform` |
| Reactions (`MessageReactionProtocol.swift`, `MessageReactionEmoji`, `MessageReactionGroup`, `MessageLocator`, `ownReactionCarrierTargets`) | a BetterLectio invention carried in message bodies |
| Message editing (`MessageEditDraft`, `MessageEditAudit.swift`, `editPostbackTarget`) | Lectio postback-only |
| BBCode (`BBCodeRichEditor.swift`, `BbcodeDocument.kt` 447 lines, `BbcodeSpannable.kt`, `BbcodeEdit.kt`) | replaced by a TinyMCE-compatible **HTML** editor (bold/italic/underline/link/bullet+numbered list — exactly the toolbar README §6 lists) |
| Signature protocol (`MessageSignature.swift`, `feature/messages/MessageSignature.kt`, `settings.messageSignatureEnabled`) | product decision #2 |
| Folders `-70 / -40 / -10 / -80 / -60` (`MessageModels.swift:230-237`) | Lectio virtual folder ids; W4 has two grids |
| Flag / star (`isFlagged`, `toggledFlag()`) | no flag column on the W4 grid |
| `SenderType.student/teacher/unknown` | W4 rows carry a plain name; kind comes from a directory lookup, not the row |

Attachment limits change: `OutgoingMessageAttachment.maximumCount = 10` and
`maximumByteCount = 25 MB` (`ios/BetterW4/OutgoingMessageAttachment.swift:14-15`) must become
**5 files × 2 MB** (README §5.2). The streaming-from-disk upload path and the temp-directory hygiene
(`purgeStaleTemporaryFiles`, `OutgoingMessageAttachment.swift:105-120`) are kept as-is. All five Danish
error strings (`OutgoingMessageAttachment.swift:155-163`) become English.

Marking read: the Android repo only invalidates the list cache (`MessageRepository.kt:176-200`). On W4 the
unread signal is the notification bell's email group, so `MailRepository.markRead(id)` calls
`notifications/read` with the matching `notification_id` when one is known, then refetches the inbox.
**UNKNOWN — needs live capture**: whether opening `mailer/view` alone clears the email notification.

### 1.5 Attendance — `fravær` becomes AC absences + latenesses + EA absences

**Verified markup** (`references/pages/UWCRCN W4.html:240-247`):

```html
<div id="absences">
  <div id="academic-absences"><h3>Academics Attendance Meter</h3>
    <p>You have 0 absences and 0 latenesses so far<br>
       <a href="…index.php?r=people/students/absences">View attendance</a></p></div>
  <div id="ea-absences"><h3>EA Attendance Meter</h3>
    <p>You have 0 absences and 0 latenesses so far<br>
       <a href="…index.php?r=people/students/eaabsences">View attendance</a></p></div>
</div>
```

Android's regex is `"""You have (\d+) absences? and (\d+) lateness(?:es)?"""`
(`feature/absence/W4AbsenceParser.kt:24-27`) — keep it, it matches the capture exactly.

```swift
enum AttendanceSource: String, Codable { case academics = "ac", extraAcademics = "ea" }
enum AttendanceKind: String, Codable { case absence, lateness }

struct AttendanceMeter: Codable, Equatable { let absences: Int; let latenesses: Int }

struct AttendanceRecord: Identifiable, Codable, Equatable {
    let id: String            // "\(source)|\(dateRaw)|\(period)|\(subject)|\(index)"
    let source: AttendanceSource
    let date: Date?
    let period: String?       // "P3", "1st period" — column label varies
    let subject: String
    let kind: AttendanceKind
    let status: String        // raw server string, shown verbatim
    let teacher: String?
    let note: String?
    let displayDate: String
}

struct AttendanceOverview: Codable, Equatable {
    let academic: AttendanceMeter
    let extraAcademic: AttendanceMeter
    let records: [AttendanceRecord]
    let fetchedAt: Date
}

struct SubjectAttendance: Identifiable {   // replaces SubjectAbsence
    var id: String { fullLabel }
    let subject: String, fullLabel: String
    let absences: Int, latenesses: Int
}

struct AbsenceRegistrationDraft {
    var date: Date                          // StudentAbsenceForm[absence_date], "dd-MMM-yyyy"
    var selectedSlotFields: Set<String>      // per-slot checkbox names, injected by W4's own JS
}
```

Deleted from `ios/BetterW4/AbsenceModels.swift`: `AbsenceSummary { regularAbsence, writtenAbsence }`
(Lectio's two percentages), `AbsenceEntry.absencePercent` / `registeredBy` / `isApproved` ("Godskrevet"),
`ActivityDetails` (Lectio tooltip payload), `AbsenceReasonOption` / `AbsenceEditDetails` and the whole
cause-editing flow (`AbsenceEditFormParser.swift`, `AbsenceViewModel.editDetails` at
`AbsenceViewModel.swift:92-120`) — W4 rows are read-only (`W4AbsenceParser.kt:154` sets
`editable = false`). The Danish cause list `AbsenceCauses.all`
(`feature/absence/AbsenceModels.kt:100-108`) and the percentage warning copy
(`feature/absence/AbsencePresentation.kt:34-46`, already short-circuited on W4 by `warningFromOverview`
returning `nil` at line 49) die with them. `AbsenceSummary.Dual`, `AbsenceChartSeries`,
`AbsenceTeamRow`, `AbsenceFraction` — all percentage-shaped — die. W4 counts events; it does not compute
a percentage.

What replaces the percentage hero: two counters (AC absences / latenesses, EA absences / latenesses) plus
a per-subject breakdown by count, sorted descending, from `AbsencePresentation.subjectBreakdown`'s grouping
logic minus the average (`feature/absence/AbsencePresentation.kt:11-28`).

Register-absence form: `people/students/absences/register` (verified,
`references/pages/Academics.html:77`). `StudentAbsenceForm[absence_date]` in `dd-M-yy` with an en-GB
datepicker, plus per-slot checkboxes added by JS (README §5.2). **The checkbox names are UNKNOWN — needs
live capture**; until then the app must scrape the form's real inputs rather than construct them.

The list tables on both absence pages are **UNKNOWN — needs live capture**; Android's header-driven column
matcher (`W4AbsenceParser.kt:104-157`, matching `date|when`, `period|slot|time|lesson`,
`class|subject|course|activity|group`, `type|kind`, `status`, `comment|note|remarks|reason|explanation`,
`teacher|staff`) is the right defensive fallback and must survive a missing `<thead>`.

### 1.6 Grades and academic records

```swift
struct GradeColumn: Codable, Hashable, Identifiable { let key: String; let label: String; var id: String { key } }
struct GradeCell: Codable, Equatable { let value: String; let weight: Double? }
struct GradeRow: Identifiable, Codable, Equatable {
    let id: String; let subject: String; let level: String?; let teacher: String?
    let cells: [String: GradeCell]
}
struct GradesReport: Codable, Equatable {
    let columns: [GradeColumn]; let rows: [GradeRow]; let alerts: [String]; let fetchedAt: Date
}
```

`ios/BetterW4/GradeModels.swift:12-18` loses `blockedWrittenProtocolTerm` / `blockedOralProtocolTerm`
(Lectio karakterprotokol), and `GradeCellValue.xprsSubject` / `.source` (Lectio XPRS). `GradeNoteEntry`
(`GradeModels.swift:63-70`) is retained only if `academics/grades/grades` actually renders teacher notes —
**UNKNOWN — needs live capture**; Android's parser does not produce any (`W4GradeParser.kt:46-73`).

Scale: **IB 1–7 only.** `GradeAverage.SEVEN_STEP` with `12/10/7/4/02/00/-3`
(`feature/grades/GradeAverage.kt:50-61`), `shortLabelForKey`'s `1.SP` / `Års` / `Eks.`
(`GradeAverage.kt:69-81`, mirrored in `GradeModels.swift:31-41`), `displaySubject`'s
`", Mundtlig"` → `(M)` (`GradeAverage.kt:191-202`), and `formatAverage`'s Danish decimal comma
(`GradeAverage.kt:188-189`) all die. What survives: per-column weighted average (never mix columns —
`GradeAverage.kt:129-142`), `defaultColumnKey` preferring `final` → `awarded` → `predicted` →
`term-2` → `term-1` (`GradeAverage.kt:14-20`), and `progressForGrade` on the IB branch
`(n - 1) / 6` (`GradeAverage.kt:207-214`). Averages format with `.` and one decimal in English.

The W4 grades table itself is **UNKNOWN — needs live capture**; Android says so in the parser header
(`feature/grades/W4GradeParser.kt:6-12`, "No captured live HTML"). It maps the first
`#content_inner table.items`, treats a `subject|course|class|name` column as the subject, `teacher|staff`
and `level|hl/sl|group` as identity, and slugs every other header into a column key. Keep exactly that.

Adjacent read-only surfaces, all rendered as sanitised HTML with a share/open-in-Safari action, all
**UNKNOWN — needs live capture**: `academics/grades/grades/sat` (SAT/ACT), `academics/transcripts/transcripts`,
`academics/rop` (Records of Progress), `academics/ee` (Extended Essay), `academics/testimonial`.
Routes verified at `references/pages/Academics.html:77`.

### 1.7 Campus status — W4-only, no Lectio ancestor

**Verified markup** (`references/pages/UWCRCN W4.html:38-48`):

```html
<div class="status-dropdown">
  <div class="status oncampus"><div class="status-value">on campus</div><div class="location"></div></div>
</div>
<div class="selection-box"><p>I am currently:</p>
  <span id="location">
    <input value="oncampus" id="location_0" checked type="radio" name="location"><label for="location_0">On campus</label>
    … values: "On a walk", "At Raudbua", "On Jarstadheia", "On the island", "In Flekke", "In Dale",
      "In A building (after 10:30pm)", "In K building (after 10:30pm)",
      "In Library/Study room (after 10:30pm)", "other" …
  </span>
  <input maxlength="20" type="text" value="" name="other" id="other">
  <div class="buttons"><input id="submit-campus-status" name="yt0" type="button" value="Set status"></div>
</div>
```

```swift
struct CampusLocationOption: Identifiable, Codable, Hashable {
    let id: String       // input value: "oncampus", "On a walk", …, "other"
    let label: String    // <label for=…> text
    var isOther: Bool { id == "other" }
    var isOnCampus: Bool { id == "oncampus" }
}
struct CampusStatus: Codable, Equatable {
    let isOnCampus: Bool          // .status has class "oncampus"
    let location: String?         // .location text; nil when on campus
    let options: [CampusLocationOption]
    let updatedAt: Date
    var displayLabel: String { isOnCampus ? "On campus" : (location ?? "Off campus") }
}
```

Write: `POST index.php?r=site/setstatus` with `status=on|off` and, when off, `location=<label or the
free-text "other" value, max 20 chars>` — jQuery `$.post`, so
`X-Requested-With: XMLHttpRequest` (README §5.3; `core/w4/W4Chrome.kt:11-29`).
The 11 options ship as a hardcoded fallback (`feature/campus/CampusStatusParser.kt:18-30` matches the
capture exactly) but the live radio list always wins when present.

Because the status widget is in the chrome of **every** authenticated page, the repository exposes
`apply(html:)` and every page fetch feeds it (`feature/schedule/ScheduleRepository.kt:72`,
`feature/campus/CampusStatusRepository.kt:22-24`). One `@Published` value, zero dedicated fetches in the
happy path.

### 1.8 Notifications bell — W4-only

```swift
enum W4NotificationSection: String, Codable { case task, email }
enum W4NotificationSeverity: String, Codable { case normal, new, overdue }

struct W4Notification: Identifiable, Codable, Equatable {
    let id: String              // data-notification-id
    let title: String
    let subtitle: String?
    let href: String?
    let type: String?           // data-notification-type — the readGroup / clearGroup key
    let section: W4NotificationSection
    let severity: W4NotificationSeverity
}
struct W4NotificationGroup: Identifiable, Codable, Equatable {
    var id: String { type ?? title }
    let type: String?; let title: String; let severity: W4NotificationSeverity
    let items: [W4Notification]
}
struct W4NotificationSnapshot: Codable, Equatable {
    let count: Int; let severity: W4NotificationSeverity
    let taskGroups: [W4NotificationGroup]; let emailGroups: [W4NotificationGroup]
    let fetchedAt: Date
    var items: [W4Notification] { taskGroups.flatMap(\.items) + emailGroups.flatMap(\.items) }
}
```

Endpoint map is **verified** — the Home page inlines it at `references/pages/UWCRCN W4.html:24`:
`notification_urls = {'read':'/index.php?r=notifications/read','readGroup':…/readgroup,
'readAll':…/readall, …}` (the capture is `\x2F`-escaped). Full set in `core/w4/W4Urls.kt:141-148`,
helpers in `core/w4/W4Chrome.kt:31-75`. Response to every one of them is an HTML fragment to swap into
`div.notifications` — so **every mutation re-parses the fragment and replaces the snapshot**
(`feature/notifications/W4NotificationRepository.kt:88-98`). Poll interval while the app is foregrounded
and the sheet is closed: **60 s** (`W4NotificationRepository.kt:172`, matching W4's own JS).

The fragment markup (`div.notifications`, `h3.tasks` / `h3.emails`, `dl > dt/dd > li`,
`a.read[data-notification-id]`, `.new` / `.overdue` classes — `feature/notifications/W4NotificationParser.kt:47-171`)
is **UNKNOWN — needs live capture**: the saved Home page has `<div class="notifications"> </div>`, empty.

### 1.9 Boarding: trips and travel forms — W4-only

```swift
enum TripStatus: String, Codable { case planning, pendingConfirmation, approved, cancelled, unknown }
struct Trip: Identifiable, Codable, Equatable {
    let id: String              // href id when present, else name+outgoing
    let name: String
    let outgoing: String        // raw "20-Sep-2026 08:00"
    let outgoingDate: Date?
    let returning: String
    let returningDate: Date?
    let destination: String
    let type: String            // "Optional", …
    let participants: String
    let status: TripStatus
    let statusRaw: String
}

enum TravelJourney: String, Codable, CaseIterable {
    case toSchoolAutumn, homeWinter, backAfterWinter, homeSummer
}
struct TravelForm: Identifiable, Codable, Equatable {
    let id: String; let journey: TravelJourney; let title: String
    let status: String; let href: String?
}
struct TravelContact: Identifiable, Codable, Equatable { let id: String; let name: String; let relation: String?; let phone: String?; let email: String? }
```

Column set (Trip name, outgoing/return, destination, type, participants, status) and the status ladder
(Planning → Pending confirmation → Approved / Cancelled, where approval auto-registers pre-arranged
absences) are from a live GET recorded in README §6; the markup is **UNKNOWN — needs live capture**.
Android reads `#content_inner table tbody tr` positionally (`feature/trips/W4TripsParser.kt:16-32`) —
acceptable as a fallback, but the iOS parser must be header-driven like the mailer/absence parsers, since
positional parsing silently mis-assigns columns.

v1 is **read-only** for both. "Plan new trip" and the four travel forms open the W4 page in an in-app
browser with the session cookie until the form fields are captured. Travel contacts:
**UNKNOWN — needs live capture**.

### 1.10 Documents CMS — W4-only

**Verified markup** (`references/pages/Documents.html:78-83`):

```html
<div id="content_inner"> <h2> Documents </h2>
  <ul class="folder-list">
    <li><a class="folder" href="…?r=documents/index&folder_id=27">Internal Information</a></li>
    <li><a class="folder" href="…?r=documents/index&folder_id=34">Outdoor Department</a></li>
  </ul></div>
```

```swift
enum DocumentNodeKind: String, Codable { case folder, page }
struct DocumentNode: Identifiable, Codable, Equatable {
    let id: String            // folder_id | page_id
    let title: String
    let kind: DocumentNodeKind
    let href: String
}
struct DocumentListing: Codable, Equatable {
    let title: String                 // #content_inner h1/h2
    let breadcrumb: [DocumentNode]
    let items: [DocumentNode]
    let bodyHTML: String?             // set when the node is a leaf page
    let isPage: Bool
    let fetchedAt: Date
}
```

`a.folder` and `folder_id=` are verified. `a.page` / `page_id=`
(`feature/documents/W4DocumentsParser.kt:34-38`) is **UNKNOWN — needs live capture** of a folder with
pages in it; the Home `#links` block does prove `documents/index&page_id=870|871|1004` and
`extraacademics/documents/index&page_id=79` are real URLs (`references/pages/UWCRCN W4.html:261`).
Two CMS roots: `documents/index` (School) and `extraacademics/documents` (EA) — same models, two entry
points. Page bodies are TinyMCE HTML: render through the same sanitiser as mail bodies.

### 1.11 Extra Academics — W4-only

Routes verified at `references/pages/Extra Academics.html:76`.

```swift
enum EAType: String, Codable { case eac, cr, pbl, leirskule, other }   // &type=eac|cr|pbl|leirsk
enum EAActivityPhase: String, Codable { case running, past, future }

struct EAActivity: Identifiable, Codable, Equatable {
    let id: String; let name: String; let type: EAType
    let weekday: String?; let timeLabel: String?; let leader: String?
    let phase: EAActivityPhase; let href: String?
}
struct EADiaryEntry: Identifiable, Codable, Equatable {
    let id: String; let activityId: String?; let date: Date?
    let text: String; let outcomes: [String]      // EAGroupStudentModel[outcomes][]
}
struct EAPortfolioItem: Identifiable, Codable, Equatable { let id: String; let title: String; let bodyHTML: String? }
struct CASInterview: Identifiable, Codable, Equatable {
    let id: String; let index: Int          // 3 interviews
    let date: Date?; let status: String; let exportHref: String?   // "export PDF"
}
struct SafetyNetReport: Identifiable, Codable, Equatable {
    var id: String { periodLabel }
    let periodLabel: String     // "Period"
    let status: String          // "Status"
    let averageWellness: Double?  // "Average wellness"
    let sleep: Double?            // "Sleep"
    let exercise: Double?         // "Exercise"
}
```

Column names for SafetyNet come from README §5.2/§6 (Period, Status, Average wellness, Sleep, Exercise;
Graph/Table toggle; weekly report create for past or current week). Every markup detail across this whole
section is **UNKNOWN — needs live capture**. v1 ships: EA timetable (folded into §1.2), My activities with
the running/past/future filter and name/weekday sort, My EA absences (§1.5), and read-only SafetyNet +
CAS interviews. Diary write (`EAGroupStudentModel[outcomes][]`) is v1.5.

### 1.12 People, birthdays, rooms, on duty

```swift
enum PersonKind: String, Codable { case student, staff }
struct Person: Identifiable, Codable, Equatable, Hashable {
    let uwcId: String; var id: String { uwcId }
    let name: String
    let preferredName: String?
    let kind: PersonKind
    let year: String?; let house: String?; let country: String?; let pronouns: String?
    let email: String?          // defaults to "\(uwcId)@uwcrcn.no"
    let photoURL: URL?          // /files/user_photos/{uwcId}_thumb.jpg
    let isActive: Bool
    let subtitle: String?       // "Year 1 · Haugland · Denmark"
}
struct Birthday: Identifiable, Codable, Equatable {
    var id: String { uwcId }
    let uwcId: String; let name: String?; let photoURL: URL?
    let when: BirthdayWhen      // today | tomorrow
}
struct Room: Identifiable, Codable, Equatable { let id: String; let name: String }
struct OnDutyEntry: Identifiable, Codable, Equatable { let id: String; let name: String; let role: String?; let uwcId: String? }
```

**Verified**: birthdays on Home are `#birthdays > #birthdays-today > ul > li > a[href*=uwc_id=] > img.photo`
with `alt="Photo of nc16jmac"` and a `.calendar` link to `r=people/birthdays`
(`references/pages/UWCRCN W4.html:193-215`). Photo path
`https://w4.uwcrcn.no/files/user_photos/{uwcId}_thumb.jpg`
(`feature/directory/W4PeopleParser.kt:91-92`), and `/images/user.png` is W4's missing-photo placeholder
which must be filtered to `nil` (`W4PeopleParser.kt:173-183`). Note the capture proves staff birthdays link
to `people/staff/staff&uwc_id=` while student birthdays link to `people/students/student&uwc_id=` — the
kind comes from the href, as `W4PeopleParser.kt:105-109` already does.

Directory sources (all verified, `references/pages/School info @ UWCRCN.html:77`):
`people/students/all`, `firstyear`, `secondyear`, `byname`, `bypreferred`, `bycountry`, `byhouse`,
`people/staff/current`, `people/staff/onleave`, `people/students/staff` (+`&type=teachers|leaders`),
`people/visitors`, `people/onduty`, `people/onduty/schedule`, `academics/timetable/room`.

**Everything in `ios/BetterW4/DirectoryModels.swift` is over-modelled for W4 and shrinks hard:**

| Dies | Why |
|---|---|
| `DirectoryEntityKind.classSynthetic/.classW4/.hold/.resource/.group/.other` (`DirectoryModels.swift:8-17`) | Lectio dropdown taxonomy. W4 has people and rooms. |
| `DirectoryEntityID { gymId, kind, rawID }` + `.key` (`DirectoryModels.swift:79-87`) | UWC id is globally unique on one host |
| `DirectoryMetadata` (10 optional fields, `DirectoryModels.swift:89-100`) | Lectio class codes / seat numbers / XPRS subject codes |
| `rawPrefixedID` / `rawPrefix` / `numericID` / `rawTypeMarker` / `rawLabel` | Lectio `S123` / `T_MH` / `HE456` / `RO24` prefixes |
| `DirectoryGroupSubtype` (`DirectoryModels.swift:69-77`) | Lectio group taxonomy |
| `SchedulableTarget` / `SchedulableTargetKind` (`DirectoryModels.swift:208-242`) | W4 exposes no per-person timetable to students; Android's `loadPersonWeek` already returns empty (`RoomScheduleRepository.kt:17-26`) |
| `ParsedHoldMember`, `DirectoryMembershipRecord` (`DirectoryStore.swift:48-61`) | no hold-members page seen; **UNKNOWN** whether `academics/classes/myclasses` lists classmates |
| Every Danish `displayName` (`Elev`, `Lærer`, `Lokale`, …) | English only |

Pinning survives, scoped to the signed-in UWC id (`PinStore` in `feature/directory/PinStore.kt:7-42` is a
clean pure model; port it directly, persisted under `w4.directory.pinned.<uwcId>` as today —
`DirectoryViewModel.swift:488`).

Avatar rate limiting survives: max 4 concurrent, ≥80 ms apart
(`feature/directory/RateLimitedAvatarLoader.kt:14-16`, mirrored by
`ios/BetterW4/RateLimitedAvatarImage.swift`) — README §5.5 exists because this is a tiny Apache box.
`DirectoryStore.batchAvatarLookup` still builds `https://www.lectio.dk/lectio/\(gymId)/GetImage.aspx?pictureid=…`
(`DirectoryStore.swift:675`) — delete that line and the whole `pictureID` column with it; on W4 the URL is
derived from the UWC id.

### 1.13 Letter of Attendance — `studiekort`'s replacement

```swift
struct AttendanceLetter {
    let data: Data
    let contentType: String
    let suggestedFileName: String   // "letter-of-attendance.pdf" | ".html"
    let fetchedAt: Date
    var isPDF: Bool { data.starts(with: Array("%PDF-".utf8)) }
}
```

Route `people/students/letter/attendance` verified (`references/pages/School info @ UWCRCN.html:77`).

**Contradiction to resolve — UNKNOWN, needs live capture:** Android's
`StudiekortRepository.openLetterOfAttendance` hard-fails unless the bytes start with `%PDF-`
(`feature/studiekort/StudiekortRepository.kt:93-98`), while README §6 describes the letter as *"large
generated document (HTML ~600KB+)"*. One of the two is wrong. The iOS implementation must sniff
`Content-Type` / the magic bytes and handle both: PDF → `QLPreviewController` + share sheet; HTML →
`WKWebView` with a "Save as PDF" print action. Never assume.

The Lectio student card (`ios/BetterW4/StudentCardView.swift`, 250 lines: barcode, QR, photo, birthday
from `w4.studentCard.birthday.<studentId>_<gymId>` at `StudentCardView.swift:28`) is replaced by a plain
profile card built from `site/profile` (UWC id, year, house, country, pronouns, email, photo) — the fields
Android already parses in `W4PeopleParser.parseProfile` (`feature/directory/W4PeopleParser.kt:35-89`).
`StudentCard.qrUrl` stays `nil`; W4 has no scannable id.

### 1.14 Announcements, RSS, personal feeds

**Verified** (`references/pages/UWCRCN W4.html:220-233`): `#announcements > #announcements-content > h3`
("College Announcements"), `.rss > a[href*="r=site/rss"]`, body `<p>No announcements...</p>` when empty.
The document `<head>` also carries
`<link rel="alternate" type="application/rss+xml" title="UWCRCN W4 Announcements" href="…r=site/rss">`.

```swift
struct Announcement: Identifiable, Codable, Equatable {
    let id: String; let title: String; let publishedAt: Date?; let bodyHTML: String; let link: URL?
}
enum PersonalFeedKind: String, Codable, CaseIterable {
    case acTimetableRSS, eaTimetableRSS, combinedRSS, assessmentsRSS
    case acTimetableICS, eaTimetableICS, combinedICS, assessmentsICS
}
struct PersonalFeed: Identifiable, Codable {
    var id: String { kind.rawValue }
    let kind: PersonalFeedKind
    let url: URL          // contains token=<secret>
}
```

Route prefixes from README §4.8: `academics/feeds/acttrss`, `eattrss`, `combottrss`, `sassttrss` and the
`…tical` variants. **The `token=` value is password-equivalent**: Keychain only, never `UserDefaults`,
never in a log line, never in a fixture. Product use: "Add to Apple Calendar" hands the ICS URL to the
system; the app does not parse personal feeds in v1 (it scrapes HTML for rooms, rotation days and the
now-line, which the feeds do not carry).

### 1.15 Resource bookings

```swift
struct BookableResource: Identifiable, Codable, Equatable { let id: String; let name: String; let category: String? }
struct ResourceBooking: Identifiable, Codable, Equatable {
    let id: String                 // reservation_id
    let resourceId: String; let resourceName: String
    let date: Date; let startTime: String; let endTime: String
    let description: String; let owner: String?
}
struct ResourceBookingDraft {      // field names from README §5.2
    var day: Int, month: Int, year: Int
    var reservationId: String?
    var timeStart: String, timeEnd: String
    var description: String
    var resourceId: String
}
```

Route `academics/resources/resources` verified (`references/pages/Academics.html:77`). Month calendar +
"Book resource"; rooms/spaces include classrooms, Auditorium, Høegh Kitchen (README §6). Markup
**UNKNOWN — needs live capture**. v1: read-only month list; booking is v1.5.

### 1.16 Home aggregate

One `site/index` fetch fills six models, so `HomeRepository` returns a composite rather than making six
screens fetch the same page:

```swift
struct HomeSnapshot: Equatable {
    let week: ScheduleWeek                 // #timetable  (UWCRCN W4.html:86)
    let academicMeter: AttendanceMeter     // #academic-absences (:240)
    let eaMeter: AttendanceMeter           // #ea-absences (:245)
    let birthdays: [Birthday]              // #birthdays (:193)
    let announcements: [Announcement]      // #announcements (:220)
    let links: [HomeLink]                  // #links (:261)
    let campus: CampusStatus               // .status-dropdown (:38)
    let fetchedAt: Date
}
struct HomeLink: Identifiable, Codable, Equatable {
    var id: String { url.absoluteString }
    let title: String; let url: URL
    var isInternalRoute: Bool { url.host == "w4.uwcrcn.no" }
}
```

The captured `#links` list is config, not code — ten entries including *UWCRCN Extra Academic Website*,
*RCN College Policies Drive*, *Trip Form* (`r=academics/trips`), *Høegh Kitchen Booking Form*,
*ManageBac*, *Bakehus* (`documents/index&page_id=870`), *Haugland times*
(`extraacademics/documents/index&page_id=79`), *Learning support* (`page_id=871`), *6 Stiar*,
*Lavvo Booking and Information* (`page_id=1004`). Render them dynamically; internal links deep-link into
the app, external links open in `SFSafariViewController`. **Never hardcode this list.** ManageBac is a
third SIS and is a link only (README §7).

### 1.17 Kill list — Lectio concepts with no W4 successor

Delete the type, its parser, its store column, its view, and its strings.

| Concept | Where it lives today |
|---|---|
| `Assignment` / `AssignmentDetail` / `AssignmentSubmission` / `AssignmentStatus` | `AssignmentModels.swift:12-88`, `AssignmentParser.swift`, `AssignmentsView.swift` (711 lines), `AssignmentsViewModel.swift`, `W4HTTPClient+Assignments.swift` |
| Message threads, replies, reactions, edits, BBCode, signature | `MessageThreadView.swift` (1 099), `MessageReactionProtocol.swift`, `MessageEditAudit.swift`, `MessageSignature.swift`, `BBCodeRichEditor.swift` |
| Absence percentages, causes, "Godskrevet", cause editing | `AbsenceModels.swift:13-16,38-61`, `AbsenceEditFormParser.swift`, `W4HTTPClient+Absence.swift` |
| Danish 7-step grade scale, standpunkt/årskarakter columns, XPRS | `GradeModels.swift:31-41,56-61`, `GradeAverage.kt:50-61` |
| Holds, hold members, synthetic classes, `HE`/`S`/`T`/`RO` prefixes, `gymId` | `DirectoryModels.swift`, `DirectoryStore.swift`, `StudentStore.swift`, `StudentModels.swift:254-272` |
| Student card / barcode / studiekort | `StudentCardView.swift` |
| Studieplaner, module statistics, terms | `feature/plans/`, `feature/teams/`, `feature/terms/` |
| School picker, `School`, `LastSchoolStore`, `loadSchoolsFromSupabase` | `AuthenticationViewModel.swift:94-129` |
| Live Activities + widget | `BetterW4App.swift:24-32`, `ScheduleView.swift:603-644`, `SettingsView.swift:94-113,332-340`, `SettingsStore.swift:83,154-157` |
| Supabase (auth, profiles, subject mappings, homework sync, schedule sync, profile pictures, schools) | `AuthenticationService.swift:10,84,114,119`, `ContentView.swift:184,502-523`, `HomeworkViewModel.swift:29`, `ScheduleViewModel.swift:37,406`, `MessagesViewModel.swift:367`, `MessageThreadViewModel.swift:591`, `SettingsStore.swift:315-353`, `StudentProfileView.swift:405`, `StudentSearchView.swift:99`, `SubjectColorSettingsView.swift:79`, `AuthenticationViewModel.swift:12,121,182,242-251` |
| Analytics / feedback / referrals | `ReviewPromptCoordinator.swift:71-72,90-93,131-132,153-154` (`Analytics`, `FeedbackLogBuffer`, `FeedbackCoordinator`, `ReferralCoordinator`) |
| `StudentProfile` (Supabase profile: instagram, custom pfp, extension install timestamps) | `ios/BetterW4/StudentProfile.swift` (whole file), `feature/directory/StudentProfile.kt` |
| Danish `AppLanguage` / `AppLocale` | `feature/settings/SettingsStore.kt:21,117-125`, `core/i18n/AppLocale.kt:41-45` |

These are not stale comments — they are live call sites that will not compile once the removed modules are
gone. Treat this table as the deletion work list.

---

## 2. Persistence

Three tiers, chosen per surface by *how much it costs to lose*:

| Tier | Mechanism | Holds |
|---|---|---|
| Secrets | Keychain, `kSecAttrAccessibleAfterFirstUnlock` | session cookie, device id, feed tokens, current student |
| Structured, queried, survives reinstall-free upgrades | SwiftData, one store file per domain | timetable, assessments, directory |
| Bulk / re-fetchable | Files under `Caches/`, `FileProtectionType.completeUntilFirstUserAuthentication` | mail JSON, raw W4 page HTML, attachments, avatars |
| Preferences | `UserDefaults.standard` | settings, pins, review gate, notification diff set |

### 2.1 SwiftData stores — final set

Each store keeps its **own store file** and the three-step recovery ladder already in the code
(open → delete `.store`/`-shm`/`-wal` and reopen → in-memory), verbatim from
`ScheduleStore.swift:91-128`. That ladder exists because two stores sharing `default.store` with different
schemas produced `no such table: ZLESSONRECORD` (`ScheduleStore.swift:96-99`). Do not merge the files.

**`Timetable.store` — `LessonRecord`** (from `ScheduleStore.swift:11-79`)

| Column | Change |
|---|---|
| `uniqueKey` `"\(uwcId)|\(lessonKey)"` | keep |
| `studentId` → `uwcId` | rename |
| `lessonKey`, `eventId`, `weekKey` (`"2026-W33"`) | keep (`ScheduleIdentity.weekKey`, `ScheduleIdentity.swift:12-17`) |
| `lessonDate`, `title`, `subtitle`→`subject`, `room`, `status`, `notes`, `isAllDay` | keep |
| `startTime: String` / `endTime: String` | → `startAt: Date?` / `endAt: Date?` |
| `teacherId` | → `teacherUwcId` |
| `homework: String?` | **drop** — assessments are their own entity now |
| `contentJSON: Data?` (`LessonContent`) | **drop** — W4 has no per-lesson content page; **UNKNOWN**, revisit if a lesson detail page turns up |
| new: `source` (`ac`/`ea`/`gcal`), `rotationDay` | add |
| `sourceUpdatedAt`, `updatedAt` | keep — they drive staleness |

**`Assessments.store` — `AssessmentRecord`** (replaces `HomeworkRecord`, `HomeworkStore.swift:14-69`)

`uniqueKey "\(uwcId)|\(assessmentId)"`, `uwcId`, `rawId`, `kind`, `title`, `subject`, `teacher`, `unit`,
`dueDate: Date?`, `daysLeft: Int?`, `serverStatus: String`, `isOverdue: Bool`,
`localStatus: String?`, `localStatusUpdatedAt: Date`, `sourceUpdatedAt`, `updatedAt`.
Dropped from `HomeworkRecord`: `displayDate`, `hold`, `room`, `itemsJSON` (the `[HomeworkItem]` blob).

**`Directory.store` — `PersonRecord`, `RoomRecord`**

`PersonRecord`: `uwcId` (`@Attribute(.unique)`), `name`, `preferredName`, `kind`, `year`, `house`,
`country`, `pronouns`, `email`, `isActive`, `subtitle`, `lastFetched`.
`RoomRecord`: `id`, `name`, `lastFetched`.
Deleted: `DirectoryEntityRecord`'s `gymId`, `kindRaw` (9 cases → 2), `rawPrefixedID`, `rawPrefix`,
`numericID`, `searchTokensData`, `rawTypeMarker`, `metadataData`, `pictureID`
(`DirectoryStore.swift:10-46`), plus the entire `DirectoryMembershipRecord` entity
(`DirectoryStore.swift:48-61`) and the entire **`Students.store` / `StudentRecord`**
(`StudentStore.swift:9-49`) — it is a duplicate people table.

Search tokens move from a stored `Data` blob to a computed normalized string, because with ~200 students
the whole table fits in memory; the batch-lookup cache and `peopleByNormalizedNameByGym` index
(`DirectoryStore.swift:952-973`) collapse to one dictionary keyed by normalized name.

### 2.2 Keychain

Service string: **`dk.jonathanb.w4`** (the shipping bundle id). Today it is `dk.elliottf.betterw4`
(`KeychainManager.swift:17`) — this is a new app with a new bundle id and no users to migrate, so change it
and delete the `isloggedin3` back-fill migration (`KeychainManager.swift:79-94`).

| Account key | Value |
|---|---|
| `w4.session.<uwcId>` | `W4Session { phpsessid, updatedAt }` |
| `w4.deviceId` | stable per-install UUID — **created once, never regenerated** (reviewer-notes.md §5; regenerating forces 2FA every launch) |
| `w4.student.current` | `Student` (as `KeychainManager.swift:149`) |
| `w4.feedTokens.<uwcId>` | `[PersonalFeedKind: String]` |

`wipeAll()` (`KeychainManager.swift:242-251`) deletes every generic-password item for the service — keep it
and call it on logout and on `.sessionExpired`.

### 2.3 UserDefaults

**`UserDefaults.standard` only.** The app group `group.dk.elliottf.betterw4`
(`SettingsStore.swift:66`) is deleted — with no widget, no Live Activity and no extension there is nothing
to share with, and an unentitled suite silently returns `nil`, which would make settings not persist at all.

| Key | Value |
|---|---|
| `w4.settings.appearance` | `system` / `light` / `dark` |
| `w4.settings.calendarStyle` | `professional` / `standard` |
| `w4.settings.useSubjectColors` | `Bool`, default `true` |
| `w4.settings.subjectMappings` | JSON `[scopeKey: [canonicalKey: ResolvedLessonMapping]]`, scope `"w4::<uwcId>"` |
| `w4.settings.notify.mail` / `.assessments` / `.timetable` / `.lessonReminder` | `Bool` |
| `w4.settings.lessonReminderMinutes` | `Int`, default 10 |
| `w4.onboarding.completed` | `Bool` |
| `w4.directory.pinned.<uwcId>` | `[String]` of UWC ids |
| `w4.notify.seen.<uwcId>` | `[String]` diff keys (§5) |
| `w4.review.launchTimestamps` / `.promptCount` / `.lastPromptAt` / `.neverAsk` / `.completedStoreFlow` | review gate |

Deleted keys: `liveActivityVariant`, `messageSignatureEnabled` (`SettingsStore.swift:73,77`),
`w4.pinnedFriends.*`, `w4.fetchedHoldIds.*` (`StudentStore.swift:356-357`),
`w4.directory.holdmembers.*` (`DirectoryStore.swift:886`),
`w4.studentCard.birthday.*` (`StudentCardView.swift:28`), `w4.schedule.*` + `w4.schedule.migrated.v2.*`
legacy migration (`ScheduleStore.swift:88-89,451-507`) — there is no legacy BetterW4 install to migrate
from, so delete the migration code rather than porting it.

### 2.4 File caches

1. **`Caches/MailCache/<b64(uwcId)>/`** — survives from `MessageCacheManager.swift:43-135`, renamed.
   `list_<b64(folderId)>.json` and `message_<b64(id)>.json`, written with
   `.completeFileProtectionUntilFirstUserAuthentication` (`MessageCacheManager.swift:59-61`). Keep the
   base64-with-`/`→`_`, `+`→`-`, `=`-stripped filename encoding (`MessageCacheManager.swift:63-68`) —
   subjects and ids are user data and must not become path components.
2. **`Caches/W4Pages/<b64(uwcId)>/<sha256(cacheKey)>.html` + `.meta.json`** — new; the iOS answer to
   Android's `SimpleCache` (`core/cache/SimpleCache.kt:13-46`). `.meta.json` holds
   `{ fetchedAt, finalURL, contentType }`, which is what makes a real TTL possible.
   **Android's `SimpleCache` has no expiry at all** — `HomeworkRepository.load` and `GradeRepository.load`
   return cached HTML forever unless the caller passes `forceRefresh`
   (`feature/homework/HomeworkRepository.kt:45-54`, `feature/grades/GradeRepository.kt:25-27`). Do not port
   that bug.
3. **`Caches/Attachments/`** — `sha256(url)__<sanitised name>` with LRU eviction at **50 MB / 100 files**
   (`feature/attachments/AttachmentCache.kt:30-76`).
4. **`tmp/BetterW4MessageAttachments/<uuid>/`** — outgoing attachment staging, purged after 24 h
   (`OutgoingMessageAttachment.swift:105-120`).
5. Avatars: `W4ImageLoader` disk cache, cleared by `clearAllCaches()`.

### 2.5 Cache and TTL policy per surface

`fetchedAt` lives with the data (SwiftData column or `.meta.json`), never in a parallel UserDefaults key.

| Surface | Serve from cache | Background refresh | Hard TTL | Notes |
|---|---|---|---|---|
| Timetable, current week | always, instantly | on every appear | 30 min ⇒ "Updated N min ago" turns amber | 5-min per-target suppression window (`ScheduleViewModel.swift:61-65`) |
| Timetable, other weeks | yes | once per session per week key | none | `fetchedWeekKeys` gate (`ScheduleViewModel.swift:131-141`) |
| School Google Calendar ICS | yes | on timetable refresh | **6 h** | `SchoolCalendarRepository.CACHE_TTL_MS` (`feature/schedule/SchoolCalendarRepository.kt:78`) |
| Assessments | yes | on appear + after any write | 15 min | writes invalidate immediately |
| Mail list (inbox/archive) | yes | on appear, pull-to-refresh | 5 min | prefetch after login is `.opportunistic` |
| Mail message body | yes, indefinitely | never (immutable) | — | evicted only by Clear cache / sign-out |
| Attendance (AC + EA + Home meters) | yes | on appear | 30 min | three cache keys, as Android (`feature/absence/AbsenceRepository.kt:24-26`) |
| Grades / SAT / transcripts | yes | on appear | 6 h | changes rarely |
| Documents folder / page | yes | on appear | 24 h | CMS content |
| Trips / travel forms | yes | on appear | 1 h | |
| EA activities / diary / portfolio / CAS / SafetyNet | yes | on appear | 6 h | |
| Directory (people) | yes | full resync when `lastFetched` > 7 d, or manual | 7 d | ~200 people; one sweep, serialised |
| Birthdays | from the Home snapshot | with Home | 12 h | |
| Announcements | from Home + `site/rss` | with Home | 1 h | |
| Campus status | in-memory `@Published` | piggybacks on every chrome-bearing fetch | — | never its own GET in the happy path |
| Notifications | in-memory only | 60 s foreground poll | — | only the diff-key set is persisted |
| Letter of Attendance | never cached on disk beyond the share sheet | on demand | — | personal document |
| Personal feeds (tokens) | Keychain | on demand | — | never logged, never in fixtures |

---

## 3. Offline, staleness and generation guards — preserve these exactly

These are the rules the current iOS code gets right. They are the reason the app feels solid, and they must
survive the port unchanged in spirit.

1. **Generation guard on every load.** Take a `UUID` at entry, store it, and check
   `loadGeneration == generation` before *every* published mutation — including inside `defer`.
   Live examples: `HomeworkViewModel.swift:41-42,54,67,83,100,105,111,119`,
   `AbsenceViewModel.swift:35-36,47,76,80,85`, `GradesViewModel.swift:27-28,37,63,66,71`,
   `AssignmentsViewModel.swift:275-276,284,296,329,332,337`. Without it, a slow fetch for account A
   overwrites the UI of account B.
2. **Cache first, network always.** Read the store, publish it, *then* fetch — never gate the fetch on
   staleness (`ScheduleViewModel.swift:81-109`, comment at line 107: "ALWAYS fetch fresh data").
   Staleness only drives the "updated N ago" label and the amber colour.
3. **Spinner only when empty.** `if threads.isEmpty { isLoading = true }`
   (`MessagesViewModel.swift:84-87`). A refresh over populated content shows a subtle indicator, not a
   blocking spinner.
4. **Errors only when there is nothing to show.**
   `if threads.isEmpty { errorMessage = … }` (`MessagesViewModel.swift:129-137`). Offline with a warm cache
   is a *working* app, not an error screen.
5. **Account switch resets in-memory state.** `if activeStudentID != student.uwcId { … clear … }`
   (`HomeworkViewModel.swift:43-49`, `AbsenceViewModel.swift:37-41`). With one school this matters most
   for demo ⇄ real transitions.
6. **A `nil` Keychain read is not a logout.** Surface a banner and let the next refresh recover — the
   verbatim reasoning is in `ScheduleViewModel.swift:171-184`. Only `.sessionExpired` logs out, exactly
   once, via the single `.w4SessionExpired` notification (`StudentModels.swift:198-249`).
   `.forbidden` (403 without `Login Required`) must never log out — a student opening a staff-only page
   would otherwise be ejected (reviewer-notes.md §3).
7. **Parse off the main actor, and honour cancellation.**
   `Task.detached(priority: .userInitiated)` + `try Task.checkCancellation()` around store writes
   (`HomeworkViewModel.swift:94-99`, `ScheduleStore.swift:303,343`). Swallow `CancellationError` and
   `URLError.cancelled` instead of showing them (`HomeworkViewModel.swift:111-115`).
8. **Snapshot semantics on replace.** A successfully parsed list is authoritative: rows that vanished are
   deleted, not kept (`HomeworkStore.swift:163-168` — "Keeping rows that disappeared causes stale homework
   to reappear"). **W4-specific amendment:** `ScheduleStore.markMissingAsCancelled`
   (`ScheduleStore.swift:270-281`) must become `markMissingAsRemoved` (delete). On Lectio a vanished lesson
   meant "aflyst"; on W4 an empty day is routine — the captured week 33 is a holiday week with zero
   `.period` elements. Synthesising a fake "cancelled" lesson for every holiday would be worse than useless.
   Guard the sweep further: only delete when the fetch actually produced a parsable `#timetable` grid
   (`div.column` count ≥ 8), never when the parse returned nothing.
9. **Store corruption is recoverable, not fatal.** Three-step ladder in every store init
   (`ScheduleStore.swift:100-121`, `HomeworkStore.swift:84-105`, `DirectoryStore.swift:82-116`,
   `StudentStore.swift:64-87`). Keep, minus `StudentStore`.
10. **Sign-out and session-expiry wipe everything derived.** Android centralises this in
    `OfflineDataCleaner.clearAll()` (`core/cache/OfflineDataCleaner.kt:27-51`) precisely so *"the next
    account on the same device cannot read prior user data"*. iOS equivalent: `SettingsStore.clearAllCaches`
    (`SettingsStore.swift:359-375`) plus `KeychainManager.wipeAll()`. Preferences (theme, subject colours,
    notification toggles) deliberately survive; data does not.
11. **`TimeProvider.now` everywhere.** Never `Date()` in domain or store code
    (`ios/BetterW4/TimeProvider.swift:19-41`); the `SIMULATED_DATE` env var is how the now-line, the
    live-lesson banner and week rollover get tested. Several sites still use `Date()` directly
    (`HomeworkStore.swift:117,238-239`, `DirectorySyncService.swift:28,69`) — fix them during the port.
12. **Serial, prioritised HTTP.** `.important` for what the user is looking at, `.opportunistic` for
    prefetch and avatars — the parallel AC/EA timetable fetch is the model
    (`feature/schedule/ScheduleRepository.kt:52-65`). Never fan out the directory sweep.

---

## 4. Demo mode — what an App Review account sees

Entry: a **"Try the demo"** button on the login screen. `Student.demo` has `uwcId = "nc00demo"`,
`displayName = "Demo Student"`, `isDemo = true`.

Two hard invariants, both already respected today and both easy to break:

- **Zero network.** No W4 fetch, no avatar fetch, no ICS fetch, no notification poll.
  (`StudentStore.swift:420`, `DirectoryStore.swift:687`, `DirectorySyncService.swift:24-29`.)
  `DemoData.kt` currently ships `https://www.gravatar.com/avatar/…` URLs
  (`feature/demo/DemoData.kt:295,299,305,313`) — **replace with locally drawn initial avatars**, otherwise
  the demo makes network calls on a reviewer's device.
- **Zero persistence.** Demo never writes SwiftData; done-state lives in an in-memory dictionary
  (`HomeworkViewModel.swift:59-63`).

All demo content must be **English and UWC-shaped**. Today it is a Danish gymnasium
(`DemoDataProvider.swift:33-59` "1x MA / Matematik A", `messageThreads` in Danish at lines 143-162,
`homeworkEntries` "Læs s. 120-128" at 232-243, `absenceReport` "Sygdom" at 517;
`DemoData.kt:105-122,145-163` likewise). Rewrite:

| Screen | What the reviewer sees |
|---|---|
| Home | Current week grid with rotation days Day 1–Day 5 + Weekend; AC blocks and one EA block; meters "You have 2 absences and 1 lateness" (AC) and "0 absences and 0 latenesses" (EA); two birthdays; one announcement; the Links list with only public URLs |
| Timetable | Two weeks × Mon–Fri, 3–5 blocks/day: Mathematics HL, English A HL, Biology SL, History HL, TOK, plus one EA activity; rooms `A1`, `K2`, `Lab 1`; teachers by initials; one `.cancelled` and one `.changed` block; now-line on today |
| Assessments | 6 items spanning −10…+12 days: 2 done, 1 overdue, 1 student-created. Confirm done / Revert to pending flip instantly and stay flipped for the session |
| Mail | Inbox: 6 messages, 2 unread, 1 with an attachment. Sent: 2. Opening one shows an HTML body. Compose opens, validates, and on send shows "Demo mode — nothing was sent" |
| Attendance | AC: 3 rows (2 absences, 1 lateness) with subject, date, period; EA: empty state. Register absence opens read-only with an explanatory note |
| Grades | IB columns Predicted / Final over 4 subjects — `DemoData.gradesReport` (`feature/demo/DemoData.kt:199-243`) is already correct; port it verbatim |
| Campus status | Starts "On campus"; all 11 captured options selectable; "Other" accepts ≤20 chars; changes persist for the session |
| Notifications | 2 items: one overdue assessment (task), one new email — `W4NotificationRepository.demoSnapshot()` (`feature/notifications/W4NotificationRepository.kt:131-169`) is the right shape |
| Trips | One trip: "Bergen weekend", 20–21 Sep, status Planning (`feature/trips/W4TripsRepository.kt:22-32`) |
| Travel forms | Four journeys, statuses: submitted / not started / not started / not started |
| Documents | Two folders (Internal Information, Outdoor Department — the real capture) each with 2 pages of invented body text |
| Extra Academics | 3 activities (one per type) with running/past/future; one diary entry; 3 CAS interviews (1 completed); SafetyNet with 4 weekly rows |
| Directory | 20 students + 5 staff, invented names, initials avatars, pinning works |
| Profile / Letter | Profile card with demo id, year, house, country, pronouns. Letter of Attendance shows "Not available in demo" (`feature/studiekort/StudiekortRepository.kt:87-89`) |
| Settings | Everything functional; Clear cache shows a confirmation and is a no-op |

Reviewer-facing copy must state plainly: *"Demo data. Not connected to W4."*

---

## 5. Local notifications — BGAppRefresh + UNUserNotificationCenter only

No widget, no Live Activity, no push server. Everything below is on-device.

### 5.1 What Android does (the behaviour to reproduce)

`NotificationDiffWorker` (`feature/notifications/NotificationDiffWorker.kt`):

- `PeriodicWorkRequestBuilder(15, TimeUnit.MINUTES)`, unique work `"bl_notif_poll"`, policy `KEEP`
  (lines 199-206).
- Bails immediately when signed out or in demo (line 60).
- Snapshot of already-notified keys in `SharedPreferences("notif_snapshots")` under `snap_<studentId>`
  (lines 65-67), rewritten at the end (line 178).
- Three independent, toggle-gated passes:
  - timetable changes → key `event:<id>:<status>`, max 5 notifications (lines 82-120);
  - new mail → key `msg:<id>`, one aggregated "N new messages" (lines 122-148);
  - W4 bell → key `w4:<id>`, max 5 (lines 150-176).
- Key helpers: `NotificationSnapshotDiff.eventKey/messageKey/assignmentKey/w4Key`
  (`feature/notifications/NotificationSnapshotDiff.kt:7-13`); `newIds` is set difference (line 8) — the
  whole point is that a still-present item never re-notifies.
- Also drives `LiveLessonNotifier` + `LiveLessonScheduler` (lines 78-79) — an ongoing "current lesson"
  notification plus exact alarms at lesson boundaries. **iOS has no equivalent** and it is not being
  rebuilt with Live Activities (product decision #1).

### 5.2 iOS design

**Background refresh**

- One `BGAppRefreshTaskRequest`, identifier `dk.jonathanb.w4.refresh`, declared in `Info.plist`
  under `BGTaskSchedulerPermittedIdentifiers`.
- `earliestBeginDate = TimeProvider.now + 15 * 60`. Re-submit at the *start* of every run; iOS decides
  actual cadence and will not honour 15 minutes reliably — the UI must never depend on it.
- Register in `BetterW4App.init` where `LiveActivityBackgroundRefresh.register` sits today
  (`BetterW4App.swift:24-32`).
- Budget ≤ 25 s. Set `task.expirationHandler` to cancel the work `Task`.
- Bail on: demo, signed out, no notification authorisation, all toggles off.
- Order of work, cheapest first, stopping on `.sessionExpired`:
  1. `POST notifications/refresh` (one tiny request, covers both tasks and emails);
  2. `GET mailer/inbox` only if the mail toggle is on and the bell produced no email group;
  3. `GET academics/deadlines` only if the assessments toggle is on and the bell produced no task group.
  The bell is authoritative when it answers — this is what keeps the tiny Apache box happy.

**Diffing**

Persist `w4.notify.seen.<uwcId>` as `[String]`. Key format ported verbatim from
`NotificationSnapshotDiff.kt`: `"w4:<notificationId>"`, `"msg:<messageId>"`,
`"asg:<assessmentId>:<status>"`, `"evt:<eventId>:<status>"`. Fire only for
`current.subtracting(previous)`; write `current` back afterwards. Cap the stored set at 500 keys, newest
first, so it cannot grow unbounded across a school year.

**Notification content**

| Trigger | Title | Body | `threadIdentifier` | `userInfo["route"]` |
|---|---|---|---|---|
| New mail (aggregated) | `New mail` | `N new messages` / the subject when N == 1 | `mail` | `mailer/inbox` |
| Assessment due/overdue | `Assessment overdue` / `Assessment due soon` | `<title> · <subject>` | `assessments` | `academics/deadlines` |
| Timetable change | `Timetable changed` | `<title> · <time>` | `timetable` | `academics/timetable/mytimetable` |
| W4 bell, other types | `<group title>` | `<item title>` | `w4` | item `href` |

`UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)`, `interruptionLevel = .active`,
no sound override, no critical alerts. Cap 5 per category per run (Android's `take(5)`,
`NotificationDiffWorker.kt:92,156`).

**Lesson reminders — the Live Activity replacement**

Scheduled locally, not diffed: after each successful timetable refresh, cancel all pending requests with
identifier prefix `lesson.` and re-schedule from the cached week:

- one `UNCalendarNotificationTrigger` per timed, non-cancelled lesson in the next 7 days, at
  `start - lessonReminderMinutes` (default 10, user-configurable);
- skip lessons that start < `reminderMinutes` from now;
- hard cap **40** requests (iOS allows 64 pending in total — leave headroom);
- identifier `lesson.<eventId>` so re-scheduling is idempotent;
- `LiveLessonBoundary.project` / `nextBoundary` (`feature/live/LiveLessonBoundary.kt:35-124`) still port,
  but now only to drive the in-app "now / next" banner, using the same eligibility filter (not cancelled,
  not all-day, `end > start`, 60-minute upcoming window — lines 15, 158-167).

**Badge**

App icon badge = unread inbox count, set from the mail parse. The existing
`.unreadMessageCountDidChange` notification (`MessageCacheManager.swift:8-12,90-97`) is the hook; retarget
it from the Lectio `-40` folder to the W4 inbox.

**Permission**

Requested lazily, the first time the user enables any notification toggle — never at launch. If
authorisation is denied, all toggles render off with a "Open Settings" row.

---

## 6. Settings — the final list

English only. `AppLanguage` / `AppLocale` (`feature/settings/SettingsStore.kt:21,117-125`,
`core/i18n/AppLocale.kt`) and the language picker are deleted; there is exactly one
`en.lproj/Localizable.strings`.

**Appearance**
- Theme — System / Light / Dark (`AppearanceMode`, `SettingsStore.swift:37-60`)
- Calendar style — Professional / Standard (`CalendarStyle`, `SettingsStore.swift:13-34`; both
  `displayName`s and both `description`s are currently Danish — translate)
- Use subject colours — toggle (`SettingsStore.swift:89`, `saveUseSubjectColors:179-182`). Off ⇒ status
  palette: normal `#3362E1`, changed `#2E9E5B`, cancelled `#D32F2F` (`SettingsStore.swift:191-195`,
  matching `feature/settings/SettingsStore.kt:411-413`)

**Subjects** (own screen, `SubjectColorSettingsView.swift`)
- One row per subject seen in the timetable: rename, hue picker from the 44 curated hues
  (`feature/settings/SubjectMapper.kt:138-142`), reset one, reset all
  (`resetAllLessonMappings`, `SettingsStore.swift:306-311`)
- Storage: local only, `w4.settings.subjectMappings`, scope `"w4::<uwcId>"`. The Supabase round-trip
  (`SettingsStore.swift:315-353,442-500`) is deleted; `ResolvedLessonMapping.mappingId` becomes
  `"local:<canonicalKey>"` as Android already does when offline
  (`feature/settings/SettingsStore.kt:190`).
- **The subject dictionary must be rebuilt for IB.** Both `SubjectMapper`s ship 55 Danish gymnasium
  subjects — `"ma": "Matematik"`, `"da": "Dansk"`, `"sa": "Samfundsfag"`, `"srp"`, `"ap"`, `"vø"` …
  (`ios/BetterW4/SubjectMapper.swift:86-139`, `feature/settings/SubjectMapper.kt:73-126`) — plus a
  Danish class-code regex (`1x`, `2hf`, `3hx-u`) and 17 Danish ignore patterns (`kor`, `udvalg`,
  `kostelever`). None of it matches `Mathematics HL`. Replace with IB subject groups (Language A/B,
  Individuals & Societies, Sciences, Mathematics, Arts, TOK, EE, CAS) keyed on the English name with
  HL/SL stripping, and keep the machinery: `canonicalKey` → override lookup → default, `normalizedHold`,
  hue→RGB at S 0.62 / V 0.88 (`feature/settings/SubjectColorResolver.kt:41-62`), and the unmapped hue 215.
  Until that dictionary exists, unknown subjects fall back to a stable hash-of-name hue — never a
  Danish default name.

**Notifications**
- New mail
- Assessments (due soon / overdue)
- Timetable changes
- Lesson reminder + "minutes before" stepper (5 / 10 / 15 / 30)
- Row showing system authorisation state with an "Open Settings" shortcut

**Data**
- Clear cache — `clearAllCaches()` (`SettingsStore.swift:359-375`): image cache, `URLCache`, timetable
  store, directory store, assessments store, mail cache, W4 page cache. Explicitly **not** credentials,
  cookies or preferences (comment at `SettingsStore.swift:357-358`). Posts `.betterW4CachesDidClear`
  (`SettingsStore.swift:522`) so open screens reload.
- Re-sync directory — forces the people sweep
- Storage used — bytes across the caches (nice-to-have)

**Privacy**
- Privacy policy link. Android's `PRIVACY_POLICY_URL = "https://w4.jonathanb.dk/privatlivspolitik"`
  (`feature/settings/SettingsStore.kt:404`) is a Danish URL for a Danish product —
  **UNKNOWN: an English privacy page URL is needed before submission.**
- "What BetterW4 stores" — a static English screen: session cookie and device id in the Keychain, cached
  W4 pages on device, no analytics, no servers, no account.

**About**
- App version + build
- W4 server version, linked to `site/relnotes` (the chrome renders it as `25.9.1` —
  `references/pages/UWCRCN W4.html:37`)
- Acknowledgements
- Sign out — `KeychainManager.wipeAll()` + `clearAllCaches()` + cookie wipe

**Deleted settings rows**: language picker, Live Activity variant + "test Live Activity"
(`SettingsView.swift:94-113,332-340`), message signature toggle, in-app feedback, referrals / invite,
profile picture, school picker, browser-extension promo (`browser_extension.*` in
`en.lproj/Localizable.strings:1-9` — that is a desktop-extension advert for a product that is not being
built).

---

## 7. Open captures, ranked by value

1. **One term-time week of `academics/timetable/mytimetable`** — unblocks the entire lesson-block parser
   (`.period`, `.inner`, `.datetime`, `.room`, absence markers) and the only honest timetable fixture.
2. **`academics/deadlines`** — the assessment `data-*` attributes and the `confirm` / `revert` / `create` /
   `save` / `delete` AJAX URLs; the whole assessments feature rests on assumed attribute names.
3. **`mailer/inbox` + one `mailer/view` + the `mailer/send&type=freeform` form** — grid columns, unread
   marker, attachment markup, and the real recipient-picker payload from `mailer/extra&type=freeform`.
4. **`notifications/refresh` response body** — the bell fragment, which also drives background
   notifications.
5. **`people/students/absences` and `.../register`** — table columns and the per-slot checkbox names.
6. **`academics/grades/grades`** — the only grades evidence today is an admittedly speculative parser.
7. **`people/students/letter/attendance` `Content-Type`** — settles the PDF-vs-HTML contradiction (§1.13).
8. **The Home `#calendar` iframe `src`** — confirms (or refutes) `calendar@uwcrcn.no` as the school
   calendar source.

Fixture hygiene for all of the above is defined in reviewer-notes.md §8: placeholder UWC ids, invented
names, no image binaries, and never a live `PHPSESSID` or feed `token=`.
