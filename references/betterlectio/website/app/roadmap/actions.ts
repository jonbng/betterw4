"use server"

import { randomUUID } from "node:crypto"

import { updateTag } from "next/cache"
import { cookies } from "next/headers"

import { ROADMAP_CACHE_TAG, ROADMAP_STATUSES } from "@/lib/roadmap"
import { getSupabaseAdmin } from "@/lib/supabase"

const VOTER_COOKIE = "bl_rmv"
const VOTER_COOKIE_MAX_AGE = 60 * 60 * 24 * 365 // 1 year
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// Soft anti-abuse: cap toggles per voter per hour. The unique
// (feedback_id, voter_id) constraint already prevents double-counting.
const MAX_VOTES_PER_HOUR = 60

export type VoteResult =
  | { ok: true; voted: boolean; count: number }
  | { ok: false; error: string }

/** Read the current voter cookie without mutating it (safe in RSC render). */
export async function readVoterId(): Promise<string | null> {
  const store = await cookies()
  const value = store.get(VOTER_COOKIE)?.value ?? null
  return value && UUID_RE.test(value) ? value : null
}

async function getOrCreateVoterId(): Promise<string> {
  const store = await cookies()
  const existing = store.get(VOTER_COOKIE)?.value
  if (existing && UUID_RE.test(existing)) return existing

  const id = randomUUID()
  store.set(VOTER_COOKIE, id, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: VOTER_COOKIE_MAX_AGE,
  })
  return id
}

async function currentVoteCount(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  feedbackId: string,
): Promise<number> {
  const { data } = await supabase
    .from("feedback_items")
    .select("roadmap_vote_count")
    .eq("id", feedbackId)
    .single()
  return (data?.roadmap_vote_count as number | undefined) ?? 0
}

export async function toggleVote(feedbackId: string): Promise<VoteResult> {
  if (typeof feedbackId !== "string" || !UUID_RE.test(feedbackId)) {
    return { ok: false, error: "invalid_item" }
  }

  const voterId = await getOrCreateVoterId()
  const supabase = getSupabaseAdmin()

  // Item must be on the public roadmap (planned / in_progress / completed).
  const { data: item, error: itemErr } = await supabase
    .from("feedback_items")
    .select("id, status")
    .eq("id", feedbackId)
    .single()
  if (
    itemErr ||
    !item ||
    !ROADMAP_STATUSES.includes(
      item.status as (typeof ROADMAP_STATUSES)[number],
    )
  ) {
    return { ok: false, error: "not_found" }
  }

  // Rate limit toggles per voter.
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  const { count: recent } = await supabase
    .from("roadmap_votes")
    .select("*", { count: "exact", head: true })
    .eq("voter_id", voterId)
    .gte("created_at", since)
  if ((recent ?? 0) >= MAX_VOTES_PER_HOUR) {
    return { ok: false, error: "rate_limited" }
  }

  const { data: existing } = await supabase
    .from("roadmap_votes")
    .select("id")
    .eq("feedback_id", feedbackId)
    .eq("voter_id", voterId)
    .maybeSingle()

  try {
    if (existing) {
      const { error } = await supabase
        .from("roadmap_votes")
        .delete()
        .eq("id", existing.id)
      if (error) throw error
    } else {
      const { error } = await supabase
        .from("roadmap_votes")
        .insert({ feedback_id: feedbackId, voter_id: voterId })
      // Ignore unique-violation races (already voted) as a no-op.
      if (error && error.code !== "23505") throw error
    }
  } catch (err) {
    console.error("[roadmap/actions] toggleVote failed", err)
    return { ok: false, error: "write_failed" }
  }

  updateTag(ROADMAP_CACHE_TAG)
  const count = await currentVoteCount(supabase, feedbackId)
  return { ok: true, voted: !existing, count }
}

export type SubmitIdeaResult =
  | { ok: true }
  | { ok: false; error: string }

export async function submitRoadmapIdea(input: {
  message: string
  title?: string
}): Promise<SubmitIdeaResult> {
  const message = input.message?.trim() ?? ""
  if (!message) return { ok: false, error: "empty" }
  if (message.length > 4000) return { ok: false, error: "too_long" }

  const title = input.title?.trim().slice(0, 200) || null

  try {
    const {
      createSupabaseServerClient,
      getLinkedStudent,
    } = await import("@/lib/supabase-auth")
    const supabase = await createSupabaseServerClient()
    const { data: userData, error: userErr } = await supabase.auth.getUser()
    if (userErr || !userData.user) {
      return { ok: false, error: "not_signed_in" }
    }

    const student = await getLinkedStudent(userData.user.id)
    if (!student) return { ok: false, error: "no_student" }

    const { error } = await supabase.rpc("submit_feedback", {
      p_student_id: student.id,
      p_school_id: student.schoolId,
      p_category: "idea",
      p_message: message,
      p_platform: "web",
      p_context: {
        title,
        locale: "da",
        app_version: "website",
      },
    })

    if (error) {
      console.error("[roadmap/actions] submitRoadmapIdea", error.message)
      if (/rate limit/i.test(error.message)) {
        return { ok: false, error: "rate_limited" }
      }
      return { ok: false, error: "submit_failed" }
    }

    return { ok: true }
  } catch (err) {
    console.error("[roadmap/actions] submitRoadmapIdea failed", err)
    return { ok: false, error: "submit_failed" }
  }
}

export async function signOutWebsite(): Promise<void> {
  try {
    const { createSupabaseServerClient } = await import("@/lib/supabase-auth")
    const supabase = await createSupabaseServerClient()
    await supabase.auth.signOut()
  } catch (err) {
    console.error("[roadmap/actions] signOutWebsite failed", err)
  }
}
