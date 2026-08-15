# BetterW4 (Native Android)

Native Kotlin + Jetpack Compose app for BetterW4.

See [NATIVE_ANDROID_PLAN.md](./NATIVE_ANDROID_PLAN.md) for the full product/architecture plan.

## Requirements

- Android Studio (current stable / 2026.x)
- JDK 17+ (Studio embedded JBR is fine)
- Android SDK 36

## Open & run

1. Open the **`android/`** folder in Android Studio (not the monorepo root).
2. Wait for Gradle sync (Studio writes `local.properties` with `sdk.dir`).
3. Optional: copy `local.properties.example` → `local.properties` if you need to set `sdk.dir` by hand.
4. Run the **app** configuration on an emulator or device.

CLI:

```bash
cd android
# local.properties must contain sdk.dir=… (Studio creates this)
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
```

### What never goes on GitHub

Signing keys, `key.properties`, `local.properties`, and build outputs are gitignored — see `.gitignore` and [SIGNING.md](./SIGNING.md).

## Package

| | |
|--|--|
| Application ID | `dk.jonathanb.w4` |
| Namespace | `dk.betterw4.android` |
| Min SDK | 29 |
| Target / compile SDK | 36 |

Debug builds append `.debug` to the application id.

## Project layout (app module)

```
app/src/main/java/dk/betterw4/android/
├── BetterW4App.kt          # Hilt Application + Timber
├── MainActivity.kt
├── core/
│   ├── di/                     # Hilt modules (OkHttp, …)
│   ├── model/                  # Domain models (Student, School)
│   └── result/                 # AppResult / AppError
└── ui/
    ├── components/
    ├── navigation/             # Bottom bar + NavHost (iOS tabs)
    ├── screens/                # Feature placeholders
    └── theme/                  # Brand Material 3 + Inter/Fraunces
```

## Stack (bootstrap)

- Kotlin, Jetpack Compose, Material 3 (AGP 9.2 / Compose BOM 2026.02)
- Navigation Compose
- Hilt **2.60+** + KSP (required for AGP 9)
- Coroutines / Flow
- OkHttp, Jsoup (ready for Lectio client)
- DataStore, Security Crypto
- Coil 3
- Timber

### AGP 9 notes

Studio generated AGP 9 with built-in Kotlin. We set `android.disallowKotlinSourceSets=false` so KSP/Hilt can add generated sources. Prefer Hilt ≥ 2.59.

## Lectio client foundation

Package: `dk.betterw4.android.core.w4`

| Component | Role |
|-----------|------|
| `LectioClient` | Public façade: `get` / `postForm` / `postback` / `getBytes` |
| `LectioHttpEngine` | Manual redirects, cookie rotation, retries, serial limiter |
| `CredentialStore` | Encrypted session + student persistence |
| `SessionController` | `AuthState` + session-expired handling |
| `AuthSessionInstaller` | WebView cookies → validate → install session |
| `AspNetForm` / `StudentIdentityParser` | Scrape helpers for future endpoints |

### Adding a feature endpoint later

```kotlin
class ScheduleRepository @Inject constructor(
    private val client: LectioClient,
) {
    suspend fun week(year: Int, week: Int): AppResult<...> {
        val html = client.get("SkemaNy.aspx?...")
        // parse with Jsoup — do not reimplement cookies/redirects
    }
}
```

Session rules (iOS parity):

- Cookie header is the single source of truth (no system cookie jar)
- Empty `autologinkeyV2` / `ASP.NET_SessionId` Set-Cookie values are **ignored**
- UniLogin broker host ⇒ session expired
- Requests are serialized with a short cooldown

Run foundation tests:

```bash
./gradlew :app:testDebugUnitTest
```

## Native message reactions

Message reactions use ordinary Lectio replies and row-scoped message edits;
there is no separate reaction backend. The app implements the shared
`blr1` carrier protocol, resolves reactions onto their target messages, and
keeps malformed or unresolved carriers visible. Changing or removing a
reaction edits the same carrier, and removal stores no copy of the old emoji.
The parser turns Lectio's automatic `Redigeret af …` audit line into a compact,
localized edited-time label and also tolerates it on valid reaction carriers.

## Sent-message editing

Sent-message editing uses the native two-ViewState flow documented in
`../extension/docs/message-editing-protocol.md`, with Lectio-native eligibility.

The protocol is intentionally kept byte-compatible with the web extension and
iOS implementation.

## Next milestones

1. MitID login UI (uses `AuthSessionInstaller` + `WebViewCookieExtractor`)
2. Schedule scrape + UI
3. Remaining tabs (messages, homework, assignments, more)

## Release signing (Play)

See **[SIGNING.md](./SIGNING.md)**. Short version:

```bash
# Once: create upload keystore (if package never published)
keytool -genkeypair -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload -storetype JKS

cp key.properties.example key.properties   # fill passwords
./gradlew :app:bundleRelease               # → app/build/outputs/bundle/release/app-release.aab
```

## Notes

- Do not commit `local.properties`, `key.properties`, or `*.jks` / signing secrets.
- Plan document lives at `NATIVE_ANDROID_PLAN.md`.
