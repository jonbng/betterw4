# Privacy Policy for BetterW4 (browser extension)

**Last updated:** 20 August 2026

BetterW4 is an unofficial browser extension for [W4](https://w4.uwcrcn.no/), the student information system at [UWC Red Cross Nordic](https://uwcrcn.no/). It is not made by, endorsed by, or affiliated with the college.

This policy covers the BetterW4 browser extension. The iOS and Android apps have their own policy in the repository root.

## The short version

BetterW4 has no servers and no account of its own. It does not collect, store, or sell your data. Using the extension is the same as using W4 in a browser: your login and everything you see goes between your browser and `w4.uwcrcn.no`, and nowhere else.

## What we do not do

- We do not run a backend, database, or account system
- We do not collect, upload, or store your data
- We do not use analytics, crash reporting, or advertising identifiers
- We do not sell or share data
- We do not track you
- We do not save your password

## What the extension talks to

The extension injects a UI into pages on **`https://w4.uwcrcn.no/`**. Login still posts W4's own form. Campus status posts to W4's existing `site/setstatus` endpoint. Geist is loaded from Google Fonts for the injected UI.

## What stays in the browser

- **Settings and theme** in `localStorage` on `w4.uwcrcn.no` (`bw-` keys)
- **A cached display name / UWC id** so the sidebar can greet you
- W4's own **`PHPSESSID`** session cookie, set by the college

Clearing extension data or using Settings → Clear local data removes the `bw-` keys. Logging out of W4 is W4's own logout.

## W4 itself

BetterW4 does not change what W4 already knows about you. Questions about grades, mail, timetable and the rest belong with the college.

## Changes

If this policy changes, the date at the top will be updated.

## Contact

Questions: open an issue on [github.com/jonbng/betterw4](https://github.com/jonbng/betterw4).
