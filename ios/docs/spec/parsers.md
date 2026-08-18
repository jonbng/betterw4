# W4 HTML parsers — iOS spec

Every parser the BetterW4 iOS app needs, with the real selectors, the real routes, the Swift models
they produce, and an honest statement of what has and has not been seen in a capture.

Read `ios/docs/spec/reviewer-notes.md` first — it covers the HTTP engine, session death and login.
This file covers only *what happens to the bytes after a 200*. Where the two overlap (timetable
geometry, fixture hygiene) they agree; if they ever disagree, reviewer-notes wins.

---

## 0. Evidence legend

Every selector in this document is tagged:

| Tag | Meaning |
|---|---|
| **[V]** | **Verified** — I read this exact markup in `references/pages/*.html`, in a response body inside `references/w4.uwcrcn.no.har`, or in a CSS/JS file W4 itself serves (a rule like `.grid-view table.items` in `css/main.css` is server-authored proof that the class exists). |
| **[I]** | **Inferred** — the Kotlin parser assumes it and it is *plausible* (Yii 1 convention, or a CSS rule that implies the element), but no capture shows the element itself. |
| **[U]** | **UNKNOWN — needs live capture.** Never seen. Parser must degrade to empty, never throw. |

The two captures we have are:

- `references/pages/UWCRCN W4.html` — real Home (`r=site/index`), saved 14 Aug 2026, plus five more
  top-level pages with their `*_files/` CSS+JS. Real chrome, real `#timetable` grid, real sdmenus.
- `references/w4.uwcrcn.no.har` — 20 entries, exactly one HTML body: entry 0,
  `GET https://w4.uwcrcn.no/index.php?r=documents` → 200, `Content-Type: text/html; charset=UTF-8`,
  `Date: Fri, 14 Aug 2026 11:30:12 GMT`. The other 19 are CSS/JS/images.

**The captured week (August 2026, ISO week 33) is a holiday week.** `UWCRCN W4.html` contains
`id="timetable"` ×2, `class="column"` ×8, `class="cell"` ×15 and **`class="period"` ×0**. No lesson
block, no assessment, no notification, no mail row has ever been seen. Everything downstream of that
is **[I]** or **[U]**, and the tests must say so.

### 0.1 The timezone proof (use this, it is not a guess)

`references/pages/UWCRCN W4.html:180`:

```html
<div id="current_time" style="opacity: 0.460236; display: block; top: 394px;">&nbsp;</div>
```

`UWCRCN W4.html:22-23` sets `var tt_start_hour = 7; var tt_end_hour = 22;` and the grid columns are
`style="height: 900px"` with 15 `.cell` hour rows (`UWCRCN W4.html:139-170`). 15 h across 900 px ⇒
**1 px == 1 minute, measured from `tt_start_hour`:00**. `top: 394px` ⇒ 07:00 + 394 min = **13:34**.
The HAR was captured the same session at `11:30:12 GMT` = **13:30 Europe/Oslo (CEST)**.

Conclusion, and it is load-bearing for every parser here:

> **W4 renders wall-clock time in `Europe/Oslo`.** All dates and times parsed out of W4 HTML are
> Oslo local time with no offset in the markup. Build every `Date` with
> `Calendar(identifier: .gregorian)` whose `timeZone = TimeZone(identifier: "Europe/Oslo")!`,
> never `.current`. A student on a trip with the phone on another timezone must still see the
> Oslo timetable. Render with the same fixed zone.

Corollary: **do not parse `#current_time`.** Its inline `top`/`opacity` were written by
`full_timetable.js` (`UWCRCN W4_files/full_timetable.js:5-13`) *in the browser* before the page was
saved; the server sends `<div id="current_time">&nbsp;</div>` with `display:none` from
`display_full_timetable.css:165-173`. Compute "now" locally from `tt_start_hour`.

### 0.2 Date formats

| Where | Format | Example | Source |
|---|---|---|---|
| Timetable header day | `dd-MMM-yyyy`, `en_GB` | `10-Aug-2026` | **[V]** `UWCRCN W4.html:94` |
| Yii datepicker fields (`StudentAbsenceForm[absence_date]`, `student_deadline_date`) | `dd-M-yy` en-GB ⇒ same rendering | `14-Aug-2026` | README §5.2 |
| Grid "Received" cell | `dd-MMM-yyyy HH:mm` | `14-Aug-2026 12:04` | **[I]** |
| ICS feeds | `yyyyMMdd` / `yyyyMMdd'T'HHmmss'Z'` | `20260814T113000Z` | **[V]** Google ICS |

One shared helper, ported from `android/.../core/w4/W4Dates.kt:12-36`:

```swift
enum W4Dates {
    static let zone = TimeZone(identifier: "Europe/Oslo")!
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c
    }
    /// Accepts d-MMM-yyyy, dd-MMM-yyyy, d-MMM-yy, dd-MMM-yy, yyyy-MM-dd, d/M/yyyy, dd/MM/yyyy.
    /// Locale is ALWAYS en_GB_POSIX — "Aug" must not depend on the phone's language.
    static func parseDate(_ raw: String) -> Date?
    /// "14-Aug-2026 12:04" -> Date; time optional, defaults to 00:00 Oslo.
    static func parseDateTime(_ raw: String) -> Date?
    static func format(_ date: Date) -> String       // dd-MMM-yyyy
}
```

`DateFormatter.locale` **must** be `Locale(identifier: "en_GB_POSIX")`. The Kotlin version uses
`Locale.UK`; on iOS a device set to Danish will otherwise fail to parse `Aug`.

### 0.3 Chrome shared by every authenticated page **[V]**

Verified identically in `UWCRCN W4.html:35-58` and in the HAR body (`?r=documents`, lines 31-54 of
the response):

```
#main
  #header
    div                       "UWCRCN W4"
    #version > a[href*=site/relnotes]        "25.9.1"
    div.notifications                        <- EMPTY when count == 0 (both captures)
    div.status-dropdown > div.status.oncampus > div.status-value / div.location
    div.selection-box  > span#location > input[type=radio][name=location] + label[for]
  #main_menu > a  (Home | Academics | Extra Academics | School | Admissions | Documents)
  #user-panel > div.right   "Welcome, {name}" + a[site/logout] | a[site/profile] | a[site/password]
  #content
    #breadcrumb > div.crumbs > a
    #content_frame
      div.sdmenu#dynamic_menu_{academics|extraacademics|people|admissions}   (absent on Home/Documents)
      #content_main > #content_inner        <- PAGE BODY. Every page parser starts here.
  #footer   "Copyright © 2009 - 2026 Red Cross Nordic United World College"
```

Error/empty containers W4 itself styles (`css/main.css`, **[V]**): `div.error`, `div.message`,
`div.warning`, `div.errorMessage`, `div.note`, `ul.page-submenu li`, `div.filter label`,
`a.sort_asc` / `a.sort_desc`, `.grid-view table.items`, `.grid-view table.items th`,
`.grid-view tr.bold td.student-name`, `.grid-view tr.bold td.entry-name`,
`tr.offline td.status`, `tr.online td.status`, `table.grades th.anticipated`,
`table.grades tr.table_1_bg td.anticipated`, `.effort-grade-meets-expectations`,
`.effort-grade-almost-meets-expectations`, `.effort-grade-does-not-meet-expectations`,
`ul.role-list li`. From `css/tables.css` **[V]**: `tr.prearranged_1`, `tr.prearranged_2`,
`tr.medical_1`, `tr.medical_2`, `td.active`, `td.inactive`, `.weekend`, `.break`,
`.pbl`, `.special`, `.classes`, `.data`.

### 0.4 Yii 1 grid convention (used by mailer, absences, grades, trips, people)

Yii's `CGridView` renders

```html
<div id="yw0" class="grid-view">
  <div class="summary">Displaying 1-20 of 37 results.</div>
  <table class="items">
    <thead><tr><th><a class="sort_desc" href="...&sort=received.desc">Received</a></th>…</tr></thead>
    <tbody><tr class="odd">…</tr><tr class="even">…</tr></tbody>
  </table>
  <div class="pager"><ul class="yiiPager">…</ul></div>
</div>
```

`.grid-view table.items` and `a.sort_asc`/`a.sort_desc` are **[V]** (they are styled in
`css/main.css`); `thead`/`tbody`/`.summary`/`.pager`/`ul.yiiPager` are **[I]** from the framework.

Empty state: Yii 1.1 emits `<tr><td colspan="N" class="empty">` and, from 1.1.14 on, an inner
`<span class="empty">No results found.</span>`. **[I]**. A separate, **[V]** empty pattern exists
outside grids: `references/pages/Current applicants at UWCRCN.html` renders
`<div class="note">No users found</div>` inside `#content_inner`.

**Shared rule for every table parser:** a row is empty if `td.empty`, or `span.empty`, or the row
text equals `No results found.`; a page is empty if `#content_inner > div.note` exists. The Kotlin
parsers only check `td.empty` — that is bug **B9** below.

**Pagination is not handled anywhere in the Android port.** Yii paginates with `&{Model}_page=2`
(or `&page=2`) and the mailer inbox of a two-year student will exceed one page.
`[U]` — needs a capture of `mailer/inbox` with >1 page. Until then: parse page 1, and if
`div.pager` exists, surface "more on w4.uwcrcn.no" rather than silently truncating.

### 0.5 SwiftSoup porting gotchas (these will bite)

1. **`getElementById` returns the first match.** Home has **two** `id="timetable"` divs
   (`UWCRCN W4.html:86` outer wrapper, `:138` inner grid). Kotlin gets the right one only because it
   writes `doc.select("#timetable").last()`. In Swift use
   `try doc.select("div#timetable").last()` or, better, `try doc.select("div#timetable div.column")`.
   `try doc.getElementById("timetable")` returns the **wrapper** and finds zero columns.
2. **Attribute selectors need quoting.** `label[for=location_0]` works, but ids containing `/` or
   spaces do not — use `label[for='\(id)']` and escape.
3. SwiftSoup throws; every parser entry point is `throws` and returns an empty model rather than
   propagating for optional sub-sections.
4. `ownText()` vs `text()` matters in `#user-panel` (the `.right` div also contains the Logout /
   Profile / Password anchors) and in notification `<dt>` (which contains read/clear anchors).
5. Parse on a background actor. `#content_inner` of `people/students/letter/attendance` is ~600 KB
   (README §6).

---

## 1. `W4ChromeParser` — identity, menus, version

**Replaces:** the identity half of `ios/BetterW4/StudentParser.swift`
(`parseStudentInfo`, `parseStudentPictureId`, `parseStudentNameFromTitle`,
`parseStudentClassFromTitle`, `parseDropdownURL`, `parseDropdownEntries`,
`parseHoldsFromHomepage`, `parseTeamMemberPictureIds`). Those are Lectio-only.
`StudentParser.swift` is **rewritten down to ~80 lines** and everything absence-related moves to §8.

**Routes:** any authenticated page. Cheapest probe: `index.php?r=site/index`.

**DOM [V]** — `UWCRCN W4.html:35-58`, HAR `?r=documents` response lines 31-54:

| Field | Selector | Captured value |
|---|---|---|
| display name | `#user-panel .right` → `ownText()` → `/Welcome,\s*([^|<]+)/` | `Jonathan Bangert` |
| uwc id | `#content_inner a[href*=people/students/student][href*=uwc_id]` whose text contains "profile" | `nc26jban` from `…&uwc_id=nc26jban` (`UWCRCN W4.html:237`, link text `W4 public profile`) |
| server version | `#version a[href*=site/relnotes]` | `25.9.1` |
| main menu | `#main_menu a` | 6 anchors, active one has `class="active"` |
| sdmenu | `div.sdmenu[id^=dynamic_menu_] > div` → `span` = section title, sibling `a` = items | see below |
| logout / profile / password | `#user-panel a[href*=site/logout]` etc. | |

sdmenu is **fully verified**. `references/pages/Academics.html` (search `dynamic_menu_academics`)
gives, as one flat line:

```html
<div class="sdmenu" id="dynamic_menu_academics">
  <div><span>My Academics</span>
    <a href="…?r=academics/deadlines">My assessments</a>
    <a href="…?r=academics/timetable/mytimetable">My timetable</a>
    … 13 links …
  </div>
  <div><span>Academics</span> …3 links… </div>
  <div><span>Trips</span><a href="…?r=academics/trips">My trips</a>
       <a href="…?r=academics/travel/travel.list">My travel forms</a></div>
  <div><span>Resources</span><a href="…?r=academics/resources/resources">Resource bookings</a></div>
</div>
```

`School info @ UWCRCN.html` → `dynamic_menu_people` with sections My School / Students / Staff /
Visitors / Birthdays / Rooms / On duty / Mailer. Note `My teachers/group leaders` there is
`r=people/students/staff` **with no `&type=`**, while Academics uses `&type=teachers` and Extra
Academics uses `&type=leaders`. `Extra Academics.html` → `dynamic_menu_extraacademics`.
`Current applicants at UWCRCN.html` → `dynamic_menu_admissions`, one link.
`sdmenu.css` **[V]** confirms the runtime classes `div.sdmenu div.collapsed` and `div.sdmenu div a.current`.

**Models:**

```swift
struct W4Identity: Codable, Equatable, Sendable {
    let uwcId: String            // "nc26jban" — the app's studentId & Keychain scope key
    let displayName: String      // "Jonathan Bangert"
    var email: String { "\(uwcId)@uwcrcn.no" }
    var avatarURL: URL { URL(string: "https://w4.uwcrcn.no/files/user_photos/\(uwcId)_thumb.jpg")! }
}

struct W4MenuSection: Identifiable, Sendable { let id: String; let title: String; let items: [W4MenuItem] }
struct W4MenuItem: Identifiable, Sendable { let id: String; let title: String; let route: String }

enum W4ChromeParser {
    static func parseIdentity(_ html: String) throws -> W4Identity?
    static func parseSideMenu(_ html: String) throws -> [W4MenuSection]   // drives the "More" tab
    static func parseServerVersion(_ html: String) throws -> String?
    static func contentInner(_ html: String) throws -> Element?
}
```

**Dates/timezone:** none.

**Edge cases:** `#user-panel` exists on the 2FA page too — never treat "chrome present" as
"logged in" (reviewer-notes §5). Documents and Home have **no** `.sdmenu` **[V]**; return `[]`.
`uwc_id` appears in birthday links as well (`UWCRCN W4.html:201-214`), so the fallback
"first `nc\d{2}[a-z]+` anywhere in the document" used by `W4Html.uwcId`
(`android/.../core/w4/W4Html.kt:55-63`) will happily return **another student's id** — bug **B17**.
Restrict to the `#hello` block / a link whose text contains "profile", else return `nil`.

**Fixture:** `Fixtures/W4/home.html` (whole Home page, ids scrubbed per reviewer-notes §8),
`Fixtures/W4/sdmenu-academics.html`, `Fixtures/W4/documents-index.html`.

**Assertions:**
- `parseIdentity` → `("nc00aaa", "Test Student")`; email derived, not scraped.
- `parseIdentity` on `Fixtures/W4/login.html` → `nil` (no throw).
- `parseSideMenu(academics)` → 4 sections; `sections[0].items.count == 13`;
  `sections[0].items[1].route == "academics/timetable/mytimetable"`;
  `sections[2].items[1].route == "academics/travel/travel.list"`.
- `parseSideMenu(home)` → `[]`.
- `parseServerVersion(home) == "25.9.1"`.

**Priority: v1.**

---

## 2. `W4CampusStatusParser` — the boarding-school feature

**Replaces:** nothing (new). No iOS file deleted.

**Routes:** read from any page's chrome (cheapest: `index.php?r=site/index`).
Write: `POST index.php?r=site/setstatus` with `status=on|off` and `location=…`
(**[V]** `UWCRCN W4.html:25` → `var status_urls = {'set':'/index.php?r=site/setstatus'}`;
payload shape **[V]** from `campusstatusdropdown.js:17-19`).

**DOM [V]** — `UWCRCN W4.html:38-49`:

```html
<div class="status-dropdown">
  <div class="status oncampus">
    <div class="status-value">on campus</div>
    <div class="location"></div>          <!-- empty while on campus -->
  </div>
</div>
<div class="selection-box">
  <p>I am currently:</p>
  <span id="location">
    <input value="oncampus"  id="location_0" checked="checked" type="radio" name="location"> <label for="location_0">On campus</label><br>
    <input value="On a walk" id="location_1" type="radio" name="location"> <label for="location_1">On a walk</label><br>
    … location_2..location_9 …
    <input value="other"     id="location_10" type="radio" name="location"> <label for="location_10">Other</label>
  </span>
  <input maxlength="20" type="text" value="" name="other" id="other" style="display:none">
  <div class="buttons"><input id="submit-campus-status" name="yt0" type="button" value="Set status"></div>
</div>
```

All eleven options, verbatim and in order **[V]**: `On campus`, `On a walk`, `At Raudbua`,
`On Jarstadheia`, `On the island`, `In Flekke`, `In Dale`, `In A building (after 10:30pm)`,
`In K building (after 10:30pm)`, `In Library/Study room (after 10:30pm)`, `Other`.
State classes: `.status.oncampus` (green `#4AC234`) / `.status.offcampus` (red `#E00D0D`)
**[V]** `campusstatusdropdown.css:16-21`.

**Model:**

```swift
struct CampusLocationOption: Identifiable, Hashable, Sendable {
    let id: String        // the input's DOM id, e.g. "location_2"
    let value: String     // POST value: "oncampus" | "other" | "At Raudbua"
    let label: String     // <label> text
    var isOnCampus: Bool { value == "oncampus" }
    var isFreeText: Bool  { value == "other" }
}

struct CampusStatus: Equatable, Sendable {
    let isOnCampus: Bool
    let location: String?              // nil when on campus
    let options: [CampusLocationOption]
    let selectedOptionID: String?      // from checked="checked"
    var label: String { isOnCampus ? "On campus" : (location ?? "Off campus") }
}

enum W4CampusStatusParser {
    static func parse(_ html: String) throws -> CampusStatus?
    /// status=on|off, location omitted when on campus, free text (max 20 chars) when value == "other"
    static func setStatusBody(option: CampusLocationOption, freeText: String?) -> [String: String]
}
```

**Bug B6 — do not copy.** `CampusStatusParser.kt:42-57` maps radios to **label strings only** and
then `CampusStatusRepository` posts that label. That is wrong for two of the eleven options: the
label `On campus` must post `status=on` (no `location`), and `Other` must post
`status=off&location={the #other text}`. Keep `value` and `label` separate, exactly as
`campusstatusdropdown.js:17-18` does.

**Bug B7.** `.location` server-side is the bare string; `campusstatusdropdown.js:28` writes
`'(' + location + ')'` after a successful POST. Strip a wrapping `(…)` when reading.

**Edge cases:** `.location` is whitespace-only when on campus **[V]** → `nil`, not `""`.
`#other` is `maxlength="20"` — enforce in the UI. If `span#location` is missing (role without the
widget), fall back to the eleven hardcoded options but keep `isOnCampus` from the `.status` class.

**Fixture:** `Fixtures/W4/campus-chrome-oncampus.html` (trimmed from the real Home chrome, **[V]**)
and `Fixtures/W4/campus-chrome-offcampus.html` (hand-built, **[I]** — label it as such in a comment).

**Assertions:**
- on-campus fixture → `isOnCampus == true`, `location == nil`, `options.count == 11`,
  `options[0].value == "oncampus"`, `options[10].value == "other"`,
  `options[2].label == "At Raudbua"`, `selectedOptionID == "location_0"`.
- `setStatusBody(options[0], nil) == ["status": "on"]` (no `location` key at all).
- `setStatusBody(options[2], nil) == ["status": "off", "location": "At Raudbua"]`.
- `setStatusBody(options[10], "Bergen airport") == ["status": "off", "location": "Bergen airport"]`.
- off-campus fixture → `location == "At Raudbua"` even when the DOM says `(At Raudbua)`.

**Priority: v1.**

---

## 3. `W4NotificationParser` — the bell

**Replaces:** nothing (new).

**Routes** — all `$.post`, `X-Requested-With: XMLHttpRequest`, response is an **HTML fragment**
(**[V]** `UWCRCN W4.html:24`, decoded from the `\x2F`-escaped literal):

| Key | Route | Fields |
|---|---|---|
| `refresh` | `notifications/refresh` | — (poll every 60 s while the dropdown is closed, `notifications.js:51-57`) |
| `read` | `notifications/read` | `notification_id` |
| `readGroup` | `notifications/readgroup` | `notification_type` |
| `readAll` | `notifications/readall` | — |
| `readAllEmails` | `notifications/readallemails` | — |
| `clear` | `notifications/clear` | `notification_id` |
| `clearGroup` | `notifications/cleargroup` | `notification_type` |
| `clearAll` | `notifications/clearall` | — |

**DOM.** The container is `#header div.notifications` **[V]**, and in **both** captures it is

```html
<div class="notifications">
</div>
```

i.e. **empty** (`UWCRCN W4.html:37-38`; HAR `?r=documents` response lines 33-34). Zero notifications
⇒ no bell, no `.btn-group`, no dropdown at all.

The populated structure is **[I]**, reconstructed from `notifications.js` + `notifications.css`
(both **[V]** — they are the real assets W4 serves):

```html
<div class="notifications">
  <div class="btn-group">
    <img class="notification-icon" …>            <!-- notifications.js:3 -->
    <div class="alert new|overdue|normal">3</div> <!-- notifications.css:12-41, badge count -->
    <div class="dropdown-menu">                   <!-- notifications.js:5, hidden by default -->
      <h3 class="tasks">…<a class="read">…</a><a class="clear">…</a></h3>   <!-- .js:7,32 -->
      <dl>
        <dt class="new|overdue">Group title<a class="read" data-notification-type="…">…</a></dt>   <!-- .js:19,38 -->
        <dd><ul><li class="new|overdue">
              <a href="/index.php?r=…">Title <span class="deadline">…</span></a>
              <a class="read" data-notification-id="…">…</a>
        </li></ul></dd>
      </dl>
      <h3 class="emails">…</h3>
      <dl class="email-list">…</dl>               <!-- notifications.css:43-49 -->
    </div>
  </div>
</div>
```

Class names that are **[V]** because W4's own CSS/JS names them: `div.notifications`, `.btn-group`,
`div.alert`, `.dropdown-menu`, `h3.tasks`, `h3.emails`, `a.read`, `a.clear`,
`data-notification-id`, `data-notification-type`, `dl.email-list`, `span.icon`, `span.duration`,
`span.deadline`, and severity `normal` / `new` / `overdue` on both `dt` and `dd li`.
What is **[U]**: the actual title/subtitle text, whether `href` is present on every item, and
whether `refresh` returns the whole `div.notifications` or only its children.

**Refresh contract [V]** — `notifications.js:65`:
`$('#header div.notifications').html($(data).children());`
So the payload is a **wrapper element whose children** are the new content. The parser must accept
either a full `div.notifications`, a bare `.btn-group`, or an anonymous wrapper.

**Model:**

```swift
enum W4NotificationSeverity: String, Codable, Sendable { case normal, new, overdue }
enum W4NotificationSection: String, Codable, Sendable { case task, email }

struct W4Notification: Identifiable, Codable, Equatable, Sendable {
    let id: String                 // data-notification-id
    let title: String
    let subtitle: String?          // span.deadline / span.duration
    let route: String?             // href, normalised to an r= route
    let type: String?              // data-notification-type (group key)
    let section: W4NotificationSection
    let severity: W4NotificationSeverity
}
struct W4NotificationGroup: Identifiable, Codable, Equatable, Sendable {
    var id: String { type ?? title }
    let type: String?; let title: String
    let severity: W4NotificationSeverity; let items: [W4Notification]
}
struct W4NotificationSnapshot: Codable, Equatable, Sendable {
    let count: Int
    let severity: W4NotificationSeverity
    let taskGroups: [W4NotificationGroup]
    let emailGroups: [W4NotificationGroup]
    static let empty = W4NotificationSnapshot(count: 0, severity: .normal, taskGroups: [], emailGroups: [])
}
```

**Bug B8 — do not copy.** `W4NotificationParser.kt:49-53` falls back to
`doc.selectFirst(".btn-group")?.parent() ?: doc.body()` and then counts
`a[data-notification-id]`. On the real, empty `div.notifications` that path still works (count 0),
but only by luck. Make "empty container ⇒ `.empty` snapshot" an explicit, tested branch: an empty
bell is the **normal** state at this school, not a parse failure.

**Edge cases:** badge text may be `9+` **[U]** → `Int(text) ?? items.count`. `dt` `ownText()` must
have the `read`/`clear` anchor text removed (Kotlin strips the literal words `read|clear` with a
regex — fragile; prefer cloning the `dt` and removing `a.read, a.clear` before reading text).
403 + `Login Required` in the body is session death, not an empty snapshot (reviewer-notes §3).

**Fixture:** `Fixtures/W4/notifications-empty.html` (**[V]**, lifted verbatim from the Home capture)
and `Fixtures/W4/notifications-refresh.html` (**[I]** — port
`android/app/src/test/resources/w4/notifications-refresh.html` and add a header comment saying it is
synthesized).

**Assertions:**
- empty fixture → `== .empty`, no throw.
- refresh fixture → `count == 3`, `severity == .new`, one task group titled `Assessments`
  with `type == "assessment"` and 2 items; item `12` has `severity == .overdue` and a route
  containing `academics/deadlines`; one email group whose single item id is `88`.
- bare-wrapper fragment (`<div><div class="btn-group">…`) parses identically → proves the
  `.html($(data).children())` contract is handled.

**Priority: v1.5** (badge polling). The empty-state branch ships in v1 with the chrome parser.

---

## 4. `W4TimetableParser` — the flagship

**Replaces:** `ios/BetterW4/ScheduleParser.swift` — **rewritten**. Delete
`parseSchedule` (`table.s2skema`, `td[data-date]`, `a.s2skemabrik.s2brik`, `data-tooltip`,
`data-brikid`), `parseTooltip`, `extractTimes`, `parseHomeworkOverview` and
`parseHomeworkContentCell` (all Lectio). **Keep** `parseLessonContent` / `parseInlines` /
`parseContentArticle` — that HTML→`[ContentBlock]` renderer is generic and is reused by
Documents (§12) and the mail body (§7). Move it to a new `HTMLContentRenderer.swift`.

**Routes:**

| Surface | Route | Query |
|---|---|---|
| Home week strip | `site/index` | — |
| AC week | `academics/timetable/mytimetable` | `year`, `week` **[U]** |
| EA week | `extraacademics/timetable/mytimetable` | `year`, `week` **[U]** |
| Room week | `academics/timetable/room` | **[U]** |

The Android port fetches `academics/timetable/mytimetable/index` with
`year=2026&week=33` (`android/.../schedule/ScheduleRepository.kt:50-65`). Neither the `/index`
suffix nor the two query params appear in any capture — the sdmenu link is the bare
`?r=academics/timetable/mytimetable` **[V]**. Treat paging params as **[U]**; the first live capture
must confirm them. Safe v1 behaviour: fetch the bare route, read the week **out of the HTML**
(§B5) and only add `year`/`week` once verified.

**DOM [V]** — `UWCRCN W4.html:86-188`:

```html
<div id="timetable">                                   <!-- OUTER wrapper (Home only) -->
  <h3>August 2026, week 33</h3>
  <div id="timetable-header">
    <div class="header-row">
      <div class="header-cell first">&nbsp;</div>
      <div class="header-cell">
        <div class="day-name">Monday</div>
        <div>10-Aug-2026</div>
        <div class="rotation-day">Day 1</div>
        <div>No EA</div>
      </div>
      … 6 more, Tue..Sun; Sat/Sun use <div class="rotation-day no-classes">Weekend</div> …
      <div class="clear"></div>
    </div>
  </div>
  <div id="timetable">                                 <!-- INNER grid -->
    <div class="column" style="height: 900px">         <!-- hour gutter -->
      <div class="cell">7:00 — 8:00</div> … <div class="cell">21:00 — 22:00</div>   <!-- 15 -->
    </div>
    <div class="column" style="height: 900px"> … </div>          <!-- Monday -->
    …
    <div class="column current" style="height: 900px">           <!-- today -->
      <div id="current_time" …>&nbsp;</div>
    </div>
    …                                                            <!-- 7 day columns total -->
    <div class="clear"></div>
  </div>
</div>
```

Verified counts in that file: `id="timetable"` ×2, `class="column"` ×8 (1 gutter + 7 days),
`class="cell"` ×15, `class="period"` ×**0**.

Day-column identification, **[V]** and worth stating precisely: a day column is a direct child of
the inner `#timetable` with class `column` **and no `.cell` descendant**. The gutter is the only
column that has `.cell` children. `div.clear` is not a column. `column current` is today.

The em dash in `7:00 — 8:00` is **U+2014** **[V]**. The time regex must accept `—`, `–` and `-`.

**Lesson blocks — [I], never captured.** From `display_full_timetable.css:82-128` **[V]** the class
names exist server-side:

```
#timetable .period                       position:absolute;  (inline top/height in px)
#timetable .period .inner                display:table-cell
#timetable .period .inner .absence       bold
#timetable .period .inner .present       green
#timetable .period .inner .normal        red
#timetable .period .inner .prearranged   blue
#timetable .period .inner .datetime
#timetable .period .inner .room
#timetable .period .close  /  .close a
```

and `UWCRCN W4.html:279` **[V]** proves each block carries a **`title` attribute**:

```js
jQuery('div.period').tooltip({'fade':250,'track':true,'content':function () { return $(this).prop('title'); }});
```

`W4TimetableParser.kt` never reads `period.attr("title")` — **bug B3**. That tooltip is the most
likely home of teacher, full subject name and change notes (it is the exact analogue of Lectio's
`data-tooltip`, which the old iOS parser mined for everything). The Swift parser must capture it raw
into `rawTooltip` and, once we have one real capture, add a structured tooltip parser.

Also **[V]** from the same CSS: empty/rotation days render as `div.column.no-classes` containing
`div.no-classes-inner` (`:58-67`), and `div.p-classes-inner` for P-classes (`:69-73`).
The header variants are `.rotation-day.no-classes` (Weekend, **[V]** at `UWCRCN W4.html:125`),
`.p-classes`, `.pbl` (`display_full_timetable.css:23-36`).
**Bug B4:** `W4TimetableParser.kt:101` drops a period whose *text* equals `"No-Classes"` — an
invented string. Use the **class** `no-classes` on the column/inner div instead.

Year switches (`.year-switch#preib-year-switch|#first-year-switch|#second-year-switch`,
`.year-switch-active`, and body classes `.preib-year`/`.first-year`/`.second-year`) are **[V]**
in `timetable.js` and `display_full_timetable.css:175-197`. They only matter on the *school-wide*
grid; on `mytimetable` the student sees one year. If a fetched grid contains `.year-switches`,
filter periods to the `.year-switch-active` year class **[I]**.

**Geometry fallback (verified, and it is the primary path until we capture a `.period`):**

```
startMinutes = tt_start_hour * 60 + round(style.top)      // 1px == 1min, §0.1
endMinutes   = startMinutes + max(15, round(style.height))
```

`tt_start_hour` / `tt_end_hour` come from the page script **[V]** (`UWCRCN W4.html:22-23`); default
to 7 / 22 if absent. When `.datetime` gives an explicit `H:MM — H:MM`, prefer it over pixels.

**Models** (replacing `ios/BetterW4/ScheduleModels.swift:12-56` — keep the file, retype the struct):

```swift
enum W4EventSource: String, Codable, Sendable { case academic, extraAcademic, schoolCalendar, local }

struct ScheduleEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String              // "ac-2026-08-10-0" or "ac-w4-42"; source-prefixed, see B20
    let title: String           // "Biology HL"
    let subtitle: String        // subject/class code when the tooltip gives one
    let source: W4EventSource
    let start: Date?            // Europe/Oslo
    let end: Date?
    let date: Date              // start of day, Europe/Oslo
    let room: String?
    let teacher: String?
    let status: EventStatus     // .normal | .changed | .cancelled
    let attendance: W4Attendance?   // .present | .absent | .prearranged  (from .present/.normal/.prearranged)
    let isAllDay: Bool
    let route: String?          // href on the block, if any
    let rawTooltip: String?     // period[title] — B3
}

struct ScheduleDay: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let dayName: String         // "Monday"
    let rotationDay: String?    // "Day 1" … "Day 5" | "Weekend"
    let isNoClasses: Bool       // .rotation-day.no-classes
    let eaNote: String?         // "No EA"
    let isToday: Bool           // column.current
    let events: [ScheduleEvent]
}

struct ScheduleWeek: Codable, Equatable, Sendable {
    let year: Int; let week: Int
    let title: String?          // "August 2026, week 33"
    let startHour: Int          // tt_start_hour
    let endHour: Int            // tt_end_hour
    let days: [ScheduleDay]     // 7, Monday-first
}

enum W4TimetableParser {
    static func parseWeek(_ html: String, source: W4EventSource) throws -> ScheduleWeek
    static func merge(_ primary: ScheduleWeek, _ extra: ScheduleWeek) -> ScheduleWeek
}
```

**Bug B5.** `parseWeek(html, year, week)` in Kotlin trusts the *caller's* year/week and only uses
the header dates as an override. Invert it: the header `dd-MMM-yyyy` cells are the truth (**[V]**),
`<h3>August 2026, week 33</h3>` is the label, and the ISO week is *derived*. Verified consistent:
`2026-08-10` is ISO 2026-W33-1. If W4 clamps a requested week to the current term, trusting the
request silently mislabels every event.

**Bug B20.** Kotlin ids are `w4-{id}` from `(?:id|class_id|group_id)=(\d+)` — an AC class 42 and an
EA group 42 collide after `mergeWeeks`. Prefix with the source: `"ac-w4-42"` / `"ea-w4-42"`.

**Edge cases [V]:** columns may be entirely empty (holiday week — the only case we have captured);
Home always renders 7 columns including the weekend; Sat/Sun carry `rotation-day no-classes`;
the EA line reads `No EA` when there is nothing; the gutter column has 15 `.cell`s but a page with a
different `tt_end_hour` will have a different count (the Android fixture uses 17 → 2 cells) so never
hardcode 15.

**Fixtures:**
- `Fixtures/W4/timetable-home-week33.html` — **[V]**, the real `#timetable` block (holiday week,
  zero periods) copied out of `UWCRCN W4.html` with names scrubbed.
- `Fixtures/W4/timetable-mytimetable-termtime.html` — **[U] placeholder**, port
  `android/app/src/test/resources/w4/timetable-week.html` but head it with
  `<!-- SYNTHESIZED, not a capture. Replace with a real academics/timetable/mytimetable body. -->`.

**Assertions:**
- Real fixture: `days.count == 7`; `days[0].date == 2026-08-10` (Oslo); `days[0].dayName == "Monday"`;
  `days[0].rotationDay == "Day 1"`; `days[5].isNoClasses == true`; `days[5].rotationDay == "Weekend"`;
  `days[0].eaNote == "No EA"`; **`days.allSatisfy { $0.events.isEmpty }`**;
  `week.week == 33 && week.year == 2026`; `startHour == 7 && endHour == 22`;
  exactly one day has `isToday == true` (the Friday column, `column current`).
- Regression test for **B1/§0.5**: `parseWeek` must find 7 day columns on a document with two
  `#timetable` ids. Assert `days.count == 7` on the *unmodified* Home markup — a `getElementById`
  port fails this and returns 0.
- Synthesized fixture (clearly marked): Monday has `Biology HL` in `A 2.1` 08:00–09:00;
  Wednesday `TOK` 09:00–11:00; geometry-only block (no `.datetime`) with `top:120px; height:119px`
  and `tt_start_hour = 7` → 09:00–10:59.
- Time-range regex accepts `8:00 — 9:00` (U+2014), `8:00 – 9:00` (U+2013) and `8:00 - 9:00`.
- Timezone: parse the fixture with `TimeZone.default` forced to `America/New_York`; the Monday
  event must still be 08:00 Oslo.

**Priority: v1.**

---

## 5. `ICSCalendarParser` + `SchoolCalendar` — the overlay

**Replaces:** nothing (new). Optional in v1.

**Sources:**
- Public college calendar **[V]** (`UWCRCN W4.html:255-257` embeds `#calendar > iframe`, and
  `android/.../schedule/SchoolCalendar.kt:17-19` resolves it to)
  `https://calendar.google.com/calendar/ical/calendar%40uwcrcn.no/public/basic.ics` — no auth.
- Personal W4 feeds, `academics/feeds` (README §4.8): `academics/feeds/acttical`, `eattical`,
  `combottical`, `sassttical` + the four `…rss` variants, each with `token=<secret>`. **[U]** —
  never fetched. **The token is password-equivalent: Keychain only, never logged, never in a
  fixture.**

**Format:** iCalendar. Port `android/.../schedule/IcsCalendarParser.kt` (541 lines) essentially
verbatim; it already handles line unfolding, `VALUE=DATE`, `Z`/UTC, `TZID=`, exclusive all-day
`DTEND`, `DURATION`, `RRULE` (DAILY/WEEKLY/MONTHLY/YEARLY + INTERVAL/UNTIL/COUNT/BYDAY), `EXDATE`,
`STATUS:CANCELLED`, `\n`/`\,` unescaping and HTML-in-DESCRIPTION stripping.

```swift
enum ICSCalendarParser {
    static func events(ics: String,
                       from: Date, toExclusive: Date,
                       zone: TimeZone = W4Dates.zone,
                       idPrefix: String = "gcal-",
                       source: W4EventSource = .schoolCalendar) -> [ScheduleEvent]
}
```

**Timezone:** UTC (`…Z`) instants convert to Europe/Oslo; floating datetimes are already Oslo;
`VALUE=DATE` becomes an all-day event anchored at Oslo midnight. Note **B21**: the Kotlin
`parseUtcDateTime` hardcodes `ZONE_OSLO` and ignores its `zone` parameter — in Swift, thread the
zone through properly.

**Edge cases:** folded lines (a continuation starts with SP/TAB); an all-day `DTEND` is exclusive,
so a 14→15 Aug event covers **only** the 14th; `STATUS:CANCELLED` is skipped entirely; recursion is
capped (400 daily / 80 weekly / 36 monthly / 8 yearly iterations) so a runaway RRULE cannot hang the
UI; `COUNT` includes `DTSTART` so counted rules expand from the start, not from the range.

**Fixture:** `Fixtures/W4/school-calendar.ics` — port
`android/app/src/test/resources/w4/school-calendar.ics` (7 VEVENTs covering all-day, multi-day,
UTC-timed, folded SUMMARY, weekly RRULE, escaped comma, cancelled). It contains no personal data.

**Assertions** for the week 10–16 Aug 2026: `Year 1 arrival in Bergen` is all-day on 14 Aug only;
`Year 2 Red Cross Day` (13→16 exclusive) expands to 13, 14, 15 and **not** 16;
`First College Meeting` `20260818T113000Z` → 13:30 Oslo on 18 Aug (outside the range ⇒ absent, and
present when the range is extended); `Partial eclipse visible in Norway` proves unfolding;
`Advisor check in` weekly BYDAY=MO produces the 10 Aug occurrence from a 2025 DTSTART;
`Staff Intro week, campus` proves `\,` unescaping; `Should not appear` is absent.

**Priority: v1.5** (v1 if the timetable capture slips — an ICS week is better than nothing).

---

## 6. `W4AssessmentParser` — Lektier + Opgaver, merged

**Replaces:** `ios/BetterW4/AssignmentParser.swift` — **deleted**. `Assignment`,
`AssignmentDetail`, `AssignmentFile`, `AssignmentSubmission` in `AssignmentModels.swift` are deleted
with it (Lectio "afleveringer" have no W4 analogue). `HomeworkEntry`/`HomeworkItem` are replaced by
the model below. `ScheduleParser.parseHomeworkOverview` is deleted (§4).

**Routes:**

| Action | Route |
|---|---|
| My assessments (month calendar) | `academics/deadlines` **[V]** sdmenu |
| All assessments | `academics/classes/assessments/all` **[V]** sdmenu |
| Confirm done / revert / save / create / delete | `academics/deadlines/{confirm,revert,edit,create,delete}` + `&month=&year=&uwc_id=` **[I]** |

The write routes come from a page-level `var ajax_urls = {confirm: …, revert: …, save: …, create: …,
delete: …}` **[I]**. Month navigation is `&month=MM&year=YYYY` **[I]**.

**DOM — [U]. This is the biggest hole in the spec.** Nothing about the assessments calendar has been
captured. The Android parser (`W4AssessmentParser.kt:29-58`) reads:

```
a.assessment-link[data-assessment-id]
  data-assessment-type   "class" | "student"
  data-status            "pending" | "done"
  data-assessment-date   "10-Aug-2026"
  data-subject-name      "Biology"
  data-class-id          "BIO HL"
  data-teacher-name      "Jane Doe"
  data-unit              "Cell biology"
  data-days-left         "4"
  data-css-class         "new" | "overdue"
  data-editable          "1"
```
inside `table.calendar tr.days td.day > div.day-header` (day number) + `div.day-content div.assessments`,
with `a.assessment-icon` as the "add" affordance, and forms `#student_assessment_form` /
`#add_assessment_form` carrying `assessment_id`, `student_assessment_id`, `student_deadline_date`,
`student_assessment_title` and Yii buttons `yt0…yt6`.

**Every one of those attribute names is invented** — the Android fixture
`app/src/test/resources/w4/assessments-calendar.html` is hand-written, not a capture. The only
independent corroboration is README §5.2, which lists the *form field* names
(`assessment_id`, `student_assessment_id`, `student_deadline_date`, `student_assessment_title`) and
the button labels `Confirm done` / `Revert to pending` / `Save` / `Delete` from a live page.

**Required capture:** `GET index.php?r=academics/deadlines` in term time, plus the request/response
of one *Confirm done*. Until then this parser ships behind a "best effort" flag: parse what matches,
render nothing if nothing matches, and never write.

**Bug B11.** The date fallback regexes `month=(\d+)` / `year=(\d{4})`
(`W4AssessmentParser.kt:90-91`) do **not** match a declaration like `var month = 08 - 1;` (spaces
around `=`); they only match by accident inside the `ajax_urls` query strings. Parse both forms:
`/\bmonth\s*=\s*(\d{1,2})/` and `/[?&]month=(\d{1,2})/`, and prefer `data-assessment-date` over
either.

**Model:**

```swift
enum W4AssessmentKind: String, Codable, Sendable { case classAssigned = "class", student }
enum W4AssessmentState: String, Codable, Sendable { case pending, done, overdue }

struct W4Assessment: Identifiable, Codable, Equatable, Sendable {
    let id: String                  // "class:42" / "student:99"
    let rawID: String               // "42"
    let kind: W4AssessmentKind
    let title: String
    let date: Date?                 // Oslo
    let subject: String?
    let classCode: String?
    let teacher: String?
    let unit: String?
    let daysLeft: Int?
    let state: W4AssessmentState
    let isEditable: Bool
    var isDone: Bool { state == .done }
}

struct W4AssessmentAjaxURLs: Codable, Sendable {
    let confirm: String; let revert: String; let save: String; let create: String; let delete: String
}

enum W4AssessmentParser {
    static func parse(_ html: String) throws -> [W4Assessment]
    static func parseAjaxURLs(_ html: String) throws -> W4AssessmentAjaxURLs?
    /// class item -> ["assessment_id": raw];  student item -> ["student_assessment_id": raw]
    static func statusFields(for item: W4Assessment) -> [String: String]
}
```

**Done state is native on W4** (README §7) — do **not** rebuild BetterLectio's local "done" store as
the source of truth. Keep a local optimistic overlay only until the next refresh confirms.

**Edge cases:** items with no date (fall back to the containing `td.day > .day-header` day number +
the page's month/year); `td.no-day` padding cells in the calendar grid; student-created items with
no subject/teacher; overdue styling arriving via `data-css-class` **or** a class on the anchor.

**Fixture:** `Fixtures/W4/assessments-calendar.html` — ported from Android, **marked SYNTHESIZED in
a leading comment**, plus `Fixtures/W4/assessments-empty.html` (a calendar with only `td.no-day`).

**Assertions:** 2 items; `class:42` → title `Lab report`, subject `Biology`, teacher `Jane Doe`,
date 10 Aug 2026 Oslo, `state == .pending`; `student:99` → `state == .done`, kind `.student`;
`parseAjaxURLs()?.confirm` contains `academics/deadlines/confirm`;
`statusFields` picks `assessment_id` vs `student_assessment_id` by kind;
empty fixture → `[]`, no throw. **Add an explicit test comment: "these assertions verify the parser
against a synthesized fixture; they do not verify W4."**

**Priority: v1** (it is the Lektier tab). Write actions (confirm/revert) **v1**, create/edit/delete
**v1.5**, both gated on the capture landing.

---

## 7. `W4MailerParser` + `W4MailDetailParser` — Beskeder

**Replaces:** `ios/BetterW4/MessageParser.swift` — **rewritten**, ~85 % smaller. Delete every
`__doPostBack` / `s_m_Content_Content_*` / context-card / reaction / edit-audit path. Delete
`MessageReactionProtocol.swift`, `MessageEditAudit.swift`, `MessageSignature.swift`,
`BBCodeRichEditor.swift` (W4 uses TinyMCE HTML, not BBCode) and the reaction/edit halves of
`MessageModels.swift`. `MessageFolder` keeps only Inbox + Sent.

**Routes [V]** (School sdmenu, `School info @ UWCRCN.html`):

| Surface | Route |
|---|---|
| Inbox | `mailer/inbox` |
| Sent | `mailer/archive` |
| Read one | `mailer/view&id={n}` **[I]** (the id is the `id=` in the row's link) |
| Compose freeform | `mailer/send&type=freeform` |
| Add recipients | `mailer/extra&type=freeform` |

Compose fields (README §5.2): `MailerForm[subject]`, `MailerForm[message]` (TinyMCE **HTML**),
`MailerForm[attachment][]` (multipart, ≤5 × 2 MB), `MailerForm[sendCC]`,
`MailerForm[attachmentSource]=upload`, plus the clicked Yii button (`yt0`).

**DOM.** The list is a Yii grid (§0.4). `.grid-view table.items` is **[V]** (styled in
`css/main.css`); the column set is **[I]**: Inbox = `Received | From | Subject`,
Sent/archive = `Send date | Subject | Attachment` (README §6). Header-driven column indexing —
as `W4MailerParser.kt:21-27` does — is the right defensive shape; **keep it**, do not hardcode
indices.

```swift
struct W4MailFolder: Identifiable, Hashable, Sendable {
    let id: String            // "inbox" | "archive"
    let title: String         // "Inbox" | "Sent"
    let route: String
    static let inbox = W4MailFolder(id: "inbox", title: "Inbox", route: "mailer/inbox")
    static let sent  = W4MailFolder(id: "archive", title: "Sent", route: "mailer/archive")
}

struct W4MailSummary: Identifiable, Codable, Equatable, Sendable {
    let id: String            // numeric id from ?id= in the subject link
    let subject: String
    let from: String?         // nil in the Sent folder
    let receivedAt: Date?     // Oslo
    let folderID: String
    let isUnread: Bool        // tr.unread / .unread  [U]
    let hasAttachment: Bool   // attachment column non-empty  [U]
    let route: String?        // href as captured
}

struct W4MailDetail: Codable, Equatable, Sendable {
    let id: String
    let subject: String
    let from: String?
    let to: [String]
    let sentAt: Date?
    let bodyHTML: String              // TinyMCE HTML, rendered via HTMLContentRenderer
    let attachments: [W4MailAttachment]
}
struct W4MailAttachment: Identifiable, Codable, Equatable, Sendable {
    let id: String; let name: String; let url: String
}

enum W4MailerParser {
    static func parseList(_ html: String, folder: W4MailFolder) throws -> [W4MailSummary]
    static func parsePager(_ html: String) throws -> W4Pager?      // §0.4, [U]
}
enum W4MailDetailParser { static func parse(_ html: String, id: String) throws -> W4MailDetail }
```

**Bug B18.** `W4MailerParser.kt:54-57` derives a row id from `row.id().removePrefix("yw0_")`.
Yii's `CGridView` does not put ids on `<tr>` unless `rowHtmlOptionsExpression` is configured.
Rely on `[?&]id=(\d+)` inside the row's anchor; fall back to a stable hash of
`(folder, subject, receivedAt)`, **not** `subject.hashCode()` (which is unstable across launches on
some platforms and collides).

**Bug B9** applies: the Kotlin `td.empty` check misses Yii's `span.empty`.

**Mail detail is [U] and currently a stub.** `android/.../messages/MessageRepository.kt:99-124`
does not parse `mailer/view` at all — it dumps `#content_inner` into one entry. iOS should do the
job properly, but the DOM is unknown. v1: render `#content_inner` through `HTMLContentRenderer`
and extract subject from `#content_inner h1, h2` and any `a[href*=download], a[href*=attachment]`
as attachments **[I]**. Upgrade once `mailer/view&id=…` is captured.

**Dates:** `14-Aug-2026 12:04` → `W4Dates.parseDateTime` **[I]**; Oslo.

**Edge cases:** empty inbox (§0.4); a `From` column absent in Sent (index lookup returns nil, not a
shifted column); subjects containing `&amp;`; pagination (§0.4); the mailer is **one message, not a
thread** — do not port the Lectio thread/reply model.

**Fixtures:** `Fixtures/W4/mailer-inbox.html` (**[I]**, ported + marked),
`Fixtures/W4/mailer-inbox-empty.html`, `Fixtures/W4/mailer-archive.html`.

**Assertions:** inbox → 2 rows; `[0].id == "12"`, subject `Welcome to term 1`, from `House Leader`,
`receivedAt` == 2026-08-14 12:04 Oslo; `[1].id == "7"`; ordering preserved from the DOM;
empty fixture → `[]`; archive fixture (no `From` header) → `from == nil` and the subject is still
column-matched, not index-2-by-luck.

**Priority: v1** (list + read). Compose/attachments **v1.5**.

---

## 8. `W4AbsenceParser` — meters and registrations

**Replaces:** the absence half of `ios/BetterW4/StudentParser.swift`
(`parseAbsenceReport`, `parseAbsenceSummary`, `parseMissingReasons`, `parseAbsenceRegistrations`,
`parseAbsenceTable`, `extractAbsenceRegistrationId`, `extractW4ActivityId`, `parseActivityDetails`,
`parseAbsenceDate`) — **all deleted**, replaced by this parser. `AbsenceModels.swift` is retyped:
W4 counts absences and latenesses as **integers**, not Lectio percentages.

**Routes:**

| Surface | Route |
|---|---|
| Home meters | `site/index` **[V]** |
| AC absences | `people/students/absences` **[V]** sdmenu |
| EA absences | `people/students/eaabsences` **[V]** sdmenu |
| Register absences (form) | `people/students/absences/register` **[V]** sdmenu |

**Home meters — [V]**, `UWCRCN W4.html:239-249`:

```html
<div id="absences">
  <div id="academic-absences">
    <h3>Academics Attendance Meter</h3>
    <p>You have 0 absences and 0 latenesses so far<br>
       <a href="…?r=people/students/absences">View attendance</a></p>
  </div>
  <div id="ea-absences">
    <h3>EA Attendance Meter</h3>
    <p>You have 0 absences and 0 latenesses so far<br>
       <a href="…?r=people/students/eaabsences">View attendance</a></p>
  </div>
</div>
```

Regex **[V]** on the captured prose: `/You have (\d+) absences? and (\d+) latenesse?s? so far/i`.
`#hello` and `#academic-absences` are also confirmed as real ids by `homepage.css` **[V]**
(`#hello, #academic-absences {…}`, `#ea-absences {…}`), along with sibling meters that exist for
other roles: `#advisor-absences`, `#mentor-absences`, `#admin-absences`, `#staff-absences` — a
student will not see those, but don't crash on them.

**List page — [U].** Never captured. Assume a Yii grid (§0.4) with header-driven columns:
`Date | Period | Class/Activity | Type | Status | Comment` **[I]**.

**Bug B14 — real and cheap to get right.** `css/tables.css` **[V]** styles
`tr.prearranged_1`, `tr.prearranged_2`, `tr.medical_1`, `tr.medical_2`. Absence *category* is
therefore encoded in the **row class**, not only in a "Type" column — and the timetable block
classes `.present` / `.normal` / `.prearranged` / `.absence`
(`display_full_timetable.css:96-110`, **[V]**) use the same vocabulary. Parse both:
row class first, "Type" text second.

**Model:**

```swift
enum W4AbsenceSource: String, Codable, Sendable { case academic = "ac", extraAcademic = "ea" }
enum W4AbsenceCategory: String, Codable, Sendable { case absence, lateness, prearranged, medical, present }

struct W4AbsenceMeter: Codable, Equatable, Sendable {
    let absences: Int; let latenesses: Int
    var total: Int { absences + latenesses }
}
struct W4AbsenceRegistration: Identifiable, Codable, Equatable, Sendable {
    let id: String                 // registration id from the row link when present, else a content hash
    let source: W4AbsenceSource
    let date: Date?                // Oslo
    let period: String?            // "P3"
    let subject: String?           // class / activity
    let category: W4AbsenceCategory
    let status: String?
    let teacher: String?
    let note: String?
}
struct W4AbsencePage: Codable, Equatable, Sendable {
    let source: W4AbsenceSource
    let meter: W4AbsenceMeter?
    let registrations: [W4AbsenceRegistration]
}

enum W4AbsenceParser {
    static func parseHomeMeters(_ html: String) throws -> (academic: W4AbsenceMeter?, ea: W4AbsenceMeter?)
    static func parseList(_ html: String, source: W4AbsenceSource) throws -> W4AbsencePage
}
```

**Bug B19.** `W4AbsenceParser.kt:140-141` builds the row id from the **row index**
(`…|index.toString()`). Sorting a Yii grid (`a.sort_asc`/`a.sort_desc` are **[V]**) or paging
renumbers everything and the app's diffable data source will animate the whole list. Use a
content hash of `(source, date, period, subject, category)` until a registration id is captured.

**Edge cases:** zero-absence students are the normal case (**[V]**: the capture reads
`0 absences and 0 latenesses`) — an empty list must render "No absences", not an error;
`latenesses` is the plural W4 actually writes (not "latenesss"); the meter can also be scraped from
the list page itself; a date cell may be `dd-MMM-yy` (2-digit year).

**Fixtures:** `Fixtures/W4/home.html` (reused, **[V]**), `Fixtures/W4/absences-ac.html` and
`Fixtures/W4/absences-ea-empty.html` (**[I]**, ported + marked).

**Assertions:** home → `academic == (0, 0)` and `ea == (0, 0)` (from the real capture — assert the
*zero* case, that is what we actually have); AC fixture → 3 rows, row 2 `category == .lateness`,
row 3 date parses from `11-Aug-26`; EA empty fixture → `registrations.isEmpty`,
`meter == (0, 0)`, no throw; a row carrying `class="prearranged_1"` → `.prearranged` even when the
Type column says `Absence`.

**Priority: v1** (meters + lists — they are in the MVP list).

---

## 9. `W4AbsenceRegisterFormParser` — the only student write form besides mail

**Replaces:** `ios/BetterW4/AbsenceEditFormParser.swift` — **deleted**. Every selector in it is
ASP.NET (`select[name*=StudentReasonDD]`, `cancelStudentNote`, `savecancelapplyBtn`,
`__EVENTTARGET`, `fravaer_aarsag.aspx`) and every user string in it is Danish.

**Route:** `people/students/absences/register` **[V]** (Academics sdmenu).

**Fields (README §5.2):** `StudentAbsenceForm[absence_date]` — a jQuery-UI datepicker, `dd-M-yy`
en-GB, so `14-Aug-2026` — plus **per-slot checkboxes injected by JS**, names **[U]**.

**This form has never been captured**, so the parser must be generic rather than hardcoded:

```swift
struct W4Form: Sendable {
    let action: String                    // resolved absolute URL
    let method: String                    // "post"
    var fields: [String: String]          // every input[name] / select / textarea, pre-filled
    let submitButtons: [(name: String, value: String)]   // yt0, yt1, …
    let checkboxes: [W4FormCheckbox]      // name, value, label, isChecked
    let datePickers: [String]             // field names carrying class "hasDatepicker"/"datepicker"
}
enum W4FormParser {
    static func parse(_ html: String, selector: String) throws -> W4Form?
    static func body(_ form: W4Form, overrides: [String: String], clicking button: String?) -> String
}
```

`W4FormParser` is shared with login/2FA (reviewer-notes §5), the mailer compose form, the
assessments forms (§6) and resource booking. Encode `application/x-www-form-urlencoded`, include the
clicked Yii button name/value, and **never** emit `__VIEWSTATE`.

**Edge cases:** no CSRF token exists on W4 (README §3) — do not invent one; unchecked checkboxes are
simply absent from the body; the datepicker input's `value` must be written in `dd-MMM-yyyy` en-GB.

**Fixture:** `Fixtures/W4/absences-register.html` — **[U] placeholder**; the file cannot be written
honestly until captured. Ship the generic `W4FormParserTests` against a small synthetic Yii form
instead (hidden + text + select + 2 checkboxes + `yt0`) and assert:
body contains every hidden field, only checked checkboxes, the clicked button, and no
`__VIEWSTATE`; percent-encoding of `[` `]` in `StudentAbsenceForm[absence_date]`.

**Priority: v1.5.**

---

## 10. `W4GradeParser`

**Replaces:** `ios/BetterW4/GradeParser.swift` — **rewritten**. Delete the Lectio specifics:
`#s_m_Content_Content_karakterView_KarakterGV`, `th.OnlyDesktop`, `data-w4contextcard`,
`title="XPRSFag: … Kilde: … Vægt: …"`, `canonicalColumnKey`'s Danish column names,
`extractBlockedTerm`. Keep the **shape**: dynamic columns keyed by header slug, so an unknown
column never shifts values (that design is good and `GradeParserTests.testMissingKnownColumnsDoNotShiftValues`
should survive, retargeted at W4 markup).

**Routes:** `academics/grades/grades` **[V]**, `academics/grades/grades/sat` **[V]**,
`academics/transcripts/transcripts` **[V]**, `academics/rop` **[V]**.

**DOM — [I], with one strong [V] hint.** `css/main.css` **[V]** contains

```css
table.grades tr.table_1_bg td.anticipated { … }
table.grades tr.table_2_bg td.anticipated { … }
table.grades th.anticipated { … }
.effort-grade-meets-expectations { … }
.effort-grade-almost-meets-expectations { … }
.effort-grade-does-not-meet-expectations { … }
```

**Bug B13.** `W4GradeParser.kt:23` looks for `table.items` and only falls back to `table`. The real
grades page is `table.grades` with alternating `tr.table_1_bg` / `tr.table_2_bg` (`css/tables.css`
**[V]**), an `anticipated` (predicted) column, and separate **effort grades** with their own
three-level class vocabulary. Selector order for iOS:
`#content_inner table.grades` → `#content_inner .grid-view table.items` → `#content_inner table`.

```swift
struct W4GradeColumn: Identifiable, Codable, Hashable, Sendable {
    let id: String          // slug of the header, unique-suffixed on collision
    let label: String
    let isAnticipated: Bool // th.anticipated
}
struct W4GradeCell: Codable, Equatable, Sendable {
    let value: String
    let effort: W4EffortGrade?    // .meets | .almostMeets | .doesNotMeet, from .effort-grade-*
}
struct W4GradeRow: Identifiable, Codable, Equatable, Sendable {
    let id: String          // slug(subject + level)
    let subject: String     // "Biology"
    let level: String?      // "HL" / "SL"
    let teacher: String?
    let cells: [String: W4GradeCell]   // keyed by column id
}
struct W4GradesReport: Codable, Equatable, Sendable {
    let columns: [W4GradeColumn]; let rows: [W4GradeRow]; let alerts: [String]
}
enum W4GradeParser { static func parse(_ html: String) throws -> W4GradesReport }
```

**Edge cases:** blank cells for un-graded subjects (`–` U+2013 and `-` both mean "no grade");
duplicate header labels must get unique keys (keep the existing `-2` suffix behaviour);
alerts from `div.errorMessage`, `div.error`, `div.warning`, `div.note` **[V]**;
IB grades are integers 1–7 but predicted/effort columns are free text — never coerce to `Int`.

**Fixture:** `Fixtures/W4/grades.html` (**[I]**, ported + marked). Add
`Fixtures/W4/grades-tablegrades.html` shaped as `table.grades` with `th.anticipated` and
`.effort-grade-meets-expectations` to lock in B13.

**Assertions:** 3 rows; `Mathematics` + level `HL` + teacher `A. Newton`; column ids
`["predicted", "final"]` in server order; `Biology.cells["final"] == nil` (blank, not `""`);
the `table.grades` fixture parses with the anticipated column flagged and effort parsed.

**Priority: v1.5.**

---

## 11. `W4PeopleParser` + `W4ProfileParser` — directory

**Replaces:** `ios/BetterW4/DirectoryParser.swift` — **deleted** (542 lines of Lectio dropdown JSON,
`gymId`, prefixed ids `S…`/`T…`/`HE…`, synthetic classes). `DirectoryModels.swift` collapses to the
struct below; `DirectoryStore.swift` (41 KB) loses everything keyed on `gymId` and prefixed ids.
`StudentParser.parseBirthday` is replaced by §13.

**Routes [V]** (School sdmenu):

| Surface | Route |
|---|---|
| All students | `people/students/all` |
| 1st / 2nd year | `people/students/firstyear` / `people/students/secondyear` |
| By name / preferred / country / house | `people/students/byname` / `bypreferred` / `bycountry` / `byhouse` |
| Current staff / on leave | `people/staff/current` / `people/staff/onleave` |
| My teachers / group leaders | `people/students/staff` (`&type=teachers` \| `&type=leaders`) |
| Public student profile | `people/students/student&uwc_id={id}` |
| Public staff profile | `people/staff/staff&uwc_id={id}` |
| Own profile | `site/profile` |
| Visitors | `people/visitors`, `people/visitors/add` |
| On duty | `people/onduty`, `people/onduty/schedule`, `people/onduty/print` |

**Identity + photos [V].** `UWCRCN W4.html:201-214`:

```html
<li><a href="…?r=people/staff/staff&amp;uwc_id=nc16jmac">
      <img class="photo" width="40" src="…/nc16jmac_thumb.jpg" alt="Photo of nc16jmac"></a></li>
<li><a href="…?r=people/students/student&amp;uwc_id=nc25wnas">
      <img class="photo" width="40" src="…/nc25wnas_thumb.jpg" alt="Photo of nc25wnas"></a></li>
```

- uwc id pattern **[V]**: `nc` + 2-digit entry year + letters — `/\b(nc\d{2}[a-z]+)\b/i`.
  Staff use the same scheme (`nc16jmac`, `nc19ndem`).
- Photo URL **[I]**: `https://w4.uwcrcn.no/files/user_photos/{uwc_id}_thumb.jpg`. The captures show
  only browser-rewritten local paths (`./UWCRCN W4_files/nc16jmac_thumb.jpg`), so the live directory
  is inferred from `android/.../directory/W4PeopleParser.kt:91-92` and the `people-all` fixture.
  `/images/user.png` is W4's missing-photo placeholder — map it to `nil`, never render it.
  Rate-limit avatar fetches (README §5.5).
- `alt="Photo of {uwc_id}"` **[V]** — useful as an id fallback, but it is **not** a display name;
  `W4PeopleParser.kt:100` strips the literal prefix `Photo of `, keep that.

List markup: `ul.user-list > li` with two anchors (photo + name) is **[I]** (the Android fixture).
The Yii grid variant is **[V]**-adjacent: `css/main.css` styles
`.grid-view tr.bold td.student-name` and `td.entry-name`, plus `tr.online td.status` /
`tr.offline td.status` — so at least one people list **is** a `CGridView` with named cells.
Support both: `a[href*=uwc_id]` anywhere (defensive), then enrich from `td.student-name`,
`td.entry-name`, `td.status`.

`Current applicants at UWCRCN.html` **[V]** shows the empty state for a people list:
`<div class="note">No users found</div>`.

**Profile [I]** — `table.detail-view` (Yii `CDetailView`) with `th` label / `td` value; fields
seen in README §6: UWC id, year, first/last/preferred name, pronouns, country, email
`{uwc_id}@uwcrcn.no`, NC/SO, last login, photo.

```swift
enum W4PersonKind: String, Codable, Sendable { case student, staff }
struct W4Person: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { uwcID }
    let uwcID: String            // "nc26jban"
    let name: String
    let kind: W4PersonKind
    let subtitle: String?        // "Denmark · 1st year" / "Advisor, Teacher"
    let photoURL: URL?
    var email: String { "\(uwcID)@uwcrcn.no" }
    var profileRoute: String {
        kind == .student ? "people/students/student&uwc_id=\(uwcID)" : "people/staff/staff&uwc_id=\(uwcID)"
    }
}
struct W4PersonProfile: Codable, Equatable, Sendable {
    let person: W4Person
    let year: String?; let house: String?; let country: String?
    let pronouns: String?; let birthday: String?; let lastLogin: String?
    let fields: [(label: String, value: String)]   // everything else, rendered generically
}
enum W4PeopleParser {
    static func parseList(_ html: String) throws -> [W4Person]
    static func parseProfile(_ html: String) throws -> W4PersonProfile?
}
```

**Kind detection [V]:** `people/staff/staff` in the href ⇒ `.staff`, `people/students/student` ⇒
`.student`. Do **not** use the Kotlin heuristic
`W4PeopleParser.kt:67-73` (which sniffs the whole document for the substring `people/staff`) — on
Home that substring is present because of the *birthday* links, so a student's own profile page
would be misclassified.

**Edge cases:** the same person appears twice per `<li>` (photo anchor + name anchor) → merge by
uwc id, preferring the anchor with real text and the `_thumb.jpg` src (port
`DirectoryParser.mergeEntity` / `pickAvatar` from `android/.../directory/DirectoryParser.kt:10-46`);
`1<sup>st</sup> year` renders as `1st year` via `text()`; the whole directory is ~200 students —
fetch serially, cache aggressively; **PII** — never log names or ids.

**Fixtures:** `Fixtures/W4/people-all.html`, `Fixtures/W4/people-empty.html` (**[V]** — the real
`<div class="note">No users found</div>` body), `Fixtures/W4/site-profile.html`. Scrub every real id
and name to `nc00aaa` / invented names first (reviewer-notes §8).

**Assertions:** list → 3 people, 2 students + 1 staff; the placeholder `/images/user.png` yields
`photoURL == nil` while `_thumb.jpg` yields a URL; each person appears **once** despite two anchors;
`profileRoute` differs by kind; `people-empty` → `[]`; profile → uwc id, `year == "1"`,
`pronouns == "he/him"`, email derived not scraped.

**Priority: v1.5.**

---

## 12. `W4DocumentsParser` — CMS

**Replaces:** nothing (new). Reuses the `HTMLContentRenderer` extracted from
`ScheduleParser.parseLessonContent` (§4).

**Routes [V]:** `documents` (index), `documents/index&folder_id={n}`, `documents/index&page_id={n}`,
and the EA CMS `extraacademics/documents`. Home's Links block **[V]** deep-links pages:
`documents/index&page_id=870` (Bakehus), `871` (Learning support), `1004` (Lavvo),
`extraacademics/documents/index&page_id=79` (Haugland times).

**DOM — [V], both from the HAR body and the saved page:**

```html
<div id="content_inner">
  <h2>Documents</h2>
  <ul class="folder-list">
    <li><a class="folder" href="/index.php?r=documents/index&amp;folder_id=27">Internal Information</a></li>
    <li><a class="folder" href="/index.php?r=documents/index&amp;folder_id=34">Outdoor Department</a></li>
  </ul>
</div>
```

`Documents_files/cmsrenderer.css` **[V]** gives the rest of the vocabulary without a capture:

| Selector | Meaning |
|---|---|
| `ul.folder-list li a.folder` | folder tile (folder_128.png) |
| `ul.folder-list li a.page` | page tile (page_128.png) |
| `div.up > a` | "up one level" |
| `div.new > a` | "new page/folder" (permission-gated) |
| `.page-title`, `.page-details`, `.page-content` | **a rendered page** |
| `#search_results li`, `#search_results div.smaller` | CMS search |
| `#page_title`, `#keywords`, `#page_content`, `#buttons` | the edit form (staff) |

```swift
enum W4DocumentKind: String, Codable, Sendable { case folder, page }
struct W4DocumentNode: Identifiable, Codable, Equatable, Sendable {
    let id: String            // folder_id or page_id
    let title: String
    let kind: W4DocumentKind
    let route: String
}
struct W4DocumentListing: Codable, Equatable, Sendable {
    let title: String
    let items: [W4DocumentNode]
    let parentRoute: String?          // div.up a
    let page: W4DocumentPage?         // non-nil when this IS a page
}
struct W4DocumentPage: Codable, Equatable, Sendable {
    let title: String                 // .page-title, else h1/h2
    let details: String?              // .page-details (author/date line)
    let contentHTML: String           // .page-content
}
enum W4DocumentsParser { static func parse(_ html: String) throws -> W4DocumentListing }
```

**Bug B16.** `W4DocumentsParser.kt:39-46` decides "this is a page" by *absence* of folders/pages and
then dumps `#content_inner` minus the first heading. Use the real classes: a page is
`#content_inner .page-content` **[V]**; fall back to the heuristic only if that is missing.

**Edge cases:** a folder can contain both sub-folders and pages (`a.folder` + `a.page`); breadcrumbs
live in `#breadcrumb .crumbs a` **[V]**; page content is TinyMCE HTML — sanitize and render, never
inject into a `WKWebView` with JS enabled; Documents has **no** `.sdmenu` **[V]**.

**Fixtures:** `Fixtures/W4/documents-index.html` (**[V]** — extract the HAR entry 0 body verbatim;
it contains no personal data beyond the Welcome name, which gets scrubbed) and
`Fixtures/W4/documents-page.html` (**[I]**, hand-built around `.page-title`/`.page-content`).

**Assertions:** index → title `Documents`, 2 folder nodes, ids `27` and `34`, routes
`documents/index&folder_id=27`, `page == nil`; page fixture → `page?.title`, non-empty
`contentHTML`, `items.isEmpty`.

**Priority: v1.**

---

## 13. `W4HomeParser` — birthdays, announcements, links

**Replaces:** nothing (new). Absorbs `StudentParser.parseBirthday`.

**Route:** `site/index` **[V]**. Related: `people/birthdays` **[V]**, `site/rss` **[V]**.

**DOM [V]** — `UWCRCN W4.html:83-266`, corroborated by `homepage.css`:

```
#homepage_info
  #top-row
    #top1 > #timetable                    (§4)
    #top2 > #birthdays-announcements
        #birthdays
          h3 "Birthdays!"
          #birthdays-today    > h4 "Today"    > div > ul > li > a[href*=uwc_id] > img.photo
          #birthdays-tomorrow > h4 "Tomorrow" > div > ul > li > a[href*=uwc_id] > img.photo
          div.calendar > a[href*=people/birthdays]
        #announcements > #announcements-content
          h3 "College Announcements"
          div.rss > a[href*=site/rss]
          <p>No announcements...</p>            <-- EMPTY STATE, captured
    #top3 > #hello-absences
        #hello  > p "Hello {name}" + p > a[href*=people/students/student&uwc_id=…] "W4 public profile"
        #absences > #academic-absences / #ea-absences      (§8)
  #bottom-row
    #bottom1 > #calendar > iframe           (Google calendar embed — see §5)
    #bottom2 > #alerts > #links > h3 "Links" + ul > li > a
```

The populated announcement shape is **[V]** from `homepage.css`:
`#announcements-content ul li dl dt`, `… dl dd`, `… dl dt span` — i.e.
`<ul><li><dl><dt>Title <span>date</span></dt><dd>body</dd></dl></li></ul>`, plus
`.announcement-content` / `.announcement-meta`. The captured page has none, so item-level parsing
is **[I]**; prefer the RSS feed `site/rss` for announcements (it is a stable, public format).

Links block **[V]**, verbatim from `UWCRCN W4.html:262` — 10 entries mixing external and internal:
UWCRCN Extra Academic Website, RCN College Policies Drive, **Trip Form** (`r=academics/trips`),
Høegh Kitchen Booking Form, **ManageBac** (`uwcrcn.managebac.com/login` — do **not** scrape it),
Bakehus (`documents/index&page_id=870`), Haugland times
(`extraacademics/documents/index&page_id=79`), Learning support (`…page_id=871`),
6 Stiar (walks near campus), Lavvo Booking and Information (`…page_id=1004`).
This is **configuration, not code** (README §6) — parse it, do not hardcode it.

```swift
struct W4HomePage: Codable, Equatable, Sendable {
    let greetingName: String?
    let publicProfileRoute: String?
    let week: ScheduleWeek?                 // §4
    let birthdaysToday: [W4Person]
    let birthdaysTomorrow: [W4Person]
    let announcements: [W4Announcement]     // empty when "No announcements..."
    let academicMeter: W4AbsenceMeter?
    let eaMeter: W4AbsenceMeter?
    let links: [W4Link]
}
struct W4Announcement: Identifiable, Codable, Equatable, Sendable {
    let id: String; let title: String; let date: String?; let bodyHTML: String?
}
struct W4Link: Identifiable, Codable, Equatable, Sendable {
    let id: String; let title: String; let url: URL; let isInternalRoute: Bool
}
enum W4HomeParser { static func parse(_ html: String) throws -> W4HomePage }
```

**Edge cases:** `#birthdays-today` may hold an empty `<div>` (no `ul`) → `[]`; birthday entries have
**no name text at all**, only `alt="Photo of nc16jmac"` **[V]** — resolve names lazily via the
directory cache, and show the photo + uwc id in the meantime; `No announcements...` (with the
ellipsis as three dots) is the captured empty state; `#calendar` is an `<iframe>` — extract nothing
from it, use the ICS (§5); one Link title contains a non-ASCII `ø` (`Høegh`) — the page is UTF-8.

**Fixture:** `Fixtures/W4/home.html` (shared with §1/§4/§8), scrubbed.

**Assertions:** `greetingName == "Test Student"`; `publicProfileRoute` contains
`people/students/student&uwc_id=`; `birthdaysToday.count == 3` and `birthdaysTomorrow.count == 1`
(scrubbed ids); every birthday person has a `photoURL` and no display name;
`announcements.isEmpty`; `links.count == 10`; `links` containing `academics/trips` has
`isInternalRoute == true` and the ManageBac link has `isInternalRoute == false`.

**Priority: v1** for links + meters + greeting; birthdays/announcements **v1.5**.

---

## 14. `W4TripsParser` — boarding, first-class

**Replaces:** nothing (new).

**Routes [V]:** `academics/trips` (My trips), `academics/travel/travel.list` (travel forms).
Home also links `academics/trips` as "Trip Form" **[V]**.

**DOM — [U].** A Yii grid (§0.4) whose columns README §6 lists as
`Trip name | Outgoing date/time | Return date/time | Destination | Type | Participants | Status`,
with a `Plan new trip` button and the status vocabulary
`Planning → Pending confirmation → Approved | Cancelled`.
`W4TripsParser.kt:17-31` takes `#content_inner table` and reads cells **positionally** — replace
that with header-driven indexing (as the mailer parser does) so a new column cannot silently shift
`status` into `participants`.

```swift
enum W4TripStatus: String, Codable, Sendable {
    case planning, pendingConfirmation, approved, cancelled, unknown
    init(label: String)   // case/spacing-insensitive match on the captured strings
}
struct W4Trip: Identifiable, Codable, Equatable, Sendable {
    let id: String            // ?id= from the row link, else content hash
    let name: String
    let outgoing: Date?       // Oslo, "20-Sep-2026 08:00"
    let returning: Date?
    let destination: String?
    let type: String?         // "Optional" / …
    let participants: Int?
    let status: W4TripStatus
    let statusLabel: String   // raw, always shown verbatim
    let route: String?
}
enum W4TripsParser { static func parse(_ html: String) throws -> [W4Trip] }
```

**Edge cases:** approval auto-registers pre-arranged absences (README §6) → after a trip refresh,
invalidate the absence cache; `participants` may be a name list rather than a count → keep the raw
string too; empty state per §0.4.

**Fixture:** `Fixtures/W4/trips.html` (**[I]**, ported + marked) + `Fixtures/W4/trips-empty.html`.

**Assertions:** 1 trip; name `Bergen weekend`; `outgoing` == 2026-09-20 08:00 Oslo;
`status == .planning` and `statusLabel == "Planning"`; header-shuffle test — the same fixture with
`Status` and `Participants` columns swapped must still yield `status == .planning`;
empty fixture → `[]`.

**Priority: v1.5.**

---

## 15. `W4RoomParser` — rooms and bookings

**Replaces:** `ios/BetterW4/DirectoryParser.swift`'s room helpers and, in the Android tree,
`feature/directory/RoomParser.kt` — which is **100 % Lectio** (`m_Content_LectioDetailIsland1_pa`,
`FindSkema.aspx?type=lokale`, the Danish string `"Der er ingen data"`, `AspNetQueries.idFromHref`).
**Do not port a single line of it.** It is dead code in the Android app; the iOS equivalent is
deleted outright.

**Routes [V]:** `academics/timetable/room` (School sdmenu → Rooms),
`academics/resources/resources` (Academics sdmenu → Resource bookings).

**DOM — [U].** Nothing captured. `academics/timetable/room` almost certainly renders the same
`#timetable` grid as §4 for a chosen room **[I]** — reuse `W4TimetableParser` with a room selector
rather than writing a second grid parser. Resource booking POSTs
`day, month, year, reservation_id, time_start, time_end, description, resource_id` (README §5.2) —
a `W4FormParser` (§9) client.

```swift
struct W4Room: Identifiable, Codable, Equatable, Sendable {
    let id: String; let name: String; let route: String
}
enum W4RoomParser {
    static func parseRoomList(_ html: String) throws -> [W4Room]         // [U]
    static func parseRoomWeek(_ html: String) throws -> ScheduleWeek     // delegates to §4
}
```

**Fixture:** none until captured. Write no test that pretends.

**Priority: v1.5** (rooms), **later** (booking writes).

---

## 16. Surfaces with no parser yet (deliberately)

`extraacademics/activities/*` (activities, diary `EAGroupStudentModel[outcomes][]`, portfolio,
interviews), `extraacademics/safetynet/mysafetynet` (Period / Status / Average wellness / Sleep /
Exercise, Graph|Table), `academics/classes/*`, `academics/subjects/pages`, `academics/ee`,
`academics/rop`, `academics/transcripts/transcripts`, `academics/testimonial`, `academics/feeds`
(token list), `people/students/letter/attendance` (~600 KB), `people/onduty*`, `people/visitors*`,
`admissions/browse/admissions`. All **[U]**, all "later" per README §7. When each is captured, add a
section here before writing the parser.

---

## 17. Bug register — do not copy these from the Kotlin port

| # | Where | Problem |
|---|---|---|
| B1 | `W4TimetableParser.kt:35` | Two `id="timetable"` on Home **[V]**; a SwiftSoup `getElementById` port finds 0 columns. Use `select("div#timetable").last()`. |
| B2 | `W4TimetableParser.kt:44` | `.period` has never been captured (0 in all captures). Every period sub-node must be optional; pixel geometry is the verified path. |
| B3 | `W4TimetableParser.kt:76-114` | Ignores `div.period[title]`, which `UWCRCN W4.html:279` **[V]** proves is the tooltip payload — likely teacher/notes. Capture it raw. |
| B4 | `W4TimetableParser.kt:101` | Drops periods whose text is the invented string `"No-Classes"`. Use the **[V]** class `no-classes` / `no-classes-inner`. |
| B5 | `W4TimetableParser.kt:24-32` | Trusts caller's `(year, week)`; header dates and `<h3>… week 33</h3>` are the truth. |
| B6 | `CampusStatusParser.kt:42-57` | Returns radio **labels**; `site/setstatus` needs **values** (`oncampus` / `other` / label). Two of eleven options break. |
| B7 | `CampusStatusParser.kt:41` | `.location` gains `(…)` parens after the JS write path; strip them. |
| B8 | `W4NotificationParser.kt:49-53` | Real chrome ships an **empty** `div.notifications` **[V]**; make that an explicit `.empty` snapshot. |
| B9 | mailer/absence/grade/trips parsers | Only check `td.empty`. Yii also emits `span.empty` / `No results found.`, and non-grid pages use `div.note` ("No users found", **[V]**). |
| B10 | all grid parsers | No pagination. Yii `div.pager` / `ul.yiiPager` + `&{Model}_page=`. Needs capture; until then surface "more on W4". |
| B11 | `W4AssessmentParser.kt:90-91` | `month=(\d+)` misses `var month = 08 - 1`; works only by hitting the ajax URL. |
| B12 | `W4AssessmentParser.kt:29-58` | Every `data-assessment-*` name is invented. Highest-value capture after the timetable. |
| B13 | `W4GradeParser.kt:23` | Real grades page is `table.grades` with `th.anticipated` and `.effort-grade-*` **[V]**, not `table.items`. |
| B14 | `W4AbsenceParser.kt:104-157` | Absence category is also carried by `tr.prearranged_*` / `tr.medical_*` **[V]**, not just the Type column. |
| B15 | `RoomParser.kt` (whole file) | Still Lectio/ASP.NET. Delete, do not port. |
| B16 | `W4DocumentsParser.kt:39-46` | "isPage" heuristic; `.page-content` / `.page-title` / `.page-details` are **[V]** in `cmsrenderer.css`. |
| B17 | `W4Html.kt:55-63` | `uwcId` falls back to the first `nc\d{2}[a-z]+` in the document — on Home that is a **birthday classmate**. |
| B18 | `W4MailerParser.kt:54-57` | Row id from `tr[id]` (Yii doesn't emit one) and `subject.hashCode()` fallback. |
| B19 | `W4AbsenceParser.kt:140-141` | Row id includes the row **index**; sorting/paging reshuffles identity. |
| B20 | `W4TimetableParser.kt:126-129` | Event ids `w4-{n}` collide between AC and EA after merge. Prefix by source. |
| B21 | `IcsCalendarParser.kt:409-415` | `parseUtcDateTime` ignores its `zone` argument and hardcodes Oslo. Harmless today, wrong by construction. |
| B22 | Home capture | `#current_time`'s inline `top`/`opacity` were written by JS before the page was saved; the server sends it hidden. Compute "now" locally. |

---

## 18. Capture wishlist (in priority order)

1. `GET index.php?r=academics/timetable/mytimetable` **in term time** — unblocks B2/B3/B4 and every
   `.period` assertion. Confirm whether `&year=&week=` paginate.
2. `GET index.php?r=academics/deadlines` + the `$.post` for **Confirm done** — unblocks B12 and all
   assessment writes.
3. `GET index.php?r=mailer/inbox` with >1 page, and one `mailer/view&id=…` — unblocks B10 and the
   mail detail parser.
4. One `notifications/refresh` response with a non-zero badge — unblocks §3.
5. `GET index.php?r=people/students/absences` and `…/absences/register` — unblocks §8/§9.
6. `GET index.php?r=academics/grades/grades` — confirms B13.
7. `GET index.php?r=people/students/all` — confirms grid vs `ul.user-list` and the live
   `/files/user_photos/` path.

Fixture hygiene for all of the above: scrub uwc ids to `nc00aaa`-style placeholders, replace names,
drop image binaries, and **never** commit a `PHPSESSID` or an `academics/feeds` `token=` value.

---

## 19. Summary table

| W4 surface | Parser (new Swift file) | Route(s) | Fixture under `ios/BetterW4Tests/Fixtures/W4/` | Priority |
|---|---|---|---|---|
| Page chrome, identity, sdmenu | `W4ChromeParser.swift` | any; `site/index` | `home.html` **[V]**, `sdmenu-academics.html` **[V]**, `documents-index.html` **[V]** | v1 |
| Campus status | `W4CampusStatusParser.swift` | read: any page · write: `site/setstatus` | `campus-chrome-oncampus.html` **[V]**, `campus-chrome-offcampus.html` **[I]** | v1 |
| Combined timetable (AC) | `W4TimetableParser.swift` | `academics/timetable/mytimetable` | `timetable-home-week33.html` **[V]**, `timetable-mytimetable-termtime.html` **[U]** | v1 |
| Combined timetable (EA) | `W4TimetableParser.swift` | `extraacademics/timetable/mytimetable` | same | v1 |
| Assessments calendar | `W4AssessmentParser.swift` | `academics/deadlines` (+ `/confirm`, `/revert`, `/edit`, `/create`, `/delete`) | `assessments-calendar.html` **[I]**, `assessments-empty.html` | v1 |
| Mailer list | `W4MailerParser.swift` | `mailer/inbox`, `mailer/archive` | `mailer-inbox.html` **[I]**, `mailer-inbox-empty.html`, `mailer-archive.html` | v1 |
| Mail detail | `W4MailDetailParser.swift` | `mailer/view&id=` | `mailer-view.html` **[U]** | v1 |
| Absence meters | `W4AbsenceParser.swift` | `site/index` | `home.html` **[V]** | v1 |
| Absence lists | `W4AbsenceParser.swift` | `people/students/absences`, `people/students/eaabsences` | `absences-ac.html` **[I]**, `absences-ea-empty.html` **[I]** | v1 |
| Documents CMS | `W4DocumentsParser.swift` | `documents`, `documents/index&folder_id=`/`&page_id=`, `extraacademics/documents` | `documents-index.html` **[V]**, `documents-page.html` **[I]** | v1 |
| Home (links, greeting) | `W4HomeParser.swift` | `site/index` | `home.html` **[V]** | v1 |
| Yii form encoder | `W4FormParser.swift` | login, 2FA, mailer, assessments, absence register | `yii-form-generic.html` **[I]** | v1 |
| Notifications bell | `W4NotificationParser.swift` | `notifications/refresh` + 7 write routes | `notifications-empty.html` **[V]**, `notifications-refresh.html` **[I]** | v1.5 |
| School calendar overlay | `ICSCalendarParser.swift` | `calendar.google.com/…/basic.ics`; later `academics/feeds/*ical` | `school-calendar.ics` **[I]** | v1.5 |
| Home birthdays / announcements | `W4HomeParser.swift` | `site/index`, `people/birthdays`, `site/rss` | `home.html` **[V]** | v1.5 |
| Grades / SAT | `W4GradeParser.swift` | `academics/grades/grades`, `…/grades/sat` | `grades.html` **[I]**, `grades-tablegrades.html` **[I]** | v1.5 |
| Directory lists | `W4PeopleParser.swift` | `people/students/all`, `firstyear`, `secondyear`, `byname`, `bypreferred`, `bycountry`, `byhouse`, `people/staff/current`, `people/staff/onleave`, `people/students/staff&type=` | `people-all.html` **[I]**, `people-empty.html` **[V]** | v1.5 |
| Profiles | `W4PeopleParser.swift` | `site/profile`, `people/students/student&uwc_id=`, `people/staff/staff&uwc_id=` | `site-profile.html` **[I]** | v1.5 |
| Trips | `W4TripsParser.swift` | `academics/trips` | `trips.html` **[I]**, `trips-empty.html` | v1.5 |
| Absence register form | `W4FormParser.swift` | `people/students/absences/register` | `absences-register.html` **[U]** | v1.5 |
| Rooms | `W4RoomParser.swift` | `academics/timetable/room` | — **[U]** | v1.5 |
| Travel forms | — | `academics/travel/travel.list` | — **[U]** | later |
| Resource bookings | `W4FormParser.swift` | `academics/resources/resources` | — **[U]** | later |
| EA activities / diary / portfolio / CAS | — | `extraacademics/activities/*` | — **[U]** | later |
| SafetyNet | — | `extraacademics/safetynet/mysafetynet` | — **[U]** | later |
| Classes / subject pages / EE / RoP / transcripts | — | `academics/classes/*`, `academics/subjects/pages`, `academics/ee`, `academics/rop`, `academics/transcripts/transcripts` | — **[U]** | later |
| Letter of Attendance | — | `people/students/letter/attendance` | — **[U]** | later |
| On duty / visitors / admissions | — | `people/onduty*`, `people/visitors*`, `admissions/browse/admissions` | — **[U]** | later |

### Existing iOS parser files — disposition

| File | Fate |
|---|---|
| `ios/BetterW4/ScheduleParser.swift` | **Rewritten** as `W4TimetableParser.swift`; the HTML→`ContentBlock` renderer moves to `HTMLContentRenderer.swift`; all `s2skema*` code deleted. |
| `ios/BetterW4/MessageParser.swift` | **Rewritten** as `W4MailerParser.swift` + `W4MailDetailParser.swift`; postback/reaction/edit paths deleted. |
| `ios/BetterW4/AssignmentParser.swift` | **Deleted** — folded into `W4AssessmentParser.swift`. |
| `ios/BetterW4/GradeParser.swift` | **Rewritten** as `W4GradeParser.swift`; dynamic-column design kept. |
| `ios/BetterW4/StudentParser.swift` | **Split and rewritten**: identity → `W4ChromeParser.swift`, absence → `W4AbsenceParser.swift`, birthdays → `W4HomeParser.swift`; the Lectio dropdown/hold/picture-id code is deleted. |
| `ios/BetterW4/DirectoryParser.swift` | **Deleted** — replaced by `W4PeopleParser.swift`. |
| `ios/BetterW4/AbsenceEditFormParser.swift` | **Deleted** — replaced by the generic `W4FormParser.swift`. |
| `ios/BetterW4/BaseParser.swift` | **Rewritten**: drop `isRobotDetectionPage` and the Danish strings; keep `String.nilIfEmpty`; `parseAllFormFields` moves into `W4FormParser` (checkbox-aware, no `__VIEWSTATE`). |
