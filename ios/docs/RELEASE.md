# BetterW4 for iOS — App Store submission notes

Everything App Review, App Store Connect and a signing engineer need, with the reasoning behind each
answer. Facts here were checked against the tree on 2026-08-16; where a claim is not yet true, it says
so rather than being aspirational.

| | |
|---|---|
| Bundle id | `dk.jonathanb.w4` |
| Display name | BetterW4 |
| Version / build | `MARKETING_VERSION = 1.0` · `CURRENT_PROJECT_VERSION = 1` |
| Category | Education (`public.app-category.education`) |
| Deployment target | iOS 18.5 |
| Devices | iPhone and iPad, all orientations on iPad, portrait + landscape on iPhone |
| Team | `9ULRK8DH95` |
| Third-party code | **SwiftSoup only** (SPM, `github.com/scinfu/SwiftSoup`) |

---

## 1. Review path — demo mode, no test account

**Do not send Apple a real W4 account.** W4 is the internal student information system of a
200-student boarding college; a live account is a real student's identity, mail and attendance record,
and its 2FA code goes to that student's phone. There is nothing to hand over that is both working and
safe.

Instead the app ships a complete offline demo. What to write in App Store Connect → *App Review
Information* → *Notes*:

> No account is required to review this app.
>
> On the first screen, tap **"Try demo"** — the button directly below **"Log in"**. That opens a
> full offline session with invented data (timetable, mail, assessments, attendance, grades, trips,
> documents, campus status). Every screen in the app is reachable from it.
>
> Demo mode performs **no network requests at all**. You can review the entire app in Airplane Mode.
>
> The sign-in form above it is for students of UWC Red Cross Nordic and authenticates against the
> college's own server; we cannot supply a shared account because each one is a named student's
> personal record and is protected by two-factor authentication.

Exactly how a reviewer reaches it, so nobody has to hunt:

1. Launch the app. The login screen is the root view — there is no onboarding, no paywall, no splash
   gate.
2. Under the username and password fields, and under the **Log in** button, is a plain text button
   labelled **Try demo** (`LoginView.swift:173`). Its accessibility hint reads *"Explore the app with
   sample data. No W4 account needed."*
3. One tap enters the app as **Demo Student**. A banner reading **"Demo data. Not connected to W4."**
   is shown, and the More tab carries a permanent demo section explaining it.

**The "no network" claim is enforced and tested, not just asserted.** Every repository branches on
`isDemo` before it can reach the client, and `DemoDataTests.testCatalogueCarriesNoFetchableURLs`
fails the build if any demo fixture ever grows a fetchable URL. Avatars in demo mode are drawn
locally from initials; there is no gravatar, no CDN, no remote image of any kind.

**Guideline 2.1 / 5.1.1 framing.** The demo satisfies the "reviewer must be able to use the app"
requirement without an account, and the app collects nothing, so there is no account-based data
collection to disclose.

---

## 2. Privacy nutrition label — "Data not collected"

Answer **"No, we do not collect data from this app"** in App Store Connect → *App Privacy*, then
publish. Every subsequent question disappears.

That answer is literally true, and here is the whole argument:

- **There is no backend.** BetterW4 has no server, no API, no account of its own, no database, no
  telemetry endpoint. Nothing about the student is transmitted anywhere except back to
  `w4.uwcrcn.no`, which is the college's own system that the student is already a user of.
- **There are no analytics.** No Firebase, no PostHog, no Sentry, no Crashlytics, no App Store
  analytics SDK, no custom event pipeline. The BetterLectio ancestor had 28 `Analytics.*` call sites;
  all of them were deleted during the port and `scripts/check-legacy.sh` keeps the Lectio-era
  subsystems from coming back.
- **There is exactly one third-party dependency, and it never touches the network.** SwiftSoup is a
  pure-Swift HTML parser. It takes a `String` and returns a document tree. It has no network code, no
  identifier access, and no analytics.
- **There is no advertising, no tracking, no IDFA.** The app never calls
  `ATTrackingManager` and links no ad framework.

Apple's definition of "collect" is *transmit off the device*. Everything BetterW4 keeps — session,
cached pages, preferences — stays in the app sandbox and is never sent anywhere.

**Privacy policy URL.** The app itself needs no external policy to function, and ships an in-app
**Settings → Privacy → "What BetterW4 stores"** screen instead (plan OQ-7). App Store Connect still
requires a policy URL on the product page, so the owner must supply one before submission. That URL
is the one remaining non-engineering blocker.

---

## 3. What the app talks to

**One host: `w4.uwcrcn.no`, over HTTPS.** That is the college's W4 server — a Yii 1 PHP application
serving HTML at `https://w4.uwcrcn.no/index.php?r=<route>`. The app scrapes those pages and posts the
same forms the website posts.

This is enforced at runtime, not just by convention:

- `W4HTTPClient.requireW4Host(_:context:)` throws `W4Error.notPortedToW4` for **any** host that is
  not `w4.uwcrcn.no`, before the request reaches the network stack. A stray URL fails loudly in
  development instead of leaking a session cookie to a third party in production.
- `W4HostGateTests` asserts it: `testRequestToLectioIsRefusedBeforeItLeavesTheDevice` builds a
  `lectio.dk` URL and proves the client refuses to send it.
- `scripts/check-legacy.sh` fails the build if a `lectio.dk` host, an `.aspx` route or an ASP.NET
  postback token reappears in Swift code.
- `Info.plist` sets `NSAppTransportSecurity → NSAllowsArbitraryLoads = false`. There is no ATS
  exception for any domain.

**One conditional second host, currently off.** `SchoolCalendar.swift:50` holds a
`calendar.google.com` public ICS URL for an optional school-calendar overlay on the timetable. It
ships **disabled** — the setting is off, the repository hook is `nil`, and the URL is never fetched —
because we have not confirmed that this is the right calendar. If a future release turns it on, the
privacy answer does not change (a public ICS feed is fetched, nothing is sent), but the App Review
note should mention it.

**Links out of the app.** ManageBac, Google Drive policy folders and the college website are opened
in Safari as ordinary links. They are not scraped and receive no app data.

---

## 4. What the app stores on the device

| What | Where | Notes |
|---|---|---|
| `PHPSESSID` (the W4 session cookie) and any other cookie W4 sets after sign-in | **Keychain**, item `w4.credentials.<uwcId>`, service `dk.elliottf.betterw4` | W4's entire auth state. Lectio-era cookie names are refused on the way in. |
| A per-install device id | **Keychain**, item `w4.deviceId`, under its **own service** so logout cannot delete it | Sent as `LoginForm[deviceId]`. A random per-install UUID — **never** `identifierForVendor`, never an advertising id, never a fingerprint. It exists so W4 can recognise the install and not demand a 2FA code on every launch. Kept `…ThisDeviceOnly`, never logged. |
| The signed-in student's identity (uwc id, display name) | **Keychain** | JSON blob; read on cold start to restore the session. |
| Cached W4 pages | `Caches/W4Pages/<base64url(uwcId)>/` | HTML plus a `.meta.json` with fetch time. Real TTLs per surface. |
| Cached mail list and message bodies, and downloaded attachments | `Caches/MailCache/…` and `Caches/Attachments/` | Attachments are LRU-evicted at 50 MB / 100 files. |
| Preferences (theme, calendar style, subject colours, notification toggles) | `UserDefaults` | ⚠️ See the caveat below. |

**Every cache directory sets `isExcludedFromBackup = true`** (`W4PageCache.swift:178`,
`MessageCacheManager.swift:200`, `AttachmentCache.swift:199`). This is deliberate and worth stating
in review notes if asked: cached pages are re-fetchable and may contain other students' names, so
they do not belong in an iCloud or iTunes backup. Only the Keychain items persist across a restore.

**Logging out wipes it.** `KeychainManager.wipeAll()` deletes the credentials and the student record,
and the caches are cleared, so the next person to hold the phone cannot read the previous student's
mail. The device id survives on purpose — regenerating it would force a fresh 2FA prompt.

**Nothing sensitive is logged.** The request log prints cookie *names* only, never values, and only
in `DEBUG`. Personal-calendar feed tokens (which are password-equivalent) are Keychain-only and
masked in the UI.

> ⚠️ **Known defect, unfixed at time of writing.** `SettingsStore` opens
> `UserDefaults(suiteName: "group.dk.elliottf.betterw4")` while the app declares **no app-group
> entitlement**, so preference writes are silently discarded on device. See
> `docs/W4_PORT_PLAN.md` §0.3 item 1. It does not affect the privacy answer — nothing leaves the
> device either way — but it should be fixed before shipping, because a settings screen that forgets
> everything is a bug reviewers may well hit.

---

## 5. Signing and entitlements

**`keychain-access-groups` is the only entitlement.** `BetterW4/BetterW4.entitlements` contains one
key:

```xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>
</array>
```

No app groups, no push notifications, no associated domains, no background modes entitlement, no
iCloud, no HealthKit, no Sign in with Apple.

**Omitting it breaks everything, in a way that does not look like a signing problem.** Without the
entitlement every `SecItemAdd` fails with **`-34018` (`errSecMissingEntitlement`)**. That means: no
session saved, no device id saved, no identity saved — the student appears to log in successfully and
is thrown back to the login screen on the next launch, with no error message anywhere. If you ever see
`-34018`, the answer is always the entitlement, never the Keychain code.

The same trap catches the test suite:

```bash
# correct — signed, entitlement applied, Keychain tests pass
xcodebuild -project BetterW4.xcodeproj -scheme BetterW4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' test

# wrong — KeychainManagerTests fail with -34018 for reasons unrelated to the code under test
xcodebuild … CODE_SIGNING_ALLOWED=NO test
```

`CODE_SIGNING_ALLOWED=NO` is fine for a plain `build`. Never pass it to `test`.

**Automatic signing.** `DEVELOPMENT_TEAM` is `9ULRK8DH95`. Simulator builds sign ad hoc and need
nothing. For a device or archive build, set your own team on the BetterW4 target and let automatic
signing create the profile — the single Keychain access group is the only capability it must carry.

---

## 6. Pre-submission checklist

Ordered so the blockers come first. Items marked ⛔️ are not done at the time of writing.

- ⛔️ **Fix the app-group `UserDefaults` bug** (`W4_PORT_PLAN.md` §0.3 item 1). One line. A reviewer
  changing the theme and relaunching would find it.
- ⛔️ **Resolve the notification story.** The app requests notification permission on first launch and
  never sends a notification; the Settings footer claims it "checks W4 in the background", and
  `UIBackgroundModes = fetch` is declared with nothing behind it. Either implement plan Wave 9.3 or
  remove the toggles, the permission request and the background mode. Shipping as-is invites a
  rejection and deserves one.
- ⛔️ **Privacy policy URL** from the owner (OQ-7).
- ⛔️ **Build and validate an archive.** No archive has been produced yet.
- ✅ Demo mode reachable in one tap and fully offline.
- ✅ Single host, enforced at runtime and in the test suite.
- ✅ `keychain-access-groups` present; no other entitlement.
- ✅ Caches excluded from backup.
- ✅ `scripts/check-legacy.sh` and `scripts/check-english.sh` both exit 0.
- ✅ 743 tests passing.
- ⚠️ Screenshots must be taken **in demo mode**. Never screenshot a real account — the timetable,
  mail list and directory all show real students' names at a 200-person college.

---

## 7. If review asks a question

**"What is this app for?"** An unofficial student client for the W4 student information system used
by UWC Red Cross Nordic. It shows a student their own timetable, assessments, mail, attendance and
campus status without the college's 2016-era desktop website. The About screen states plainly that it
is unofficial and not made by the college.

**"Does it require a login?"** For real data, yes — a college account. For review, no: demo mode is
one tap from the first screen and covers every surface.

**"What data do you collect?"** None. There is no server to collect it to.

**"Why does it need the Keychain?"** To hold the W4 session cookie and the per-install device id so a
student does not have to re-enter their password and a 2FA code on every launch.

**"Is the login a WebView?"** No. Username, password and the one-time code are native fields posted
directly to the college's login form. There is no embedded browser anywhere in the auth path.
