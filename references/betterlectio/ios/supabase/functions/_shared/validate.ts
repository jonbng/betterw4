// Gate between "we fetched something from Lectio" and "we may write it".
//
// WHY THIS EXISTS
// ---------------
// The notification trigger turns writes to public.lessons into push
// notifications, and a push cannot be recalled. The dangerous failure is not a
// fetch that errors — that is loud and handled. It is a fetch that SUCCEEDS
// with the wrong body: a 200 carrying a login form, a truncated response, the
// wrong student's schedule, or a page whose markup changed so the parser
// returns nothing. Each of those is indistinguishable from "this student's week
// is now empty", and empty weeks are how you mass-cancel a school.
//
// So validation fails CLOSED. Anything that is not positively recognisable as
// this student's schedule page is rejected, and rejection means the poller
// bumps last_used_at and failure counters but writes NOTHING.

export type RejectReason =
  | "empty-body"
  | "too-short"
  | "login-page"
  | "error-page"
  | "wrong-student"
  | "not-a-schedule-page"

export interface ValidationOk {
  ok: true
  elevId: string
}

export interface ValidationRejected {
  ok: false
  reason: RejectReason
  detail: string
}

export type ValidationResult = ValidationOk | ValidationRejected

// A real authenticated Lectio schedule page is tens of kilobytes. Anything this
// small is a stub, an error, or a truncated transfer — never a week of lessons.
const MIN_PLAUSIBLE_LENGTH = 4000

function reject(reason: RejectReason, detail: string): ValidationRejected {
  return { ok: false, reason, detail }
}

/**
 * Decides whether `html` is genuinely `expectedElevId`'s schedule page.
 *
 * Order matters: cheap structural checks first, identity last, so the returned
 * reason is the most specific true statement about what went wrong.
 */
export function validateSchedulePage(
  html: string,
  expectedElevId: string,
): ValidationResult {
  if (!html || html.trim().length === 0) {
    return reject("empty-body", "response body was empty")
  }

  if (html.length < MIN_PLAUSIBLE_LENGTH) {
    return reject(
      "too-short",
      `body was ${html.length} bytes, below the ${MIN_PLAUSIBLE_LENGTH} byte floor`,
    )
  }

  // A login page returns 200 with a perfectly valid-looking body. This is the
  // single most likely way a stale token produces "an empty week".
  if (
    /name="m\$Content\$username"/i.test(html) ||
    /id="m_Content_password"/i.test(html) ||
    /Loginv[æa]lger/i.test(html) ||
    /unilogin/i.test(html)
  ) {
    return reject("login-page", "body contains login form markers")
  }

  if (/Der er opstået en fejl/i.test(html) || /Fejl \d{3}/i.test(html)) {
    return reject("error-page", "body contains a Lectio error page marker")
  }

  // Identity check. Lectio will happily serve a different student's schedule if
  // the elevid parameter and the session disagree; writing that under the wrong
  // student would notify the wrong people about lessons they do not attend.
  const contextCard = html.match(/data-lectioContextCard="S(\d+)"/i)
  if (!contextCard) {
    return reject(
      "not-a-schedule-page",
      "no data-lectioContextCard marker found; page is not an authenticated schedule",
    )
  }
  if (contextCard[1] !== expectedElevId) {
    return reject(
      "wrong-student",
      `page belongs to elevid ${contextCard[1]}, expected ${expectedElevId}`,
    )
  }

  // Structural marker of the schedule grid itself. Its absence means either a
  // different page, or that Lectio changed its markup — in which case the
  // parser is about to return nothing and we must not act on that.
  if (!/s2skemabrik|s2dayHeader|SkemaNyMedNavigation/i.test(html)) {
    return reject(
      "not-a-schedule-page",
      "no schedule grid markers found; Lectio markup may have changed",
    )
  }

  return { ok: true, elevId: contextCard[1] }
}

/**
 * Second gate, applied after parsing.
 *
 * A page can validate structurally and still parse to nothing if Lectio changed
 * the brick markup. `previousLessonCount` is how many lessons we already
 * believe exist for this student-week; a collapse to zero against a non-zero
 * prior is treated as a parser failure, not as a week of cancellations.
 *
 * Genuinely empty weeks exist (holidays), which is why this only rejects the
 * transition from "we had lessons" to "we parsed none" rather than rejecting
 * empty results outright.
 */
export function validateParseResult(
  parsedLessonCount: number,
  previousLessonCount: number,
): ValidationResult {
  if (parsedLessonCount === 0 && previousLessonCount > 0) {
    return reject(
      "not-a-schedule-page",
      `parsed 0 lessons for a week that previously had ${previousLessonCount}; ` +
        "treating as a parse failure rather than a mass cancellation",
    )
  }
  return { ok: true, elevId: "" }
}
