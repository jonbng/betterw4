# BetterW4 - Architecture & Project Documentation

## Overview

**BetterW4** is a browser extension that enhances [W4](https://w4.uwcrcn.no/), the student information system at UWC Red Cross Nordic. It provides a modern interface while preserving original W4 functionality.

It is unofficial. It is not made by, endorsed by, or affiliated with the college. There is no BetterW4 server — the extension talks to `w4.uwcrcn.no` and stores settings on the device.

### Key Goals
- Replace W4's 2016-era jQuery UI with a modern shell
- Improve navigation with a custom sidebar (W4's `.sdmenu` is section-scoped)
- Maintain full compatibility with existing W4 forms and pages
- Support Chrome (Manifest V3) and Firefox (Manifest V2)

---

## Technology Stack

| Technology | Purpose |
|------------|---------|
| [WXT](https://wxt.dev/) 0.20 | Browser extension framework |
| [Preact](https://preactjs.com/) | Lightweight React alternative (3KB) |
| TypeScript | Type safety |
| Tailwind CSS 4 | Utility-first styling |
| shadcn/ui + Radix UI | Component system + accessible primitives |
| **Bun** | Package manager and runtime |

No analytics, no Supabase, no backend. Match the iOS/Android apps: W4 is the source of truth.

---

## Project Structure

```
extension/
├── entrypoints/
│   ├── content.tsx           # Main content script
│   ├── login.content.tsx     # Login / 2FA redesign
│   ├── hide-flash.content.ts # FOUC + CSS layer wrapping
│   └── background.ts         # Service worker
├── components/               # Preact UI (sidebar, settings, login)
│   └── ui/                   # shadcn/ui primitives
├── lib/                      # URL helpers, settings, theme, parsers
├── hooks/
├── styles/globals.css
└── public/                   # Icons, logos
```

---

## Architecture

### Content Script Injection Model

```
Content Scripts (inject into w4.uwcrcn.no)
├── hide-flash.content.ts  [document_start]
│   ├── Hides page until custom UI is ready (FOUC)
│   └── Wraps W4 CSS in @layer w4 (cascade layers)
├── login.content.tsx      [document_end, login routes]
│   └── Shell around the native Yii login form
└── content.tsx            [document_idle]
    └── Renders sidebar wrapper, moves original DOM
```

### Execution Flow

1. User navigates to `w4.uwcrcn.no`
2. `hide-flash.content.ts` runs at `document_start` — hides page, wraps W4 CSS in `@layer w4`
3. If the URL is `site/login` / `site/verify2fa` / `site/forgotpass`, `login.content.tsx` wraps the native form
4. Otherwise `content.tsx` snapshots chrome, creates `#bw-root`, renders `<DashboardLayout>`, moves original DOM into `#bw-original-content`
5. Native Yii forms and jQuery handlers keep working because nodes were **moved**, not cloned

### DOM structure

```
body.bw-dashboard-active
└── #bw-root
    ├── AppSidebar
    └── #bw-w4-content
        └── #bw-original-content
            └── original W4 DOM (#main, #content_inner, …)
```

---

## CSS Architecture

Layer order (lowest → highest): `w4 < theme < base < components < utilities`

- `#bw-original-content :where(*) { all: revert-layer }` keeps Tailwind preflight off native W4
- Native chrome (`#header`, `#main_menu`, `#user-panel`, `.sdmenu`, `#footer`) is hidden when `behavior.hideNativeChrome` is on
- Custom UI uses Tailwind utilities + semantic tokens

---

## W4 surface (student)

See `../PROTOCOL.md` for login, cookies, and page inventory.

| Sidebar | W4 route |
|---------|----------|
| Home | `site/index` |
| Timetable | `academics/timetable/mytimetable` |
| Assessments | `academics/deadlines` |
| Mail | `mailer/inbox` |
| Documents | `documents` |
| Campus status | `POST site/setstatus` |

`lib/w4-routes.ts` holds the rest of Academics / Extra Academics / School.

---

## Browser Compatibility

| Browser | Manifest | Status |
|---------|----------|--------|
| Chrome | V3 | Supported |
| Firefox | V2 | Supported |
| Edge | V3 | Should work (untested) |
| Safari (macOS 15+) | V3 | Build with `bun run build:safari` |

WXT handles manifest differences. Firefox gecko id is set in `wxt.config.ts`. Safari emits `background.scripts` alongside `service_worker` for host-permission CORS.

---

## Development

```bash
bun install
bun run dev          # Chrome
bun run dev:firefox  # Firefox
bun run build
```

Default dev URL: `https://w4.uwcrcn.no/`.
