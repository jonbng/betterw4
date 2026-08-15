// Run: deno test supabase/functions/_shared/validate.test.ts
//
// These tests exist to prove the poller stays SILENT on bad input. Every case
// below is a way a fetch can look successful while carrying no usable schedule.
// If any of these start passing validation, the poller will write an empty week
// and the change trigger will push false cancellations to real students.

import { assertEquals } from "jsr:@std/assert@1"
import { validateParseResult, validateSchedulePage } from "./validate.ts"

const ELEV = "12345678901"

// Minimal stand-in for a real authenticated schedule page: long enough to clear
// the size floor, carries the identity marker and a schedule grid marker.
function realSchedulePage(elevId = ELEV): string {
  return `<!DOCTYPE html><html><body>
    <div data-lectioContextCard="S${elevId}"></div>
    <div class="s2skemabrik s2brik">Matematik</div>
    ${"<!-- filler -->".repeat(500)}
  </body></html>`
}

Deno.test("accepts a real schedule page for the expected student", () => {
  const result = validateSchedulePage(realSchedulePage(), ELEV)
  assertEquals(result.ok, true)
})

Deno.test("rejects an empty body", () => {
  const result = validateSchedulePage("", ELEV)
  assertEquals(result.ok, false)
  if (!result.ok) assertEquals(result.reason, "empty-body")
})

Deno.test("rejects a truncated response", () => {
  // A transfer that died early: valid markup, far too short to be a week.
  const result = validateSchedulePage(
    `<html><body><div data-lectioContextCard="S${ELEV}"></div>`,
    ELEV,
  )
  assertEquals(result.ok, false)
  if (!result.ok) assertEquals(result.reason, "too-short")
})

Deno.test("rejects a login page served with 200", () => {
  // The most dangerous case: a stale token yields a perfectly valid page that
  // parses to zero lessons.
  const loginPage = `<!DOCTYPE html><html><body>
    <form><input name="m$Content$username"><input id="m_Content_password"></form>
    ${"<!-- filler -->".repeat(500)}
  </body></html>`
  const result = validateSchedulePage(loginPage, ELEV)
  assertEquals(result.ok, false)
  if (!result.ok) assertEquals(result.reason, "login-page")
})

Deno.test("rejects another student's schedule", () => {
  const result = validateSchedulePage(realSchedulePage("99999999999"), ELEV)
  assertEquals(result.ok, false)
  if (!result.ok) assertEquals(result.reason, "wrong-student")
})

Deno.test("rejects a page whose schedule grid markers are gone", () => {
  // Stands in for a Lectio markup change: authenticated, correct student, but
  // the parser would find nothing.
  const changed = `<!DOCTYPE html><html><body>
    <div data-lectioContextCard="S${ELEV}"></div>
    <div class="brand-new-markup">Matematik</div>
    ${"<!-- filler -->".repeat(500)}
  </body></html>`
  const result = validateSchedulePage(changed, ELEV)
  assertEquals(result.ok, false)
  if (!result.ok) assertEquals(result.reason, "not-a-schedule-page")
})

Deno.test("treats a collapse to zero lessons as a parse failure", () => {
  const result = validateParseResult(0, 28)
  assertEquals(result.ok, false)
})

Deno.test("allows a genuinely empty week when none were known before", () => {
  // Holiday weeks are real. Only the transition from "had lessons" to "parsed
  // none" is suspicious.
  assertEquals(validateParseResult(0, 0).ok, true)
})

Deno.test("allows a normal week", () => {
  assertEquals(validateParseResult(28, 28).ok, true)
})
