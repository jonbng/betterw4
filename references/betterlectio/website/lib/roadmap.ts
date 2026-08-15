import "server-only"

import { unstable_cache } from "next/cache"

import { getSupabaseAdmin } from "@/lib/supabase"

// Public roadmap: planned / in_progress / completed show with real title/message.
// Pending, review, declined, and duplicate stay hidden.
export type RoadmapColumnKey = "planned" | "in_progress" | "done"
export type RoadmapCategory = "bug" | "idea" | "other"

/** DB statuses that appear on the public roadmap. */
export const ROADMAP_STATUSES = [
  "planned",
  "in_progress",
  "completed",
] as const

export type RoadmapItem = {
  id: string
  title: string
  description: string | null
  category: RoadmapCategory
  column: RoadmapColumnKey
  eta: string | null
  voteCount: number
}

export type RoadmapColumn = {
  key: RoadmapColumnKey
  label: string
  items: RoadmapItem[]
}

export const ROADMAP_CACHE_TAG = "roadmap"
const CACHE_REVALIDATE_SECONDS = 60 * 5 // 5 min; votes also bust the tag on write

const STATUS_TO_COLUMN: Record<(typeof ROADMAP_STATUSES)[number], RoadmapColumnKey> =
  {
    planned: "planned",
    in_progress: "in_progress",
    completed: "done",
  }

const COLUMN_LABELS: Record<RoadmapColumnKey, string> = {
  planned: "Planlagt",
  in_progress: "I gang",
  done: "Færdig",
}

const COLUMN_ORDER: RoadmapColumnKey[] = ["planned", "in_progress", "done"]

type RoadmapRow = {
  id: string
  status: string
  category: string
  title: string | null
  message: string
  roadmap_eta: string | null
  roadmap_sort: number | null
  roadmap_vote_count: number | null
  created_at: string | null
}

function normalizeCategory(value: string): RoadmapCategory {
  return value === "bug" || value === "idea" ? value : "other"
}

function displayTitle(row: Pick<RoadmapRow, "title" | "message">): string {
  if (row.title?.trim()) return row.title.trim()
  const first = row.message.trim().split(/\n/)[0] ?? ""
  return first.length > 80 ? `${first.slice(0, 77)}…` : first || "Untitled"
}

function displayDescription(
  row: Pick<RoadmapRow, "title" | "message">,
  title: string,
): string | null {
  const message = row.message.trim()
  if (!message) return null
  // When there's a real title, show the full message as the body.
  if (row.title?.trim()) return message
  // Title was derived from the first line — only show a body if there's more.
  if (message === title || message.startsWith(title.replace(/…$/, ""))) {
    const rest = message.includes("\n")
      ? message.split(/\n/).slice(1).join("\n").trim()
      : message.length > 80
        ? message.slice(80).trim()
        : ""
    return rest || null
  }
  return message
}

async function fetchRoadmap(): Promise<RoadmapColumn[]> {
  const empty = COLUMN_ORDER.map((key) => ({
    key,
    label: COLUMN_LABELS[key],
    items: [] as RoadmapItem[],
  }))

  try {
    const supabase = getSupabaseAdmin()
    const { data, error } = await supabase
      .from("feedback_items")
      .select(
        "id, status, category, title, message, roadmap_eta, roadmap_sort, roadmap_vote_count, created_at",
      )
      .in("status", ROADMAP_STATUSES)
    if (error) throw error

    const rows = (data ?? []) as RoadmapRow[]
    const byColumn = new Map<RoadmapColumnKey, RoadmapRow[]>()
    for (const row of rows) {
      const column =
        STATUS_TO_COLUMN[row.status as (typeof ROADMAP_STATUSES)[number]]
      if (!column) continue
      const list = byColumn.get(column) ?? []
      list.push(row)
      byColumn.set(column, list)
    }

    return COLUMN_ORDER.map((key) => {
      const rowsForColumn = (byColumn.get(key) ?? []).slice().sort(sortRows)
      return {
        key,
        label: COLUMN_LABELS[key],
        items: rowsForColumn.map((row) => {
          const title = displayTitle(row)
          return {
            id: row.id,
            title,
            description: displayDescription(row, title),
            category: normalizeCategory(row.category),
            column: key,
            eta: row.roadmap_eta?.trim() || null,
            voteCount: row.roadmap_vote_count ?? 0,
          }
        }),
      }
    })
  } catch (err) {
    console.error("[lib/roadmap] fetchRoadmap failed", err)
    return empty
  }
}

// Manual sort in JS so we can put null sort values last (Postgres nulls-first
// ordering is awkward through the JS client): sort asc, then most votes, then
// newest.
function sortRows(a: RoadmapRow, b: RoadmapRow): number {
  const sa = a.roadmap_sort
  const sb = b.roadmap_sort
  if (sa != null && sb != null && sa !== sb) return sa - sb
  if (sa != null && sb == null) return -1
  if (sa == null && sb != null) return 1
  const va = a.roadmap_vote_count ?? 0
  const vb = b.roadmap_vote_count ?? 0
  if (va !== vb) return vb - va
  const ta = a.created_at ? Date.parse(a.created_at) : 0
  const tb = b.created_at ? Date.parse(b.created_at) : 0
  return tb - ta
}

export const getRoadmap = unstable_cache(fetchRoadmap, ["bl-roadmap"], {
  revalidate: CACHE_REVALIDATE_SECONDS,
  tags: [ROADMAP_CACHE_TAG],
})

/**
 * feedback_item ids the given voter has already upvoted. Per-visitor, so this
 * is intentionally NOT cached.
 */
export async function getVotedIds(voterId: string | null): Promise<Set<string>> {
  if (!voterId) return new Set()
  try {
    const supabase = getSupabaseAdmin()
    const { data, error } = await supabase
      .from("roadmap_votes")
      .select("feedback_id")
      .eq("voter_id", voterId)
    if (error) throw error
    return new Set((data ?? []).map((r) => r.feedback_id as string))
  } catch (err) {
    console.error("[lib/roadmap] getVotedIds failed", err)
    return new Set()
  }
}
