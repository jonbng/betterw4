# BetterLectio — Native Android Implementation Plan

> **Status:** Investigation complete · ready for phased build  
> **Target location:** `android/` (currently empty)  
> **Primary UX reference:** `ios/BetterLectio`  
> **Feature/API reference:** `flutter/` + `flutter/lectio_wrapper`  
> **Date:** 2026-07-10

---

## 1. Goal

Build a **native Android app** for BetterLectio that:

1. **Looks and feels like the iOS app** (navigation, information architecture, schedule polish, settings).
2. **Has feature parity with iOS + Flutter combined** (every Lectio surface either app exposes).
3. Follows **current Android best practices** (Kotlin, Jetpack Compose, Material 3, modular clean architecture, offline-first, stable session handling).
4. Is **super stable**: robust cookie/session lifecycle, offline cache, typed errors, regression tests around scraping, no silent data loss.

This document is the blueprint. Implementation should follow it unless product priorities change.

---

## 2. What Exists Today

| Codebase | Path | Role | Scale |
|----------|------|------|-------|
| **iOS (SwiftUI)** | `ios/BetterLectio/` | Newest product UX; MitID WebView auth; rich schedule/messages/directory; Live Activities; Supabase sync | ~24k LOC Swift |
| **Flutter app** | `flutter/lib/` | Mature feature breadth (absence edit, plans, rooms, modul stats, WorkManager notifications, studiekort QR) | ~11k LOC Dart |
| **lectio_wrapper** | `flutter/lectio_wrapper/` | Portable Lectio client: Dio + BeautifulSoup scrapers, ASP.NET postbacks, cookie jar | ~4k LOC Dart |
| **Native Android** | `android/` | **Empty** — this project | — |

### 2.1 How the three relate

```
┌─────────────────────────────────────────────────────────────┐
│                         Lectio.dk                           │
│              (HTML pages + ASP.NET postbacks)               │
└───────────────────────────┬─────────────────────────────────┘
                            │ scrape / cookie session
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────────┐
│ lectio_wrapper│   │ iOS HTTP      │   │ Android (new)     │
│ Dio + soup    │   │ URLSession +  │   │ OkHttp + Jsoup    │
│               │   │ SwiftSoup     │   │ (port of both)    │
└───────┬───────┘   └───────┬───────┘   └─────────┬─────────┘
        │                   │                     │
        ▼                   ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────────┐
│ Flutter UI    │   │ SwiftUI app   │   │ Compose UI        │
│ BLoC          │   │ ViewModels    │   │ (iOS-inspired)    │
└───────────────┘   └───────┬───────┘   └───────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Supabase      │
                    │ (optional     │
                    │  sync layer)  │
                    └───────────────┘
```

There is **no shared Lectio API**. All clients scrape Lectio HTML and manage `ASP.NET_SessionId` + `autologinkeyV2` cookies locally. The Android app must reimplement this client layer in Kotlin (not call Flutter).

---

## 3. Feature Inventory & Parity Matrix

Legend: ✅ present · ⚠️ partial · ❌ missing · ★ primary implementation reference

### 3.1 Auth & session

| Feature | iOS | Flutter | Android must ship |
|---------|-----|---------|-------------------|
| School picker | ✅ Supabase list + demo | ✅ scraped gym list | ✅ Prefer iOS Supabase list + fallback scrape |
| MitID / UniLogin WebView | ✅ WKWebView | ✅ WebView | ✅ Chrome Custom Tabs / WebView cookie capture |
| Username/password login | ❌ | ✅ | ⚠️ Optional; MitID is primary |
| Cookie extraction & Keychain/secure storage | ✅ | ✅ secure storage | ✅ Encrypted prefs + Keystore |
| Cookie rotation on every hop | ✅ sophisticated | ✅ Dio cookie jar | ✅ Must match iOS redirect merge rules |
| Session expired → re-login | ✅ UniLogin host detection | ✅ login callback | ✅ Same as iOS |
| Demo mode (App Review) | ✅ | ✅ | ✅ |
| Auto-login on cold start | ✅ | ✅ | ✅ |
| Logout clears all | ✅ | ✅ | ✅ |

### 3.2 Primary tabs / navigation

| Surface | iOS | Flutter | Android recommendation |
|---------|-----|---------|------------------------|
| Tab shell | Skema · Beskeder · Lektier · Opgaver · Mere | Skema · Lektier · Fravær · Mere | **Follow iOS** 5-tab shell |
| Unread badge on messages | ✅ | ⚠️ | ✅ iOS |
| Same-tab reselect scroll-to-top | ✅ | ⚠️ | ✅ Material / Compose best practice |

### 3.3 Schedule (Skema)

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Week schedule scrape | ✅ | ✅ | ✅ |
| Day / timeline views | ✅ professional + standard styles | ✅ week day view | ✅ Both calendar styles |
| Calendar strip / week nav | ✅ | ✅ | ✅ |
| Event status (Ændret / Aflyst) | ✅ | ✅ | ✅ |
| All-day events | ✅ | ⚠️ | ✅ iOS |
| Rich lesson content (blocks, links, images) | ✅ rich parser | ⚠️ simpler | ✅ iOS quality |
| Lesson detail / participants / resources | ⚠️ in content | ✅ ModulDetails | ✅ Combine both |
| Private events create | ✅ | ✅ wrapper | ✅ |
| Subject colors / rename | ✅ + Supabase | ⚠️ | ✅ iOS |
| Live Activity during lesson | ✅ ActivityKit | ❌ | ✅ Android ongoing notification + lock-screen style |
| Background refresh of live state | ✅ BGAppRefresh | WorkManager notifs | ✅ WorkManager |

### 3.4 Messages (Beskeder)

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Folder list (Nyeste, Ulæst, Inbox, Sent, Deleted) | ✅ | ✅ | ✅ |
| Thread list + unread | ✅ | ✅ | ✅ |
| Thread detail + HTML body | ✅ custom renderer | ✅ flutter_html | ✅ |
| Attachments download/open | ✅ | ✅ open_filex | ✅ |
| Reply / compose | ✅ | ✅ | ✅ |
| Recipient search | ✅ directory | ✅ | ✅ |
| Prefetch + disk cache | ✅ | ⚠️ | ✅ iOS-level cache |

### 3.5 Homework (Lektier)

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Homework list by date/group | ✅ | ✅ | ✅ |
| Detail / lesson content | ✅ | ✅ | ✅ |
| Mark done (local + Supabase sync) | ✅ | ⚠️ | ✅ iOS |
| Offline cache | ✅ | ✅ | ✅ |

### 3.6 Assignments (Opgaver)

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Overview list + filters | ✅ | ✅ | ✅ |
| Detail view | ✅ | ✅ | ✅ |
| Status / deadline | ✅ | ✅ | ✅ |
| Notifications on status change | ⚠️ basic | ✅ WorkManager handler | ✅ Flutter behavior |

### 3.7 Absence (Fravær)

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Overview percentages / charts | ✅ | ✅ richer charts | ✅ Flutter depth |
| Registrations list | ⚠️ | ✅ | ✅ |
| **Edit absence causes** | ❌ | ✅ only wrapper update path | ✅ **Flutter critical gap fill** |

### 3.8 Grades (Karakterer)

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Grade overview | ✅ | ✅ | ✅ |
| Subject detail | ✅ | ✅ | ✅ |
| Grade notes | ⚠️ | ✅ | ✅ Flutter |

### 3.9 Directory / people / school structure

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Full catalog search (students, teachers, classes, holds, rooms, groups, resources) | ✅ rich DirectoryStore | ⚠️ people + rooms + classes | ✅ **iOS depth** |
| Class / hold members | ✅ | ✅ | ✅ |
| Student card / studiekort | ✅ | ✅ + QR | ✅ + QR from Flutter |
| Rooms overview | ⚠️ via directory | ✅ dedicated | ✅ |
| Study plans (Studieplan) | ❌ | ✅ | ✅ Flutter |
| Module statistics (Modulregnskab) | ❌ | ✅ | ✅ Flutter |
| Change school year (term) | ❌ | ✅ | ✅ Flutter |

### 3.10 Settings & polish

| Feature | iOS | Flutter | Ship? |
|---------|-----|---------|-------|
| Theme light/dark/system | ✅ | ✅ | ✅ |
| Subject color settings | ✅ | ❌ | ✅ |
| Calendar style | ✅ | ❌ | ✅ |
| Notification toggles (events, messages, assignments) | ⚠️ coarse | ✅ granular | ✅ Flutter |
| Notification history | ❌ | ✅ | ✅ |
| Clear cache | ✅ | ✅ | ✅ |
| Debug cookie tools | ✅ dev | ❌ | ⚠️ debug builds only |
| App update prompt | ❌ | ✅ upgrader | ✅ Play In-App Updates |
| Danish locale only (v1) | ✅ | ✅ da | ✅ |
| Privacy policy link | ⚠️ | ✅ | ✅ |

### 3.11 Supabase (optional enhancement layer)

Used on iOS for:

- School list
- Auth edge function `token-for-auth` (maps Lectio cookies → Supabase JWT)
- Homework done-state sync
- Schedule / subject preference sync
- Settings scope per student

Flutter is mostly **local-only**. Android should implement Supabase as **best-effort** (same as iOS): core Lectio features must work offline and without Supabase configured.

---

## 4. Recommended Tech Stack (2026 Android)

### 4.1 Core

| Concern | Choice | Why |
|---------|--------|-----|
| Language | **Kotlin 2.x** | First-class Android, coroutines, multiplatform-ready types |
| UI | **Jetpack Compose** + **Material 3** | iOS-like declarative UI; Material You dynamic color optional |
| Architecture | **Modular Clean Architecture** | Testability + stability for scraping surface |
| DI | **Hilt** | Standard, compile-time safe |
| Async | **Coroutines + Flow / StateFlow** | Match iOS async ViewModels |
| Navigation | **Navigation Compose** (type-safe routes) | Multi-tab + deep links |
| HTTP | **OkHttp** (+ cookie jar interceptor) | Fine-grained redirect/cookie control like iOS `URLSession` |
| HTML parse | **Jsoup** | Direct analog of SwiftSoup / BeautifulSoup |
| Local DB | **Room** | Structured cache (messages, directory, schedule weeks) |
| Key-value | **DataStore** | Settings |
| Secrets | **EncryptedSharedPreferences** or **Security Crypto** + Keystore | Cookies / autologin |
| Images | **Coil** | Cookie-aware image loading for Lectio avatars |
| Background | **WorkManager** | Notification polling (port Flutter) |
| Widgets / live lesson | **Glance** + **ongoing Notification** | Live Activity equivalent |
| Analytics / crash | Optional: Play Crashlytics later | Stability signal |
| Backend | **Supabase Kotlin** (official) | Parity with iOS optional sync |
| Min SDK | **26** (or 28 if simpler) | Covers Danish student devices; WebView MitID needs modern WebView |
| Target / compile | **API 35+** | Current Play requirement trajectory |
| Build | **Gradle Kotlin DSL**, Version Catalog (`libs.versions.toml`) | Modern standard |
| Testing | **JUnit5 + Turbine + MockWebServer + Compose UI tests** | Scraper regression is non-negotiable |

### 4.2 What we deliberately do **not** use

- Flutter embedding / hybrid — user wants **native** Android.
- Scraping on a remote server for core data — privacy + offline match iOS/Flutter local model.
- Firebase Auth as primary — Lectio cookies are the source of truth.
- XML Views as default — Compose only (legacy only if a library forces it).

### 4.3 Android feature mapping (iOS → Android)

| iOS | Android equivalent |
|-----|--------------------|
| SwiftUI TabView + NavigationStack | `Scaffold` + bottom `NavigationBar` + nested nav graphs |
| Keychain | EncryptedSharedPreferences / Keystore |
| WKWebView MitID | `WebView` (cookie capture) or Custom Tabs + deep link if possible; **WebView required** for cookie extraction like iOS |
| ActivityKit Live Activity | Ongoing high-priority notification + optional lock-screen RemoteViews / Glance widget |
| BGAppRefresh | WorkManager + `setExactAndAllowWhileIdle` carefully for lesson boundaries |
| UNUserNotificationCenter | `NotificationManager` + channels |
| App Groups (widget data) | Shared `DataStore` / Room in app process |
| Dynamic Type | Compose Material type scale + font scale |
| Face ID optional | BiometricPrompt optional gate later |

---

## 5. Architecture Recommendation

### 5.1 Gradle modules

```
android/
├── app/                          # Application shell, DI root, MainActivity
├── core/
│   ├── common/                   # Result, dispatchers, time, extensions
│   ├── model/                    # Pure Kotlin domain models (no Android)
│   ├── network/                  # OkHttp, LectioClient, cookie jar, robot detection
│   ├── scraping/                 # Jsoup parsers (schedule, messages, …)
│   ├── database/                 # Room entities + DAOs
│   ├── datastore/                # Settings + secure session storage
│   └── designsystem/             # Theme, typography (Inter/Fraunces), components
├── feature/
│   ├── auth/
│   ├── schedule/
│   ├── messages/
│   ├── homework/
│   ├── assignments/
│   ├── absence/
│   ├── grades/
│   ├── directory/
│   ├── studentcard/
│   ├── plans/
│   ├── teams/
│   ├── settings/
│   └── notifications/
├── sync/                         # Supabase adapters (optional)
└── widget/                       # Glance + live-lesson notification
```

**Why modular:** scraping breaks often when Lectio changes HTML. Isolating parsers + tests prevents UI churn and lets CI run scraper fixtures without Compose.

### 5.2 Layering (per feature)

```
UI (Compose screens)
    ↓ StateFlow / events
ViewModel (feature)
    ↓
UseCase / Repository (domain)
    ↓
Data sources
  ├── LectioRemoteSource (network + scrape)
  ├── LocalCache (Room / DataStore)
  └── SupabaseSource (optional)
```

### 5.3 Domain models (shared `core:model`)

Port from both:

- **iOS** models for schedule richness (`ScheduleEvent`, `LessonContent`, `ContentBlock`, message folders).
- **lectio_wrapper** types for absence causes, study plans, rooms, terms, assignment details.

Prefer **immutable data classes** + sealed hierarchies for statuses and content blocks.

### 5.4 Lectio client — critical design

The hardest, most important piece. Port **iOS `LectioHTTPClient` redirect/cookie rules** as the gold standard (they are more battle-tested against UniLogin expiry and empty `Set-Cookie` traps), and use **lectio_wrapper scrapers** as the second reference for endpoints that iOS has not implemented yet.

#### Must-have behaviors

1. **Cookie jar** with protected cookies: never clear `autologinkeyV2` / `ASP.NET_SessionId` when Lectio sends empty values (see iOS `CookieManager` + Supabase edge function comments).
2. **Per-hop Set-Cookie merge** on redirects (iOS custom `URLSession` delegate).
3. **UniLogin broker host** ⇒ emit session-expired (immediate logout UI).
4. **Robot detection** page handling with backoff / user-visible error.
5. **ASP.NET postbacks**: extract `__VIEWSTATEX`, `__EVENTVALIDATION`, etc. (from lectio_wrapper `extractASPData`).
6. **User-Agent** consistent and non-bot-looking (match iOS/edge function style).
7. **Rate limiting** on avatar/image loads (iOS has `RateLimitedAvatarImage`).
8. **Demo mode** short-circuit (no network).

#### Suggested API surface (`LectioApi`)

Mirror `Student` controllers from lectio_wrapper:

```
login / session
weeks.get(year, week)
events.detail(id) / private.create(...)
homework.list() / detail
assignments.list() / detail
messages.folders / threads / thread / reply / compose
absence.overview / registrations / updateCause
grades.list / notes
directory.sync / search
classes / teams / rooms / plans / terms
profile / studiekort
files.download(url)
images.avatar(pictureId)
```

Implement incrementally behind interfaces so UI can ship with stubs/fixtures.

### 5.5 Session & auth flow (Android)

```
Cold start
  → load encrypted credentials
  → if demo → DemoRepository
  → if cookies present → validate with lightweight Lectio request
      → ok → Main tabs
      → UniLogin / 401 shape → Login
  → else → Login

Login
  → pick school (Supabase list or scrape)
  → open WebView on lectio login.aspx
  → detect callback (unilogin.aspx / forside.aspx)  [same as iOS]
  → extract CookieManager cookies
  → validate + parse student id/name
  → persist credentials
  → best-effort Supabase token-for-auth
  → Main tabs
```

**WebView note:** Cookie capture must use the same WebView process that completed MitID. Android `CookieManager.getInstance()` sync after page finish is required. Test MitID on real devices early (emulators often fail MitID).

---

## 6. UI / UX Plan (iOS-first)

### 6.1 Visual system

- **Fonts:** Inter + Fraunces (already in Flutter `assets/fonts/` — reuse).
- **Brand blue:** Flutter splash `#3362E1` as seed; Material 3 tonal palette.
- **Dark mode:** follow system + explicit override (iOS `AppearanceMode`).
- **Edge-to-edge:** enable; handle IME/insets properly.
- **Predictive back:** enabled for all stacks.
- **Motion:** restrained (iOS-like), use shared element sparingly for student avatars.

### 6.2 Navigation map (target)

```
MainActivity
└── AuthGraph | MainGraph
    MainGraph (bottom bar)
    ├── Skema
    │   ├── Week/Day schedule
    │   ├── Lesson detail
    │   └── Add private event
    ├── Beskeder
    │   ├── Folders / thread list
    │   ├── Thread detail
    │   └── Compose / reply
    ├── Lektier
    │   └── Homework detail
    ├── Opgaver
    │   └── Assignment detail
    └── Mere
        ├── Profile header
        ├── Katalog / directory search
        ├── Karakterer → subject detail
        ├── Fravær → registrations → edit cause
        ├── Studiekort (+ QR)
        ├── Klasser / Hold / Lokaler / Studieplan / Modulregnskab
        ├── Indstillinger
        │   ├── Appearance, calendar style, subjects
        │   ├── Notifications + history
        │   ├── Term / year
        │   ├── Cache, privacy, version
        │   └── Live-lesson / widget prefs
        └── Log ud
```

### 6.3 Schedule UI

Port iOS concepts:

- `CalendarStyle.professional` vs `.standard`
- Timeline list + day columns
- Status chips for Ændret/Aflyst
- Subject color mapping (`SubjectMapper`)
- Pull-to-refresh + stale cache indicator (“Sidst opdateret”)

### 6.4 Stability UX patterns

- Skeleton/shimmer on first load (Flutter has `bl_shimmer`).
- Cached content shown immediately; refresh in background.
- Typed error screens: offline, session expired, robot detection, parse failure.
- Never wipe local cache on transient network errors.
- Explicit “Log ind igen” on session expiry without losing offline data until re-auth succeeds.

---

## 7. Background Work & “Live Lesson”

### 7.1 Notifications (port Flutter WorkManager)

Handlers to port:

| Handler | Behavior |
|---------|----------|
| Events | Diff week schedule; notify on status change (aflyst/ændret) |
| Messages | Diff unread folder; notify on new threads |
| Assignments | Diff status; notify on completion/status change |

Requirements:

- Notification channels (Danish labels).
- User toggles per type (Flutter settings).
- History store (Flutter notification history).
- Battery optimization education (Flutter already uses disable-battery-optimizations prompt — reimplement carefully, Play policy compliant).
- Unique tags/IDs to avoid spam.

### 7.2 Live lesson (port iOS Live Activity)

Android cannot use ActivityKit. Recommended stack:

1. **Foreground-capable ongoing notification** while a lesson is active (title = subject, progress = time remaining).
2. **Exact alarms / WorkManager** at lesson boundaries to advance content (mirror `LiveActivityBoundaryScheduler`).
3. Optional **home-screen Glance widget** for today’s next lesson.
4. Variants compact / standard / expanded (iOS `LiveActivityVariant`).

Respect Doze, exact-alarm permission (`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` policy), and user toggles.

---

## 8. Data Persistence Strategy

| Data | Storage | TTL / policy |
|------|---------|--------------|
| Credentials / cookies | Encrypted storage | Until logout / expiry |
| Student profile | Encrypted + Room | Until logout |
| Schedule weeks | Room | Soft stale ~15–60 min; keep offline indefinitely |
| Messages threads | Room | Prefetch unread/newest; LRU for bodies |
| Homework + done flags | Room + optional Supabase | Done flags merge remote |
| Directory entities | Room | Sync on demand / daily |
| Settings | DataStore | Immediate |
| Notification history | Room | Cap e.g. 200 entries |
| Images | Coil disk cache | Standard |

Cache clear action must wipe Room + Coil + message prefetch, **not** credentials unless logging out.

---

## 9. Testing Strategy (stability)

### 9.1 Must-have

1. **HTML fixture tests** for every parser  
   - Capture real Lectio HTML samples (sanitized) under `core/scraping/src/test/resources/fixtures/`.  
   - Golden tests: schedule weeks, cancelled events, message threads, absence tables, ASP postback fields.
2. **Cookie jar unit tests**  
   - Empty protected cookie ignored.  
   - Redirect hop merge.  
   - UniLogin detection.
3. **ViewModel tests** with fake repositories (Turbine).
4. **MockWebServer** integration for client redirect chains.
5. **Compose screenshot / UI tests** for critical flows (login shell, schedule empty/error, message list).
6. **Demo mode smoke test** — no network.

### 9.2 Continuous

- CI: unit + parser fixtures on every PR.
- Optional nightly job against a secret test account (careful; Lectio ToS + MitID make this hard) — prefer fixtures.
- Baseline Profile generation for startup after feature-complete.

---

## 10. Implementation Phases

Prioritize **stable core → iOS UX parity → Flutter gap-fill → polish**.

### Phase 0 — Project scaffold (0.5–1 week)

- [ ] Create Android Studio project in `android/` (Kotlin, Compose, Version Catalog).
- [ ] Module skeleton as in §5.1.
- [ ] Design system: colors, Inter/Fraunces, Material 3 theme, dark mode.
- [ ] Hilt, Navigation, logging (Timber or official).
- [ ] CI Gradle checks.
- [ ] README with run instructions + secrets template (`local.properties` / `secrets.properties` for Supabase).

### Phase 1 — Auth & session (1–2 weeks) ★ critical path

- [ ] School list (Supabase + scrape fallback).
- [ ] MitID WebView login + cookie extraction.
- [ ] Secure credential storage.
- [ ] LectioClient with redirect cookie merge + session-expired bus.
- [ ] Validate credentials → Student model.
- [ ] Demo mode.
- [ ] Auto-login / logout.
- [ ] Error states (offline, MitID fail, robot).

**Exit criteria:** cold start restore works; logout is clean; real MitID login works on a physical device.

### Phase 2 — Schedule (2 weeks) ★ primary daily driver

- [ ] Week scrape + parser (from iOS `ScheduleParser` + lectio_wrapper weeks).
- [ ] Room cache + ScheduleRepository.
- [ ] Compose schedule UI (professional + standard).
- [ ] Lesson detail with rich content.
- [ ] Subject colors.
- [ ] Pull-to-refresh, week navigation.
- [ ] Private event create.
- [ ] Fixture tests for schedule HTML.

**Exit criteria:** offline week display; status chips correct; no crashes on empty weeks.

### Phase 3 — Messages (1.5–2 weeks)

- [ ] Folders, thread list, detail, reply, compose.
- [ ] Attachment download/open (FileProvider).
- [ ] Prefetch unread + badge on tab.
- [ ] Cache strategy.

### Phase 4 — Homework & Assignments (1–1.5 weeks)

- [ ] Lists, details, filters.
- [ ] Homework done toggle + optional Supabase sync.
- [ ] Assignment status model for notifications later.

### Phase 5 — More tab core (1.5–2 weeks)

- [ ] Profile header.
- [ ] Grades + subject detail + notes.
- [ ] Absence overview + registrations + **cause edit** (Flutter).
- [ ] Studiekort + QR.
- [ ] Settings (appearance, calendar, subjects, cache, about).

### Phase 6 — Directory & school graph (1.5–2 weeks)

- [ ] Directory sync/store (port iOS `DirectoryStore` concepts).
- [ ] Search: students, teachers, classes, holds, rooms, groups, resources.
- [ ] Class/hold member lists.
- [ ] Rooms, study plans, modulregnskab, term switch.

### Phase 7 — Notifications & live lesson (1–1.5 weeks)

- [ ] WorkManager pollers + channels + toggles + history.
- [ ] Live-lesson ongoing notification + boundary scheduler.
- [ ] Optional Glance widget.

### Phase 8 — Supabase polish & Play readiness (1 week)

- [ ] token-for-auth, settings sync, subject/homework sync.
- [ ] In-app updates, Play privacy form, ProGuard/R8 keep rules for Jsoup models.
- [ ] Accessibility pass, large font, TalkBack on main flows.
- [ ] Performance: startup, scroll jank on schedule.
- [ ] Store listing assets (reuse Flutter icons / betterlectio branding).

### Rough total

**~10–14 weeks** for one experienced Android engineer to full parity, assuming Lectio HTML fixtures and access to a real student account for manual MitID. Two engineers can parallelize features after Phase 1.

---

## 11. Porting Guide (where to look)

### 11.1 Prefer iOS for

| Concern | Files |
|---------|-------|
| Auth / cookies | `AuthenticationService`, `CookieManager`, `KeychainManager`, `LectioWebView` |
| HTTP client | `LectioHTTPClient*.swift` |
| Schedule models/UI | `ScheduleModels`, `ScheduleParser`, `ScheduleView*`, `ModernScheduleComponents` |
| Messages | `MessageModels`, `MessageParser`, `MessagesView*`, `ComposeMessageView` |
| Directory | `DirectoryModels`, `DirectoryStore`, `DirectorySyncService`, `StudentSearchView` |
| Live activity semantics | `LiveActivityManager`, `LiveActivityBoundaryScheduler`, variants |
| Supabase | `Supabase*`, `ios/supabase/functions/token-for-auth` |
| Tab IA | `ContentView` |

### 11.2 Prefer Flutter / lectio_wrapper for

| Concern | Files |
|---------|-------|
| Endpoint map & scrapers | `lectio_wrapper/lib/topics/**` |
| ASP postback helpers | `utils/scraping.dart`, `utils/dio_client.dart` |
| Absence cause update | `topics/absence/**` |
| Study plans, rooms, teams stats, terms | respective wrapper controllers + Flutter screens |
| Notification diff logic | `flutter/lib/notifications/**` |
| Studiekort QR | `topics/studiekort/**` |
| Branding assets | `flutter/assets/**` |

### 11.3 Porting scrapers safely

1. Read Dart/Swift parser with a real HTML fixture open.
2. Reimplement in Kotlin + Jsoup selectors (do not translate line-by-line blindly).
3. Add fixture test before wiring UI.
4. Log parse warnings; never crash on unexpected optional nodes.
5. When Lectio changes, fix parser module only.

---

## 12. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Lectio HTML changes | Feature break | Fixture tests; defensive parsing; versioned scrapers |
| MitID WebView cookie issues on Android | Login broken | Early device testing; WebView cookie flush APIs; match iOS callback detection |
| Robot detection / rate limits | Temporary lockout | Backoff, caching, polite User-Agent, no aggressive background scrape |
| WorkManager killed by OEMs | Missed notifications | Channels + battery guidance; don't promise 100% delivery |
| Exact alarms policy | Live lesson drift | Fallback to inexact + refresh on open |
| Dual sources of truth (iOS vs Flutter scrapers) | Inconsistent behavior | Single Kotlin API; document divergences; pick better source per endpoint |
| Scope creep (full directory + all Flutter extras) | Delay | Phase gates; ship schedule+auth first to internal testers |
| Play policy (background, cookies, scraping) | Store rejection | Transparent privacy policy; user-owned Lectio session; no credential exfiltration |
| Supabase optional | Confusing bugs | Feature flags; app fully functional without keys |

---

## 13. Security & Privacy

- Store only Lectio session cookies + student metadata needed for UX.
- Never log full cookie values in release builds (iOS already redacts in production logging patterns — follow that).
- HTTPS only to `lectio.dk`, UniLogin, Supabase.
- WebView: disable file access; restrict JS to required; clear on logout.
- Attachments via `FileProvider` with grant URI permissions.
- Privacy policy link in settings (Flutter has this).
- Demo mode for screenshots / review without real credentials.

---

## 14. Success Criteria

The Android app is “done” when:

1. MitID login + auto-login + logout work reliably on real devices.
2. All **iOS primary tabs** work with offline cache.
3. All **Flutter-only** features (absence edit, plans, modulregnskab, term switch, granular notifications, studiekort QR) work.
4. Parser suite is green on fixtures; crash-free rate is Play-quality.
5. Live-lesson notification correctly tracks the current module.
6. UX is recognizably BetterLectio (iOS IA + brand), not a bare Material scaffold.
7. Supabase enhancements work when configured and degrade gracefully when not.

---

## 15. Immediate Next Steps

When you say go on implementation:

1. Scaffold the Gradle multi-module project in `android/`.
2. Implement `core:network` + `core:scraping` with cookie jar tests.
3. Ship auth + demo + empty main shell.
4. Implement schedule end-to-end as the first complete vertical slice.

---

## Appendix A — Combined feature checklist (build tracker)

### Auth
- [ ] School picker
- [ ] MitID WebView
- [ ] Cookie persist / rotate
- [ ] Session expired handling
- [ ] Demo mode
- [ ] Logout

### Skema
- [ ] Week load + cache
- [ ] Professional style
- [ ] Standard style
- [ ] Lesson detail + rich content
- [ ] Private events
- [ ] Subject colors
- [ ] Live-lesson notification

### Beskeder
- [ ] Folders
- [ ] Thread list / detail
- [ ] Reply / compose
- [ ] Attachments
- [ ] Unread badge
- [ ] Prefetch cache

### Lektier
- [ ] List / detail
- [ ] Done toggle (+ sync)

### Opgaver
- [ ] List / filters / detail

### Fravær
- [ ] Overview + charts
- [ ] Registrations
- [ ] Edit causes

### Karakterer
- [ ] Overview / subject / notes

### Mere / directory
- [ ] Katalog search all entity kinds
- [ ] Klasser / hold / rooms
- [ ] Studiekort + QR
- [ ] Studieplan
- [ ] Modulregnskab
- [ ] Skift årgang

### System
- [ ] Settings
- [ ] Notifications (3 types) + history
- [ ] Clear cache
- [ ] Supabase optional
- [ ] In-app updates
- [ ] Fixture test suite

---

## Appendix B — Key constants & URLs

| Item | Value / pattern |
|------|-----------------|
| Lectio base | `https://www.lectio.dk/lectio/{gymId}/` |
| Login | `.../login.aspx` |
| Schedule | `SkemaNy.aspx` (see parsers) |
| Callback detection | `lectio.dk/.../unilogin.aspx` or `forside.aspx` (not `broker.unilogin.dk`) |
| Session death host | `broker.unilogin.dk` |
| Images | `GetImage.aspx?pictureid=...` |
| Protected cookies | `autologinkeyV2`, `ASP.NET_SessionId` |
| Brand color | `#3362E1` |
| Locale | `da` |

---

## Appendix C — Why not reuse Flutter’s Android shell?

The Flutter tree already produces an Android APK, but the product goal is a **native** app aligned with the iOS experience, Compose, and long-term platform features (widgets, notifications, performance, Play quality). Keeping Flutter as a **reference implementation** (and lectio_wrapper as the API map) is the right balance: learn from it, reimplement in Kotlin for quality and maintainability.

---

*End of plan. Update this document as phases complete and as Lectio HTML or product scope changes.*
