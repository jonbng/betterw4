# SafariExtension

The macOS Safari Web Extension appex that ships inside **BetterLectio for Mac**
(`BetterLectioMac` target). Together they are the macOS half of the Universal
Purchase pair — same bundle identifier as the iOS app, `dk.echolabs.betterlectio.app`,
so users who own one see the other as already purchased.

## Layout

| Path | Owner |
|---|---|
| `SafariExtension/Info.plist` | hand-written — declares the `com.apple.Safari.web-extension` extension point |
| `SafariExtension/SafariWebExtensionHandler.swift` | hand-written — required principal class, deliberately a stub |
| `../SafariExtensionResources/` | **generated — do not edit** |
| `../BetterLectioMac/EXTENSION_BUILD_INFO.json` | **generated — do not edit** |

## Why the web resources live outside this folder

`SafariExtensionResources/` sits at the repo root, *not* inside `SafariExtension/`,
and that placement is load-bearing.

`SafariExtension/` is a `PBXFileSystemSynchronizedRootGroup` — Xcode automatically
bundles everything it contains. For a web extension that is actively harmful: a
synchronized group **flattens** nested files, so `chunks/a.js` and
`content-scripts/content.js` would land as `a.js` and `content.js` in the bundle
root, colliding with each other and breaking `manifest.json`'s paths. Setting
`EXCLUDED_SOURCE_FILE_NAMES` to `Resources/**` does *not* suppress it (verified —
the flattened duplicates still appeared alongside the correct copies).

Keeping the tree outside every synchronized group avoids the problem entirely.
The appex's final **"Copy WXT Web Resources"** build phase `rsync`s it into
`Contents/Resources/`, preserving structure. Because that phase writes into
`BUILT_PRODUCTS_DIR`, the target sets `ENABLE_USER_SCRIPT_SANDBOXING = NO`
(the project-level default is `YES`).

## Refreshing the web extension

`SafariExtensionResources/` is the committed Manifest V3 build output of the WXT
extension from the separate [jonbng/betterlectio](https://github.com/jonbng/betterlectio)
repo. It is committed on purpose so Xcode builds stay hermetic — no `bun`, no
build secrets, and no network access required to build the Mac app.

```sh
./scripts/sync-safari-extension.sh --dry-run   # preview
./scripts/sync-safari-extension.sh             # build + sync
```

The script expects the extension repo checked out as a sibling directory
(`../extension`) and a gitignored `.env.safari` at the repo root holding the four
`VITE_*` build variables. See the script's header for details. It refuses to run
if `VITE_SUPABASE_URL` is unset, because `wxt.config.ts` would silently fall back
to a `https://*.supabase.co/*` wildcard host permission.

`EXTENSION_BUILD_INFO.json` records which extension commit and version produced the
current resources. It is written into `BetterLectioMac/` so it ships inside the app
bundle (not the appex) and `ExtensionBuildInfo.bundled` can surface the version on
the Status and About screens.

## Building

Until the sync script has been run at least once, the Mac app will not build — the
copy phase fails with a pointer to the script. That is intentional: shipping an
appex with no `manifest.json` would produce an app whose extension silently never
appears in Safari.
