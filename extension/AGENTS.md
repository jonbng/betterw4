# BetterW4

!IMPORTANT: Please update @AGENTS.md and @ARCHITECTURE.md after each big change.

Browser extension that restyles [W4](https://w4.uwcrcn.no/) without replacing its navigation.

## Tech
WXT, Preact, TypeScript, Tailwind 4 (utilities only — **no preflight**), shadcn/ui.

## What this extension does
- Restyle W4's existing chrome: one-line top bar (`#header` + `#main_menu`), `.sdmenu`
- Custom notifications popover (W4 `notifications/*` endpoints) and profile dropdown
- Do **not** hide or replace top nav or sdmenu. W4's IA stays W4's.
- Redesign login / 2FA around the native Yii form (do not reimplement the POST)
- Dark mode + colour presets from Settings (`BetterW4` in the user panel)

## What this extension does not do
- Custom sidebar / duplicate student IA
- Move the page DOM into a dashboard shell
- Parse other people's birthday thumbs as "my photo"

## Identity parsing
- **Name:** first text node of `#user-panel .right` (`Welcome, {name}` before the `<br>`). Never `textContent` of the whole panel (that includes Logout/Profile).
- **UWC id:** `#hello a[href*="uwc_id="]` on Home only. Cache it. Never birthday/staff thumbs.
- **Photo:** `/files/user_photos/{uwcId}_thumb.jpg` from that id.

## CSS
W4 CSS is wrapped in `@layer w4` at `document_start`. Overrides go in `@layer components` in `styles/globals.css`. OKLCH only. Prefix: `bw-`.

## Commands
```bash
bun run dev          # Chrome
bun run dev:firefox
bun run build
```
