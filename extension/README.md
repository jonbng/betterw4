<p align="center">
  <img src="public/assets/logo.png" alt="BetterW4 Logo" width="128" height="128">
</p>

<h1 align="center">BetterW4</h1>

<p align="center">
  A browser extension that modernizes <a href="https://w4.uwcrcn.no/">W4</a>, the student system at <a href="https://uwcrcn.no/">UWC Red Cross Nordic</a>.
</p>

Not made by, endorsed by, or affiliated with the college.

---

## Features

- **Same navigation as W4** — top menu and sdmenu stay; they are just restyled
- **Login / 2FA** — restyled native Yii forms (the POST is still W4's)
- **Dark mode** and colour presets (BetterW4 in the user panel)
- **No flash of unstyled W4** — original CSS is layered under the restyle

## Installation

### From Source

1. Clone this repository
2. `cd extension && bun install`
3. `bun run build` (Chrome) or `bun run build:firefox`
4. Load the extension:
   - **Chrome:** `chrome://extensions` → Developer mode → Load unpacked → `.output/chrome-mv3`
   - **Firefox:** `about:debugging` → This Firefox → Load Temporary Add-on → any file in `.output/firefox-mv2`

## Development

```bash
bun install
bun run dev          # Chrome
bun run dev:firefox  # Firefox
bun run build
bun run zip
```

## Tech Stack

| Technology | Purpose |
|------------|---------|
| [WXT](https://wxt.dev/) | Browser extension framework |
| [Preact](https://preactjs.com/) | Lightweight React alternative |
| [TypeScript](https://www.typescriptlang.org/) | Type safety |
| [Tailwind CSS](https://tailwindcss.com/) | Utility-first styling |
| [shadcn/ui](https://ui.shadcn.com/) | UI component system |

## Privacy

No backend, no analytics, no ads. Settings live in `localStorage` on `w4.uwcrcn.no`. Session cookie stays W4's `PHPSESSID`. See [PRIVACY.md](PRIVACY.md).
