// Server-side Lectio schedule parser.
//
// SCOPE: only the fields a notification can be about — identity, date, times,
// status, room, teacher, title. Deliberately NOT a port of the whole of
// BetterLectio/ScheduleParser.swift: homework, notes, presentation blocks and
// LessonContent trees are irrelevant here, and every field this parser does not
// read is a field it cannot get wrong.
//
// COMPATIBILITY IS THE WHOLE GAME
// -------------------------------
// The phone and this worker write to the SAME public.lessons rows, keyed by
// lesson_key. If `resolvedEventId` here diverges from Swift's by so much as a
// prefix, the two writers create two different rows for the same real lesson,
// students link to whichever one their client produced, and notifications go
// silently missing — no error, no log, just students not being told their
// lesson was cancelled.
//
// So `resolvedEventId` and `contentBasedId` below mirror
// ScheduleParser.swift:150-177 exactly, including the "ABS"/"AFT"/"AD" prefixes
// and the 16-byte SHA-256 truncation. Change them only in lockstep with Swift.

import { DOMParser, type Element } from "jsr:@b-fuze/deno-dom@0.1.48"

export type LessonStatus = "normal" | "cancelled" | "changed"

export interface ParsedLesson {
  /** Mirrors ScheduleEvent.id — becomes lesson_key. */
  id: string
  title: string
  /** ISO yyyy-mm-dd, from the day column's data-date attribute. */
  date: string
  /** "HH:mm", or "" for all-day events. */
  startTime: string
  endTime: string
  teacher: string | null
  room: string | null
  status: LessonStatus
  isAllDay: boolean
}

// ── identity (must mirror Swift exactly) ────────────────────────────

export function resolvedEventId(brikId: string, href: string): string | null {
  if (brikId !== "") return brikId

  const abs = href.match(/absid=(\d+)/)
  if (abs && abs[1]) return `ABS${abs[1]}`

  const aftale = href.match(/aftaleid=(\d+)/)
  if (aftale && aftale[1]) return `AFT${aftale[1]}`

  return null
}

/**
 * Stable id for all-day chips, which often carry no data-brikid or href.
 * Swift: "AD" + first 16 BYTES of SHA-256("yyyy-MM-dd|tooltip") as hex (32 chars).
 */
export async function contentBasedId(date: string, tooltip: string): Promise<string> {
  const data = new TextEncoder().encode(`${date}|${tooltip}`)
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", data))
  const hex = Array.from(digest.slice(0, 16))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
  return `AD${hex}`
}

// ── tooltip ─────────────────────────────────────────────────────────

interface TooltipFields {
  title: string
  timeInfo: string
  teacher: string | null
  room: string | null
  isAllDay: boolean
}

/** Mirrors ScheduleParser.parseTooltip, minus the note/homework sections. */
export function parseTooltip(tooltip: string): TooltipFields {
  const lines = tooltip.split(/\r?\n/).map((l) => l.trim())

  let title: string | null = null
  let holdName: string | null = null
  let timeInfo = ""
  let teacher: string | null = null
  let room: string | null = null
  let isAllDay = false
  // Once Lectio starts a Note:/Lektier: section, following lines are section
  // body — never a title. We don't capture the bodies, but we must still track
  // that we're inside one or a note's first line could be mistaken for a title.
  let inSection = false

  for (const line of lines) {
    if (line === "") continue

    if (line === "Ændret!" || line === "Aflyst!") continue

    if (line.includes("Hele dagen")) {
      isAllDay = true
      continue
    }

    if (timeInfo === "" && /\d{2}:\d{2}\s+(til|-)\s+\d{2}:\d{2}/.test(line)) {
      timeInfo = line
      continue
    }

    if (line.startsWith("Hold:")) {
      holdName = line.slice("Hold:".length).trim()
      continue
    }

    // Order matters: "Lærere:" does not contain the substring "Lærer:" (the
    // character after "Lærer" is "e", not ":"), so stripping both is safe.
    if (line.startsWith("Lærer:") || line.startsWith("Lærere:")) {
      teacher = line.replace("Lærere:", "").replace("Lærer:", "").trim()
      continue
    }

    if (line.startsWith("Lokale:") || line.startsWith("Lokaler:")) {
      room = line.replace("Lokaler:", "").replace("Lokale:", "").trim()
      continue
    }

    if (line.startsWith("Note:") || line.startsWith("Lektier:") || line.startsWith("Øvrigt indhold:")) {
      inSection = true
      continue
    }

    // Title candidate: Swift rejects anything containing "/" or ":" so dates and
    // key:value metadata can never become a title.
    if (title === null && !inSection && !line.includes("/") && !line.includes(":")) {
      title = line
    }
  }

  // Hold names beginning with a digit ("1x Fy") are real subjects and preferred.
  // Generic groups ("Alle 1. G. elever") are not, so fall back to the title.
  const firstChar = holdName?.charAt(0) ?? ""
  const finalTitle = /\d/.test(firstChar)
    ? (holdName as string)
    : (title ?? holdName ?? "Ukendt")

  return { title: finalTitle, timeInfo, teacher, room, isAllDay }
}

/** Mirrors ScheduleParser.extractTimes. */
export function extractTimes(timeInfo: string): { start: string; end: string } {
  const til = timeInfo.match(/(\d{2}:\d{2})\s+til\s+(\d{2}:\d{2})/)
  if (til) return { start: til[1], end: til[2] }

  const dash = timeInfo.match(/(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})/)
  if (dash) return { start: dash[1], end: dash[2] }

  return { start: "", end: "" }
}

// ── bricks ──────────────────────────────────────────────────────────

function statusFromClasses(brick: Element): LessonStatus {
  // Lectio signals these with CSS classes, NOT with the "Aflyst!"/"Ændret!"
  // tooltip lines (which parseTooltip skips). ScheduleParser.swift does the
  // same; keep them in agreement.
  const cls = brick.getAttribute("class") ?? ""
  if (/\bs2cancelled\b/.test(cls)) return "cancelled"
  if (/\bs2changed\b/.test(cls)) return "changed"
  return "normal"
}

async function parseBrick(brick: Element, date: string): Promise<ParsedLesson | null> {
  const tooltip = brick.getAttribute("data-tooltip") ?? ""
  const brikId = brick.getAttribute("data-brikid") ?? ""
  const href = brick.getAttribute("href") ?? ""

  const fields = parseTooltip(tooltip)
  const { start, end } = fields.isAllDay
    ? { start: "", end: "" }
    : extractTimes(fields.timeInfo)

  const id = resolvedEventId(brikId, href) ?? (await contentBasedId(date, tooltip))

  return {
    id,
    title: fields.title,
    date,
    startTime: start,
    endTime: end,
    teacher: fields.teacher,
    room: fields.room,
    status: statusFromClasses(brick),
    isAllDay: fields.isAllDay,
  }
}

/**
 * Parses a full week from a SkemaNy.aspx document.
 *
 * Returns [] when the schedule table is absent — but callers must NOT treat []
 * as "this week is empty". Run validateSchedulePage() first and
 * validateParseResult() after; an empty parse is far more likely to mean a
 * markup change or a login redirect than a week with no lessons.
 */
export async function parseWeekSchedule(html: string): Promise<ParsedLesson[]> {
  const doc = new DOMParser().parseFromString(html, "text/html")
  if (!doc) return []

  const table = doc.querySelector("table.s2skema")
  if (!table) return []

  const lessons: ParsedLesson[] = []

  for (const dayColumn of table.querySelectorAll("td[data-date]")) {
    const el = dayColumn as unknown as Element
    const date = el.getAttribute("data-date") ?? ""
    if (!date) continue

    for (const node of el.querySelectorAll("a.s2skemabrik.s2brik")) {
      const parsed = await parseBrick(node as unknown as Element, date)
      if (parsed) lessons.push(parsed)
    }
  }

  return lessons
}
