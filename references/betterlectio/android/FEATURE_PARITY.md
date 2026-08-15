# BetterLectio Android — Feature Parity Overview

> **Goal:** Native Android (`android/`) should have **full feature parity** with **iOS** (`ios/BetterLectio`) and **Flutter** (`flutter/` + `flutter/lectio_wrapper`) combined, and feel **first-class**.  
> **Date:** 2026-07-10  
> **Related:** [NATIVE_ANDROID_PLAN.md](./NATIVE_ANDROID_PLAN.md)

---

## 1. Snapshot

Android is a **first-class Lectio client**: MitID + demo, 5-tab iOS IA, full daily path depth, directory pins/search, optional Supabase, Glance widget, live-lesson boundaries, offline stores, help, and Play IAU.

### Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Present and product-quality (or close) |
| ⚠️ | Partial / best-effort |
| ❌ | Missing / out of scope |

---

## 2. Status matrix

### Auth & session

| Capability | Android | Notes |
|------------|---------|-------|
| School picker | ✅ | Supabase catalog when configured + scrape fallback |
| MitID WebView | ✅ | |
| Username/password login | ❌ | Removed — Lectio no longer offers password login |
| Secure cookies / rotation | ✅ | |
| Session expired → re-login | ✅ | |
| Demo mode | ✅ | |

### Navigation

| Capability | Android | Notes |
|------------|---------|-------|
| 5-tab iOS shell | ✅ | |
| Unread badge | ✅ | |
| Same-tab scroll-to-top | ✅ | |
| Nested stacks | ✅ | Messages / homework / assignments full-screen NavHost; Mere in-tab |

### Schedule

| Capability | Android | Notes |
|------------|---------|-------|
| Week/day/timeline | ✅ | Professional hour-grid + all-day + now line |
| Lesson detail | ✅ | Blocks, participants, resources |
| Private create/update/delete | ✅ | Lectio post; create fails when rejected; edit from detail |
| Subject colors/rename | ✅ | Lesson-mapping v2: SubjectMapper + scoped Supabase sync (friendly names + hues) |
| Live lesson | ✅ | Ongoing notif + next boundary + open-app action + WorkManager/alarm |

### Messages

| Capability | Android | Notes |
|------------|---------|-------|
| Folders + list | ✅ | |
| Full-screen thread | ✅ | Nested NavHost (not sheet) |
| Compose + recipients | ✅ | Full-screen compose; students + teachers |
| BBCode formatting toolbar | ✅ | B/I/U/link/lists (native Compose; tags visible) |
| Compose attachments | ✅ | Photo Picker + SAF → `dokumentupload.aspx` + attach postback |
| BetterLectio signature | ✅ | Append BBCode link; skip for teachers / settings toggle |
| “Skal ikke kunne besvares” | ✅ | `RepliesNotAllowedChkBox` on compose postbacks |
| Reply / mark read / flag / delete | ✅ | SmartPostback; reply has BBCode + attachments + signature |
| Attachments open | ✅ | |
| Cache | ✅ | SimpleCache + Room OfflineMessageStore / OfflineDirectoryStore |
| Prefetch unread/newest | ✅ | MessageListPrefetcher after auth |

### Homework / assignments / absence / grades

| Capability | Android |
|------------|---------|
| Homework groups + detail HTML + local/remote done | ✅ |
| Assignment filters + detail | ✅ |
| Absence tabs (overview + registrations) + edit sheet (Flutter UX) | ✅ |
| Grades + notes | ✅ |

### Directory / plans / studiekort

| Capability | Android | Notes |
|------------|---------|-------|
| Search + kinds | ✅ | Smart rank: pins, classmates, prefix |
| Pins | ✅ | Durable PinStore |
| Avatars | ✅ | Coil singleton ImageLoader rate-limits Lectio GetImage |
| Class members / room week | ✅ | |
| Rooms live occupancy | ✅ | `aktuelleallelokaler` + FindSkema merge; Mere → Lokaler |
| Directory full-catalog offline sync | ✅ | After auth: DirectorySyncService + hold bootstrap |
| Plans list + detail | ✅ | |
| Modulregnskab / term | ✅ | |
| Studiekort scrape/QR | ✅ | Birthday from Lectio span when present |
| Change profile picture | ✅ | PhotoDialog form post with image data-URL (demo always succeeds) |

### Settings / platform

| Capability | Android | Notes |
|------------|---------|-------|
| Theme / calendar style / notif toggles / history | ✅ | |
| Help + privacy | ✅ | |
| Play In-App Updates | ✅ | Real `AppUpdateManager` flexible/immediate when available |
| Glance schedule widget | ✅ | |
| Offline durable KV | ✅ | EntityOfflineStore |
| Optional Supabase | ✅ | Schools, auth EF + session gate, homework LWW, week + lesson content, subjects |
| Multi-module Gradle | ❌ | Plan-only single `app` |
| Exact ActivityKit | ❌ | Approximated (see live lesson) |

---

## 3. Remaining / out of scope

1. **Multi-module Gradle** — plan infrastructure only  
2. **Exact iOS ActivityKit Live Activities** — platform limit; Android uses notification + boundary scheduling  
3. **Real-session soak** of SmartPostback against live Lectio school templates (logic is in place)  

---

## 4. Change log

| Date | Note |
|------|------|
| 2026-07-16 | Compose parity with extension: BBCode toolbar, file/image attach, signature, no-reply checkbox, reply composer upgrade |
| 2026-07-10 | Initial audit → Phase A/B → full §5 close-out |
| 2026-07-10 | Thin/optional close: full-screen messages, password login, profile photo, IAU flow, directory smart search, rate limiter, multi-variant postbacks, richer live notif, subject sync |
| 2026-07-10 | SmartPostback; Room offline messages/directory; Coil rate-limit ImageLoader; full-screen homework + assignments NavHost |
| 2026-07-10 | Gap close: rooms occupancy, birthday, PhotoDialog upload, absence chart, directory sync, private update + reject, message prefetch (no battery prompts / no Live Activity widget / no contribute) |
