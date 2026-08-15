import "server-only"

import { createServerClient } from "@supabase/ssr"
import { createClient, type SupabaseClient } from "@supabase/supabase-js"
import { cookies } from "next/headers"

export type LinkedStudent = {
  id: string
  schoolId: number
  firstName: string | null
  lastName: string | null
}

function requireEnv(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`Missing ${name}`)
  return value
}

/** Cookie-backed Supabase client for the signed-in website user (anon key). */
export async function createSupabaseServerClient(): Promise<SupabaseClient> {
  const url = requireEnv("SUPABASE_URL")
  const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY")
  const cookieStore = await cookies()

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll()
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options)
          }
        } catch {
          // Called from a Server Component — cookie writes are ignored.
          // middleware.ts refreshes sessions on /roadmap and /auth/*.
        }
      },
    },
  })
}

export async function getWebsiteSession() {
  try {
    const supabase = await createSupabaseServerClient()
    const { data, error } = await supabase.auth.getUser()
    if (error || !data.user) return null
    return data.user
  } catch (err) {
    console.error("[supabase-auth] getWebsiteSession failed", err)
    return null
  }
}

export async function getLinkedStudent(
  supabaseUid: string,
): Promise<LinkedStudent | null> {
  try {
    // Service role: students RLS won't allow anon to look up by supabase_id.
    const url = requireEnv("SUPABASE_URL")
    const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY")
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data, error } = await admin
      .from("students")
      .select("id, school_id, lectio_first_name, lectio_last_name")
      .eq("supabase_id", supabaseUid)
      .order("last_seen_at", { ascending: false })
      .limit(1)
      .maybeSingle()
    if (error || !data) return null
    return {
      id: data.id as string,
      schoolId: data.school_id as number,
      firstName: (data.lectio_first_name as string | null) ?? null,
      lastName: (data.lectio_last_name as string | null) ?? null,
    }
  } catch (err) {
    console.error("[supabase-auth] getLinkedStudent failed", err)
    return null
  }
}
