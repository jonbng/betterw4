# BetterW4 Google Play screenshots

The six listing images are designed as one continuous 6480×1920 panorama and exported as six 1080×1920 PNG files.

## Preview

Open `index.html` in Chrome. Red seam guides are visible in the browser preview and omitted from exports.

## Render

```sh
node play-store/render.mjs
```

Outputs are written to `play-store/output/`:

- `panorama.png` for reviewing the complete composition
- six numbered, upload-ready Google Play PNG files

Edit copy and phone placement in `config.js`; edit the visual system in `styles.css`. Source screenshots must remain 1280×2856 PNGs and use the filenames under `play-store/assets/`.
