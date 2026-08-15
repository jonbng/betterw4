// Run: deno test --allow-net supabase/functions/_shared/schedule-parser.test.ts
//
// The id-fallback chain gets the most coverage here, because it is the one
// thing that fails SILENTLY. A wrong title shows up as a wrong title. A wrong
// lesson_key creates a duplicate row that nobody notices until a student is not
// told their lesson was cancelled.

import { assertEquals } from "jsr:@std/assert@1"
import {
  contentBasedId,
  extractTimes,
  parseTooltip,
  parseWeekSchedule,
  resolvedEventId,
} from "./schedule-parser.ts"

// ── identity: must mirror ScheduleParser.swift exactly ──────────────

Deno.test("prefers data-brikid verbatim, with no prefix", () => {
  assertEquals(resolvedEventId("12345678", "/lectio/94/aktivitet.aspx?absid=999"), "12345678")
})

Deno.test("falls back to ABS-prefixed absid", () => {
  assertEquals(resolvedEventId("", "/lectio/94/aktivitetforside2.aspx?absid=77216"), "ABS77216")
})

Deno.test("falls back to AFT-prefixed aftaleid for private appointments", () => {
  assertEquals(resolvedEventId("", "/lectio/94/privat_aftale.aspx?aftaleid=5512"), "AFT5512")
})

Deno.test("absid wins over aftaleid when both appear", () => {
  assertEquals(resolvedEventId("", "/x?absid=1&aftaleid=2"), "ABS1")
})

Deno.test("returns null when no identifier is available", () => {
  assertEquals(resolvedEventId("", "/lectio/94/forside.aspx"), null)
})

Deno.test("content id is AD + 32 hex chars and is stable", async () => {
  const a = await contentBasedId("2026-08-10", "Hele dagen\nStudietur")
  const b = await contentBasedId("2026-08-10", "Hele dagen\nStudietur")
  assertEquals(a, b)
  assertEquals(a.startsWith("AD"), true)
  assertEquals(a.length, 34) // "AD" + 16 bytes as hex
})

Deno.test("content id differs when the date differs", async () => {
  const a = await contentBasedId("2026-08-10", "Studietur")
  const b = await contentBasedId("2026-08-11", "Studietur")
  assertEquals(a === b, false)
})

// ── tooltip ─────────────────────────────────────────────────────────

Deno.test("extracts teacher and room from a normal tooltip", () => {
  const f = parseTooltip(
    "10/8-2026 09:00 til 09:50\nHold: 1x Ma\nLærer: Anders Berg (AB)\nLokale: 24",
  )
  assertEquals(f.teacher, "Anders Berg (AB)")
  assertEquals(f.room, "24")
  assertEquals(f.title, "1x Ma")
})

Deno.test("handles the plural Lærere:/Lokaler: forms", () => {
  // "Lærere:" does not contain the substring "Lærer:", so stripping both in
  // sequence must not mangle it into "e:".
  const f = parseTooltip("09:00 til 09:50\nLærere: AB, CD\nLokaler: 24, 25")
  assertEquals(f.teacher, "AB, CD")
  assertEquals(f.room, "24, 25")
})

Deno.test("skips the Aflyst!/Ændret! status lines", () => {
  // Status comes from CSS classes; these lines must never become the title.
  const f = parseTooltip("Aflyst!\n09:00 til 09:50\nHold: 1x Ma")
  assertEquals(f.title, "1x Ma")
})

Deno.test("prefers a digit-leading hold name as the title", () => {
  const f = parseTooltip("Fysik forsøg\n09:00 til 09:50\nHold: 1x Fy")
  assertEquals(f.title, "1x Fy")
})

Deno.test("falls back to the activity title for generic group names", () => {
  const f = parseTooltip("Fællesmøde\n09:00 til 09:50\nHold: Alle 1. G. elever")
  assertEquals(f.title, "Fællesmøde")
})

Deno.test("never lets a Note: body become the title", () => {
  const f = parseTooltip("09:00 til 09:50\nHold: Alle 1. G. elever\nNote:\nHusk bog")
  assertEquals(f.title, "Alle 1. G. elever")
})

Deno.test("detects all-day events anywhere in the tooltip", () => {
  const f = parseTooltip("Studietur\nHele dagen")
  assertEquals(f.isAllDay, true)
})

Deno.test("extractTimes handles both til and dash forms", () => {
  assertEquals(extractTimes("10/8-2026 09:00 til 09:50"), { start: "09:00", end: "09:50" })
  assertEquals(extractTimes("09:00-09:50"), { start: "09:00", end: "09:50" })
  assertEquals(extractTimes("Hele dagen"), { start: "", end: "" })
})

// ── document level ──────────────────────────────────────────────────

const WEEK_HTML = `<html><body>
<table class="s2skema">
  <tr>
    <td data-date="2026-08-10">
      <a class="s2skemabrik s2bgbox s2brik" data-brikid="111"
         data-tooltip="10/8-2026 09:00 til 09:50&#10;Hold: 1x Ma&#10;Lærer: AB&#10;Lokale: 24"></a>
      <a class="s2skemabrik s2bgbox s2brik s2cancelled" data-brikid="222"
         data-tooltip="Aflyst!&#10;10/8-2026 10:00 til 10:50&#10;Hold: 1x En&#10;Lokale: 12"></a>
    </td>
    <td data-date="2026-08-11">
      <a class="s2skemabrik s2bgbox s2brik s2changed" data-brikid="333"
         data-tooltip="11/8-2026 08:00 til 08:50&#10;Hold: 1x Fy&#10;Lokale: Lab"></a>
    </td>
  </tr>
</table>
</body></html>`

Deno.test("parses every brick across every day column", async () => {
  const lessons = await parseWeekSchedule(WEEK_HTML)
  assertEquals(lessons.length, 3)
  assertEquals(lessons.map((l) => l.id), ["111", "222", "333"])
})

Deno.test("maps CSS classes to status, not tooltip text", async () => {
  const lessons = await parseWeekSchedule(WEEK_HTML)
  assertEquals(lessons[0].status, "normal")
  assertEquals(lessons[1].status, "cancelled")
  assertEquals(lessons[2].status, "changed")
})

Deno.test("attaches the day column's date to each lesson", async () => {
  const lessons = await parseWeekSchedule(WEEK_HTML)
  assertEquals(lessons[0].date, "2026-08-10")
  assertEquals(lessons[2].date, "2026-08-11")
})

Deno.test("never emits status 'moved' — a move is inferred by the DB trigger", async () => {
  // ScheduleParser.swift only ever produces normal/cancelled/changed. A move is
  // detected by comparing times across syncs, which happens in the trigger.
  const lessons = await parseWeekSchedule(WEEK_HTML)
  assertEquals(lessons.some((l) => (l.status as string) === "moved"), false)
})

Deno.test("returns empty for a document with no schedule table", async () => {
  // Callers must gate on validateSchedulePage/validateParseResult — [] here is
  // not evidence that the week is empty.
  assertEquals((await parseWeekSchedule("<html><body>nope</body></html>")).length, 0)
})
