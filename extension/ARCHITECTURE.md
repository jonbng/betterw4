# BetterW4 — architecture

Unofficial restyle of [W4](https://w4.uwcrcn.no/). No backend. W4 is the source of truth.

## Goal
Make W4 look like a modern site **without changing how you get around**. Top nav, sdmenu, Yii forms, and campus status stay W4's. We restyle them.

## Stack
WXT 0.20 · Preact · TypeScript · Tailwind 4 **without preflight** · shadcn/ui for settings/login only.

## Injection

```
hide-flash.content.ts   document_start   FOUC + wrap W4 CSS in @layer w4
login.content.tsx       document_end     login / 2FA / forgot-password shell
content.tsx             document_idle    theme, restyle native chrome, settings overlay
background.ts                            toolbar icon → settings
```

Logged-in pages are **not** moved into a custom layout. `body.bw-themed` restyles `#main`, `#header`, `#main_menu`, `#user-panel`, `.sdmenu` in place.

`#bw-root` on logged-in pages only hosts the settings dialog. On login it is the full-page shell.

## Identity
See AGENTS.md. Name from `#user-panel .right` first text node. Own `uwc_id` from Home `#hello`. Photo URL derived from that id, never from other photos on the page.

## Files
- `entrypoints/` — the three content scripts + background
- `components/LoginPage.tsx`, `SettingsModal.tsx`, `AppOverlays.tsx`
- `lib/w4-url.ts`, `profile-cache.ts`, `settings-storage.ts`, `theme-*.ts`
- `styles/globals.css` — tokens + native chrome modernizer + login form
