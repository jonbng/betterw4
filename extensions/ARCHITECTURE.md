# BetterW4 Browser Extension — Architecture

A browser extension that modernizes [W4](https://w4.uwcrcn.no/) (the student system at
UWC Red Cross Nordic) the same way BetterLectio modernizes Lectio: inject custom UI on top of
the original DOM, keep all original functionality working.

> The reference implementation is `references/betterlectio/extension`. Its architecture applies
> directly here, but W4 is simpler than Lectio, so this extension is correspondingly smaller.

---

## 1. The one idea that changes everything

The iOS/Android apps must **fake a browser login** (POST `site/login`, handle 2FA, mint a stable
`deviceId`, then replay `Cookie: PHPSESSID=…` on every request). See `PROTOCOL.md` §4.

A browser extension does **none of that**. It runs *inside* a tab where the user is already logged
in. The session cookie `PHPSESSID` is already in the browser's cookie jar, so the extension can:

- read/write the live DOM directly, and
- call `fetch(url, { credentials: 'include' })` for extra pages, which sends `PHPSESSID` automatically.

Consequences:

| Concern | Native app (iOS/Android) | Browser extension |
|---|---|---|
| Login + 2FA + deviceId | Must implement | **Not needed** (user is logged in) |
| Cookie storage | Keystore / EncryptedSharedPreferences | **Browser jar** |
| Session-expiry detection | Manual redirect watching | Same detection, but via fetch status/DOM |
| Backend (Supabase etc.) | N/A | **Not needed** — W4 has no JSON API |
| Data source | Scrape HTML | Scrape HTML (reuse parsing strategy) |

So the extension is: **content scripts + DOM parsing + same-origin fetch + injected Preact UI**.
No backend, no analytics, no ads (consistent with `PRIVACY.md`).

---

## 2. Tech stack

Mirror BetterLectio so patterns transfer 1:1:

| Technology | Purpose |
|---|---|
| [WXT](https://wxt.dev/) | Extension framework (Chrome MV3 + Firefox + Safari) |
| Preact | 3KB React alternative (`react` aliased to `preact/compat`) |
| TypeScript | Type safety |
| Tailwind CSS 4 | Utility-first styling for injected UI |
| No backend | W4 has no JSON API; all data is scraped HTML |

Deliberately **omitted** vs BetterLectio: Supabase, PostHog, UserJot, referral system, i18n (W4 is
Danish-only but content is English/Norwegian mixed — start single-locale, keep the text as-is).

---

## 3. Project layout

```
extensions/
├── wxt.config.ts              # manifest: content scripts on *://w4.uwcrcn.no/*
├── package.json
├── tsconfig.json
├── entrypoints/
│   ├── hide-flash.content.ts  # document_start: FOUC guard + CSS @layer wrapping
│   ├── content.tsx            # document_idle: main UI injection
│   └── background.ts          # (optional) icon click → open settings
├── components/
│   ├── AppChrome.tsx          # #header + #main_menu + .sdmenu replacement shell
│   ├── TimetableView.tsx      # home week strip + mytimetable
│   ├── AssessmentsView.tsx    # academics/deadlines calendar + done state
│   ├── MailerView.tsx         # inbox / compose (TinyMCE)
│   ├── CampusStatusControl.tsx# campus on/off dropdown
│   └── ui/                    # minimal primitives (button, dialog, badge…)
├── lib/
│   ├── fetch.ts               # same-origin fetch w/ credentials + redirect detection
│   ├── session.ts             # session-dead detection (PROTOCOL.md §4.5)
│   ├── parse/                 # HTML parsers, one per W4 page
│   │   ├── timetable.ts
│   │   ├── assessments.ts
│   │   ├── mailer.ts
│   │   ├── absence-meter.ts
│   │   └── chrome.ts          # #header / #user-panel / notifications / campus
│   └── settings.ts            # localStorage-backed settings (no sync)
└── styles/globals.css         # tokens + @layer plumbing + W4 overrides
```

---

## 4. Injection model

W4's logged-in page shell (from `PROTOCOL.md` §5.6):

```
#header        — "UWCRCN W4" title, relnotes link, notifications, campus dropdown
#main_menu     — Home | Academics | Extra Academics | School | Admissions | Documents
#user-panel    — "Welcome, {name}" · Logout · Profile · Password
.sdmenu        — sectioned sidebar links
#content_inner — page body
#footer        — copyright
```

Same cascade-layer strategy as BetterLectio:

```
content scripts on w4.uwcrcn.no
├── hide-flash.content.ts  [document_start]
│   ├── hide body until custom UI is ready
│   └── wrap W4's CSS in @layer w4
└── content.tsx            [document_idle]
    ├── detect page (site/index, academics/timetable/mytimetable, …)
    ├── create #bw4-root, render AppChrome
    ├── move original DOM into #bw4-content (original W4 DOM reverts to its own layer)
    └── mount page-specific view (TimetableView, AssessmentsView, …)
```

Layer order (low → high): `w4` → `base` → `components` → `utilities`. Original W4 DOM gets
`all: revert-layer` so Tailwind preflight doesn't break it (same isolation as BetterLectio).

---

## 5. Session & data fetching

No manual cookie handling. One helper:

```ts
// lib/fetch.ts
export async function fetchW4(path: string, init?: RequestInit): Promise<Response> {
  const res = await fetch(path, { credentials: 'include', ...init });
  if (isSessionDead(res)) { notifySessionExpired(); }
  return res;
}
```

`isSessionDead` reuses `PROTOCOL.md` §4.5 but from inside the page:

1. `res.status === 302` to `r=site/login`, or final URL contains `r=site/login`
2. `res.ok` but body is the login form (`LoginForm[username]`, title `Login Site`)
3. JSON `403` with body `Login Required`

On session death: show a toast and redirect the tab to `https://w4.uwcrcn.no/` (W4's own
`init_ajax.js` does `location.href='/'` anyway). No re-login UI needed — the browser owns login.

Since the extension can't easily watch `location.href='/'` redirects that happen natively, the
simplest robust rule is: **if any injected view detects login-page HTML, render a "session
expired — reload" screen** instead of the view.

---

## 6. Page surface (what to build, in order)

From `PROTOCOL.md` §6. Chrome on every page (campus status, notifications, profile) is shared.

### v1 MVP
| W4 area | Route | Extension treatment |
|---|---|---|
| Home | `site/index` | Restyle the combined week timetable + attendance meters + birthdays |
| My timetable | `academics/timetable/mytimetable` | Rebuild grid; "now" line; hold colours |
| My EA timetable | `extraacademics/timetable/mytimetable` | Same component, EA source |
| Assessments | `academics/deadlines` | Calendar + Confirm done / Revert to pending (native post) |
| Mailer | `mailer/send&type=freeform` + inbox | No-reload read/reply (iframe-post or fetch) |
| Campus status | `site/setstatus` | Native `$.post` equivalent via fetch |
| Notifications | `notifications/refresh` | 60s poll, styled dropdown |
| My absences / EA absences | `people/students/absences`, `eaabsences` | Attendance meter cards |

### v1.5
Trips, travel forms, resource bookings, directory (`people/students/*`), grades
(`academics/grades/grades`), rooms, on-duty.

### Not in scope
ManageBac (third SIS — do not scrape), Admissions CRM, staff-only modules.

---

## 7. Form posts (W4-specific, replaces Lectio postbacks)

W4 forms are far simpler than ASP.NET (`PROTOCOL.md` §5.2–5.3):

- URL-encoded Yii forms: include the clicked button name (`yt0`, `yt1`, …).
- No `__VIEWSTATE` / `__EVENTVALIDATION`.
- File uploads: `multipart/form-data`.
- TinyMCE fields: send **HTML**, not markdown.
- AJAX calls: `$.post` with `X-Requested-With: XMLHttpRequest` (optional; W4 reads the body).

So `lib/fetch.ts` plus a small `postYiiForm(url, fields)` helper covers every mutation.

---

## 8. What to port from BetterLectio vs delete

**Port:**
- WXT + Preact + Tailwind setup, `react → preact/compat` alias
- `hide-flash` FOUC guard + `@layer` CSS strategy
- Content-isolation pattern (`#bw4-content :where(*) { all: revert-layer }`)
- `lib/utils.ts` `cn()` helper
- Serial request limiter (be kind — tiny Apache box, `PROTOCOL.md` §5.5)

**Delete (Lectio-specific):**
- Supabase client, settings sync, referral system, PostHog/UserJot
- ASP.NET postback parsing, `__VIEWSTATE`
- MitID / UniLogin / school picker
- Cookie-jar/cookie-capture login machinery (browser owns the session)

---

## 9. Build & run

```bash
cd extensions
bun install
bun run dev          # wxt dev (Chrome MV3)
bun run build        # wxt build
```

`wxt.config.ts` matches `*://w4.uwcrcn.no/*` only.

---

## 10. Open questions / risks

- **Timetable "now" line & colours** come from W4's own `full_timetable.js` / `timetable.js`
  globals — parse HTML rather than re-implementing the JS (as BetterLectio does for Lectio).
- **TinyMCE** on mailer/documents: keep the native editor inside an iframe (same approach as
  BetterLectio's Elevfeedback editor) rather than reimplementing.
- **2FA mid-login** is browser-owned; the extension never touches it.
- **Letter of Attendance** pages can be ~600KB+ HTML — parse lazily, don't prefetch.
