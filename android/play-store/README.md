# BetterW4 Google Play screenshots

The six listing images are designed as one continuous 6480×1920 panorama and exported as six 1080×1920 PNG files. Copy is English — W4 and the app are English.

The listing sells **W4 on your phone**, not a better Lectio. Mail is off (`MAIL_ENABLED = false`). Assessments is one surface, not homework + deadlines.

## Preview

Open `index.html` in Chrome. Red seam guides are visible in the browser preview and omitted from exports.

## Render

```sh
node play-store/render.mjs
```

Outputs are written to `play-store/output/`:

- `panorama.png` for reviewing the complete composition
- six numbered, upload-ready Google Play PNG files
- `feature-graphic.png` — 1024×500 Play Store feature graphic

| File | Panel | Capture this |
|---|---|---|
| `01-w4-now-on-mobile.png` | Hero + your timetable | Own week, light, with lessons |
| `02-students.png` | Find anyone, see their week | Student profile on the Schedule tab |
| `03-classes.png` | Class roster | A class with the student list |
| `04-houses.png` | Houses and rooms | A house with rooms and people |
| `05-assessments.png` | Assessments calendar | Month view of My assessments |
| `06-absence.png` | Absence, dark mode | Absence overview in dark theme |

Edit copy and phone placement in `config.js`; edit the visual system in `styles.css`. Source screenshots must remain 1280×2856 PNGs and use the filenames under `play-store/assets/`.

Capture replacements **in demo mode** — never from a live W4 account. The college is ~200 people; timetable, directory and houses all show real names.
