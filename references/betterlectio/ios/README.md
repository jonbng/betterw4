# BetterLectio for iOS

BetterLectio is a native SwiftUI client for Lectio. It combines Lectio data with optional BetterLectio services from Supabase and includes schedules, homework, assignments, grades, absence, messages, directory search, student profiles, widgets, and Live Activities.

This README describes the current repository-wide change set. The update brings the iOS app close to Android feature parity, adds an App Clip and automated tests, and hardens the existing networking and persistence layers.

## What changed

### Message attachments and signatures

- New messages and replies can attach photos or files. Selection uses `PhotosPicker` and the system file importer.
- Draft attachments are copied into app-owned temporary directories, deduplicated, limited to 10 files and 25 MB per file, and removed after send, discard, or stale-file cleanup.
- Uploads follow Lectio's real multi-stage flow: upload the multipart body from disk, extract the returned document ID, post it through the current ASP.NET form, preserve the updated hidden fields, and only then perform the final send.
- Dynamic form-control discovery replaces assumptions about fixed Lectio row IDs. Each recipient, attachment, reply, and final send must be confirmed in the returned page.
- Upload state is visible per file and failed/cancelled sends retain the draft for retry.
- Compose state now lives in `ComposeMessageViewModel`, and replies have the same attachment lifecycle.
- An enabled-by-default setting can append a linked “Sendt med BetterLectio” signature at send time. It never alters the visible draft, does not duplicate an existing signature, and is skipped for teacher or mixed teacher/student recipients.
- Thread parsing now retains stable participant IDs so reply signatures can apply the same teacher rule.

### Native message reactions

- Messages support 👍, ❤️, 😂, 😮, 😢, and 👎 reactions with optimistic chips, a compact picker, haptic confirmation, and a reactor list.
- Reactions travel exclusively through ordinary Lectio replies and row-scoped edits using the shared `blr1` carrier protocol; no Supabase or analytics events are involved.
- Tapping the current reaction removes it by replacing the carrier with `Fjernede sin reaktion` and an `emoji: null` payload, so the previous emoji cannot be recovered from the clear message.
- Malformed or unresolved carriers remain visible. Lectio's automatic `Redigeret af …` audit line is parsed into a compact, localized edited-time label on every message and remains tolerated on valid reaction carriers.
- The implementation stays byte-compatible with the web extension and Android protocol.

### Editable absence reasons

- Absence rows with a Lectio registration ID now open an editor for the reason and optional note.
- The registration ID used by `fravaer_aarsag.aspx` is stored separately from the related schedule activity ID.
- Valid reasons, the current selection, note, hidden ASP.NET fields, and save target are parsed from the live edit form.
- A save is accepted only when Lectio redirects away from the editor without a validation error.
- After a confirmed save, the UI updates immediately and then reconciles with a fresh absence report. A refresh failure is reported as a refresh warning, not as a failed save.
- Missing reasons are called out clearly, edits are protected from accidental dismissal, and demo mode supports the entire flow locally.

### Dynamic grade columns

- Grade categories are parsed from the current Lectio table header instead of being hard-coded to five positional columns.
- Server order and display labels are preserved. Known labels receive stable keys, while unfamiliar future columns are retained with generated keys.
- Missing or reordered columns can no longer shift a value into the wrong category.
- Filters, the all-grades table, subject detail, charts, and weighted averages all use the parsed columns.
- Averages ignore non-grades and accept only values on the Danish seven-point scale.
- Demo data and decoding models use the new `[columnKey: GradeCellValue]` representation.

### Rich student profiles and avatars

- Selecting a student opens a dedicated profile instead of going directly to a schedule.
- Profiles can show an approved display name, description, class, consent-gated birthday, allowlisted Instagram handle, BetterLectio membership state, and custom avatar.
- Profile actions include message, pin/unpin, class, and schedule navigation. Teachers and other directory entities retain the schedule-first flow.
- Supabase profile reads use school-scoped RPCs and a viewer-aware five-minute cache. Batch reads avoid one network call per avatar in message lists.
- Avatar order is custom BetterLectio image, Lectio image, then initials. Public images require safe HTTPS URLs and are downsampled and memory-cached.
- Profile-image changes invalidate caches and refresh More, search, messages, and thread avatars.
- Loading, missing-profile, inactive-member, offline, retry, demo, VoiceOver, Dynamic Type, and Reduce Motion states are covered in the UI.

### Referrals and App Clip attribution

- More now contains an “Inviter venner” screen with a stable share URL, native sharing, copy action, click/conversion statistics, recent referrals, reward progress, nudges, and conversion celebrations.
- The reward unlocks after three completed referrals.
- Universal links under `https://betterlectio.dk/r/<student-id>` are validated before storage. The first valid, unexpired token wins and finalization is retried after transport failures.
- Pending attribution, finalization attempts, nudge state, and previous conversion counts are scoped by student to prevent account crossover.
- The new `BetterLectioClip` target handles deferred-install attribution. It validates or creates the referral click token, stores it in a shared App Group, and presents the App Clip install overlay.
- The full app and App Clip include the associated-domain and shared-App-Group entitlements required by this flow.

The App Clip code is complete, but production invocation still requires Apple identifier, App Store Connect experience, AASA, website, and backend setup. See [App Clip rollout](docs/APP_CLIP_REFERRALS.md).

### Referral-unlocked profile pictures

- Eligible students can select, square-crop, preview, compress, and submit a profile picture for moderation.
- Client validation permits JPEG, PNG, or WebP up to 5 MB and verifies the file signature. The editor produces a normalized JPEG for upload.
- The backend remains authoritative for entitlement, an existing pending submission, file validation, and the three-month post-approval cooldown.
- Locked, ready, pending, rejected, approved, cooldown, retry, and demo states are represented. Rejections display the moderator reason and note.
- The existing avatar remains visible during moderation. Returning to the app checks for an approval/rejection transition and refreshes all avatar caches.
- Uploads use the shared `profile-picture-submit` Edge Function with platform `ios`; no separate iOS moderation path was introduced.

Production dependencies and rollback controls are listed in the [release runbook](docs/REFERRAL_PROFILE_PICTURE_RELEASE.md).

### Shake-to-feedback

- A deliberate two-impulse shake opens feedback anywhere in the authenticated app. Settings provides an accessible button for the same action.
- The sheet supports Bug, Idea, and Other categories, preserves the draft on failure, and lets the user independently include or exclude a pre-sheet screenshot and diagnostic logs.
- Screenshots are resized and compressed to a bounded JPEG. Text feedback is submitted first, so a screenshot upload failure is presented as partial success and cannot create a duplicate feedback row.
- Diagnostics use a bounded in-memory ring buffer. Cookies, authorization data, tokens, passwords, message/note fields, email addresses, and user-specific home paths are redacted.
- System alerts are never captured, and demo mode never writes production feedback.

### Browser-extension promotion

- More and Settings now present a native sheet explaining that the BetterLectio extension is installed on a desktop browser.
- The canonical download URL is defined once in `BetterLectioLinks` and can be copied or shared.
- Open, copy, and share actions emit allowlisted analytics events.

### Analytics, privacy, and authentication

- PostHog is configured behind one `Analytics` boundary with an explicit event allowlist. Automatic lifecycle/screen/interaction capture, session replay, surveys, push capture, and feature-flag preload are disabled.
- Student identity is shared with the Android convention and reset on logout. Demo students are never identified.
- Operational exceptions have a small daily deduplication budget.
- Cookie and request logging now prints compact paths and cookie names only. Session IDs, autologin keys, authorization values, redirects containing query secrets, and response cookie values are not logged.
- Initial login waits for the Supabase/Lectio cookie handoff before exposing authenticated screens.
- Cold-start validation and Supabase authentication complete in sequence before app data begins loading, preventing replay of a pre-rotation Lectio token.
- Logout clears message, profile, public-image, credential, and WebView state.

### Networking and responsiveness

- All native Lectio traffic shares a priority-aware serial gate. User-initiated work runs ahead of opportunistic prefetches, while requests still observe Lectio's cooldown.
- Waiting and active `URLSession` tasks are cancellation-aware. Multipart uploads stream from disk instead of loading the full body into memory.
- Supabase authentication joins an existing in-flight task instead of launching a second cookie-rotating request.
- HTML parsing and larger SwiftData reads/writes have moved off the main actor where safe.
- Schedule, homework, assignments, grades, absence, messages, and directory loads use generation/target guards so stale responses cannot overwrite a newly selected account, folder, week, or entity.
- Background lesson prefetch is cancellable and lower priority. Schedule loads avoid redundant refreshes for five minutes and cache events by day.
- Repeated formatters, grouping, filtering, member counts, lookups, and search sections are cached rather than rebuilt during every SwiftUI body evaluation.
- Message and directory searching is debounced and performed away from the UI actor.
- Received message images and public avatars are downsampled and held in bounded `NSCache` instances.
- Widget timelines reload only when the shared lesson payload actually changes.

### Persistence and cache safety

- Directory, schedule, homework, student, and message stores have asynchronous APIs backed by fresh/background SwiftData contexts.
- Directory snapshots and membership sets are updated in batches, with in-memory indexes for entity, picture, name, membership, class, and pin lookups.
- SQLite recovery removes the main store plus `-wal` and `-shm` sidecars; directory and student caches fall back to memory-only containers if disk recovery fails.
- Homework completion merges local pending writes and remote state without allowing an older server response to undo a newer tap.
- Cache clearing now awaits each asynchronous store operation and removes scoped defaults.
- The message cache is actor-isolated and cleared for the logging-out student.

### Project, tests, CI, and repository hygiene

- `BetterLectioTests` is now a first-class test target in the shared scheme.
- Sent-message editing follows Lectio's native row-scoped, two-ViewState flow documented in `../extension/docs/message-editing-protocol.md`; edit eligibility always comes from Lectio's rendered controls.
- The suite covers attachment postbacks, absence editing, dynamic grade tables, signatures, rich profiles, referrals, feedback, profile pictures, message editing/reactions, and schedule parser failures.
- Eleven sanitized Lectio fixtures cover absence and message ASP.NET form stages.
- GitHub Actions runs `xcodebuild test` on an iPhone 16 Pro simulator for relevant pushes and pull requests.
- PostHog was added as a Swift Package dependency; SwiftSoup and Supabase remain shared dependencies.
- `.gitignore` now excludes Xcode user state, build products, DerivedData, local package state, `.DS_Store`, and schedule debug dumps.
- Previously tracked build output, `.DS_Store`, and per-user Xcode workspace/scheme files are removed from the repository.

## Main architecture

| Layer | Responsibility |
|---|---|
| SwiftUI views and view models | Presentation, local draft state, cancellation, and user-facing retry/error states |
| `LectioHTTPClient` extensions | Authenticated Lectio requests, ASP.NET postbacks, cookie rotation, redirects, and upload confirmation |
| Parsers | Convert Lectio HTML/JSON into stable app models without relying on fixed row positions |
| SwiftData stores | Offline-first schedules, homework, directory, students, and messages |
| Supabase services | BetterLectio authentication, profiles, feedback, referral stats/attribution, homework sync, and moderated profile pictures |
| Coordinators | App-wide feedback presentation, referral lifecycle, and profile-picture review notifications |
| App Clip | Capture a referral before installation and pass the token through the shared App Group |

## Repository layout

- `BetterLectio/` — main iOS application, models, parsers, services, stores, and SwiftUI screens.
- `BetterLectioClip/` — referral App Clip target.
- `live-lesson/` — widget and Live Activity extension.
- `BetterLectioTests/` — unit/parser tests and sanitized fixtures.
- `docs/` — rollout, release, design, and parity documentation.
- `.github/workflows/ios.yml` — simulator test workflow.
- `lectio_plus_plus/` — separate legacy Flutter application retained in the repository.

## Requirements and local development

- macOS with Xcode capable of the configured iOS 18.6 targets.
- An iOS 18.6+ simulator or device for the main app and App Clip.
- Automatic Swift Package resolution for SwiftSoup, Supabase Swift, and PostHog.
- Apple team/signing access is required for device builds, Associated Domains, App Groups, the widget, and App Clip. Simulator tests disable code signing.

Open `BetterLectio.xcodeproj`, select the `BetterLectio` scheme, resolve packages, and run. The app includes an offline demo path; live Lectio and BetterLectio features require valid services and authentication.

Configuration is read from `BetterLectio/Info.plist` and target build settings:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `POSTHOG_HOST`
- `POSTHOG_PROJECT_TOKEN`

These are client-side identifiers, not service-role secrets. Server-only secrets must stay in the deployment environment.

Run the simulator suite with:

```sh
xcodebuild test \
  -project BetterLectio.xcodeproj \
  -scheme BetterLectio \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

## Backend and release dependencies

The app compiles independently of a production rollout, but the following features require their matching server contracts:

- Student profiles: `get_student_profile` and `get_student_profiles` RPCs with same-school/privacy enforcement.
- Feedback: `submit_feedback`, `register_feedback_attachment`, and the private `feedback-attachments` bucket.
- Referrals: referral stats RPC, `referral-click`, `referral-finalize`, and the atomic finalization migration.
- Profile pictures: `get_my_profile_picture_state`, `profile-picture-submit` with `ios` allowed, moderation tables/buckets, and cleanup jobs.
- Deferred referral attribution: website routes, AASA, App Clip registration, shared App Group, and the default App Clip experience.

Deploy and validate those pieces in the order documented by the release runbooks. Referral and profile-picture functionality should remain behind server-side feature switches until the production checks are complete.

## Detailed planning documents

- [Android-to-iOS parity plan](docs/plans/2026-08-02-android-feature-parity-priorities.md)
- [Referral App Clip rollout](docs/APP_CLIP_REFERRALS.md)
- [Referral and profile-picture release runbook](docs/REFERRAL_PROFILE_PICTURE_RELEASE.md)
- [Rich lesson content design](docs/superpowers/specs/2026-04-08-rich-lesson-content-design.md)
