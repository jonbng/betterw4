# Reviewer notes — read before implementing the W4 client on iOS

These are findings from reading the Android W4 engine and the existing iOS client side by side.
They override any spec text that contradicts them.

## 1. Keep these iOS strengths — the Android port does not have them

`ios/BetterW4/W4HTTPClient.swift` already has machinery the Kotlin engine lacks. Do not throw it away
while swapping Lectio for W4:

- **`PriorityRequestLimiter`** (actor, bottom of the file): serial gate + 100 ms cooldown, `.important`
  jumps the queue ahead of `.opportunistic`, and waiters are cancellation-aware. This is the "be kind
  to a tiny Apache box" rule from README §5.5. Keep as-is.
- **Cancellation-aware `URLSessionTask` wrappers** (`dataTaskForW4Request`, `uploadTaskForW4Request`
  with `W4CancellableTaskBox`): cancelling the Swift task actually cancels the HTTP task.
- **Streaming multipart upload from disk** (`performFileUploadRequest`) — the mailer allows up to
  5 attachments x 2 MB; never materialise that in memory.
- **Cookies fully disabled on the shared `URLSession`** (`httpShouldSetCookies = false`,
  `httpCookieStorage = nil`, `httpCookieAcceptPolicy = .never`) so the manual `Cookie:` header is the
  single source of truth. This is exactly right for W4 too — keep it.
- **Compact, redacted logging** (`W4RequestLog`): cookie *names* only, never values. Keep, and delete
  the noisy `print` calls that dump status/redirect chains in non-DEBUG builds.

## 2. Redirect policy — the one real behavioural change

The iOS client installs a `URLSessionTaskDelegate` that merges `Set-Cookie` per hop and then lets
`URLSession` follow the redirect. The manual `case 301, 302, ...` branch in `performSingleAttempt` is
therefore mostly unreachable today.

For W4 that is wrong. README §4.5 and §5.4: a 302 to `index.php?r=site/login` is the single most
reliable session-death signal, and auto-following turns it into a 200 that contains login HTML.

Required behaviour, matching `W4HttpEngine.performSingleAttempt` in the Android port:

1. In `willPerformHTTPRedirection`, merge `Set-Cookie` from the hop into the jar **first**.
2. Then inspect the target. If the target route is `site/login` and the request did **not** set
   `allowLoginPage`, call `completionHandler(nil)` so the 302 surfaces to the caller, and classify it
   as session-expired.
3. Otherwise rewrite the `Cookie` header on the follow-up request and continue, capped at 5 hops.
4. On 302/303 following a POST, the method must become GET with no body (the Kotlin engine does this
   explicitly; `URLSession` does it for you, but the manual path must too).

`allowLoginPage` is a per-request flag: the login/OTP flow needs to *see* login pages without the
engine screaming "session expired". Port that flag.

## 3. Session-death classification (README §4.5) — implement all of it

In priority order, and each maps to a distinct typed error:

| Signal | Meaning | Error |
|---|---|---|
| 302 whose `Location` route is `site/login` | dead session | `.sessionExpired` |
| 200 whose body has `LoginForm[username]` or title `Login Site` | dead session | `.sessionExpired` |
| 403 whose body contains `Login Required` | dead session (W4's own `init_ajax.js` rule) | `.sessionExpired` |
| 403 without that string | logged in, wrong role | `.forbidden` — **must not** log the user out |
| 409 | server error, body is the message | `.serverConflict(String)` |
| redirect budget exhausted | treat as dead session | `.sessionExpired` |

`.sessionExpired` is the only one that posts the logout notification. Getting `.forbidden` wrong means
a student who opens a staff-only page gets kicked to the login screen.

## 4. Delete outright (Lectio-only, no W4 analogue)

- `isW4UniLoginURL` / every `broker.unilogin.dk` check.
- `isRobotDetectionPage` and the Danish robot strings — W4 has no robot page.
- The two-cookie model: `autologinkey`, `additionalCookies`, and all "never wipe an empty protected
  cookie" logic. W4 has exactly one cookie, `PHPSESSID`, host-only, `Secure`, not `HttpOnly`,
  no `Domain`, no `SameSite`. Merge it when non-empty; ignore empty values.
- `Referer: https://www.lectio.dk` → `https://w4.uwcrcn.no`.
- `gymId` in every URL and model — W4 is one host, one school.
- ASP.NET postback helpers (`__VIEWSTATE`, `__EVENTVALIDATION`, `SmartPostback`) — Yii forms only
  need the form's own hidden fields plus the clicked submit button name (`yt0`, `yt1`, …).
- The school picker and `LastSchoolStore`.

## 5. Login flow — copy the Android shape, it is better than guessing

`android/.../core/w4/auth/W4LoginClient.kt` solves the "we never captured the 2FA field names"
problem properly, and the Swift port must do the same:

- GET `index.php?r=site/login` with an empty credential jar and `allowLoginPage = true` to obtain
  `PHPSESSID`.
- Parse the real form rather than hardcoding: take every hidden input, add `LoginForm[username]`,
  `LoginForm[password]`, `LoginForm[deviceId]`, and the form's own submit button name/value
  (default `yt0` / `Login`).
- POST to the same URL, then **classify the response**, checking OTP *before* "authenticated":
  a 2FA page still renders logged-in chrome (`Welcome,` / `#user-panel`), so a naive
  `isAuthenticatedHtml` check would sail straight past it.
- OTP field discovery is dynamic: among the form's non-hidden, non-`LoginForm` inputs, prefer a name
  matching /otp|totp|2fa|code|token|pin|sms|verify|authenticator|one[-_]?time/, else the sole
  candidate. Post it back to the form's own action with the hidden fields preserved.
- `deviceId` is a **stable per-install UUID in the Keychain**, created once and never regenerated.
  Do not reimplement ClientJS fingerprinting. Regenerating it means a 2FA prompt on every launch.
- Show the server's own error text on failure (`.errorSummary li`, `.flash-error`, `.errorMessage`).

## 6. Identity

After login, identity comes from the page chrome, not from a JSON profile:
`Welcome, {display name}` inside `#user-panel`, and the UWC id from the profile link
`a[href*=people/students/student][href*=uwc_id]`, pattern `nc\d{2}[a-z]+` (e.g. `nc26jban`).
That id is the app's `studentId` and the Keychain scope key. There is no numeric student id.

## 7. Evidence status — what is verified vs. assumed

Verified against `references/pages/UWCRCN W4.html` (the real Home page):

- `#timetable` → `<h3>August 2026, week 33</h3>`, `#timetable-header .header-row .header-cell`
  with `.day-name`, a `dd-MMM-yyyy` date line (`10-Aug-2026`), `.rotation-day` (`Day 1`…`Day 5`,
  or `Weekend` carrying `.no-classes`), and an EA line that reads `No EA` when empty.
- `#absences` → `#academic-absences` and `#ea-absences`, each with prose of the form
  "You have N absences and M latenesses so far" plus a link to
  `r=people/students/absences` / `r=people/students/eaabsences`.
- `#birthdays` → `#birthdays-today` / `#birthdays-tomorrow`, `li > a[href*=uwc_id=]` wrapping
  `img.photo` thumbnails.
- `#links`, `#announcements`, `#calendar` (an iframe), `#current_time` all exist on Home.
- `#header` → `#version` reading `W4 v. 25.9.1` (linking `r=site/relnotes`), an initially-empty
  `div.notifications`, and the campus control:

  ```
  div.status-dropdown > div.status.oncampus > div.status-value  ("on campus")
                                            > div.location      (empty when on campus)
  div.selection-box  > #location > input[type=radio][value=…] + label[for=location_N]
  ```

  The radio values are the literal location labels — `oncampus`, `On a walk`, `At Raudbua`, … and
  `other` with a free-text field. The Android `CampusStatusParser` selectors match this capture
  exactly, so that parser ports across with confidence; the POST is
  `r=site/setstatus` with `status=on|off` plus `location` only when off campus.
- `#user-panel .right` → `Welcome, {name}` then Logout / Profile / Password links, and `#hello`
  carries the signed-in student's own public-profile link, which is where the UWC id comes from.

The timetable **grid body** is confirmed too, and it pins down the geometry:

```
#timetable
  div.column[style="height: 900px"]      <- hour gutter: 15 x div.cell "7:00 — 8:00" … "21:00 — 22:00"
  div.column[style="height: 900px"] x 7  <- one per day, Monday..Sunday
  div.column.current                     <- today; contains #current_time with an inline top: NNNpx
  div.clear
```

with `tt_start_hour = 7` and `tt_end_hour = 22` in the page script. 15 hours across 900 px means
**1 px == 1 minute**, offset from 07:00 — which is what the Android parser's `top`/`height` maths
assumes. The em-dash in the hour labels is `—` (U+2014), not a hyphen; the time-range regex must
accept `—`, `–` and `-`.

> **The single most important caveat in this whole port:** the captured week (August 2026, week 33)
> is a holiday week. Every day column is empty, so the capture contains **zero `.period` elements**.
> `.period`, `.inner`, `.datetime`, `.room` and the absence/present marker classes are inherited
> assumptions from the Android parser and have never been checked against a real W4 lesson block.
> Consequences: (a) the timetable parser must treat every one of those nodes as optional and fall
> back to the pixel geometry, which *is* verified; (b) the fixture test we can honestly write today
> asserts "7 days, correct dates, no events, current-time marker on the right day" — do not write a
> test that fakes lesson markup and then claim the parser is verified; (c) getting one real
> term-time capture of `academics/timetable/mytimetable` is the highest-value next capture.

Assumed, never captured — parsers must be defensive and tests must not pretend otherwise:

- **Lesson blocks inside the timetable grid** (see the caveat above).

- The mailer grids. The Android parser targets a generic Yii `div.grid-view table.items` with
  header-driven column indexes, which is the right defensive shape. Keep that.
- The assessments calendar POST payloads (confirm done / revert to pending).
- The 2FA form field names (handled by dynamic discovery, above).
- The notifications `refresh` HTML fragment.

Anything in this second list must degrade to an empty list plus a logged warning, never a crash.

## 8. Fixture hygiene

The captured pages contain real people: UWC ids, names, birthday photo filenames. Before anything
lands in `ios/BetterW4Tests/Fixtures/W4/`, replace real UWC ids with `nc00aaa`-style placeholders,
names with invented ones, and drop image binaries. Never commit a live `PHPSESSID` or an iCal
`token=` value — the personal feed tokens in `academics/feeds` are password-equivalent.
