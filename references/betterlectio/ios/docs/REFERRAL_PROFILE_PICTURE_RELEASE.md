# Referral and profile-picture release runbook

The code is releasable only after every gate below is checked in the target production environment.

## Required secrets and controls

- Supabase: set `BL_IP_HASH_SALT` to at least 32 random characters.
- Supabase: set `REFERRALS_ENABLED=true` and `PROFILE_PICTURES_ENABLED=true` only for the rollout cohort. Setting either to `false` is the immediate server rollback.
- Admin: set a strong `ADMIN_PIN`, a random 32+ character `ADMIN_SESSION_SECRET`, and a named `ADMIN_ACTOR`. Apply an edge/WAF rate limit to `/api/auth` in addition to application throttling.
- Schedule `maintenance-cleanup` daily with `Authorization: Bearer <service-role-key>` and alert on any non-2xx result.

## Deployment order

1. Reconcile the linked Supabase migration history with the repository (the current dry-run reports remote versions missing locally); do not use `migration repair` until the missing SQL has been reviewed and restored. Back up the affected tables, rerun `supabase db push --dry-run`, then apply all migrations through `20260807_atomic_referral_finalization.sql`.
2. Deploy Edge Functions using `extension/supabase/config.toml`: `referral-click`, `referral-finalize`, `profile-picture-submit`, then `maintenance-cleanup`.
3. Smoke-test functions while both feature switches are `false`, then enable them in staging.
4. Deploy admin, verify signed login, approve/reject flows, reviewer attribution, normalized JPEG output, and private-object deletion.
5. Deploy website and verify AASA returns `application/json` directly without redirects or authentication.
6. Register the App Clip child identifier, Associated Domains, and App Group for both identifiers. Publish the default experience for `https://betterlectio.dk/r/`.
7. Archive the iOS app in Release configuration, validate the archive, and distribute to an internal TestFlight group before production.

## Required device matrix

- Physical iPhone on the minimum supported iOS and current iOS; light/dark mode, Dynamic Type XXXL, VoiceOver, Reduce Motion.
- Referral opened from Safari, Messages, Mail, QR, installed full app, uninstalled app/App Clip, cold start, warm start, offline then retry.
- Tokenless App Clip URL, valid token URL, forged token, expired token, two competing links, self-referral, returning user, and simultaneous finalization requests.
- Logout/login with two students on one device; no names, stats, nudges, or celebrations may cross accounts.
- JPEG/PNG/WebP, transparent image, rotated EXIF image, 5MB boundary, >25MP image, malformed/polyglot input, interrupted upload, approval, rejection, retry, and three-month cooldown.

## Observability and rollback

- Dashboard click volume, 429s, validation failures, attributed/rejected results, atomic RPC failures, unlocks, upload failures, moderation age, cleanup results, and storage growth. Alert on error-rate spikes and pending moderation older than the agreed SLA.
- Rollback server behavior first with the two environment switches. Do not roll back the additive migrations while released clients may call their RPCs. Roll back website/App Clip experience next, then the app binary if necessary.
- The privacy page and App Store privacy labels must disclose referral attribution metadata/cookie, PostHog events, private moderation, retention, and deletion behavior before review submission.
