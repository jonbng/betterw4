# W4 protocol

How W4 works: routes, cookies, login, session death, form payloads. The iOS and Android apps both
implement this.

W4 is the SIS at `https://w4.uwcrcn.no/`. Custom Yii 1 PHP app (v**25.9.1**, Sep 2025), not Lectio,
not ManageBac. There is **no public JSON API** in use. Clients scrape HTML and post forms.

For the apps themselves, see [`README.md`](README.md).

---

## 1. What you are cloning

| | Lectio | BetterLectio Android | W4 |
|---|---|---|---|
| Who | Danish gymnasiums | Student client over Lectio | One IB boarding college (~200 students) |
| Auth | MitID / UniLogin | WebView cookie capture | Username + password + **mandatory 2FA** + device fingerprint |
| Session | `ASP.NET_SessionId` + `autologinkeyV2` | Encrypted cookie jar, manual redirects, never wipe empty Set-Cookie | **One cookie:** `PHPSESSID` |
| API | None (HTML + ASP.NET postbacks) | OkHttp + Jsoup | None (HTML + Yii forms / jQuery `$.post`) |
| Daily path | Skema, beskeder, lektier, opgaver | 5 tabs matching that | Timetable, assessments, mail, campus status, extra-academics |
| Companion | — | Optional Supabase | **ManageBac** (official IB) linked from Home |

Do **not** port lektier/opgaver as two tabs. W4’s analog is a single **assessments calendar** (add item, confirm done). Do **not** ignore boarding: campus status and trips are first-class.

Staff **Administrative** exists in release notes but is **not** in the student nav we captured. Build the student app first.

---

## 2. Evidence

Captured 14 Aug 2026 against a **student** account that also sees Admissions → Applicants.

| Source | What it gives you |
|---|---|
| `references/w4.uwcrcn.no.har` | Documents page + chrome (notifications, campus status) |
| `references/pages/*.html` | Full **sdmenu** IA: Home, Academics, Extra Academics, School, Admissions, Documents |
| Live GETs with `PHPSESSID` | Subpage behaviour (timetable, assessments, mailer, trips, SafetyNet, feeds, …) |
| Public `site/relnotes` (140 versions, 2012–2025) | Historical modules (Connect, concerns, alumni, REST stub) |
| Public login / forgot-password (no session) | Auth form, `Set-Cookie` flags, `deviceId` fingerprint |

Role-gated: menus are **not** the full staff product. Applicant/student list rows were not inventoried (PII).

---

## 3. Stack (server)

- **Host:** `w4.uwcrcn.no` (HTTPS only in practice; cookie is `Secure`)
- **App:** Yii 1.x, routes `https://w4.uwcrcn.no/index.php?r={module}/{controller}/{action}&k=v`
- **Server:** Apache 2.4.59 (Debian) `mpm-itk`, OpenSSL 1.1.1n
- **Front-end:** jQuery + jQuery Migrate 1.4.1 + jQuery UI 1.12.1 (2016), TinyMCE on mail/documents, `sdmenu` sidebars
- **Pages:** XHTML 1.0 Transitional, `charset=utf-8`
- **Caching:** every authenticated page sends `Cache-Control: no-store, no-cache, must-revalidate`, `Pragma: no-cache`, `Expires: Thu, 19 Nov 1981 08:52:00 GMT` (PHP session default)
- **CSRF:** **no** `YII_CSRF_TOKEN` cookie or hidden field on login or the student forms we opened. Posts are cookie-auth only.
- **Copyright:** 2009–2026 Red Cross Nordic United World College

Yii button names on forms are `yt0`, `yt1`, … (submit). Include the clicked button name when posting a Yii form, same idea as Lectio postbacks but far fewer hidden fields (no `__VIEWSTATE`).

---

## 4. Auth, cookies, session (read this twice)

This is the part that will make or break the apps. BetterLectio’s Lectio client is the right **shape** (WebView login → extract cookies → native HTTP with **manual** cookie header, no OkHttp cookie jar). The **rules** are simpler than Lectio.

### 4.1 Cookie

| | |
|---|---|
| Name | `PHPSESSID` |
| Domain | host-only `w4.uwcrcn.no` (no `Domain=` attribute) |
| Path | `/` |
| Flags | `Secure`. **Not** `HttpOnly`. **No** `SameSite` |
| Lifetime | Session cookie (no `Max-Age` / `Expires` on `Set-Cookie`). Server-side PHP GC still expires it. |
| Count | **This is the only cookie we saw.** No autologin key, no CSRF cookie. |

Because it is **not HttpOnly**, a WebView `CookieManager` can read it after login (easier than Lectio). Still persist it in the OS keystore / EncryptedSharedPreferences — never in prefs plaintext, never in logs.

PHP may **regenerate** the id on login (classic `session_regenerate_id`). On every response, **merge non-empty** `Set-Cookie: PHPSESSID=…` into the store. Ignore empty values (Lectio taught us that). One name, one value.

### 4.2 Unauthenticated entry

```
GET https://w4.uwcrcn.no/
→ 302 Location: https://w4.uwcrcn.no/index.php?r=site/login
→ Set-Cookie: PHPSESSID=…; path=/; secure
```

`GET index.php?r=site/login` is 200 + login HTML and also sets `PHPSESSID` if you had none.

**Always send the cookie you were given** on the subsequent POST. Yii sessions are sticky to that id.

### 4.3 Login form

`POST /index.php?r=site/login`  
`Content-Type: application/x-www-form-urlencoded`

| Field | Notes |
|---|---|
| `LoginForm[username]` | `maxlength=16`. Typical UWC id: `nc` + 2-digit entry year + initials, e.g. `nc26jban`. Alumni docs use the same pattern. |
| `LoginForm[password]` | password |
| `LoginForm[deviceId]` | **Hidden.** Filled by ClientJS: `new ClientJS().getFingerprint()` from `/js/clientjs-0.2.1/dist/client.base.min.js` |
| `yt0` | Submit button value `Login` |

There is **no** CSRF hidden field.

Forgot password: `GET/POST index.php?r=site/forgotpass` with `ForgotPassForm[username]` (`maxlength=8` on that form — login allows 16) and `yt0=Reset`. Emails a new password to the address on file.

### 4.4 Device fingerprint + 2FA

Release **24.10.1** (11 Oct 2024): *“add mandatory two factor authentication.”*

Login always ships ClientJS and writes a browser fingerprint into `LoginForm[deviceId]`. That is almost certainly how W4 binds a **trusted device** so 2FA is not prompted every time.

`index.php?r=site/verify2fa` is the live mid-login 2FA page (password accepted, code not yet entered). Research originally guessed `site/otp`; that route **exists**, but unauthenticated (and fully-logged-in) GETs **302 → `site/login`**. The 2FA page is only reachable in the mid-login state. Form field names were not in the first capture; a live login on 14 Aug 2026 confirmed the **route** is `site/verify2fa`. Expect a Yii form posting a code, then a 302 to Home.

**Recommended auth UX:** native username/password (and OTP) forms. POST the same Yii fields W4 already accepts — no WebView, no ClientJS.

1. Native screen: username + password.
2. `GET /index.php?r=site/login` to obtain `PHPSESSID`.
3. `POST` `LoginForm[username]`, `LoginForm[password]`, `LoginForm[deviceId]` (a **stable per-install UUID**, persisted in EncryptedSharedPreferences — not a ClientJS fingerprint), `yt0=Login`.
4. If the response is the OTP page (`r=site/verify2fa`, `r=site/otp`, or a form with a code field), show a native OTP field and POST the parsed form.
5. Success: URL is `r=site/index` **or** HTML contains `Welcome,` / `id="user-panel"` and does **not** contain `LoginForm[username]`.
6. Persist `PHPSESSID` in Keystore. Confirm with `GET index.php?r=site/index`.

A stable `deviceId` is enough for v1: the first login on this install looks like a new device (OTP once); later launches reuse the same id. Reimplementing ClientJS is unnecessary.

Logout: `GET index.php?r=site/logout`. Then wipe local `PHPSESSID`.

### 4.5 How to tell the session is dead

In order of reliability:

1. **HTTP 302** to `index.php?r=site/login` (or `Location` path contains `r=site/login`).
2. **HTTP 200** whose body is the login form (`LoginForm[username]`, title contains `Login Site`).
3. **AJAX 403** with body containing `Login Required` — W4’s own `init_ajax.js` then does `location.href='/'`.
4. AJAX **403** without that string → “not authorized” (logged in, wrong role). Do **not** treat as session expiry.
5. AJAX **409** → server error string in body.
6. Missing `Welcome,` in chrome on a page that should have `#user-panel`.

Native client: on (1)–(3) emit `sessionExpired`, drop the user on the native login form, do not retry the original call as if cookies were fine.

Follow redirects **manually** (BetterLectio already does this: OkHttp `followRedirects(false)`). If you auto-follow, a dead session becomes a 200 login HTML and parsers will throw garbage.

### 4.6 What BetterLectio does that you can delete

Lectio-specific. **Do not port:**

- `autologinkeyV2` / empty-Set-Cookie protection for two primary cookies (you have one)
- UniLogin broker host detection
- ASP.NET `__VIEWSTATEX` / `__EVENTVALIDATION` postbacks
- Robot-detection page (not seen on W4)
- School picker / gym id in the URL (`/lectio/{id}/…`) — W4 is one host
- MitID

**Do port:**

- Encrypted credential store
- Manual `Cookie:` header, `CookieJar.NO_COOKIES`
- Merge `Set-Cookie` per hop on redirects
- Serial request limiter (be kind; this is a tiny school server)
- Stable desktop-ish User-Agent
- Session-expired → re-login UI
- Demo mode for store review

### 4.7 2017 “REST API”

Relnote **17.12.2** claimed an early REST API (login/logout + mailer read/delete) “to enable a mobile application.” We did not find a live `/api` surface in this pass. **Do not depend on it.** Scrape HTML until someone proves an authenticated JSON route.

### 4.8 Personal calendar tokens (bonus, not login)

`academics/feeds` lists **unauthenticated** RSS and iCal URLs for *this user*, query `token=<long secret>`:

| Kind | Route prefix |
|---|---|
| AC timetable RSS | `academics/feeds/acttrss` |
| EA timetable RSS | `academics/feeds/eattrss` |
| Combined RSS | `academics/feeds/combottrss` |
| Assessments RSS | `academics/feeds/sassttrss` |
| Same four as iCal | `…/acttical`, `eattical`, `combottical`, `sassttical` |
| Public announcements | `site/rss` (no token) |

Treat the token like a password: store encrypted, never log, never put in git. A v1 timetable can **skip HTML scrape** and parse iCal if the feed is complete enough (unverified). Still scrape HTML for colours, rooms, absences-on-grid, “now” line.

---

## 5. HTTP conventions for a native client

### 5.1 GET (pages)

```
GET /index.php?r=academics/timetable/mytimetable HTTP/1.1
Host: w4.uwcrcn.no
Cookie: PHPSESSID=…
Accept: text/html
User-Agent: <stable browser UA>
```

Parse HTML. Identity: `Welcome, {display name}` in `#user-panel`. Profile / public pages use `uwc_id=nc26jban` (pattern `nc` + year + letters).

### 5.2 Yii form POST

Standard Yii 1 `application/x-www-form-urlencoded`:

```
POST /index.php?r=site/login
Content-Type: application/x-www-form-urlencoded

LoginForm[username]=…&LoginForm[password]=…&LoginForm[deviceId]=…&yt0=Login
```

Other captured forms:

| Action | Fields (subset) |
|---|---|
| `people/students/absences/register` | `StudentAbsenceForm[absence_date]` (`dd-M-yy`, datepicker) + per-slot checkboxes added in JS |
| `mailer/send&type=freeform` | `MailerForm[subject]`, `[message]` (TinyMCE HTML), `[attachment][]` (multipart, up to 5 × 2MB), `[sendCC]`, `[attachmentSource]=upload` |
| Resource book | `day, month, year, reservation_id, time_start, time_end, description, resource_id` |
| Assessments (student) | `assessment_id`, `student_assessment_id`, `student_deadline_date`, `student_assessment_title` + buttons Confirm done / Revert to pending / Save / Delete |
| SafetyNet | weekly report create; view `Graph` / `Table`; columns Period, Status, Average wellness, Sleep, Exercise |

For file uploads use `multipart/form-data`. For TinyMCE fields send HTML, not markdown.

### 5.3 jQuery AJAX POST

W4 uses `$.post(url, {…})` (urlencoded). jQuery also sends `X-Requested-With: XMLHttpRequest`.

**Campus status** (`campusstatusdropdown.js`):

```
POST /index.php?r=site/setstatus
status=on|off
location=<string or omitted>
```

- On campus: `status=on`, `location` null/omitted  
- Off campus: `status=off`, `location` = selected label (`On a walk`, `At Raudbua`, …) or the `other` text (`maxlength=20`)

**Notifications** (poll every **60s** while dropdown closed):

| Key | Path |
|---|---|
| `read` | `notifications/read` (`notification_id`) |
| `readGroup` | `notifications/readgroup` (`notification_type`) |
| `readAll` | `notifications/readall` |
| `readAllEmails` | `notifications/readallemails` |
| `clear` / `clearGroup` / `clearAll` | `notifications/clear…` |
| `refresh` | `notifications/refresh` |

Response is HTML to swap into `div.notifications`. Types include **tasks** (classes `new` / `overdue`) and **emails**.

Global AJAX errors: `init_ajax.js` — 403 + `Login Required` → session dead; 403 otherwise → forbidden; 409 → `Error from remote server: {body}`.

### 5.4 Redirect policy

Use **manual** redirects (max ~5). Merge `Set-Cookie` on **each** hop before the next request. After login, a 302 to `site/index`, `site/verify2fa`, or `site/otp` is success-in-progress, not failure.

Detect login loop: if after POST login you land on `site/login` again with an error node, show the server’s message (Yii `errorMessage` / `.errorSummary`).

### 5.5 Concurrency

This is a small Apache box. Copy BetterLectio’s **serial limiter** + light cooldown. Do not prefetch the entire directory with unbounded parallelism. Avatar/photo URLs exist (`/…_thumb.jpg` on people); rate-limit those.

### 5.6 HTML layout for parsers

Almost every logged-in page:

- `#header` — title `UWCRCN W4`, version link `site/relnotes`, notifications, campus dropdown
- `#main_menu` — Home \| Academics \| Extra Academics \| School \| Admissions \| Documents
- `#user-panel` — `Welcome, {name}` · Logout · Profile · Password
- `.sdmenu` — sectioned links (`#dynamic_menu_academics`, `_extraacademics`, `_people`, `_admissions`)
- `#content_inner` — page body
- `#footer` — copyright

Home is special: week timetable (`#timetable`, hours 7:00–22:00, days Day 1–5 / Weekend, EA row), birthdays, announcements, AC/EA **attendance meters**, configurable **Links**.

Timetable “now” line: `full_timetable.js` uses `tt_start_hour` / `tt_end_hour` and `#current_time`. Year switches on the school grid: pre-IB / 1st / 2nd (`timetable.js`).

---

## 6. Student product surface (what to implement)

Captured menus for this role. Routes are `r=` values.

### Home — `site/index`

- Combined week strip (AC blocks + “No EA” when empty)
- Birthdays today/tomorrow → `people/birthdays`
- Announcements + public RSS `site/rss`
- AC meter → `people/students/absences` (absences **and latenesses**)
- EA meter → `people/students/eaabsences`
- Public profile `people/students/student&uwc_id={id}`
- Links (config, not code): Extra Academic Google Site, policies Drive, **Trip Form**, kitchen Google Form, **ManageBac**, document pages (Bakehus, Haugland times, Learning support, Lavvo)

### Academics

| Label | Route |
|---|---|
| My assessments | `academics/deadlines` |
| My timetable | `academics/timetable/mytimetable` |
| My classes | `academics/classes/myclasses` |
| My teachers | `people/students/staff&type=teachers` |
| My absences | `people/students/absences` |
| Register absences | `people/students/absences/register` |
| My grades | `academics/grades/grades` |
| My SAT/ACT scores | `academics/grades/grades/sat` |
| My transcripts | `academics/transcripts/transcripts` |
| My Records of Progress | `academics/rop` |
| My Extended Essay | `academics/ee` |
| My student testimonial form | `academics/testimonial` |
| My personal feeds | `academics/feeds` |
| All classes | `academics/classes/allclasses` |
| All assessments | `academics/classes/assessments/all` |
| Subject pages | `academics/subjects/pages` |
| My trips | `academics/trips` |
| My travel forms | `academics/travel/travel.list` |
| Resource bookings | `academics/resources/resources` |

**Assessments:** month calendar; student can **add** items; **Confirm done** / **Revert to pending**. Global calendar filters by class. This is lektier + opgaver.

**Trips:** columns Trip name, outgoing/return, destination, type, participants, status. **Plan new trip**. Status: Planning → Pending confirmation (house leader and/or absences manager) → Approved (pre-arranged absences auto-registered) / Cancelled.

**Travel forms:** four journeys (to school autumn, home winter, back after winter, home summer) + “Manage my travel contacts”.

**Resources:** month calendar; Book resource; rooms/spaces (classrooms, Auditorium, Hoegh Kitchen, …).

**Subject pages:** IB subjects as CMS (Biology, TOK, Visual Art, Learning Support, …).

**Letter of Attendance:** `people/students/letter/attendance` — large generated document (HTML ~600KB+). Closest thing to a studiekort.

### Extra Academics

| Label | Route |
|---|---|
| My EA timetable | `extraacademics/timetable/mytimetable` |
| My activities | `extraacademics/activities/myactivities` |
| My group leaders | `people/students/staff&type=leaders` |
| My EA diary | `extraacademics/activities/myactivities/diary` |
| My portfolio | `extraacademics/activities/myportfolio` |
| My absences | `people/students/eaabsences` |
| My CAS interviews | `extraacademics/activities/interviews` (export PDF; 3 interviews) |
| My SafetyNet | `extraacademics/safetynet/mysafetynet` |
| All / EAC / CR / PBL / Leirskule | `extraacademics/activities/ea` (`&type=eac\|cr\|pbl\|leirsk`) |
| Documents | `extraacademics/documents` |

Activities filter: running / past / future; sort by name or weekday. Diary uses `EAGroupStudentModel[outcomes][]`.

**SafetyNet:** weekly wellbeing (Average wellness, Sleep, Exercise); add report for past or current week; Graph/Table. Pastoral, not academic.

### School (`people`)

My teachers/leaders, Letter of Attendance, student lists (all / 1st / 2nd / by name / preferred name / country / house), current staff / staff on leave, visitors list + register, birthdays, rooms (`academics/timetable/room`), on duty today / full schedule / print, **Mailer** (freeform, inbox, sent).

**Mailer:** Inbox columns Received, From, Subject. Compose: TinyMCE (bold/italic/underline/link/lists), attachments, CC me, add recipients (`mailer/extra&type=freeform`).

### Admissions

This student role: **Browse → Applicants** only (`admissions/browse/admissions`). Do not build an admissions CRM in v1.

### Documents

CMS folders/pages (`documents/index&folder_id=` / `page_id=`), TinyMCE, role permissions (from CSS/JS). Folders seen: Internal Information, Outdoor Department.

### Chrome on every page

- Campus status (locations listed in the HAR/pages)
- Notifications bell
- Profile `site/profile` (UWC id, year, names, pronouns, country, email `{uwc_id}@uwcrcn.no`, NC/SO, last login, photo, privacy-ish fields)
- Password `site/password`

---

## 7. Suggested app IA (BetterLectio → W4)

BetterLectio Android tabs: Skema · Beskeder · Lektier · Opgaver · Mere.

| BetterLectio | W4 student app |
|---|---|
| Skema | Combined AC+EA timetable (Home week + `mytimetable`; iCal optional) |
| Beskeder | Mailer inbox / compose |
| Lektier | **Assessments calendar** (done state is native on W4) |
| Opgaver | fold into assessments + EE later |
| Mere | Grades, AC/EA absence, directory, rooms, documents, trips, EA activities, SafetyNet, settings, campus status (or status in the app bar) |

**v1 MVP:** login WebView, campus status, combined timetable, assessments, inbox, absence meters, documents list, EA this week.

**v1.5:** trips + travel forms, resource booking, directory, grades, on-duty.

**Later / staff:** Connect, student concerns, disciplinary, RoP admin, admissions, alumni. Not in this menu.

**Do not scrape ManageBac** unless you explicitly take that on — it is a third SIS.

---

## 8. Mapping BetterLectio client code → W4

Keep the Android/iOS **architecture**, swap the Lectio module:

| BetterLectio | W4 |
|---|---|
| `LectioHttpEngine` (no cookie jar, no auto-redirect, merge Set-Cookie) | Same engine, one cookie name |
| `AuthSessionInstaller` + MitID WebView | WebView on `site/login` until Welcome / `site/index` |
| `UniLoginDetector` | `Location` contains `r=site/login` or body has `LoginForm` |
| Jsoup parsers per `*.aspx` | Jsoup per `r=` page; `#content_inner` + `.sdmenu` |
| `dokumentupload.aspx` | `MailerForm[attachment][]` multipart |
| WorkManager notification diffs | Poll `notifications/refresh` and/or scrape inbox/assessments |
| Glance widget / live lesson | `#current_time` + timetable hours; campus status is the extra widget |
| Supabase | Optional later; W4 is the source of truth |

HTML is English. Locale still matters for dates: W4 uses `dd-M-yy` (`14-Aug-2026`) and `en-GB` datepicker.

---

## 9. Staff-only (release notes, not this session)

If you ever get a staff capture: Administrative → Progress (RoP, transcripts, SAT, grades schedule), take absences, trip approval, Connect (`People→Students→Connect`), student concerns, disciplinary, EA proposals / CAS interview admin, NC/SO mailer, admissions import, SafetyNet all-students, alumni. Relnote 17.12.2 REST stub mentioned login + mailer only.

---

## 10. Unknowns / next captures

### Resolved — the login form, captured live 16 Aug 2026

An unauthenticated `GET index.php?r=site/login` returns the real form. It is exactly what §4.3 predicted, so the login POST needs no guesswork:

```html
<form action="/index.php?r=site/login" method="post">
  <input name="LoginForm[deviceId]" id="LoginForm_deviceId" type="hidden" />
  <input name="LoginForm[username]" id="LoginForm_username" type="text" maxlength="16" class="text_input" />
  <input name="LoginForm[password]" id="LoginForm_password" type="password" class="text_input" />
  <input name="yt0" id="submit_button" type="submit" value="Login" />
</form>
```

Confirmed: **no CSRF token**, no other hidden fields, and the page still ships ClientJS
(`/js/clientjs-0.2.1/dist/client.base.min.js`) to populate `deviceId`. Title is
`UWCRCN W4: UWCRCN W4 - Login Site`, which is the string the session-death check keys on.

### Still open

A HAR of **one full login** (password → OTP → home) remains the single highest-value capture: exact OTP field names, whether `PHPSESSID` rotates on login, and whether `deviceId` is stored server-side. The iOS client works around the unknown by discovering the OTP field from the rendered form rather than hardcoding a name, but that is a mitigation, not knowledge.

Ranked next captures, by what they unblock:

1. **A term-time `academics/timetable/mytimetable`** — every capture we have is from a holiday week with **zero** lesson blocks, so `.period`, `.inner`, `.datetime`, `.room` and the attendance marker classes are entirely unverified. The grid geometry *is* proven (`tt_start_hour = 7`, 900px over 15 hours ⇒ 1px = 1 minute), so a single capture would convert the daily-driver parser from assumed to evidenced.
2. **`mailer/inbox` and one `mailer/view`** — the mailer parser is written defensively against a generic Yii `CGridView` and has never seen a real grid.
3. **POST payloads for Confirm done / Revert to pending** (`academics/deadlines`) — the app's only write surface besides campus status, currently behind a feature flag for exactly this reason.
4. A notifications `refresh` fragment with content — the captured chrome ships an *empty* `div.notifications`.
5. `people/students/absences` with real rows, and `academics/grades/grades`.

Do not commit live `PHPSESSID` or iCal `token=` values. The `academics/feeds` tokens are password-equivalent: anyone holding one can read that student's timetable and assessments without logging in.

---

## 11. References in this repo

```
references/w4.uwcrcn.no.har          # Documents chrome
references/pages/                    # Saved top-level pages + sdmenus
references/betterlectio/android/     # Client to port (session/http/cookie)
```

Public: `https://w4.uwcrcn.no/` · `index.php?r=site/login` · `index.php?r=site/relnotes` · `index.php?r=site/rss`.
