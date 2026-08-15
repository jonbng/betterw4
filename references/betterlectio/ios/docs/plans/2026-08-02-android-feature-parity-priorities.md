# Android-to-iOS Feature Parity Priorities

## Overview

This document defines nine Android features that should be brought to the native iOS app. It describes the existing Android behavior, the current iOS gap, the intended iOS experience, implementation considerations, and completion criteria.

The objective is functional parity, not a literal translation of Jetpack Compose or Android platform APIs. Each feature should feel native in SwiftUI and use the existing iOS networking, storage, authentication, and Supabase infrastructure.

## Priorities at a Glance

| Feature | User value | Expected effort | Important dependency |
|---|---:|---:|---|
| Message attachments when composing/replying | Very high | High | Lectio multipart upload flow |
| Edit absence reason and note | Very high | Medium | ASP.NET postback implementation |
| Dynamic grade columns | High | Medium | Grade model and cache migration |
| Rich student profiles | High | High | Supabase student-profile API and privacy rules |
| Shake-to-feedback | Medium-high | Medium-high | Feedback RPC, storage, and diagnostic log buffer |
| Referral system | Medium-high | High | iOS attribution/deferred-link strategy |
| Referral-unlocked custom profile pictures | Medium-high | Medium | Referral entitlement, moderated upload API, and rich profiles |
| Browser-extension promotion | Medium | Low | Download URL and presentation copy |
| Optional message signature | Medium | Low-medium | Shared compose/reply body transformation |

## Shared Principles

- Existing Lectio credentials must continue to be handled through `KeychainManager` and `LectioHTTPClient`.
- ASP.NET form posts must preserve hidden fields, cookies, redirects, and credential rotation.
- Demo mode must remain fully offline and must not write production Supabase data.
- New Supabase reads and writes must follow the existing authenticated student scope and row-level security rules.
- Failure in an enhancement must not discard a user's drafted message, absence edit, or feedback text.
- New user-facing strings should be structured so future localization is possible, even though much of the current iOS UI is hardcoded Danish.
- Analytics must never contain message bodies, absence notes, private profile fields, screenshots, credentials, or raw diagnostic logs.

---

## 1. Message Attachments When Composing or Replying

### Existing Android behavior

Android supports attachments in both new messages and replies:

- Select multiple photos or documents.
- Show pending attachments before sending.
- Remove an attachment before sending.
- Upload documents through Lectio's upload flow.
- Preserve attachment state while editing the message.
- Disable or limit additional selection when the attachment limit is reached.
- Send the final message only after the required attachment postbacks succeed.

Relevant Android implementations:

- `ui/screens/messages/MessagesScreen.kt`
- `ui/screens/messages/MessagesViewModel.kt`
- `feature/messages/DocumentUpload.kt`
- `feature/messages/MessageRepository.kt`
- `feature/messages/MessagePostbackFields.kt`

### Current iOS gap

`ComposeMessageView` sends only recipients, subject, and a plain-text body. `MessageThreadView` supports a text reply but has no attachment picker or pending-attachment state. Existing received-message attachment support does not solve outgoing uploads.

### Intended iOS experience

- Add an attachment button to both compose and reply editors.
- Present a native menu for:
  - Photo library selection.
  - Files/document selection.
- Display selected items as removable chips or rows with filename, type, and upload state.
- Keep the draft editable while attachments are selected.
- Show upload and send progress without clearing the draft prematurely.
- If one upload fails, identify the failed file and allow retry or removal.
- Prevent duplicate sends while an upload/send operation is active.

Use `PhotosPicker` for images and `fileImporter` for documents. Security-scoped file URLs must be copied or read while access is valid. Large files should be streamed where practical rather than retained entirely in view state.

### Technical work

1. Add an outgoing attachment model containing a stable ID, display name, MIME type, size, local source, and upload state.
2. Move compose state into a view model so it survives sheet/view recomposition and can coordinate asynchronous uploads.
3. Extend `LectioHTTPClient+Messages.swift` with the multipart upload/postback sequence already proven on Android.
4. Preserve and resend the current ASP.NET hidden fields between recipient, attachment, and final-send requests.
5. Implement the same feature for `MessageThreadViewModel` replies.
6. Add limits and validation based on the constraints Lectio actually accepts. Do not silently discard excess or unsupported files.
7. Ensure temporary files are cleaned up after success, cancellation, or terminal failure.

### Acceptance criteria

- A new message can be sent with one or more supported images/documents.
- A reply can be sent with one or more supported images/documents.
- Attachments can be removed before sending.
- Attachment filenames and contents arrive correctly in Lectio.
- A failed upload leaves the message body, recipients, subject, and remaining attachments intact.
- Sending with no attachments continues to behave exactly as before.
- Demo mode can exercise the UI without performing a network upload.
- Parser/network tests use captured sanitized HTML fixtures for every upload/postback stage.

---

## 2. Edit Absence Reason and Note

### Existing Android behavior

Android shows separate absence overview and registration views. Registrations are divided into missing and completed reasons. Selecting a registration opens an editor where the student can choose a reason, edit a note, and submit the change to Lectio.

Relevant Android implementations:

- `ui/screens/more/MoreScreen.kt` (`AbsenceScreenContent` and the edit sheet)
- `ui/screens/more/MoreViewModel.kt`
- `feature/absence/AbsenceRepository.kt`
- `feature/absence/AbsenceParser.kt`

### Current iOS gap

The iOS absence feature parses and displays missing reasons and registrations, but it is read-only. There is no HTTP client method for loading reason choices or posting an updated cause/note.

### Intended iOS experience

- Keep the existing absence overview.
- Make absence registration rows selectable.
- Clearly distinguish registrations missing a reason from completed registrations.
- Present a sheet containing:
  - Registration summary: date, module/activity, absence percentage, and existing reason.
  - A single-select list or picker of valid Lectio reasons.
  - An optional note field.
  - Cancel and Save actions.
- Disable Save until a reason is selected and something has changed.
- Refresh or update the local report immediately after a successful save.

### Technical work

1. Expand the absence models with the stable registration/form identifiers needed for postback.
2. Parse valid cause choices and all hidden ASP.NET form fields from the absence page.
3. Add an update method to `LectioHTTPClient+Absence.swift`.
4. Verify success from the returned page rather than treating every HTTP 200 response as success.
5. Update `AbsenceViewModel` optimistically only if rollback is reliable; otherwise show progress and replace the report from the confirmed server response.
6. Handle session expiration through the existing global authentication path.

### Acceptance criteria

- Missing absence reasons are easy to identify.
- The user can add a reason and optional note.
- The user can change an existing reason or note.
- The saved result remains correct after a full refresh and app restart.
- Cancel never mutates local or remote data.
- Lectio validation errors are shown without losing the edited values.
- Tests cover parsing reason options, form construction, successful updates, and rejected updates.

---

## 3. Dynamic Grade Columns

### Existing Android behavior

Android reads grade column names and order from the live Lectio table header. Grade values are stored in a map keyed by a canonical form of the actual header. This matters because schools and terms can expose different columns, and fixed positional parsing can shift values into the wrong category.

Relevant Android implementations:

- `feature/grades/GradeParser.kt`
- `feature/grades/GradeModels.kt`
- `feature/grades/GradeAverage.kt`
- `ui/screens/more/MoreScreen.kt` grade views

### Current iOS gap

The iOS model has five fixed properties (`firstStandpoint`, `secondStandpoint`, `internalExam`, `yearGrade`, and `finalExamOrYearTest`). `GradeParser` assumes these occupy cells 2 through 6. A school or term with a different header set can therefore lose, mislabel, or shift grades.

### Intended iOS experience

- Display exactly the grade categories returned by Lectio.
- Preserve their server-provided order.
- Build the filter/picker from the parsed columns instead of a fixed `GradeType` enum.
- Continue to offer an “Alle” view.
- Calculate weighted averages independently for each available column.
- Show all available values in the subject-detail screen.
- Keep notes associated with the correct hold/subject.

### Proposed model direction

```swift
struct GradeColumn: Codable, Equatable, Hashable, Identifiable {
    let key: String
    let label: String
    var id: String { key }
}

struct GradeEntry: Codable, Equatable, Identifiable {
    let id: String
    let hold: String
    let holdElementId: String?
    let subject: String
    let grades: [String: GradeCellValue]
}
```

The canonical key should normalize known labels for stable identity while preserving the original label for display. Unknown columns must still be retained rather than ignored.

### Technical work

1. Parse desktop header cells first, excluding Hold and Subject.
2. Parse each data cell against the matching live column.
3. Replace the fixed `GradeType` selection with a selected column key.
4. Generalize average calculation and the subject-detail presentation.
5. Decide how to migrate or invalidate cached `GradesReport` values encoded with the old schema.
6. Retain current blocked-protocol alerts.

### Acceptance criteria

- A table with fewer, additional, reordered, or unfamiliar grade columns parses correctly.
- Grade values never move to another category because a preceding column is absent.
- The picker contains only “Alle” plus columns returned by Lectio.
- Weighted averages use values and weights from the selected column only.
- Subject detail shows every populated grade cell with the correct label.
- Fixtures cover multiple real table layouts and an unknown future column.

---

## 4. Rich Student Profiles

### Existing Android behavior

Android augments Lectio directory identities with BetterLectio profiles stored in Supabase. A student profile can include a preferred display name, description, Instagram handle, optional birthday, custom profile picture, class information, and whether the student uses BetterLectio. The profile also combines actions such as viewing the schedule, writing a message, opening the class, and pinning the person.

Relevant Android implementations:

- `ui/screens/more/StudentProfileScreen.kt`
- `feature/directory/StudentProfile.kt`
- `feature/supabase/SupabaseStudentProfileService.kt`
- `ui/screens/more/MoreViewModel.kt`

### Original iOS gap

iOS has a strong Lectio directory with search, pinning, photos, class/hold membership, and schedules. It did not fetch or render BetterLectio profile metadata, and it lacked a direct “write message” action on the student profile/schedule destination.

### Implementation status (2026-08-02)

Implemented. Students now open a dedicated SwiftUI profile with preferred identity, approved public avatar, description, consent-gated birthday, allowlisted Instagram link, membership state, message/pin/class actions, and schedule navigation. Reads use same-school Supabase RPCs; database column privileges prevent authenticated clients from reading `students.birthdate` directly. The UI includes explicit loading, missing, inactive, offline/error, retry, refresh, Dynamic Type, VoiceOver, Reduce Motion, and offline demo behavior. Teachers and other directory entities keep their existing schedule flow.

### Intended iOS experience

- Selecting a student opens a dedicated profile screen rather than immediately showing only their schedule.
- The profile header uses BetterLectio data when allowed and falls back to Lectio data.
- Suggested profile content:
  - Profile picture or initials.
  - Display name and class.
  - BetterLectio membership indicator.
  - Optional description.
  - Optional Instagram link.
  - Optional birthday only when the owner has enabled visibility.
- Primary actions:
  - Write message.
  - Pin/unpin.
  - View class.
- The student's schedule remains directly available below the profile or through a clear action.

### Privacy and trust requirements

- Never infer that a private field is public merely because the client received it.
- Supabase should return only fields the viewer is authorized to see.
- Birthday visibility must be enforced server-side as well as hidden in the UI.
- External social links must be normalized and allowlisted before opening.
- Inactive/deleted BetterLectio profiles must fall back cleanly to Lectio identity.
- Do not expose internal Supabase identifiers in analytics or UI.

### Technical work

1. Add a `StudentProfile` model and `SupabaseStudentProfileService` equivalent on iOS.
2. Resolve Lectio directory IDs to the correct BetterLectio student ID without name-based matching.
3. Cache profile responses with a short, explicit freshness policy.
4. Add a student profile route to the existing directory navigation.
5. Reuse `ComposeMessageView` with the selected student prefilled as a recipient.
6. Preserve the existing person-schedule behavior for teachers and non-profile entities.

### Acceptance criteria

- A BetterLectio user displays authorized rich-profile fields.
- A non-user or unavailable profile displays the existing Lectio identity without an error.
- Hidden birthdays and other private fields never appear.
- Instagram URLs are safely normalized and open correctly.
- Write Message opens compose with the correct stable recipient ID.
- Pin, class navigation, schedule navigation, and directory back navigation remain intact.
- Profiles work from search results, pinned people, classes, and holds.

---

## 5. Shake-to-Feedback

### Existing Android behavior

Android listens for a deliberate device shake at the app root. It captures the current screen and recent diagnostic logs before presenting the feedback sheet. The user selects Bug, Idea, or Other, writes feedback, chooses whether to include the screenshot/logs, and submits privately through Supabase.

Relevant Android implementations:

- `ui/feedback/FeedbackHost.kt`
- `ui/feedback/FeedbackSheet.kt`
- `feature/feedback/ShakeDetector.kt`
- `feature/feedback/ScreenshotCapturer.kt`
- `feature/feedback/FeedbackLogBuffer.kt`
- `feature/feedback/FeedbackRepository.kt`
- `feature/supabase/SupabaseFeedbackService.kt`

### Current iOS gap

iOS has no in-app feedback entry point or diagnostic submission pipeline.

### Intended iOS experience

- A deliberate shake opens a feedback sheet from anywhere in the authenticated app.
- The sheet includes:
  - Category: Bug, Idea, or Other.
  - Feedback text.
  - Screenshot preview with an include/exclude toggle.
  - Diagnostic log summary with an include/exclude toggle.
  - A short privacy explanation.
- Submission shows clear sending, success, and retry states.
- Add a visible “Send feedback” item in Settings as an accessible alternative to shaking.

### Technical work

1. Add a root-level shake event bridge using UIKit motion events without interfering with normal gestures.
2. Capture the active app window before presenting the sheet.
3. Implement a bounded in-memory log buffer with explicit redaction.
4. Add iOS models and a Supabase feedback service matching the existing RPC/storage contract where possible.
5. Upload screenshots only after the feedback record is successfully created.
6. Retain text locally in the sheet after recoverable submission errors.

### Privacy and security requirements

Before logs can be attached, redact at minimum:

- `ASP.NET_SessionId`, `autologinkeyV2`, and all cookies.
- Authorization headers and Supabase access/refresh tokens.
- Message bodies, absence notes, and other scraped personal content.
- Full request/response bodies.
- Local file paths containing personal identifiers where possible.

Screenshot and log inclusion must be opt-out at submission time and clearly disclosed. Feedback storage must be private and protected by appropriate row-level security.

### Acceptance criteria

- Shake detection works reliably without repeated accidental openings.
- Settings provides a non-shake entry point.
- The captured screenshot represents the screen before the sheet appears.
- The user can independently exclude screenshot and logs.
- Sensitive tokens and cookies are never present in submitted diagnostics.
- Submission succeeds with text only, text plus screenshot, or text plus diagnostics.
- Demo mode does not submit production feedback.
- Network failure preserves the draft and supports retry.

---

## 6. Referral System

### Existing Android behavior

Android gives each student a referral link, tracks clicks and completed referrals, displays recent conversions, shows progress toward an unlock threshold, and supports share/copy actions. Android can attribute an install using Google Play Install Referrer data.

Relevant Android implementations:

- `feature/referral/ReferralCoordinator.kt`
- `feature/referral/InstallReferrerReader.kt`
- `feature/referral/ReferralStore.kt`
- `feature/referral/ReferralModels.kt`
- `feature/supabase/SupabaseReferralService.kt`
- `ui/screens/more/MoreScreen.kt` (`ReferralScreenContent`)

### Current iOS gap

iOS has no referral UI, stats service, referral finalization, or attribution mechanism.

### Platform constraint

Google Play Install Referrer has no direct App Store equivalent. The Android attribution implementation cannot simply be ported. iOS needs an explicit attribution design, for example:

- Universal link attribution when the app is already installed.
- A first-party landing page that stores a short-lived referral token and attempts to recover it after installation.
- An App Clip-based flow, if justified.
- A third-party deferred deep-link provider, only after a privacy and cost review.
- A user-confirmed referral code as a reliable fallback.

The chosen method must account for iOS privacy limitations and should not use fingerprinting.

### Intended iOS experience

- Add “Inviter venner” under More.
- Show:
  - Progress toward the current reward/unlock threshold.
  - Share button using `ShareLink` or a native share sheet.
  - Copy Link action.
  - Click and completed-referral counts.
  - Recent completed referrals when available.
- Show lightweight referral nudges sparingly and allow dismissal.
- Finalize attribution only once for a newly authenticated student.

### Technical work

1. Reuse the Supabase referral models/RPCs or formalize a cross-platform contract.
2. Add an iOS referral service and coordinator.
3. Support universal links in the app and website.
4. Select and implement the deferred-install strategy separately from the basic referral screen.
5. Persist at-most-once finalization and nudge dismissal locally.
6. Present the existing custom-profile-picture reward once the moderated upload flow described below is available on iOS.

### Delivery recommendation

Ship in two phases:

1. Referral screen, link sharing, stats, and attribution for already-installed apps.
2. Deferred install attribution after the product and privacy design is approved.

### Acceptance criteria

- Every eligible student can retrieve and share a stable referral URL.
- Copy and native sharing use the correct URL and campaign parameters.
- Click/conversion counts match the backend.
- An already-installed app correctly attributes a universal referral link.
- The same referral is not finalized more than once for one student.
- Self-referral and invalid/expired tokens are rejected server-side.
- The UI clearly distinguishes clicks from completed referrals.
- No device fingerprinting is used.

---

## 7. Referral-Unlocked Custom Profile Pictures

### Existing Android behavior

Android lets students who have earned the existing referral reward choose a custom BetterLectio profile picture. The image is submitted privately for moderation and does not replace the current avatar until an admin approves it. The profile-picture editor is available from More, the student card, and the unlocked referral reward.

The browser extension and Android share the same Supabase implementation:

- `students.referral_reward_unlocked_at` is the permanent entitlement source of truth.
- `get_my_profile_picture_state` returns entitlement, referral progress, moderation state, current approved URL, and cooldown state.
- `profile-picture-submit` accepts authenticated multipart submissions.
- `profile_picture_submissions` and the private `profile-picture-submissions` storage bucket hold images awaiting review.
- Admin approval publishes an immutable public object and updates `students.custom_pfp_url`.

Relevant Android implementations:

- `feature/profilepicture/ProfilePictureModels.kt`
- `feature/supabase/SupabaseProfilePictureService.kt`
- `ui/screens/more/ProfilePictureEditorSheet.kt`
- `ui/screens/more/MoreViewModel.kt`
- `ui/screens/more/MoreScreen.kt`

### Implementation status (2026-08-02)

Implemented on iOS. The referral and own-profile surfaces open a reusable editor backed by `get_my_profile_picture_state` and the shared `profile-picture-submit` function. The editor includes entitlement, pending, rejection, cooldown, retry, manual refresh, foreground refresh, interactive cropping, validated uploads, Danish/English strings, and offline demo submission. Approved public images are loaded without cookies and preferred across profile, directory, schedule, and messaging surfaces with Lectio and initials fallbacks. Review transitions invalidate cached profile data and refresh visible avatars. Unit tests cover state decoding, validation, review transitions, and fallback order. The multi-state demo gallery remains deferred; production deployment still follows `docs/REFERRAL_PROFILE_PICTURE_RELEASE.md`.

### Product rules

- Unlock requires the existing referral entitlement, currently earned after three completed referrals. Clients must not derive entitlement from a local count alone.
- Only JPEG, PNG, and WebP are accepted, with a maximum file size of 5 MB.
- Every new image requires admin review before publication.
- The existing approved or Lectio avatar remains visible while a submission is pending.
- An approval starts a cooldown of three calendar months from the approval timestamp.
- A rejection does not consume the cooldown and allows an immediate retry.
- Rejections include a required reason; the `other` reason requires a moderator note.
- iOS must use the shared backend contract and must not add a separate bucket, entitlement, or moderation path.

### Intended iOS experience

- Show the custom-profile-picture reward and progress in the referral screen.
- Once unlocked, provide a clear “Skift profilbillede” action from the referral reward and the user's own profile.
- Present a native SwiftUI sheet with:
  - The currently approved avatar.
  - A `PhotosPicker` image selector.
  - A preview cropped from the top in the same portrait aspect ratio used elsewhere.
  - Format and 5 MB limit guidance.
  - A Send for Approval action.
- While pending, explain that the current avatar remains live and provide manual status refresh.
- After rejection, show the localized reason and moderator note, then allow immediate reselection and retry.
- During cooldown, show the exact next eligible date and disable selection/submission.
- Approved pictures should become the preferred avatar throughout iOS, with Lectio pictures and initials as fallbacks.

### Technical work

1. Add Codable models matching `get_my_profile_picture_state`, including submission, rejection, and cooldown fields.
2. Add an authenticated Supabase service for the state RPC and multipart `profile-picture-submit` Edge Function call with platform set to `ios`.
3. Extend the Edge Function and database platform constraint to accept `ios` in the same deployment that enables the client. Do not ship the iOS UI before this backend compatibility is deployed.
4. Validate type and size client-side for immediate feedback; retain server-side magic-byte, ownership, entitlement, active-submission, and cooldown validation as authoritative.
5. Build the picker/editor as a reusable SwiftUI sheet and connect it to the referral screen and own-profile entry point.
6. Refresh profile-picture state after submission and whenever the editor is reopened or the app returns to the foreground.
7. Update shared iOS avatar resolution to prefer `custom_pfp_url`, then `lectio_pfp_url` or Lectio directory imagery, then initials.
8. Add localized Danish and English status, validation, rejection, and cooldown strings.
9. Keep demo mode local-only with representative locked, pending, rejected, cooldown, and approved states.

### Acceptance criteria

- A student without `referral_reward_unlocked_at` cannot submit, even if the UI or request is manipulated.
- An entitled student can select and submit a valid JPEG, PNG, or WebP image no larger than 5 MB.
- Invalid type, oversize file, expired authentication, duplicate pending submission, and server errors produce recoverable UI states.
- A pending image remains private and never replaces the current avatar.
- Approval makes the immutable custom URL the preferred avatar throughout iOS.
- The next submission is blocked until three calendar months after approval.
- Rejection shows the reason/note and permits an immediate retry.
- Reopening the editor accurately reflects moderation performed outside the app.
- Demo mode never uploads an image or writes Supabase data.
- Unit tests cover state decoding, entitlement, pending/rejected/cooldown presentation, MIME/size validation, and avatar fallback order.

---

## 8. Browser-Extension Promotion

### Existing Android behavior

Android exposes “Browser-udvidelse” in More and Settings. It presents a sheet explaining that the extension is installed on a computer, displays the BetterLectio download URL, and lets the user copy it.

Relevant Android implementation:

- `ui/extension/ExtensionInviteSheet.kt`

### Implementation status (2026-08-02)

Implemented on iOS. More and Settings open one localized native sheet that explains the desktop requirement and supports copy and native sharing. The canonical download URL is shared with the message-signature feature, analytics record only the entry source/action, and the flow works without networking in demo mode.

### Intended iOS experience

- Add “Browser-udvidelse” under the app section in More.
- Present a native sheet with:
  - Short explanation of what the extension adds.
  - Clear wording that installation happens on a desktop browser.
  - Canonical download URL.
  - Copy Link action.
  - Share Link action, useful for sending the URL to the user's computer.
  - Optional “Learn more” link.
- Do not imply that the extension can be installed directly in the iOS app.

### Technical work

1. Define the canonical URL in one shared configuration location.
2. Add a small SwiftUI sheet and route from More.
3. Use `UIPasteboard` or `ShareLink` for copy/share actions.
4. Add analytics for sheet open, copy, and share without attaching student identity unless required and documented.

### Acceptance criteria

- The extension entry is discoverable from More.
- The sheet explains the desktop requirement.
- Copy puts the correct HTTPS URL on the pasteboard.
- Share opens the native share sheet with useful accompanying text.
- Links remain configurable without editing multiple views.
- The feature works in demo mode.

---

## 9. Optional Message Signature

### Existing Android behavior

Android can append a linked “Sendt med BetterLectio” footer when sending a new message or reply. It avoids duplicates, skips the footer when messaging teachers, and provides a setting to disable it.

Relevant Android implementations:

- `feature/messages/MessageSignature.kt`
- `feature/settings/SettingsStore.kt`
- `ui/screens/more/MoreScreen.kt` message settings
- `feature/messages/MessageRepository.kt`

### Current iOS gap

iOS removes historical BetterLectio footer text when rendering received messages, but it does not add a footer when sending and has no signature preference.

### Intended iOS experience

- Add a Messages setting controlling the BetterLectio signature.
- Apply the same policy to new messages and replies.
- The setting label should describe the actual state clearly. Prefer a positive toggle such as “Tilføj BetterLectio-signatur” instead of a double-negative disable switch.
- The body visible in the editor remains the user's content; the generated signature is appended at send time.

### Signature policy

- Never append when the setting is off.
- Never append when the message already contains the current or a historical BetterLectio signature.
- Skip when any known recipient is a teacher, matching Android behavior.
- For replies, determine recipient types from stable Lectio context-card IDs, not display names.
- Append valid Lectio BBCode using the canonical BetterLectio download URL.
- Do not mutate or persist the user's draft with the generated footer.

### Technical work

1. Add a persisted signature preference to `SettingsStore`.
2. Create a pure `MessageSignature` helper shared by compose and reply flows.
3. Ensure parsed recipients retain stable `S…`/`T…` identifiers where available.
4. Transform the body immediately before constructing the final Lectio form post.
5. Keep renderer cleanup compatible with both old and new footer forms.

### Acceptance criteria

- Enabling the preference adds exactly one linked signature to eligible new messages and replies.
- Disabling it sends the original body unchanged.
- Messages to teachers do not receive the signature.
- Existing signature text is not duplicated.
- Failed sends leave the editor body unchanged and do not expose the generated footer as draft content.
- Unit tests cover enabled, disabled, teacher, mixed recipients, duplicate prevention, blank body, and reply cases.

---

## Suggested Delivery Order

1. Dynamic grade columns — isolated correctness improvement with fixture-driven tests.
2. Optional message signature — establishes shared send-time body transformation.
3. Browser-extension promotion — small, independent UI feature and canonical link configuration.
4. Edit absence reason and note — high-value Lectio postback feature.
5. Message attachments — largest daily-use messaging improvement and highest networking complexity.
6. Rich student profiles — establishes approved custom-avatar rendering and depends on a reviewed Supabase data contract.
7. Shake-to-feedback — depends on safe diagnostic capture and backend storage policy.
8. Referral system — build the basic screen first; treat deferred install attribution as a separate platform project.
9. Referral-unlocked custom profile pictures — follows the referral screen and rich-profile avatar resolution; requires enabling `ios` in the shared submission backend.

This sequence is ordered for implementation safety and dependency reuse, not solely by user value. Message attachments and absence editing remain the most valuable user-facing additions and can be moved earlier if multiple workstreams are available.

## Definition of Done for the Initiative

- Each feature has automated model/parser/request tests where applicable.
- Sanitized real-world fixtures cover Lectio HTML and ASP.NET postback variations.
- New Supabase functionality is protected by reviewed row-level security policies.
- Demo mode has a usable, non-production path for every new screen.
- Session expiration, offline behavior, cancellation, and retry states are handled.
- Accessibility labels, Dynamic Type, VoiceOver order, reduced motion, and dark mode are verified.
- No credentials, personal content, screenshots, or diagnostic logs are added to analytics.
- Existing schedules, messages, directory data, grades, absence data, and authentication continue to work.
