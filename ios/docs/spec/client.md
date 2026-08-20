# BetterW4 iOS — W4 networking / session / auth layer

**Status:** implementation spec. Replaces the Lectio client in `ios/BetterW4/`.
**Authority:** `PROTOCOL.md` §4 and §5 (the W4 protocol brief) + the finished Kotlin port in
`android/app/src/main/java/dk/betterw4/android/core/w4/**`.
**Scope:** everything below `W4Client` — URL building, HTTP, cookies, errors, login, session, demo.
Feature scrapers and view models are out of scope except where they touch these types.

Every claim here is either (a) cited to a file+line I read, (b) cited to a captured artefact in
`references/`, or (c) explicitly marked **UNKNOWN — needs live capture**. Nothing is invented.

---

## 0. Evidence base and its holes

| Thing | Evidence | Confidence |
|---|---|---|
| Route shape `index.php?r={module}/{controller}/{action}&k=v` | `references/pages/UWCRCN W4.html` contains e.g. `index.php?r=site/index`, `index.php?r=site/logout`, `index.php?r=people/students/student&amp;uwc_id=nc26jban` | **Certain** |
| Sibling query keys are *not* part of `r` | same file: `r=people/students/student&amp;uwc_id=nc25wnas` | **Certain** |
| AJAX routes for notifications + campus status | `references/pages/Documents.html:19-20` — `var notification_urls = {'read':'/index.php?r=notifications/read', 'readGroup':'…/readgroup', 'readAll':'…/readall', 'clear':'…/clear', 'clearGroup':'…/cleargroup', 'clearAll':'…/clearall', 'refresh':'…/refresh', 'readAllEmails':'…/readallemails'}` and `var status_urls = {'set':'/index.php?r=site/setstatus'}` (values are `\x2F`/`\x3F`-escaped in the source) | **Certain** |
| AJAX error semantics (403/409/404) | `references/w4.uwcrcn.no.har` → `js/init_ajax.js`, verbatim: `if (XMLHttpRequest.status == 409) { alert('Error from remote server: ' + data); } … else if (XMLHttpRequest.status == 403) { if (data.search('Login Required') >= 0) { location.href='/'; } else { alert('Error 403: not authorized'); } }` | **Certain** |
| `$.post` payloads for campus status | HAR → `assets/f76dbbc7/campusstatusdropdown.js`: `$.post(status_urls.set, {status: status, location: location})`, `status = selection === 'oncampus' ? 'on' : 'off'`, `location = … null … : ($('#other').val())` | **Certain** |
| Notification poll interval 60 s while the dropdown is closed | HAR → `assets/9a3d26e5/notifications.js`: `setInterval(function() { if (!$('#header div.dropdown-menu').is(':visible')) { $.post(notification_urls.refresh, …) } }, 60000)` | **Certain** |
| Authenticated chrome markers | `references/pages/UWCRCN W4.html` contains `user-panel"` and the literal text `Welcome, Jonathan Bangert` | **Certain** |
| Response headers / no-store caching | HAR entry 0 response: `Cache-Control: no-store, no-cache, must-revalidate`, `Pragma: no-cache`, `Expires: Thu, 19 Nov 1981 08:52:00 GMT`, `Server: Apache/2.4.59 (Debian) mpm-itk/2.4.7-04 OpenSSL/1.1.1n`, `Content-Type: text/html; charset=UTF-8` | **Certain** |
| Login form field names, `yt0=Login`, 2FA route `site/verify2fa` | **Only** `README.md:92-125`. There is **no** login page, no `LoginForm` string, no `verify2fa` string, and no ClientJS asset anywhere in `references/` (verified by grep across `references/pages/` and the HAR). | **README-only** |
| OTP field name(s) on `site/verify2fa`; whether `PHPSESSID` rotates on login; whether the 2FA page has a "trust this device" control; the exact login-error node class | Nothing | **UNKNOWN — needs live capture** |

> **The single most valuable capture that would de-risk this layer** is a HAR of one full login:
> `GET site/login` → `POST site/login` → 2FA page → `POST` OTP → home. It resolves the OTP field
> name, the OTP form's `action`, the submit button name/value, whether `PHPSESSID` rotates, and the
> error node used for a wrong password. Until then, `W4LoginForm` (§7.4) must stay
> *discovery-based* — parse whatever form is on the page rather than hardcode names.

---

## 1. Type inventory

New/renamed files, all under `ios/BetterW4/`. Package prefix on every type is `W4`.

| Swift type | File | Replaces (iOS) | Mirrors (Kotlin) |
|---|---|---|---|
| `enum W4Hosts` | `W4Hosts.swift` | ad-hoc `contains("lectio.dk")` in 78 places | `W4Hosts.kt:6-15` |
| `enum W4URLs` (+ `W4URLs.Route`) | `W4URLs.swift` | hardcoded `"https://www.lectio.dk/lectio/\(schoolId)/…"` strings | `W4Urls.kt:15-183` |
| `enum W4Dates` | `W4Dates.swift` | — | `W4Dates.kt:11-37` |
| `struct W4Credentials` | `W4Models.swift` | `StudentModels.swift:59-172` | `W4Credentials.kt:11-92` |
| `struct W4Request` / `struct W4Response` | `W4Models.swift` | tuple return of `performRequest` | `W4Request.kt:5-20`, `W4Response.kt:5-16` |
| `enum FetchPriority` | `W4Models.swift` | `W4HTTPClient.swift:594-597` (moved, unchanged) | `FetchPriority.kt:7-13` |
| `enum W4Error` | `W4Errors.swift` | `StudentModels.swift:206-250` | `W4Error.kt:9-79` |
| `enum W4CookieJar` | `W4CookieJar.swift` | `CookieManager.swift` (gutted) | `W4CookieJar.kt` + `CookieHeaderBuilder.kt` + `SetCookieParser.kt` |
| `enum W4UserAgent` | `W4UserAgent.swift` | inline UA strings at `W4HTTPClient.swift:379,441`, `W4ImageLoader.swift:59` | `W4UserAgent.kt:9-17` |
| `actor PriorityRequestLimiter` | `W4RequestGate.swift` | `W4HTTPClient.swift:606-703` (moved, `private` → `internal`, + acquire timeout) | `PriorityRequestLimiter.kt:25-123` |
| `final class W4HTTPEngine` | `W4HTTPEngine.swift` | core of `W4HTTPClient.swift` | `W4HttpEngine.kt:42-308` |
| `final class W4Client` | `W4Client.swift` | `W4HTTPClient` façade + its 7 `+Feature` extensions | `W4Client.kt:25-312` |
| `enum YiiForm` | `YiiForm.swift` | `SmartPostback`/ASP.NET helpers | `YiiForm.kt:10-84` |
| `enum W4LoginForm` | `W4LoginForm.swift` | — | `W4Form.kt:12-90` |
| `enum W4HTML` | `W4HTML.swift` | `W4HTTPClient.decodeHTML` (569-577), `isRobotDetectionPage` (579-583, deleted) | `W4Html.kt:10-69` |
| `enum W4Session` | `W4Session.swift` | `isW4UniLoginURL` (`W4HTTPClient.swift:116-118`, deleted) | `W4Session.kt:17-48` |
| `enum W4IdentityParser` / `struct W4Identity` | `W4IdentityParser.swift` | `StudentParser.parseStudentInfo` | `W4IdentityParser.kt:5-24` |
| `protocol W4CredentialStore` + `KeychainManager` + `InMemoryCredentialStore` | `KeychainManager.swift` | `KeychainManager.swift` (edited) | `CredentialStore.kt:17-170` |
| `enum W4DeviceIDStore` | `W4DeviceIDStore.swift` | — | `W4DeviceIdStore.kt:19-48` |
| `final class W4LoginClient` | `W4LoginClient.swift` | — | `W4LoginClient.kt:46-188` |
| `final class W4AuthService` | `W4AuthService.swift` | `AuthenticationService.swift` (rewritten) | `AuthSessionInstaller.kt:38-335` |
| `enum W4SessionEvents` | `W4SessionEvents.swift` | `Notification.Name.w4SessionExpired` (`StudentModels.swift:198-204`) | `SessionEvents.kt:14-24` |
| `enum W4LastLoginStore` | `W4LastLoginStore.swift` | `LastSchoolStore` (**referenced but undefined** — `AuthenticationViewModel.swift:45,67,…`) | `LastSchoolStore.kt:60-120` |
| `enum W4MultipartBuilder` | `W4Multipart.swift` | `W4HTTPClient+Messages.swift:877-914` (generalised) | — (iOS-only, better than Android) |
| `actor W4ImageLoader` | `W4ImageLoader.swift` | same file, retargeted | `W4AuthInterceptor.kt` (worse; see §9) |
| `W4Client` chrome extensions | `W4Chrome.swift` | — | `W4Chrome.kt:11-76` |

**Deleted outright:** `W4WebView.swift`, `SchoolPickerView` (referenced at `LoginView.swift:26`),
`W4ActiveWebViewRegistry` (`CookieManager.swift:12-46`), `StudentManager.swift`,
`W4HTTPClient+Student.swift`, all seven `W4HTTPClient+*.swift` Lectio scrapers (their *shapes*
inform the new feature specs but none of their URLs survive).

---

## 2. `W4Hosts`, `W4UserAgent`, `W4Dates`

```swift
enum W4Hosts {
    static let host = "w4.uwcrcn.no"
    static let origin = "https://w4.uwcrcn.no"
    static func isW4Host(_ host: String?) -> Bool     // exact match or ".w4.uwcrcn.no" suffix, case/dot-insensitive
    static func isW4URL(_ url: URL) -> Bool           // https + isW4Host(url.host)
}
```
Port of `W4Hosts.kt:10-14`: lowercase, trim, strip a leading `.`, then `== host || hasSuffix(".\(host)")`.
`isW4URL` must additionally require `scheme == "https"` — the existing
`W4ImageLoader.isW4URL` (`W4ImageLoader.swift:129-132`) already does this; keep that behaviour.
**Nothing outside `W4Hosts` may ever attach a `Cookie` header.** This is the whole reason the type
exists: today `W4ImageLoader.swift:31-34` is the only call site that checks, and it checks
`lectio.dk`.

```swift
enum W4UserAgent {
    static let value = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    static let referer = W4Hosts.origin
    static let ajax = "XMLHttpRequest"
}
```
Exact string from `W4UserAgent.kt:11-13`, so both apps present one identity to a shared server.
It must be **stable across releases** (`W4UserAgent.kt:6-8`: "Do not rotate — W4 is a small Apache
box"). The captured browser UA in the HAR is `Chrome/151.0.0.0` on X11/Linux, so a desktop-Linux UA
is demonstrably accepted. Delete the three inline macOS-Chrome-120 strings
(`W4HTTPClient.swift:379,441`, `W4ImageLoader.swift:59`) and the `Referer: https://www.lectio.dk`
values next to them (`W4HTTPClient.swift:380,442`, `W4ImageLoader.swift:58`).

```swift
enum W4Dates {
    static func parse(_ value: String) -> Date?       // DateComponents-based, en_GB, UTC-free (calendar day)
    static func format(_ date: Date) -> String        // "dd-MMM-yyyy" → "14-Aug-2026"
}
```
Formats in priority order, from `W4Dates.kt:12-20`: `d-MMM-yyyy`, `dd-MMM-yyyy`, `d-MMM-yy`,
`dd-MMM-yy`, ISO `yyyy-MM-dd`, `d/M/yyyy`, `dd/MM/yyyy`. Use `Locale(identifier: "en_GB_POSIX")`
and a fixed `Calendar(identifier: .gregorian)` so a Danish device locale cannot break parsing.
README §8 line 407: *"W4 uses `dd-M-yy` (`14-Aug-2026`) and `en-GB` datepicker."*

---

## 3. `W4URLs` — Yii `r=` route building

### 3.1 The three rules

1. **Route goes in the `r` query key.** `https://w4.uwcrcn.no/index.php?r=academics/timetable/mytimetable`.
2. **Extra params are *sibling* query keys, never part of `r`.** `people/students/student&uwc_id=nc26jban`
   becomes `?r=people/students/student&uwc_id=nc26jban`, i.e. the `&uwc_id=` is a second query key.
   Evidence: `references/pages/UWCRCN W4.html` links, and `W4Urls.kt:11-14` documents exactly this.
   A route string handed to the client **may** carry inline sibling keys and the builder must split
   them out (`W4Urls.kt:157-172`).
3. **The route-encoding quirk: `/` inside the `r` value stays literal.** W4's own links are
   `r=site/login`, not `r=site%2Flogin`. Kotlin achieves this by percent-encoding each `/`-separated
   segment individually and rejoining with a raw `/`, then post-fixing `+` → `%20`
   (`W4Urls.kt:174-178`).

### 3.2 The Swift trap you must avoid

**Do not use `URLComponents.queryItems`.** Its percent-encoding uses `CharacterSet.urlQueryAllowed`,
which contains `&`, `=`, `+`, `?` and `/`. A value like `On a walk & back` or a base64-ish token
containing `+` would be emitted raw and silently corrupt the request (PHP decodes `+` as a space).
Build `percentEncodedQuery` yourself:

```swift
enum W4URLs {
    static let index = "index.php"

    /// Form-encodes a single component: alphanumerics + "-._~" pass through, everything else
    /// becomes %XX (UTF-8). Space becomes %20, never "+".
    static func encodeComponent(_ s: String) -> String

    /// Percent-encodes each "/"-separated segment but re-joins with a literal "/".
    static func encodeRoute(_ route: String) -> String

    static func origin() -> URL
    static func route(_ r: String, query: [String: String] = [:]) -> URL
    static func resolve(_ pathOrURL: String, query: [String: String] = [:]) -> URL?
    static func routeOf(_ url: URL) -> String?
    static func routeOf(_ url: String) -> String?
    static func student(uwcID: String) -> URL          // route(.studentProfile, ["uwc_id": uwcID])
    internal static func splitRouteAndQuery(_ raw: String) -> (route: String, query: [String: String])
}
```

`encodeComponent` already exists on iOS as `W4HTTPClient.formURLEncode`
(`W4HTTPClient.swift:585-589`) — allowed set `alphanumerics ∪ {-, ., _, ~}`. Lift it verbatim.

**`route(_:query:)` algorithm** (port of `W4Urls.kt:22-36`):
1. `splitRouteAndQuery(r)` → `(routeName, inlineQuery)`.
2. Merge: `inlineQuery` first, then `query` (explicit wins). Drop any key literally named `r`.
3. Emit `\(origin)/index.php?r=\(encodeRoute(routeName))` then, **in insertion order**,
   `&\(encodeComponent(k))=\(encodeComponent(v))` for each merged pair.
   `r` must be the first key — every W4-generated link does this and Referer-matching is cheap insurance.
4. Query ordering must be deterministic (use an ordered array of pairs internally, or sort by key
   after the merge). `[String: String]` is unordered in Swift; **the implementation must not iterate
   a `Dictionary` directly** or tests will flake. Recommended: the public API takes
   `[String: String]` for ergonomics and sorts keys ascending before emitting; the tests in §10
   assume sorted order.

**`splitRouteAndQuery`** (port of `W4Urls.kt:157-172`): trim, strip leading `/`; if there is no `&`,
the whole string is the route; otherwise everything before the first `&` is the route and the
remainder is split on `&`, each part split on the first `=`, both sides percent-*decoded*, and any
key named `r` or empty is dropped.

**`resolve`** (port of `W4Urls.kt:48-62`) accepts, in this order:
- an absolute URL (`https://…`) → used as-is, plus `query` appended;
- a path starting with `/` → `origin + path`;
- a string starting with `index.php` or `?r=` → `origin + "/" + s`;
- otherwise a bare route → `route(s, query)`.

**`routeOf`** (port of `W4Urls.kt:67-73`): percent-decode the whole URL string, regex
`[?&]r=([^&]+)` case-insensitive, take group 1, trim, strip a trailing `/`. Decoding first is what
makes `r=site%2Flogin` and `r=site/login` both classify as the login page.

### 3.3 `W4URLs.Route`

A `enum Route { static let … }` namespace of `String` constants, ported 1:1 from
`W4Urls.kt:75-149`. The full list (do not paraphrase, these are the wire values):

`site/index`, `site/login`, `site/logout`, `site/otp`, `site/verify2fa`, `site/forgotpass`,
`site/profile`, `site/password`, `site/rss`, `site/setstatus`, `site/relnotes`;
`academics/deadlines`, `academics/timetable/mytimetable`, `academics/timetable/mytimetable/index`,
`academics/classes/myclasses`, `academics/classes/allclasses`, `academics/classes/assessments/all`,
`academics/grades/grades`, `academics/grades/grades/sat`, `academics/transcripts/transcripts`,
`academics/rop`, `academics/ee`, `academics/testimonial`, `academics/feeds`,
`academics/subjects/pages`, `academics/trips`, `academics/travel/travel.list`,
`academics/resources/resources`, `academics/timetable/room`;
`extraacademics/timetable/mytimetable`, `extraacademics/timetable/mytimetable/index`,
`extraacademics/activities/myactivities`, `extraacademics/activities/myactivities/diary`,
`extraacademics/activities/myportfolio`, `extraacademics/activities/interviews`,
`extraacademics/safetynet/mysafetynet`, `extraacademics/activities/ea`, `extraacademics/documents`;
`people/students/absences`, `people/students/absences/register`, `people/students/eaabsences`,
`people/students/student`, `people/students/all`, `people/students/firstyear`,
`people/students/secondyear`, `people/students/staff`, `people/staff/current`,
`people/staff/staff`, `people/students/letter/attendance`, `people/birthdays`;
`mailer/inbox`, `mailer/archive`, `mailer/view`, `mailer/send`, `mailer/extra`;
`documents/index`, `admissions/browse/admissions`;
`notifications/read`, `notifications/readgroup`, `notifications/readall`,
`notifications/readallemails`, `notifications/clear`, `notifications/cleargroup`,
`notifications/clearall`, `notifications/refresh`.

The eight `notifications/*` values and `site/setstatus` are **verified against a live page**
(`references/pages/Documents.html:19-20`); the rest are from `W4Urls.kt` / README §6.

**No `gymId`, no `schoolId`, no `/lectio/{id}/` path segment appears anywhere in this type.**

---

## 4. Models

### 4.1 `W4Credentials`

```swift
struct W4Credentials: Codable, Equatable, Sendable {
    var sessionID: String                      // PHPSESSID; "" means "no session yet"
    var additionalCookies: [String: String]    // must never contain "PHPSESSID"

    static let cookieName = "PHPSESSID"

    var isEmpty: Bool { sessionID.isEmpty }
    func clearingSessionID() -> W4Credentials
    func withSessionID(_ new: String) -> W4Credentials
    static let empty = W4Credentials(sessionID: "", additionalCookies: [:])
}
```

Deletions from `StudentModels.swift:59-172`: `autologinkey`, `autologinkeyExpiresAt`,
`sessionIdExpiresAt`, `isValid`, `isExpiringSoon`, `clearingASPNETSessionId()`,
`withASPNETSessionId(_:)`, `clearingAutologinkeyV2()`, `withAutologinkeyV2(_:)`, and the
`isloggedin3` seeding (`CookieManager.swift:103-106`, `KeychainManager.swift:81-94`).

**No expiry fields.** README §4.1: `PHPSESSID` is a session cookie with no `Max-Age`/`Expires`;
server-side PH​P GC decides. Any client-side expiry check would be a lie. The Kotlin port kept
`sessionIdExpiresAt` (`W4Credentials.kt:14-20`) purely for JSON compatibility with the old Lectio
store — iOS is a fresh keychain namespace and should not inherit that. `additionalCookies` stays
because merging is defensive: if W4 ever sets a second cookie we carry it, but we never *require* it.

### 4.2 `W4Request` / `W4Response`

```swift
struct W4Request {
    var url: URL
    var method: String = "GET"
    var body: Body = .none                // .none | .data(Data) | .file(URL)
    var headers: [String: String] = [:]
    var priority: FetchPriority = .important
    /// When set, the engine re-reads credentials from the store immediately before each attempt
    /// and persists rotations under this id.
    var studentID: String? = nil
    /// Login GETs/POSTs land on site/login on purpose; when true that is not session death.
    var allowLoginPage: Bool = false
    /// jQuery $.post — adds X-Requested-With and applies init_ajax.js 403/409 semantics.
    var ajax: Bool = false
}

struct W4Response {
    let html: String          // decoded per W4HTML.decode
    let data: Data
    let finalURL: URL
    let statusCode: Int
    let contentType: String?
    let contentDisposition: String?
    let credentials: W4Credentials   // jar after this response (PHPSESSID may have rotated)
}
```
Ports of `W4Request.kt:5-20` and `W4Response.kt:5-16`. `Body.file` is the iOS addition that keeps
streaming uploads (§6.6) — Android has no equivalent.

### 4.3 `FetchPriority`

Move `W4HTTPClient.swift:594-597` verbatim into `W4Models.swift`. Two cases, `.important` and
`.opportunistic`; semantics per `FetchPriority.kt:7-13` — opportunistic work waits until no
important work is queued.

### 4.4 `W4Error`

```swift
enum W4Error: Error, LocalizedError, Equatable {
    case invalidURL
    case noResponse
    case offline                       // URLError.notConnectedToInternet / .cannotFindHost / DNS
    case sessionExpired                // definitive: re-auth required
    case invalidCredentials            // retryable auth blip; escalates to .sessionExpired after retries
    case missingCookies                // no PHPSESSID in the store for a request that needs one
    case forbidden                     // HTTP 403 without "Login Required" — wrong role, still logged in
    case serverConflict(String)        // HTTP 409, body is the message
    case http(Int)
    case network(URLError)
    case parse(String)
    case loginFailed(String?)          // server-rendered login error text, if any
    case invalidOTP
    case keychain(OSStatus)
}
```

Port of `W4Error.kt:9-79`. Two Lectio cases are **deleted**: `.robotDetection` (README §4.6 — "Robot
-detection page (not seen on W4)") and `.cookieExpired`. `errorDescription` must be **English**
(the current `StudentModels.swift:217-238` is entirely Danish: *"Din session er udløbet. Log ind
igen"* etc.). All strings go through `en.lproj/Localizable.strings`.

UI mapping (README §4.5 + `W4Error.kt:67-78`):

| Error | UI behaviour |
|---|---|
| `.sessionExpired`, `.missingCookies` | post `.w4SessionExpired` → wipe session → LoginView with username prefilled |
| `.invalidCredentials` | internal only; the engine retries, then converts to `.sessionExpired` |
| `.forbidden` | inline "You do not have access to this page." **Stay signed in.** Never post `.w4SessionExpired` |
| `.serverConflict(body)` | inline "Error from remote server: \(body)" — same wording as `init_ajax.js` |
| `.offline` | offline banner + cached content |
| `.http`, `.network`, `.parse` | inline retryable error |

`W4Error.notifyIfSessionExpired()` (`StudentModels.swift:241-250`) survives but its trigger changes
from `.invalidCredentials` to `.sessionExpired` **and** `.missingCookies`.

---

## 5. `W4CookieJar` — one cookie, merged per hop

```swift
enum W4CookieJar {
    /// "PHPSESSID=<v>" plus any non-empty extras, extras sorted by name. Empty string when no session.
    static func cookieHeader(for credentials: W4Credentials) -> String

    /// Returns nil when nothing changed (so callers do not churn the keychain).
    static func merge(response: HTTPURLResponse, into current: W4Credentials) -> W4Credentials?

    /// "PHPSESSID=abcd…yz" — never a full value. Debug logs only.
    static func redactedPreview(_ credentials: W4Credentials) -> String
}
```

Rules, from README §4.1 and `W4CookieJar.kt:19-67`:

1. **Host gate first.** If `!W4Hosts.isW4Host(response.url?.host)`, return `nil` — merge nothing.
2. Parse with `HTTPCookie.cookies(withResponseHeaderFields:for:)` (handles iOS's folding of multiple
   `Set-Cookie` headers into one comma-joined `allHeaderFields` entry). Keep only cookies whose
   `domain` passes `W4Hosts.isW4Host` after stripping a leading `.`.
3. For `PHPSESSID`: **assign only if the new value is non-empty.** An empty `Set-Cookie: PHPSESSID=;`
   must *not* wipe a live session — this is the single hard-won Lectio lesson worth keeping
   (README §4.1 "Ignore empty values (Lectio taught us that)"; the existing iOS code has the same
   guard at `CookieManager.swift:203-209`).
4. For any other cookie name: empty value → remove the key; non-empty → set it.
5. Return `nil` if the resulting struct equals the input (`CookieManager.swift:226` and
   `W4CookieJar.kt:60-66` both already do this). This gate is what keeps the Keychain quiet.

`cookieHeader` (port of `CookieHeaderBuilder.kt:21-33`): emit `PHPSESSID=<v>` first when non-empty,
then extras sorted by name, skipping empty values, joined with `"; "`. The Lectio-leftover filter in
`CookieHeaderBuilder.kt:15-19` (`autologinkeyV2`, `isloggedin3`) is not needed on iOS because the
keychain namespace is new — but keep a one-line `Set(["autologinkeyV2","isloggedin3","ASP.NET_SessionId"])`
deny-list anyway so a stale restored keychain item can never leak a Lectio cookie to UWC's server.

`logResponseCookies` (`CookieManager.swift:148-169`) survives as-is: it is already `#if DEBUG` and
already prints `\(cookie.name)=<redacted>`. Keep the redaction absolutely.

---

## 6. `W4HTTPEngine` — the request loop

```swift
final class W4HTTPEngine {
    init(store: W4CredentialStore = KeychainManager.shared,
         gate: PriorityRequestLimiter = .shared,
         session: URLSession = W4HTTPEngine.makeSession())

    /// One logical request: gate → up to 3 attempts → manual redirect chain → classified result.
    func execute(_ request: W4Request, credentials: W4Credentials) async throws -> W4Response

    static func makeSession() -> URLSession
    static let shared = W4HTTPEngine()
}
```

### 6.1 `URLSession` configuration

Keep the existing config (`W4HTTPClient.swift:187-194`) — it is already correct and hard-won:

```swift
let config = URLSessionConfiguration.default
config.httpShouldSetCookies = false
config.httpCookieStorage = nil
config.httpCookieAcceptPolicy = .never
config.requestCachePolicy = .reloadIgnoringLocalCacheData
config.timeoutIntervalForRequest = 30
config.timeoutIntervalForResource = 60
```
The comment at `W4HTTPClient.swift:181-184` explains why cookies are fully disabled (session cookies
don't survive app kill in `HTTPCookieStorage`, and a silent merge would override our manual header).
That reasoning holds verbatim for `PHPSESSID`. The timeouts are new; Kotlin uses connect 30 / read 45
/ write 30 (`W4Module.kt:70-72`). `requestCachePolicy` matches W4's `Cache-Control: no-store` (HAR).

### 6.2 Manual redirects — the one structural change

Today the app both auto-follows (delegate at `W4HTTPClient.swift:121-168` returns `completionHandler(request)`)
**and** has a manual 3xx branch (`W4HTTPClient.swift:491-512`) that almost never executes. That must
collapse to one mechanism. README §4.5 line 140: *"Follow redirects **manually** … If you auto-follow,
a dead session becomes a 200 login HTML and parsers will throw garbage."*

The delegate becomes:

```swift
func urlSession(_ session: URLSession, task: URLSessionTask,
                willPerformHTTPRedirection response: HTTPURLResponse,
                newRequest request: URLRequest,
                completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)          // stop here; the engine drives the chain
}
```
Passing `nil` makes `URLSession` return the 3xx response (with its headers, including `Set-Cookie`
and `Location`) to the task's completion handler instead of following it. That is what gives the
engine per-hop `Set-Cookie` visibility with zero registry bookkeeping.

With `nil` redirects, `W4URLSessionTaskCookieRegistry` (`W4HTTPClient.swift:75-97`) and the
in-delegate merge (`:150-166`) become dead weight for HTML traffic. **Keep the registry and
`W4DataTaskCookieContext`** anyway — `W4ImageLoader.swift:84-93` uses them and they cost nothing —
but the engine no longer depends on them.

### 6.3 Attempt loop (outer)

Port of `W4HttpEngine.kt:51-110` onto the shape already at `W4HTTPClient.swift:199-258`.
`maxAttempts = 3`, `maxRedirects = 5` (`W4HTTPClient.swift:175-176`; identical in
`W4HttpEngine.kt:48-49`).

| Thrown from an attempt | Behaviour |
|---|---|
| `.sessionExpired`, `.forbidden`, `.serverConflict` | **rethrow immediately**, no retry (`W4HttpEngine.kt:75-80`) |
| `.invalidCredentials` | retry after 0.5 s (attempt 0) then 1.5 s; after the last attempt convert to `.sessionExpired` and post the notification (`W4HttpEngine.kt:81-85, 105-108`; iOS equivalent `W4HTTPClient.swift:232-236, 253-257`) |
| `URLError.timedOut / .networkConnectionLost / .notConnectedToInternet` | retry after 1 s + jitter, else rethrow as `.offline`/`.network` (`W4HTTPClient.swift:244-247`) |
| `CancellationError` | rethrow, never retry, never post session-expired |
| anything else | rethrow |

Keep iOS's random jitter (`W4HTTPClient.swift:239`) on the backoff; Android uses flat delays.
Delete the `.robotDetection` retry arm (`W4HTTPClient.swift:237-243` and `:352-354`).

### 6.4 Single attempt (inner)

```
withSerialW4Request(priority:) {
    creds = request.studentID.flatMap(store.loadCredentials) ?? credentials      // freshest jar
    url = request.url; redirects = 0
    loop {
        build URLRequest:
            Cookie:           W4CookieJar.cookieHeader(for: creds)      // omit when empty
            User-Agent:       W4UserAgent.value
            Referer:          W4UserAgent.referer
            Accept:           "text/html"  (GET only, unless caller set Accept)
            X-Requested-With: "XMLHttpRequest"  (iff request.ajax)
            + request.headers (Cookie key ignored)
        send (dataTask or uploadTask)
        creds = W4CookieJar.merge(response:into:creds) ?? creds   // persist iff changed & studentID != nil
        switch status { … §6.5 … }
    }
}
```

Two details worth stating explicitly because both are currently wrong on iOS:

- **Do not set `Accept-Encoding` manually.** `W4HTTPClient.swift:381` and `:443` send
  `"gzip, deflate, br"`. `URLSession` sets and transparently decodes its own; overriding it can
  produce an undecoded body. Delete both lines.
- **The redirect log lines at `W4HTTPClient.swift:136-140` and `:467, :493-504` are not `#if DEBUG`-guarded.**
  Every log in this layer must be, and must print only `W4CookieJar.redactedPreview`. `W4RequestLog.outbound`
  (`W4HTTPClient.swift:13-23`) is the correct model — it is `#if DEBUG` and prints cookie *names* only.
  Fix `W4RequestLog.compactPath` (`:25-31`) to drop its `lectio.dk` special case.

### 6.5 Status classification (README §4.5, `W4HttpEngine.kt:179-244`)

| Status | Condition | Result |
|---|---|---|
| 200–299 | `!allowLoginPage && (W4Session.isLoginURL(finalURL) ‖ W4HTML.isLoginHTML(html))` | `.sessionExpired` (+ notification if `studentID != nil`) |
| 200–299 | otherwise | `W4Response` |
| 301/302/303/307/308 | no `Location` header | `.parse("Redirect without Location")` |
| 301/302/303/307/308 | `!allowLoginPage && W4Session.isLoginURL(location)` | `.sessionExpired` |
| 302, 303 | else | follow as **GET**, drop the body (`W4HttpEngine.kt:219-222`) |
| 301, 307, 308 | else | follow with the **same method + body** |
| any 3xx | `redirects >= 5` | `.sessionExpired` if `studentID != nil`, else `.invalidCredentials` (`W4HttpEngine.kt:252-253`) |
| 401, 403 | body contains `"Login Required"` (case-insensitive) | `.sessionExpired` |
| 401, 403 | otherwise | `.forbidden` — **do not log out** |
| 409 | — | `.serverConflict(trimmedBody)` |
| 404 | — | `.http(404)` |
| other | — | `.http(code)` |

The 403/409 split is not a guess: `init_ajax.js` in the HAR does exactly this
(`data.search('Login Required') >= 0 → location.href='/'`, else `alert('Error 403: not authorized')`,
and `409 → alert('Error from remote server: ' + data)`).

`Location` resolution: try an absolute URL first, else resolve relative to the current URL —
`URL(string: location, relativeTo: currentURL)` (already correct at `W4HTTPClient.swift:498-499`).

### 6.6 Bodies, forms and multipart

- **urlencoded:** `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`. Encode with
  `W4URLs.encodeComponent` per key and value, joined `k=v&k=v`, **keys sorted** for test determinism.
  Never `+` for space. (`W4Form.kt:21-29` uses OkHttp's `FormBody`, which is `%20`-for-space too.)
- **jQuery `$.post`:** same body, plus `X-Requested-With: XMLHttpRequest`
  (`W4Client.kt:155-158`, README §5.3). No W4 code path currently sends this header on iOS.
- **multipart:** keep the streaming implementation. `W4MultipartBuilder.makeBodyFile(fields:files:boundary:)`
  generalises `W4HTTPClient+Messages.swift:877-914` (which today hardcodes one part named `"file"`):

```swift
enum W4MultipartBuilder {
    struct FilePart { let name: String; let filename: String; let mimeType: String; let url: URL }
    /// Writes to FileManager.temporaryDirectory/BetterW4Uploads/<uuid>; caller deletes it.
    static func makeBodyFile(fields: [(String, String)],
                             files: [FilePart],
                             boundary: String = "BetterW4-\(UUID().uuidString)") throws -> URL
}
```
  It must keep the 256 KB chunked copy loop (`:905-907`) so a 2 MB attachment never materialises in
  RAM. W4's mailer takes up to 5 × 2 MB as `MailerForm[attachment][]` (README §5.2), so `files` is an
  array and the same `name` repeats — the builder must not deduplicate by name.
  `performFileUploadRequest` (`W4HTTPClient.swift:322-364`) survives; retarget its hardcoded UA,
  Referer and `Origin: https://www.lectio.dk` header (`W4HTTPClient+Messages.swift:865`) to
  `W4Hosts.origin`.

### 6.7 `PriorityRequestLimiter` — keep, with one import from Android

The existing actor (`W4HTTPClient.swift:606-703`) is the better implementation of the two and must
survive intact:
- per-waiter `UUID` + `withTaskCancellationHandler` (`:624-631`) so a cancelled SwiftUI `.task`
  removes itself from the queue instead of deadlocking the gate;
- the `pendingAcquisitionIDs` / `cancelledWaiterIDs` handshake (`:642-678`) covers the race where a
  waiter is handed the slot and *then* cancelled — `begin` re-checks cancellation at `:634` and
  calls `end()` at `:637`;
- 100 ms minimum gap between consecutive requests (`:618, :680-687`) — README §5.5 "be kind; this is
  a tiny school server".

Required changes:
1. `private actor` → `actor` (+ a `static let shared`) so `BetterW4Tests` can drive it directly.
2. Add Android's **acquire timeout**: `PriorityRequestLimiter.kt:37-49, 121` fails a waiter after
   90 s rather than letting a hung background request pin the UI forever. Swift: wrap `acquireSlot`
   in a `withThrowingTaskGroup` race against `Task.sleep(for: .seconds(90))`, throw
   `W4Error.network(URLError(.timedOut))` on loss.
3. The gate is process-global. `W4ImageLoader` already routes through it
   (`W4ImageLoader.swift:75-77`) at `.opportunistic`; keep that.

---

## 7. `W4Client` — the façade features talk to

Feature scrapers must depend on `W4Client`, never on `W4HTTPEngine` (`W4Client.kt:20-24`).

```swift
final class W4Client {
    init(engine: W4HTTPEngine = .shared,
         store: W4CredentialStore = KeychainManager.shared,
         session: W4SessionController = .shared)
    static let shared = W4Client()

    func get(_ routeOrURL: String,
             query: [String: String] = [:],
             priority: FetchPriority = .important,
             credentials: W4Credentials? = nil,
             studentID: String? = nil,
             allowLoginPage: Bool = false) async throws -> W4Response

    func postForm(_ routeOrURL: String,
                  fields: [String: String],
                  query: [String: String] = [:],
                  priority: FetchPriority = .important,
                  credentials: W4Credentials? = nil,
                  studentID: String? = nil,
                  allowLoginPage: Bool = false) async throws -> W4Response

    /// jQuery $.post — urlencoded + X-Requested-With. 403+"Login Required" is death,
    /// other 403 is .forbidden, 409 is .serverConflict.
    func postAjax(_ routeOrURL: String,
                  fields: [String: String],
                  query: [String: String] = [:],
                  priority: FetchPriority = .important,
                  credentials: W4Credentials? = nil,
                  studentID: String? = nil) async throws -> W4Response

    func postMultipart(_ routeOrURL: String,
                       bodyFile: URL,
                       contentType: String,
                       query: [String: String] = [:],
                       priority: FetchPriority = .important,
                       credentials: W4Credentials? = nil,
                       studentID: String? = nil) async throws -> W4Response

    /// GET the page, merge its Yii fields + `extra` + the clicked submit button, POST the same URL.
    func postYiiForm(_ routeOrURL: String,
                     extra: [String: String] = [:],
                     submitName: String = "yt0",
                     submitValue: String? = nil,
                     query: [String: String] = [:],
                     priority: FetchPriority = .important,
                     credentials: W4Credentials? = nil,
                     studentID: String? = nil,
                     allowLoginPage: Bool = false) async throws -> W4Response

    func getData(_ routeOrURL: String, query: [String: String] = [:],
                 priority: FetchPriority = .important,
                 credentials: W4Credentials? = nil,
                 studentID: String? = nil) async throws -> Data

    func url(_ routeOrURL: String, query: [String: String] = [:]) -> URL
}
```

Signatures are `W4Client.kt:26-91` with Kotlin's `AppResult<T>` replaced by `throws` (idiomatic
Swift, and the existing iOS client already throws). `postMultipart` takes a **file URL**, not
`ByteArray` — the deliberate divergence from `W4Client.kt:58-66`.

**Credential resolution** (port of `W4Client.kt:278-302`), executed before every call:
1. Explicit `credentials` given → use it; but if its `sessionID` is empty **and** `!allowLoginPage`,
   emit session-expired and throw `.missingCookies`.
2. No `studentID` → if `allowLoginPage`, use `W4Credentials.empty` (this is the login GET);
   otherwise emit session-expired and throw `.missingCookies`.
3. Load from the store; `nil` or empty `sessionID` → emit session-expired, throw `.missingCookies`.

"Emit session-expired" = `W4SessionEvents.postSessionExpired()`, but **only when a non-demo student
is currently signed in** (`W4Client.kt:304-309`). Emitting while already signed out just churns the
login screen.

### 7.1 `YiiForm`

```swift
enum YiiForm {
    struct Parsed { let action: String?; let fields: [String: String]; let submitButtons: [String: String] }
    static func parse(_ html: String, selector: String? = nil) throws -> Parsed
    static func parse(form: Element) throws -> Parsed                       // SwiftSoup.Element
    static func fieldsForSubmit(html: String, extra: [String: String] = [:],
                                submitName: String = "yt0", submitValue: String? = nil,
                                selector: String? = nil) throws -> [String: String]
    static func encode(_ fields: [String: String]) -> Data
}
```
Port of `YiiForm.kt:18-83` using SwiftSoup (already a dependency of **both** targets —
`BetterW4.xcodeproj/project.pbxproj:10-11, 505-514`). Element rules, verbatim from `YiiForm.kt:31-57`:
- `textarea` → its text;
- `select` → the **last** `option[selected]`, else the first `option`, taking `value` then text;
- `input[type=checkbox|radio]` → included only when `checked`, value defaults to `"on"`;
- `input[type=submit|button|image]` → goes to `submitButtons`, not `fields`;
- `input[type=file]` → skipped;
- everything else → its `value` attribute.

`fieldsForSubmit` merges `extra` over the parsed fields and then sets
`fields[submitName] = submitValue ?? submitButtons[submitName] ?? submitButtons.values.first ?? ""`
(`YiiForm.kt:73-82`). README §3 line 55: *"Yii button names on forms are `yt0`, `yt1`, … Include the
clicked button name when posting a Yii form."* There is **no CSRF token** on W4 (README §3 line 52) —
do not look for `YII_CSRF_TOKEN`.

### 7.2 `W4HTML`

```swift
enum W4HTML {
    static let uwcIDPattern = #"\b(nc\d{2}[a-z]+)\b"#          // case-insensitive
    static func decode(_ data: Data) -> String
    static func isLoginHTML(_ html: String) -> Bool
    static func isAuthenticatedHTML(_ html: String) -> Bool
    static func isAjaxLoginRequired(_ body: String) -> Bool
    static func displayName(_ html: String) -> String?
    static func uwcID(_ html: String) -> String?
    static func contentInner(_ html: String) -> String?
}
```
Port of `W4Html.kt:10-68`:
- `decode`: UTF-8 first; if the result contains U+FFFD, retry ISO-8859-1. The existing
  `W4HTTPClient.decodeHTML` (`:569-577`) tries UTF-8 → isoLatin1 but **without** the replacement-char
  check, so it never falls back (UTF-8 decoding of arbitrary bytes rarely returns nil in Swift's
  `String(data:encoding:)`… but when it does succeed lossily you get mojibake). Adopt the Kotlin check.
  W4 declares `charset=UTF-8` (HAR response header), so this is belt-and-braces.
- `isLoginHTML`: contains `"LoginForm[username]"` **or** `"Login Site"`, case-insensitive.
  *(The `"Login Site"` title string is from README §4.5 item 2 only — no captured login page exists.
  Treat it as a secondary signal; the `LoginForm[username]` substring is the load-bearing one.)*
- `isAuthenticatedHTML`: (contains `"Welcome,"` **or** `id="user-panel"` / `id='user-panel'`) **and**
  `!isLoginHTML`. Both markers verified present in `references/pages/UWCRCN W4.html`.
- `isAjaxLoginRequired`: contains `"Login Required"`, case-insensitive (from `init_ajax.js`).
- `displayName`: `#user-panel .right` own-text → regex `Welcome,\s*([^|<]+)`; fall back to
  `#user-panel` own-text/text, strip anything from `"Logout"` onward, trim.
- `uwcID`: prefer `a[href*=people/students/student][href*=uwc_id]` whose link text contains
  `"profile"`, else the first such anchor, else the first `uwcIDPattern` match anywhere; lowercase it.
  (`W4Html.kt:55-63`. The saved home page yields `nc26jban` for the signed-in user this way.)

### 7.3 `W4Session`

```swift
enum W4Session {
    static func isLoginURL(_ url: URL) -> Bool
    static func isLoginURL(_ url: String) -> Bool
    static func isOTPURL(_ url: URL) -> Bool
    static func isOTPURL(_ url: String) -> Bool
    static func isHomeURL(_ url: URL) -> Bool
    static func isHomeURL(_ url: String) -> Bool
    static func isAuthProgressURL(_ url: URL) -> Bool     // isOTPURL || isHomeURL
}
```
Port of `W4Session.kt:19-47`. All of them work on `W4URLs.routeOf(url)?.lowercased()`:
- login ⇔ route == `site/login`;
- OTP ⇔ route == `site/otp` **or** `site/verify2fa` **or** (route starts with `site/` and contains
  `otp`/`2fa`/`verify`) — the fuzzy third clause is deliberate insurance against the unverified route
  name (README §4.4 says `site/otp` exists but 302s when unauthenticated; `site/verify2fa` is the
  live one as of 14 Aug 2026);
- home ⇔ route == `site/index` or `site`.

This type replaces `isW4UniLoginURL` (`W4HTTPClient.swift:116-118`) 1:1 as the "is this URL a
logout signal" oracle. README §8 maps it explicitly: *"`UniLoginDetector` → `Location` contains
`r=site/login` or body has `LoginForm`."*

### 7.4 `W4LoginForm`

```swift
enum W4LoginForm {
    struct Parsed {
        let action: String?
        let fields: [String: String]        // hidden/current values, minus the OTP field
        let submitName: String?
        let submitValue: String?
        let otpFieldName: String?
    }
    static func parse(_ html: String) -> Parsed?
    static func loginError(_ html: String) -> String?
    static func inputInventory(_ html: String) -> String     // debug only
}
```
Port of `W4Form.kt:31-89`. Form selection order (`W4Form.kt:33-37`), first match wins:
1. `form:has(input[name^=LoginForm])`
2. `form[action*=otp], form[action*=verify2fa], form[action*=2fa]`
3. `#content_inner form, #content form`
4. `form`

OTP-field discovery (`W4Form.kt:75-85`) — this is the part that has to survive an unknown field name:
take all `input[name]` in the form, drop anything whose name starts with `LoginForm` and anything
whose `type` ∈ `{hidden, submit, checkbox, radio, button, file, image}`; then pick the first whose
**name** matches
`/otp|totp|2fa|code|token|pin|sms|verify|verification|authenticator|onetime|one[_-]?time/i`,
else the single remaining candidate, else the first candidate.

`loginError` (`W4Form.kt:50-62`): `.errorSummary li` → `.errorSummary` → `.flash-error, .alert-error,
.errorMessage, div.error`; first non-empty trimmed text. **UNKNOWN — needs live capture:** which of
these W4 actually renders on a bad password. Yii 1's default is `.errorSummary`; the code tries all
of them and returns `nil` if none match, in which case the UI shows a generic
"Wrong username or password."

`inputInventory` returns `name:type` pairs for debug logging when OTP discovery fails
(`W4Form.kt:64-68`, used at `W4LoginClient.kt:131, 145-147`). It must be `#if DEBUG` on iOS and must
never print `value` attributes.

### 7.5 `W4Chrome` — client extensions

Port of `W4Chrome.kt:11-76`, verified against the two JS files in the HAR:

```swift
extension W4Client {
    /// POST site/setstatus {status:"on"|"off", location:<label>}. On campus → location omitted.
    func setCampusStatus(onCampus: Bool, location: String? = nil,
                         priority: FetchPriority = .important) async throws -> W4Response
    func refreshNotifications(priority: FetchPriority = .opportunistic) async throws -> W4Response
    func markNotificationRead(_ notificationID: String) async throws -> W4Response       // notification_id
    func markNotificationGroupRead(type: String) async throws -> W4Response              // notification_type
    func markAllNotificationsRead() async throws -> W4Response
    func markAllNotificationEmailsRead() async throws -> W4Response
    func clearNotification(_ notificationID: String) async throws -> W4Response
    func clearNotificationGroup(type: String) async throws -> W4Response
    func clearAllNotifications() async throws -> W4Response
}
```
All of these are `postAjax`. `location` is omitted (not sent empty) when `onCampus == true` —
`campusstatusdropdown.js` sends JS `null`, which jQuery drops from the payload; free-text "other"
has `maxlength=20` (README §5.3). All responses are **HTML fragments** to swap into
`div.notifications`, not JSON (README §5.3 line 247).

---

## 8. Session, credentials, identity, auth

### 8.1 `W4CredentialStore` + `KeychainManager`

```swift
protocol W4CredentialStore: AnyObject {
    func saveCredentials(_ c: W4Credentials, for studentID: String) throws
    func loadCredentials(for studentID: String) -> W4Credentials?
    func updateCredentials(_ c: W4Credentials, for studentID: String) throws
    func deleteCredentials(for studentID: String) throws
    func saveStudent(_ s: W4Student) throws
    func loadStudent() -> W4Student?
    func deleteStudent() throws
    func wipeAll()
}
```
`KeychainManager` (`KeychainManager.swift`) already implements every one of these; it conforms with
three edits:
1. `service` (`:17`) `"dk.elliottf.betterw4"` → `"dk.jonathanb.w4"` (the shipping bundle id) so the
   port never reads a Lectio-era item. Account keys stay `w4.credentials.<studentID>` (`:255-257`)
   and `w4.student.current` (`:149`).
2. Delete the `isloggedin3` migration block (`:81-94`) — Lectio-only.
3. English error text; `W4Error.keychain(OSStatus)` instead of `keychainError(String)` with Danish
   messages (`:46, 122, 141, 171, 186, 233`).

Keep `kSecAttrAccessibleAfterFirstUnlock` (`:40, 180`) for credentials — background refresh needs
the item before first unlock in a day.

`InMemoryCredentialStore` is a new test double, mirroring `CredentialStore.kt:138-170`.

`W4Student` replaces `Student` (`StudentModels.swift:12-23`): `uwcID: String` (the `nc26jban` value,
used as the store key), `name: String?`, `isDemo: Bool`. **`gymId` and `School` are deleted** — W4 is
one host (README §4.6). That touches 447 `gymId` occurrences across 40 files and 186 `schoolId`
occurrences; to keep the tree compiling while features are ported one at a time, add a single
transitional `enum W4School { static let id = 1; static let name = "UWC Red Cross Nordic" }`
(mirrors `Student.kt:33-37`) and delete it when the last feature file stops referencing it. It must
never reach a URL.

### 8.2 `W4DeviceIDStore`

```swift
enum W4DeviceIDStore {
    /// Stable per-install UUID, created on first use. Never a ClientJS fingerprint.
    static func getOrCreate() -> String
    static func reset()          // debug only, exposed nowhere in the UI
}
```
Port of `W4DeviceIdStore.kt:24-29`. Storage: Keychain generic-password, service `"dk.jonathanb.w4"`,
account `"w4.deviceId"`, accessibility **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** so the
value never syncs to iCloud Keychain or lands in an encrypted backup — a device restored from backup
*should* look like a new device to W4's 2FA. Value: `UUID().uuidString`.

README §4.4 lines 118, 123: *"a **stable per-install UUID**, persisted in EncryptedSharedPreferences
— not a ClientJS fingerprint … A stable `deviceId` is enough for v1: the first login on this install
looks like a new device (OTP once); later launches reuse the same id. Reimplementing ClientJS is
unnecessary."* Do not ship `client.base.min.js`, do not run JS, do not use `identifierForVendor`
(it resets when all the vendor's apps are deleted, silently re-triggering OTP).

**Never log the deviceId.** It is a device-binding secret in the same class as the session cookie.

### 8.3 `W4SessionEvents` and `W4SessionController`

```swift
enum W4SessionEvents {
    static let sessionExpired = Notification.Name("dk.jonathanb.w4.sessionExpired")
    static func postSessionExpired()      // idempotent at the observer, not the poster
}
```
Rename of `StudentModels.swift:198-204` (whose raw value is `"dk.elliottf.betterw4.sessionExpired"`).
Kotlin equivalent: `SessionEvents.kt:14-24`.

`W4SessionController` (@MainActor, `ObservableObject`) owns `AuthState`
(`StudentModels.swift:176-194` survives unchanged apart from `Student` → `W4Student`) and mirrors
`SessionController.kt:33-141`:

```swift
@MainActor final class W4SessionController: ObservableObject {
    @Published private(set) var authState: AuthState = .loading
    var currentStudent: W4Student? { authState.student }
    static let shared = W4SessionController()

    func restore()                                                  // cold start
    func install(student: W4Student, credentials: W4Credentials?)
    func installDemoSession()
    func clearSession(keepStudentProfile: Bool = false)
    func loadCredentialsForCurrentStudent() -> W4Credentials?
}
```
`restore()` (`SessionController.kt:79-97`): no stored student → `.unauthenticated`; demo student →
`.authenticated` with no network; stored student but missing/empty `PHPSESSID` → remember the
username hint, delete the student record, `.unauthenticated`.

`handleSessionExpired` observes `W4SessionEvents.sessionExpired` and is **idempotent** — it returns
early for demo students and for an already-unauthenticated state
(`SessionController.kt:60-77`; the iOS analogue is `AuthenticationViewModel.swift:64-81` and its
guard at `:65` already does this). Keep that guard: several view models can surface the same dead
session in the same runloop tick.

### 8.4 `W4LastLoginStore`

```swift
enum W4LastLoginReason: String { case sessionExpired, loggedOut }
struct W4LastLoginHint: Codable { let username: String?; let reason: W4LastLoginReason }
enum W4LastLoginStore {
    static func load() -> W4LastLoginHint?
    static func save(_ hint: W4LastLoginHint)
    static func remember(student: W4Student, reason: W4LastLoginReason)
    static func clear()
}
```
`UserDefaults`, **not** Keychain: the username is not a secret and this store must never hold a
password, a cookie or the deviceId (`LastSchoolStore.kt:14-16` says exactly that). It replaces the
`LastSchoolStore`/`LastSchoolHint` types that `AuthenticationViewModel.swift:45, 67-68, 162, 199, 219,
348-354, 397` calls but which **do not exist anywhere in `ios/BetterW4/`** — verified by grep; the
tree currently does not compile. Purpose shrinks from "one-tap MitID at the last school" to "prefill
the username field and explain why the user is back at the login screen."

### 8.5 `W4LoginClient` — the login/2FA state machine

```swift
struct W4OTPChallenge {
    let credentials: W4Credentials
    let formAction: URL
    let hiddenFields: [String: String]
    let otpFieldName: String
    let submitName: String?
    let submitValue: String?
}

enum W4LoginStep {
    case authenticated(credentials: W4Credentials, html: String, finalURL: URL)
    case needsOTP(W4OTPChallenge)
    case failed(message: String?, invalidOTP: Bool)
}

final class W4LoginClient {
    init(engine: W4HTTPEngine = .shared)
    func submitPassword(username: String, password: String) async throws -> W4LoginStep
    func submitOTP(_ challenge: W4OTPChallenge, code: String) async throws -> W4LoginStep
}
```
Port of `W4LoginClient.kt:46-188`.

**`submitPassword` — exact sequence** (README §4.4 steps 1-6, `W4LoginClient.kt:50-89`):

1. `let loginURL = W4URLs.route(.login)` → `https://w4.uwcrcn.no/index.php?r=site/login`.
2. `engine.execute(W4Request(url: loginURL, method: "GET", priority: .important, allowLoginPage: true),
   credentials: .empty)`.
   `allowLoginPage: true` is mandatory — without it the engine's rule §6.5 would classify the login
   page as session death. The response's `Set-Cookie` gives the initial `PHPSESSID`
   (README §4.2: `GET index.php?r=site/login` is 200 + login HTML and sets `PHPSESSID` if you had none).
   **The cookie you were given must be sent on the POST** — Yii sessions are sticky to that id
   (README §4.2 line 88).
3. `let parsed = W4LoginForm.parse(html)`; build the body with
   `YiiForm.fieldsForSubmit(html:extra:submitName:submitValue:selector:)` where
   - `selector = "form:has(input[name^=LoginForm])"`,
   - `extra = ["LoginForm[username]": username.trimmed,
               "LoginForm[password]": password,
               "LoginForm[deviceId]": W4DeviceIDStore.getOrCreate()]`,
   - `submitName = parsed?.submitName ?? "yt0"`, `submitValue = parsed?.submitValue ?? "Login"`.
   Starting from the parsed form (rather than a hand-written 4-field body) means any hidden field
   W4 adds later is carried automatically.
4. POST to the same `loginURL`, `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`,
   `Referer: <loginURL>`, `allowLoginPage: true`. The engine follows 302s manually, merging cookies
   per hop; a 302 to `site/verify2fa`, `site/otp` or `site/index` is **success in progress**, not
   failure (README §5.4 line 253).
5. `classify(credentials, html, finalURL)`.

**`classify`** (`W4LoginClient.kt:120-174`), order matters:

| # | Condition | Result |
|---|---|---|
| 1 | `credentials.sessionID.isEmpty` | `.failed(nil, invalidOTP: expectingOTP)` — no cookie means nothing worked |
| 2 | `W4Session.isOTPURL(finalURL)` **or** (`!isLoginHTML` and the parsed form has an `otpFieldName`) | `.needsOTP(challenge)` |
| 3 | `W4HTML.isLoginHTML(html)` **or** `W4Session.isLoginURL(finalURL)` | `.failed(W4LoginForm.loginError(html), …)` |
| 4 | `W4HTML.isAuthenticatedHTML(html)` **or** `W4Session.isHomeURL(finalURL)` | `.authenticated` |
| 5 | anything else | `.failed(nil, …)` + a debug log with `W4LoginForm.inputInventory` |

**Check 2 must come before check 4.** `W4LoginClient.kt:138` calls this out explicitly: the 2FA page
still renders logged-in chrome (`Welcome,` / `#user-panel`), so an `isAuthenticatedHTML`-first order
would declare victory mid-login and then every subsequent request would 302 back to `site/login`.

**Challenge construction** (`W4LoginClient.kt:150-163`): `formAction` = the form's `action` resolved
against the origin, falling back to `finalURL`, falling back to `W4URLs.route(.verify2fa)`;
`hiddenFields` = the parsed fields **minus** the OTP field itself.

**`submitOTP`** (`W4LoginClient.kt:91-118`): `hiddenFields + [otpFieldName: code.trimmed]`, plus
`submitName ?? "yt0"` = `submitValue ?? "Verify"` **only if that key is not already present**
(`putIfAbsent` semantics). POST urlencoded to `challenge.formAction` with `Referer: <formAction>`
and `allowLoginPage: true`. Classify again with `expectingOTP: true` so a failure surfaces as
`.invalidOTP` rather than "wrong password".

> **UNKNOWN — needs live capture:** the OTP input's real `name`, the submit button's name/value, the
> form `action`, and whether a "trust this device" checkbox exists. The discovery-based design above
> works without them; a HAR of one full login would let us replace discovery with an assertion
> (and add a fixture-driven regression test, §10).

### 8.6 `W4AuthService`

Replaces `AuthenticationService.swift` (which today imports Supabase at `:11`, calls
`SupabaseAuthService.shared.authenticateWithW4` at `:84-88`, builds
`https://www.lectio.dk/lectio/\(school.id)/login.aspx` at `:22`, and detects a MitID callback at
`:28-39` — all deleted).

```swift
final class W4AuthService {
    enum Outcome { case loggedIn(W4Student); case otpRequired(W4OTPChallenge) }

    func loginWithPassword(username: String, password: String) async throws -> Outcome
    func loginWithOTP(_ challenge: W4OTPChallenge, code: String, username: String) async throws -> Outcome
    func enterDemoSession() throws -> W4Student
    func logout(student: W4Student) async
    func wipeAuthState() async
    func loadStoredStudent() -> W4Student?
    func hasStoredCredentials(for student: W4Student) -> Bool
    func coldStartValidate(student: W4Student) async -> ColdStartResult   // .ok | .dead | .deferred(Error)
}
```
Port of `AuthSessionInstaller.kt:57-334`.

**`finishLogin`** (`AuthSessionInstaller.kt:97-176`) — the post-authentication ritual, in order:
1. `W4IdentityParser.parse(html)` → `(uwcID, name)`.
2. If `uwcID` is nil or the page still looks like login HTML, `GET site/index` with the fresh
   credentials (`allowLoginPage: true`) and re-parse; if *that* is login HTML too → `.loginFailed`.
   (README §4.4 step 6: *"Confirm with `GET index.php?r=site/index`."*)
3. `uwcID ?? username.trimmed` is the student id. If both are empty → `.parse("Could not parse W4 user id")`.
4. `store.saveCredentials(credentials, for: uwcID)` — **before** the confirmation request, so any
   `PHPSESSID` rotation during that request binds to the right keychain key
   (`AuthSessionInstaller.kt:155-166`; the iOS analogue is the `onCredentialsUpdated` plumbing at
   `W4HTTPClient+Student.swift:33-45`, whose whole purpose is "rotated cookies during validation are
   otherwise lost because we don't yet know the studentId").
5. `GET site/index` again with `studentID: uwcID` set, save the resulting credentials, then
   `sessionController.install(student:credentials:)`.

**`coldStartValidate`** (`AuthSessionInstaller.kt:305-334`, iOS analogue
`AuthenticationService.swift:173-185` + `AuthenticationViewModel.swift:197-236`): one
`.opportunistic` `GET site/index`. **Only** `.sessionExpired` / `.invalidCredentials` /
`.missingCookies` mean `.dead` → log out. Offline, network, HTTP and parse errors mean `.deferred` →
**stay signed in** and recover on the next user-driven fetch. This asymmetry is deliberate and both
ports already agree on it; do not "simplify" it.

**`logout`** (`AuthSessionInstaller.kt:207-237`): remember the username hint, clear the UI session
immediately, then fire-and-forget `GET index.php?r=site/logout` at `.opportunistic` with
`allowLoginPage: true` (a redirect to `site/login` is the expected, correct outcome — without the
flag the engine would classify the successful logout as session death and post a redundant
notification), then `store.wipeAll()`. README §4.4 line 125: *"Logout: `GET index.php?r=site/logout`.
Then wipe local `PHPSESSID`."*

`wipeAuthState` (`AuthenticationService.swift:112-120`) keeps only `keychainManager.wipeAll()` and
`W4ImageLoader.shared.clearCache()`; the Supabase sign-out, `SupabaseStudentProfileService`,
`PublicProfileImageLoader` and `cookieManager.clearAllWebViewData()` lines all go (no WKWebView
participates in auth any more).

### 8.7 `W4LoginView` and the view model

`LoginView.swift` is a full rewrite: username field (`textContentType(.username)`,
`autocapitalization(.never)`, `maxLength 16` per README §4.3), password field
(`textContentType(.password)`), a "Sign in" button, an inline error row, and a pushed OTP screen
(`textContentType(.oneTimeCode)`, `keyboardType(.numberPad)`). English strings only. The MitID sheet
(`:28-47`), `SchoolPickerView` (`:26`), the resume/"Vælg anden skole" branch (`:52-145`) and the
"Sikker godkendelse via MitID & W4" footer (`:290-304`) are deleted.

`AuthenticationViewModel` loses: `import Supabase` (`:12`), `schools`/`selectedSchool`/
`isLoadingSchools`/`schoolLoadError`/`hasLoadedSchoolsFromSupabase` (`:20-28`), `loadSchools()`
(`:96-107`), `loadSchoolsFromSupabase()` (`:112-132`), `ensureSupabaseSession()` (`:242-256`),
`loginWithMitID()` (`:283-303`), `handleWebViewAuthComplete()` (`:325-387`), and every `Analytics.*`
call (`:71, 154, 165, 202, 222, 295, 313, 346-347, 370-371, 401` — `Analytics` is referenced in 5
files and **defined in none**). It gains `username`, `password`, `otpCode`, `pendingChallenge` and
`submitPassword()` / `submitOTP()`.

---

## 9. Where iOS is already better than the Android port — keep these

1. **Cancellation-aware URL tasks.** `W4CancellableTaskBox` (`W4HTTPClient.swift:52-72`) +
   `withTaskCancellationHandler` around `withCheckedThrowingContinuation`
   (`:266-288`, `:297-319`) cancels the actual `URLSessionTask` when the Swift `Task` is cancelled —
   so scrolling away from a screen frees the serial gate immediately. Kotlin's
   `client.newCall(okRequest).execute()` inside `withContext(Dispatchers.IO)`
   (`W4HttpEngine.kt:54, 176`) is a **blocking** call: coroutine cancellation cannot interrupt it,
   so a cancelled Android request still occupies the limiter until the socket returns.
2. **Streaming multipart uploads.** `uploadTaskForW4Request(_:bodyFileURL:)` (`:291-319`) plus the
   256 KB chunked temp-file writer (`W4HTTPClient+Messages.swift:877-914`) means a 2 MB attachment
   never sits in RAM. `W4Client.postMultipart` on Android takes the whole body as `ByteArray`
   (`W4Client.kt:58-66`). Keep the file-based API; do not "simplify" it to `Data`.
3. **Priority gate with true structured-concurrency cancellation.** The actor at
   `W4HTTPClient.swift:606-703` removes cancelled waiters from the queue *and* releases a slot that
   was handed to a waiter which then cancelled (`:624-640, :667-678`). Kotlin does the same thing
   (`PriorityRequestLimiter.kt:87-101`) but with more moving parts; the Swift actor is the cleaner of
   the two. Only Android's 90 s acquire timeout is missing — port that one thing back (§6.7).
4. **Rotation callback for the pre-identity window.** `onCredentialsUpdated` threading through
   `performRequest` → redirect context → completion (`:104-109, :208, :455-459, :472`) lets the login
   flow capture a `PHPSESSID` rotation *before* the student id is known
   (`W4HTTPClient+Student.swift:33-45`). Android papers over this by saving credentials and then
   re-requesting (`AuthSessionInstaller.kt:155-166`). Keep the callback; it makes §8.6 step 4 cheaper.
5. **Keychain write only on actual change.** `CookieManager.updateCredentials` returns `nil` when the
   jar is unchanged (`:226`) and the caller gates on that (`:156-159, :470-476`) with the reasoning
   spelled out at `:101-103`. Same idea as `W4CookieJar.kt:60-66`, but iOS also avoids firing the
   observer callback. Keep both gates.
6. **Avatar traffic goes through the same global gate.** `W4ImageLoader` acquires
   `W4HTTPClient.withSerialW4Request(priority: .opportunistic)` (`:75-77`), re-reads the freshest
   credentials inside the gate (`:82-83`) and persists rotations (`:90-93`), on top of NSCache +
   in-flight dedup (`:16-17, :42-49`) and `CGImageSourceCreateThumbnailAtIndex` downsampling
   (`:142-154`). Android hands avatars to Coil through `W4AuthInterceptor`
   (`W4AuthInterceptor.kt:15-43`), which runs on a **separate OkHttp stack** — so Android's avatar
   traffic bypasses the serial limiter entirely and can hammer the school's Apache box. iOS is
   strictly better here; keep the design and just retarget `isW4URL` and the UA/Referer constants.
   People thumbnails on W4 are `…_thumb.jpg` under `/people` (README §5.5) and require the cookie.
7. **Debug-only, value-redacted request logging.** `W4RequestLog.outbound` (`:13-23`) prints method,
   compact path and cookie **names**, under `#if DEBUG`, with the rationale at `:11-12` ("debug builds
   are routinely distributed to testers"). Extend the same discipline to the redirect logs at
   `:136-140, :467, :493-504`, which are currently unguarded `print`s.
8. **Jittered backoff.** `UInt64.random(in: 0...1_500_000_000)` (`:239, :353`) avoids a thundering
   herd when several screens retry together; Kotlin uses flat delays (`W4HttpEngine.kt:83-90`).
   Keep the jitter (retarget it from robot-detection to 429/503).

---

## 10. `BetterW4Tests` — concrete tests for this layer

XCTest, `@testable import BetterW4`, matching the existing style
(`BetterW4Tests/GradeParserTests.swift:1-4`). Fixtures go in `BetterW4Tests/Fixtures/W4/`.

**`W4URLsTests`**
1. `route("site/login")` == `https://w4.uwcrcn.no/index.php?r=site/login` — the `/` is **not**
   `%2F` (the encoding quirk).
2. `route("people/students/student", ["uwc_id": "nc26jban"])` ==
   `…?r=people/students/student&uwc_id=nc26jban` — sibling key, not inside `r`.
3. `route("people/students/student&uwc_id=nc26jban")` produces the identical URL to (2) — inline
   siblings are split out.
4. Explicit `query` overrides an inline duplicate of the same key.
5. A key literally named `r` in `query` is dropped.
6. A value containing `&`, `=`, `+` and a space (`"On a walk + back & forth"`) round-trips as
   `%2B`/`%20`/`%26`/`%3D`, never a bare `+`. (Regression guard against `URLComponents.queryItems`.)
7. `routeOf("https://w4.uwcrcn.no/index.php?r=site%2Flogin")` == `"site/login"` (decode-first).
8. `routeOf(".../index.php?r=academics/deadlines&month=9")` == `"academics/deadlines"`.
9. `resolve("/index.php?r=site/index")`, `resolve("index.php?r=site/index")`,
   `resolve("https://w4.uwcrcn.no/index.php?r=site/index")` and `resolve("site/index")` all agree.
10. `resolve` never produces a non-`w4.uwcrcn.no` host from a bare route.
11. Two calls with the same `[String: String]` query produce byte-identical URLs (dictionary-order
    determinism).

**`W4CookieJarTests`**
12. `Set-Cookie: PHPSESSID=abc123; path=/; secure` merges into an empty jar → `sessionID == "abc123"`.
13. `Set-Cookie: PHPSESSID=` against a live jar returns `nil` and does **not** clear the session.
14. A second `Set-Cookie: PHPSESSID=xyz` replaces the value (regeneration on login).
15. A `Set-Cookie` on host `evil.example.com` returns `nil` — nothing merges.
16. An unrelated cookie merges into `additionalCookies`; the same name with an empty value removes it.
17. `merge` returns `nil` when nothing changed (keychain-churn guard).
18. `cookieHeader` for `sessionID: ""` is `""` (so the engine omits the header entirely).
19. `cookieHeader` never emits `autologinkeyV2`, `isloggedin3` or `ASP.NET_SessionId` even if they
    are somehow present in `additionalCookies`.
20. `redactedPreview` never contains the full session value.

**`W4SessionClassificationTests`** (drive `W4HTTPEngine` against a stubbed `URLProtocol`)
21. 302 with `Location: /index.php?r=site/login` → `W4Error.sessionExpired`, and `.w4SessionExpired`
    is posted exactly once.
22. Same 302 with `allowLoginPage: true` → the redirect is followed, no error.
23. 200 whose body contains `LoginForm[username]` → `.sessionExpired`.
24. 403 with body `"Login Required"` → `.sessionExpired`.
25. 403 with body `"Some other page"` → `.forbidden`, and **no** notification is posted.
26. 409 with body `"Deadline already confirmed"` → `.serverConflict("Deadline already confirmed")`.
27. 302 → 302 → 302 → 302 → 302 → 302 (6 hops) → `.sessionExpired` when `studentID != nil`.
28. `Set-Cookie` on hop 1 is present in the `Cookie` header of hop 2 (per-hop merge), and the final
    `W4Response.credentials` carries the last value.
29. A 302 answering a POST is re-issued as a **GET with no body**; a 307 keeps method and body.
30. 404 → `.http(404)`, not `.sessionExpired`.
31. `ajax: true` sets `X-Requested-With: XMLHttpRequest`; `ajax: false` does not.
32. Every outbound request carries the exact `W4UserAgent.value` and `Referer: https://w4.uwcrcn.no`,
    and no `Accept-Encoding` header.

**`PriorityRequestLimiterTests`**
33. Two concurrent `.important` requests never overlap (assert via a counter inside the block).
34. An `.opportunistic` waiter yields to an `.important` waiter queued after it.
35. Cancelling a queued waiter's `Task` removes it and does not deadlock the next waiter.
36. Cancelling a waiter that has just been handed the slot releases the slot.
37. Consecutive requests are ≥ 100 ms apart.
38. A waiter that never gets a slot fails after the acquire timeout instead of hanging.

**`YiiFormTests` / `W4LoginFormTests`** (fixtures; the login/2FA ones must be **synthetic** until a
real capture exists, and the file header must say so)
39. `YiiForm.parseForm` picks the last `option[selected]`, skips unchecked checkboxes, includes
    checked ones with `value` (or `"on"`), skips `input[type=file]`, and routes submits to
    `submitButtons`.
40. `fieldsForSubmit` sets `yt0` from the form's own button value; an explicit `submitValue` wins.
41. `W4LoginForm.parse` on a synthetic login page finds `LoginForm[username]`, `LoginForm[password]`,
    `LoginForm[deviceId]` and `yt0=Login`.
42. `W4LoginForm.parse` on a synthetic `site/verify2fa` page finds the OTP field for each of the
    names `otp`, `code`, `verification_code`, `Verify2faForm[code]` and `token`.
43. When the 2FA page has exactly one non-hidden text input with an unrecognised name, it is still
    chosen (the `singleOrNull` fallback).
44. `loginError` extracts text from `.errorSummary li`, then `.errorMessage`, then returns `nil`.
45. `YiiForm.encode` emits `%20` for a space and `%2B` for `+`, keys sorted.

**`W4HTMLTests`** — run against the **real** saved page
`references/pages/UWCRCN W4.html` (copy it into `Fixtures/W4/home.html`)
46. `isAuthenticatedHTML` is `true`; `isLoginHTML` is `false`.
47. `displayName` == `"Jonathan Bangert"`.
48. `uwcID` == `"nc26jban"` — and specifically **not** `nc25wnas`/`nc25eros`, the other `uwc_id`s
    that appear earlier in the birthdays block. This is the test that protects the "prefer the
    profile link" heuristic (`W4Html.kt:55-63`).
49. `contentInner` is non-nil.
50. `W4HTML.decode` on ISO-8859-1 bytes containing `ø` produces `"ø"`, not U+FFFD.

**`W4SessionURLTests`**
51. `isLoginURL` true for `?r=site/login` and `?r=site%2Flogin`, false for `?r=site/logout` and
    `?r=site/index`.
52. `isOTPURL` true for `site/verify2fa`, `site/otp`, `site/verify2FA`; false for `site/index`.
53. `isHomeURL` true for `site/index` and bare `site`.

**`W4DeviceIDStoreTests`**
54. `getOrCreate()` is stable across calls and is a valid `UUID`.
55. After `reset()`, a new value is produced (and the old one is not returned again).

**`W4LoginFlowTests`** (stubbed `URLProtocol`, scripted responses)
56. `GET site/login` → 200 login HTML with `Set-Cookie: PHPSESSID=s1`; the subsequent POST carries
    `Cookie: PHPSESSID=s1` and a body containing all four required fields with the deviceId from
    `W4DeviceIDStore`.
57. POST → 302 to `site/verify2fa` → 200 OTP page ⇒ `.needsOTP`, and the challenge's `hiddenFields`
    do **not** contain the OTP field.
58. OTP POST → 302 to `site/index` → 200 home HTML ⇒ `.authenticated`.
59. A page that is *both* on `site/verify2fa` **and** contains `Welcome,` classifies as `.needsOTP`,
    not `.authenticated` (the ordering bug guard).
60. POST → 200 login HTML with `.errorSummary` ⇒ `.failed(message: "…")` with the server's text.
61. A response with no `Set-Cookie` and an empty jar ⇒ `.failed`, never `.authenticated`.
62. `.needsOTP` → wrong code → 200 OTP page again ⇒ `.failed(invalidOTP: true)`.

**`W4DatesTests`**
63. `parse("14-Aug-2026")`, `parse("4-Aug-26")`, `parse("2026-08-14")` and `parse("14/08/2026")` all
    yield 14 Aug 2026; `format` round-trips to `"14-Aug-2026"` under a `da_DK` device locale.

---

## 11. Demo mode

**Android:** demo is a short-circuit at the *client* boundary plus per-repository fallbacks.
`DefaultW4Client.execute` refuses network the moment the current student is demo and no explicit
credentials were passed (`W4Client.kt:238-243` — returns a failure, it does not silently succeed);
`W4AuthInterceptor` returns no cookie for a demo student (`W4AuthInterceptor.kt:47`);
`SessionController.installDemoSession()` wipes the credential store first
(`SessionController.kt:117-122`); `AuthSessionInstaller.enterDemo()` installs `Student.Demo`
(`:180-186`); `coldStartValidate` is skipped entirely for demo (`:274-277`). Every repository then
returns canned data from `feature/demo/DemoData.kt` (373 lines) before touching the client —
e.g. `CampusStatusRepository.kt:27-30`, `W4TripsRepository.kt:20`.

**iOS must do the same, in the same two places:**

1. **Hard gate in `W4Client`.** Before resolving credentials:
   ```swift
   if session.currentStudent?.isDemo == true, credentials == nil {
       throw W4Error.parse("Demo mode: no network W4 calls")
   }
   ```
   This is a *belt-and-braces* invariant, not the primary mechanism — it exists so that a feature
   author who forgets the demo branch gets a loud failure instead of a real request carrying a real
   cookie. Mirror it in `W4ImageLoader.loadImage` (which already has exactly this guard at
   `W4ImageLoader.swift:36-38`) and in `W4Chrome`'s campus-status write.
2. **Per-feature canned data.** `DemoDataProvider.swift` already exists and is already the pattern
   (`ScheduleViewModel.swift:56, 116, 125, 146, 350, 428`, `MessagesViewModel.swift:68, 148, 190, 225`,
   `AbsenceViewModel.swift:52, 93, 133`, `GradesViewModel.swift:42`, …). Its **content** is Lectio
   (Danish subject names, `School.demo == "Demo School"`, `Student.demo.classLabel == "3a"`,
   `MessageFolder(id: "inbox", displayName: "Indbakke")` at `DemoDataProvider.swift:15-17`) and must
   be rewritten as UWC data in English — but the *shape* survives.
3. `W4Student.demo` keeps `uwcID == "demo"` (`StudentModels.swift:28-31` — `isDemo` is derived from
   the id, which is neat; keep it). `W4SessionController.installDemoSession()` must call
   `store.wipeAll()` first so a demo session can never inherit a real `PHPSESSID`.
4. Demo never runs `coldStartValidate`, never posts `.w4SessionExpired`, and logging out of demo
   skips the `site/logout` request.

The demo entry point moves from "pick Demo School in the picker"
(`AuthenticationViewModel.swift:289-291`) to a plain "Try the demo" button on the new login screen.

---

## 12. Migration ledger

**Survives with edits**

| File | Edit |
|---|---|
| `W4HTTPClient.swift` | split into `W4HTTPEngine.swift` + `W4RequestGate.swift` + `W4RequestLog.swift`; delete `isW4UniLoginURL` (116-118), `isRobotDetectionPage` (579-583) and its retry arms (237-243, 352-354); redirect delegate returns `nil` (121-168); UA/Referer/Accept-Encoding constants (379-381, 441-443) → `W4UserAgent`; keep 52-97, 261-319, 322-364, 527-547, 585-597, 606-703 |
| `CookieManager.swift` | reduce to `W4CookieJar`: keep 124-143 (reshaped), 148-169, 172-227 (PHPSESSID-only + host gate); delete 12-46, 52, 64-118, 250-254, 258-448 |
| `KeychainManager.swift` | conform to `W4CredentialStore`; `service` → `dk.jonathanb.w4`; delete the `isloggedin3` migration (81-94); English errors; add the deviceId item |
| `StudentModels.swift` | `W4Credentials` → PHPSESSID-only (delete 120-172); `W4Error` rewritten in English (206-250); `AuthState` kept (176-194); `Student` → `W4Student` without `gymId`; `School`/`School.demo` deleted (43-54) |
| `AuthenticationViewModel.swift` | strip Supabase, Analytics, school picker, MitID and WebView paths; keep the session-expired observer (52-58) and its idempotency guard (65) |
| `W4ImageLoader.swift` | retarget `isW4URL` (129-132) to `W4Hosts`; UA/Referer → `W4UserAgent`; drop the `defaultfoto_small.jpg` retry (26, 110-114) which is Lectio-specific; keep everything else |
| `RateLimitedAvatarImage.swift` | unchanged except that `W4AvatarView.pictureURL(for:gymId:)` (104-106) loses `gymId` |

**Deleted**

`W4WebView.swift` (entire file — no WebView participates in auth); `AuthenticationService.swift`
(rewritten as `W4AuthService`); `StudentManager.swift` (Lectio dropdown/`holdelementid` scraping);
`W4HTTPClient+{Student,Schedule,Messages,Assignments,Absence,Homework,PrivateEvents}.swift` (1 755
lines of `*.aspx` URLs); `SchoolPickerView`; `LastSchoolStore`/`LastSchoolHint` (replaced);
every `__VIEWSTATE` / `__EVENTVALIDATION` / `__doPostBack` helper — they live in
`W4HTTPClient+Messages.swift`, `W4HTTPClient+Assignments.swift`,
`W4HTTPClient+PrivateEvents.swift` and `AbsenceEditFormParser.swift`. README §4.6 is explicit:
no `autologinkeyV2`, no dual-primary-cookie protection, no UniLogin host detection, no robot page,
no `gymId` in URLs, no ASP.NET postbacks, no MitID, no school picker.

**Blocking pre-existing breakage** (not caused by this spec, but this layer's work will surface it):
`Supabase` is imported/called in 11 files with no package and no `SupabaseManager` type; `Analytics`
is called in 5 files and defined in none; `LastSchoolStore`/`LastSchoolHint` are called in
`AuthenticationViewModel.swift` and defined nowhere. The auth/session rewrite removes most of these
call sites; the rest belong to the feature specs.

---

## 13. Open questions for the next live capture

1. **A HAR of one full login** (`GET site/login` → `POST` → 2FA → `POST` OTP → home). Resolves: OTP
   field name, OTP form `action`, submit button name/value, whether `PHPSESSID` rotates on login,
   whether a "remember this device" control exists, and the login-error node class.
2. **Is `LoginForm[deviceId]` actually persisted server-side?** README §4.4 line 110 says it is
   "almost certainly" how W4 binds a trusted device, but nothing confirms it. If it is not, every
   launch prompts for OTP and the UX needs a different answer.
3. **A 403 response body from an authenticated-but-unauthorised page** — to confirm that `Login Required`
   really is absent there and the `.forbidden` branch is reachable.
4. **A `notifications/refresh` response sample** — confirms it is an HTML fragment and shows the
   markup the notification parser must handle.
5. **Whether any authenticated page sets a second cookie.** Every capture so far shows exactly one
   (README §4.1 "This is the only cookie we saw"), which is why `additionalCookies` is defensive
   rather than load-bearing.
