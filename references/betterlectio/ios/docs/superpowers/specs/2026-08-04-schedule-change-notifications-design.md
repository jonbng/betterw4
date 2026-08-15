# Schedule Change Notifications — Design

**Date:** 2026-08-04
**Status:** Approved, ready for implementation planning

## Goal

Push-notify students when a lesson is cancelled, moved, or changed (room, teacher),
without requiring the app to be open and without any single student's Lectio account
being polled excessively.

## Background — what already exists

- The app scrapes Lectio on-device (`LectioHTTPClient+Schedule`, `ScheduleParser`).
- `EventStatus` already models `normal / cancelled / moved / changed`.
- Every synced week is already mirrored to Supabase by `SupabaseScheduleService`:
  a `lessons` table keyed by `lesson_key`, a student↔lesson link table, and `week_sync`.
- `lesson_key` prefers Lectio's `data-brikid`, which is the **class-block id** — the same
  value for every student in that class. This is what makes shared/crowdsourced freshness
  work: one student's fetch freshens the row their whole class reads.
- `BGTaskScheduler` and `UNUserNotificationCenter` are wired for Live Activities only.
  There is no APNs device-token registration today.

## Credential model

There are no passwords to store. Login is MitID in a `WKWebView`; the app persists two
cookies — `ASP.NET_SessionId` (short-lived) and `autologinkeyV2` (long-lived auto-login
token). A MitID login cannot be replayed server-side.

Server-side polling therefore means: **the app uploads `autologinkeyV2` to Supabase, and a
cron worker replays it to mint a session and fetch the schedule.**

Properties: the token is revocable (logging out of Lectio kills it), scoped to Lectio only,
and never exposes MitID. It is still a bearer credential granting full read access to that
student's account, so:

- Envelope-encrypt at rest.
- RLS such that the anon key can only insert/replace its own row and can never read any row.
  Only the service role (cron worker) reads.
- Upload is explicit opt-in, tied to enabling notifications, with plain-language wording.
  Revoking deletes the row.

## Polling strategy

Scope is deliberately tight — Lectio is a small vendor and we would be hitting it from a few
datacenter IPs on behalf of every user.

**Objective:** every current-week, future lesson has `last_verified_at` within 15 minutes.

The unit of *staleness* is a lesson; the unit of *fetch* is a (student, week). One Lectio
request returns that student's whole week (~30 lessons), so the scheduler is a greedy
set-cover: pick the stalest lesson, cover it with its least-recently-used eligible student,
and ~30 lessons go fresh in one request.

### Worker loop

Runs every 5 minutes (`pg_cron` → Edge Function), during school hours on school days:

1. Find the most-stale lesson where `last_verified_at < now() - 15 min`, restricted to the
   current week and future lessons.
2. Pick the eligible linked student with the oldest `last_used_at`. **Eligible** = token not
   disabled AND `last_used_at < now() - 15 min`.
3. Fetch that student's current week, validate, upsert, bump `last_used_at` and every touched
   lesson's `last_verified_at`.
4. Repeat up to a per-tick budget (~50 fetches), then stop.

If no student is eligible, the lesson stays stale. No fallback, no forcing — the client's own
sync covers it when someone opens the app.

### Why the cooldown floor is not optional

LRU ordering alone does not protect a student who is the *only* linked student on a lesson —
they would be nominated every single cycle. The hard `last_used_at < now() - 15 min` floor is
what bounds per-student load. A per-day cap per student is a further backstop.

### Failure handling

- On fetch failure, **still bump `last_used_at`**. Otherwise a student with a dead token stays
  permanently at the front of the LRU queue and starves everyone behind them.
- Track `consecutive_failures`; after ~3, set `disabled_at` and flag the app to re-upload a
  fresh token on next foreground. Back off exponentially.

## Diffing — one path for both writers

The diff lives in a **Postgres `BEFORE UPDATE` trigger on `lessons`**, not in the worker.

It compares `OLD` to `NEW` and, if a notify-worthy field changed, inserts one
`notification_outbox` row per linked student. Whoever wrote the row — cron worker or a
student's iPhone syncing in the foreground — is irrelevant. Both paths get notifications with
zero duplicated logic, and a student who pulls a change in the app automatically becomes the
source of the push to their classmates.

### Notify-worthy changes

| Change | Notification |
|---|---|
| `status` → `cancelled` | "Matematik 10:00 er aflyst" |
| `lesson_date` / `start_time` / `end_time` changed | "Matematik er flyttet til 12:00" |
| `room` changed | "Matematik er flyttet til lokale 24" |
| `teacher` changed | "Matematik: vikar — NN" |
| `notes` set/changed | opt-in only, off by default |
| `homework` changed | no notification (too noisy) |

### Suppressions (in the trigger, not the client)

- **Past lessons never notify.**
- **First link never notifies** — when a student links to a lesson for the first time every
  field is "new". Gate on the *link row's* age, not the lesson's.
- **Collapse rapid churn** — outbox idempotency key is
  `(student, lesson_key, new_state_hash)`; the sender holds a row ~2 minutes so a second write
  to the same lesson replaces rather than duplicates.

### Sender

A separate function drains the outbox every minute, signs an APNs JWT with a p8 key, posts to
Apple.

**Quiet hours:** if outside ~07:00–21:00 *and* the affected lesson is more than 12 hours away,
hold until morning. A same-day 07:15 cancellation always sends immediately.

## Safety — cancellation must never be inferred from absence

`markMissingLessonsAsCancelled` currently infers cancellation from absence: any lesson
previously known for a student-week that is missing from the latest fetch is set to
`cancelled`. Today this only writes a wrong row nobody sees. Once the diff trigger exists, that
same path becomes "push to every linked student saying their lesson is cancelled."

Absence is a bad cancellation signal: an empty parse is indistinguishable from a week where
everything was cancelled. A Lectio HTML change breaking `ScheduleParser`, a session silently
redirecting to a login page with a 200, a truncated response, or a holiday week all produce
empty parses — now on a cron, across many students, simultaneously. Worst case: a parser
regression ships, the worker fetches hundreds of weeks, every lesson goes `cancelled`, and tens
of thousands of false "AFLYST" pushes land before anyone notices. Pushes cannot be rolled back.

Three required mitigations:

1. **Never infer cancellation from absence.** Lectio marks cancellations explicitly and
   `ScheduleParser` already reads "Aflyst!" into `EventStatus.cancelled`; cancelled lessons stay
   visible with a strikethrough rather than vanishing. Only the explicit status may produce a
   cancellation notification. Absence may still update the stored row, but as a distinct
   **low-confidence "missing" state that the trigger ignores.**
2. **Validate every fetch before it may write.** Require: student identity in the HTML matches
   the student fetched for, no login form present, plausible parse shape. A fetch that fails
   validation bumps `last_used_at` and `consecutive_failures` and writes nothing.
3. **Circuit breaker on the outbox.** Before draining, check volume — if pending notifications
   exceed a threshold in a window (e.g. >200 in 5 min, or >30% of a school's lessons flipping to
   cancelled at once), halt sending and alert. Real cancellations are bursty but bounded; a
   parser regression is not.

Principle: notifications are irreversible side effects, so every inference feeding them must
fail closed — silence on uncertainty, never a confident wrong push.

## Data model additions

- `lessons.last_verified_at` — bumped on *every* write, client or server. Staleness clock,
  distinct from `updated_at` which means "content actually changed".
- `lessons.presence_state` — `present` / `missing` (low-confidence). Trigger ignores `missing`.
- `lectio_tokens` — one row per student: encrypted `autologinkeyV2`, `last_used_at`,
  `consecutive_failures`, `disabled_at`.
- `device_tokens` — APNs token per device per student.
- `notification_outbox` — pending pushes with idempotency key, scheduled-send time, state.

## Client changes

**New:**
- APNs registration (`registerForRemoteNotifications`), upload token to `device_tokens`.
- Upload encrypted `autologinkeyV2` to `lectio_tokens` after login and on rotation.
- Re-upload on foreground when the server has flagged the token disabled.
- Notification settings: master toggle plus per-type switches (cancellations only is a
  legitimate preference).
- Deep-link from a push tap to that lesson in `ScheduleView`.
- Explicit opt-in consent flow for token upload, with working revoke.

**Changed:**
- `SupabaseScheduleService` drops `markMissingLessonsAsCancelled` in favour of writing
  `presence_state = missing`.
- `SupabaseScheduleService` bumps `last_verified_at` on sync.

## Testing

The risk concentrates server-side in pure functions, which is convenient.

- **Diff trigger** — table-driven over old/new row pairs, covering every suppression (past
  lessons, first link, churn collapse). Plain SQL fixtures; no Lectio, no APNs.
- **Scheduler** — seed lessons/students/tokens; assert the LRU pick, the cooldown floor, that a
  failed fetch still bumps `last_used_at`, and that a single-student lesson is not hammered.
- **Fetch validation** — fixture HTML for the login-redirect page, a truncated response, a
  holiday week, and a real week. Assert only the last one writes.
- **Circuit breaker** — synthesize a mass cancellation, assert the sender halts.
- **Parser** — snapshot real Lectio HTML into fixtures now, so a future markup change fails a
  test rather than a lock screen.

## Explicitly out of scope

- Homework/assignment change notifications.
- Notifications for weeks other than the current one (client sync still covers them; the diff
  trigger will notify if a client happens to pull a future-week change).
- Android / web-extension notification delivery.
