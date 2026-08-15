# Android release signing (Google Play)

BetterLectio Android uses package id **`dk.betterlectio.android`**.

## Two keys (Play App Signing)

| Key | Who holds it | Role |
|-----|----------------|------|
| **Upload key** | You (this keystore) | Signs the `.aab` you upload to Play Console |
| **App signing key** | Google (recommended) | Signs what users download from Play |

You only need a local **upload keystore**. On first upload, enroll **Play App Signing** so Google holds the app signing key. If you lose the upload key later, Google can let you register a new one; if Google does **not** hold the app signing key and you lose it, you can never update that package.

## Decision: reuse or create?

```
Is dk.betterlectio.android already on Google Play?
│
├─ YES → You MUST use the same upload keystore that signed the last AAB/APK.
│         (Or request “Upload key reset” in Play Console if that key is lost.)
│         Look for: old key.properties, *.jks, password manager, CI secrets,
│         teammate who published Flutter BetterLectio.
│
└─ NO  → Create a new upload keystore (below). This is the normal path
          for a first native release that has never been published.
```

On this machine today:

- No `key.properties` or `*.jks` in `android/` or `flutter/android/`
- Only `~/.android/debug.keystore` (debug installs — **not** for Play)
- Gradle is ready: when `key.properties` exists, `release` is signed automatically

Flutter’s `build.gradle` already expected `flutter/android/key.properties`, but no real keystore file is present here. Treat that as “pattern only” unless you find the file elsewhere.

## Create a new upload keystore

Run from the **`android/`** directory:

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storetype JKS
```

You will be prompted for:

1. **Keystore password** (storePassword) — keep in a password manager  
2. **Key password** (keyPassword) — can match the store password  
3. Name / org / city / country (e.g. `BetterLectio`, `DK`) — metadata only  

Then:

```bash
cp key.properties.example key.properties
# Edit key.properties with the passwords you just chose
```

Example `key.properties`:

```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=upload
storeFile=upload-keystore.jks
```

`storeFile` is relative to **`android/`** (project root for Gradle).

### Backup (do this once)

Store offline / in a vault (not git):

- `upload-keystore.jks`
- passwords + alias
- optionally a PEM export of the cert for support tickets:

```bash
keytool -export -rfc \
  -keystore upload-keystore.jks \
  -alias upload \
  -file upload_certificate.pem
```

## Wire-up status (repo)

| File | Role |
|------|------|
| `app/build.gradle.kts` | Loads `key.properties`; sets `signingConfigs.release` when present |
| `key.properties.example` | Template (committed) |
| `key.properties` | Secrets (gitignored) |
| `upload-keystore.jks` | Binary key (gitignored via `*.jks`) |

Without `key.properties`, `assembleRelease` / `bundleRelease` still build but are **not** signed with a Play upload key (unusable for Console upload).

## Build a Play upload bundle

```bash
cd android
./gradlew :app:bundleRelease
```

Output:

```text
app/build/outputs/bundle/release/app-release.aab
```

Verify the AAB is signed with your upload alias:

```bash
# jarsigner is part of the JDK
jarsigner -verify -verbose -certs app/build/outputs/bundle/release/app-release.aab | head -40
```

Or inspect the keystore:

```bash
keytool -list -v -keystore upload-keystore.jks -alias upload
```

## First upload in Play Console

1. Create the app (or open existing `dk.betterlectio.android`).  
2. **Release → Setup → App signing** — use Google-managed app signing (default for new apps).  
3. Upload `app-release.aab` to **Internal testing**.  
4. Keep the upload keystore safe for every future release.

## If you find an old Flutter upload key

1. Copy the `.jks` into `android/` (e.g. `upload-keystore.jks`).  
2. Recreate `key.properties` with the **same** alias and passwords.  
3. Build `bundleRelease` and upload — Play will accept it only if the cert matches.

## Security rules

- Never commit `key.properties`, `*.jks`, or `*.keystore`.  
- Never put passwords in `local.properties` that you might share screenshots of.  
- CI: inject `key.properties` + keystore as encrypted secrets, not in the repo.  
- Losing the upload key is recoverable with Play App Signing; treating the keystore casually still costs a support delay.
