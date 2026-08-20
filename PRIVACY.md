# Privacy Policy for BetterW4

**Last updated:** 18 August 2026

BetterW4 is an unofficial student app for [W4](https://w4.uwcrcn.no/), the student information system at [UWC Red Cross Nordic](https://uwcrcn.no/). It is not made by, endorsed by, or affiliated with the college.

This policy covers the BetterW4 apps for iOS and Android.

## The short version

BetterW4 has no servers and no account of its own. It does not collect, store, or sell your data. Using the app is the same as using W4 in a browser: your login and everything you see goes between your device and `w4.uwcrcn.no`, and nowhere else.

## What we do not do

- We do not run a backend, database, or account system
- We do not collect, upload, or store your data
- We do not use analytics, crash reporting, or advertising identifiers
- We do not sell or share data
- We do not track you
- We do not save your password

## What the app talks to

The app talks to **W4** at `https://w4.uwcrcn.no/` over HTTPS. That is the college's own system. BetterW4 signs you in the same way the website does (username, password, and 2FA) and then reads and posts the same pages and forms a browser would.

If you turn on the school calendar overlay, the app also fetches the college's **public** calendar. Nothing about you is sent with that request.

Links such as ManageBac or the college website open in the system browser. They are not scraped and they receive no data from BetterW4.

## What stays on your device

Everything BetterW4 knows lives on the device you are holding.

- **Your W4 session.** The session cookie and a random device identifier stay on the device so you do not have to complete 2FA on every launch. Your password is never saved.
- **Cached W4 pages.** Timetable, mail, assessments, attendance, directory and similar pages are cached so the app works offline. You can clear the cache at any time.
- **Your settings.** Theme, calendar style, subject names and colours, and notification choices.

Logging out removes the session and every cached page for that account, so the next person to use the device cannot read them.

## W4 itself

BetterW4 does not change what W4 already knows about you. Grades, mail, timetable, attendance and the rest are stored by the college on `w4.uwcrcn.no`, just as they are when you use the website. Questions about that data belong with the college, not with BetterW4.

## Changes

If this policy changes, the date at the top will be updated.

## Contact

Questions about this policy: open an issue on the BetterW4 repository, or write to the maintainer who published the app.
