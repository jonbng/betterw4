# BetterW4

!IMPORTANT: Please update @AGENTS.md and @ARCHITECTURE.md after each big change to reflect changes

**Design skill:** When building big new features that require design, or doing significant UI changes/refactors, use the `frontend-design` skill to generate high-quality, polished interfaces. Always invoke it for new page redesigns, component overhauls, or visual reworks.

@ARCHITECTURE.md

Browser extension that modernizes [W4](https://w4.uwcrcn.no/), the student information system at UWC Red Cross Nordic.

## Tech Stack
- **WXT** - Browser extension framework
- **Preact** - Lightweight React alternative (aliased from React)
- **TypeScript** + **Tailwind CSS**
- **shadcn/ui** + **Radix UI** - UI components

## Key Files

### Entry Points
- `entrypoints/content.tsx` - Main content script, renders the sidebar shell, moves original W4 DOM
- `entrypoints/login.content.tsx` - Login / 2FA / forgot-password redesign around the native Yii form
- `entrypoints/hide-flash.content.ts` - FOUC prevention + intercepts W4 CSS into `@layer w4`
- `entrypoints/background.ts` - Service worker; toolbar icon opens settings

### Components
- `components/AppSidebar.tsx` - Student navigation: Home / Timetable / Assessments / Mail / Documents plus Academics, Extra Academics, and School collapsibles
- `components/AppOverlays.tsx` - Settings modal owner
- `components/LoginPage.tsx` - Shell around the native W4 login form (do not reimplement the POST)
- `components/CampusStatusWidget.tsx` - On/off campus setter (`POST site/setstatus`)
- `components/SettingsModal.tsx` - Appearance + about

### Libraries
- `lib/w4-url.ts` - Yii `r=` helpers, login detection
- `lib/w4-routes.ts` - Fixed student IA (sdmenu is section-scoped on W4, so do not snapshot one page's menu as the whole nav)
- `lib/w4-navigation.ts` - Live chrome snapshot (top menu, sdmenu, welcome name, version)
- `lib/campus-status.ts` - Parse + POST campus status
- `lib/profile-cache.ts` - Name / UWC id from `#user-panel`
- `lib/settings-storage.ts` - localStorage feature flags
- `lib/theme-storage.ts` + `lib/theme-presets.ts` - OKLCH colour presets
- `styles/globals.css` - Tokens, layer plumbing, native W4 overrides

## Architecture
Content scripts inject a custom Preact UI that wraps the original W4 DOM. The original DOM is **moved** (not cloned) to preserve event handlers and Yii forms.

## CSS Cascade Layers
W4's CSS is intercepted at `document_start` by `hide-flash.content.ts` and wrapped in `@layer w4 { }`.

**Layer order** (lowest -> highest): `w4 < theme < base < components < utilities`

When adding new CSS overrides for W4 elements, put them in `@layer components { }` in `globals.css`. Only use `!important` when overriding **inline styles** or `display: none/block` for chrome hiding.

**Content isolation:** `#bw-original-content :where(*) { all: revert-layer }` in `@layer base` prevents Tailwind's preflight from breaking W4's native DOM.

## Styling Rule (Tailwind-First)

All custom/injected Preact UI should be styled with Tailwind utility classes directly in `.tsx` components.

- Profile pictures / avatars must use `object-top`.
- Prefer semantic token utilities (`bg-background`, `text-foreground`, `bg-primary`, `border-border`, `ring-ring`).
- Keep `globals.css` for platform-level concerns: tokens, layer plumbing, native W4 overrides.

### Typography / hierarchy (injected UI)

- **Page or card title** — `text-base font-semibold`
- **Primary line in list row** — `text-sm font-medium text-foreground`
- **Secondary / description** — `text-sm text-muted-foreground`
- **Meta** — `text-xs text-muted-foreground`
- **Section chrome** — `text-xs font-semibold uppercase tracking-wide text-muted-foreground`

## Color System — OKLCH Only

**All colors MUST use `oklch()`.** Never use `hsl()`, `rgb()`, `rgba()`, or hex anywhere.

- **Primary (Fjord):** hue 210 — `oklch(0.48 0.12 210)` (light) / `oklch(0.72 0.1 210)` (dark)
- **Alpha:** `oklch(L C H / alpha)` or `color-mix(in oklch, var(--token) N%, transparent)`
- **Tailwind arbitrary:** underscores for spaces — `bg-[oklch(0.48_0.12_210)]`
- **Shadows:** `oklch(0 0 0 / alpha)` not `rgba(0,0,0,alpha)`

## W4 rules (do not port Lectio habits)

- One host: `w4.uwcrcn.no`. No school picker, no `/lectio/{id}/`.
- One cookie: `PHPSESSID`. No ASP.NET `__VIEWSTATE`. Yii forms use `yt0`, `yt1`, …
- Routes are `index.php?r={module}/{controller}/{action}`.
- HTML is English. Dates are `dd-M-yy` (`14-Aug-2026`) in `Europe/Oslo`.
- Login POSTs the **native** form (username, password, hidden `LoginForm[deviceId]`, `yt0=Login`). Do not rebuild ClientJS. 2FA is `site/verify2fa`.
- Assessments is one surface (not lektier + opgaver). Campus status and Extra Academics are first-class.
- Absolute URLs for `fetch()` (Firefox). Credentials: `include`.
- Prefix: CSS/ids `bw-`, storage `bw-`, events `betterw4:`.

## Commands
```bash
bun run dev          # Development (Chrome)
bun run dev:firefox  # Development (Firefox)
bun run dev:safari   # Development (Safari, MV3)
bun run build        # Production build
bun run zip          # Package extension
```
