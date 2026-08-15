import "server-only"

import { NextResponse, type NextRequest } from "next/server"

import {
  isValidStudentId,
  mobileAppTargetForUserAgent,
} from "@/lib/mobile-app-download"
import { getSupabaseAdmin } from "@/lib/supabase"

async function stampFirstQrScan(studentId: string | null): Promise<void> {
  if (!isValidStudentId(studentId)) return

  try {
    const { error } = await getSupabaseAdmin()
      .from("students")
      .update({ app_qr_scanned_at: new Date().toISOString() })
      .eq("id", studentId.trim())
      .is("app_qr_scanned_at", null)

    if (error) throw error
  } catch (error) {
    // Downloading must never depend on analytics availability.
    console.error("[download/app] failed to stamp QR scan", error)
  }
}

export async function handleMobileAppDownload(req: NextRequest): Promise<NextResponse> {
  await stampFirstQrScan(req.nextUrl.searchParams.get("u"))

  const destination = mobileAppTargetForUserAgent(
    req.headers.get("user-agent") ?? "",
  )
  const response = NextResponse.redirect(
    new URL(destination, req.nextUrl.origin),
    307,
  )
  response.headers.set("Cache-Control", "private, no-store")
  response.headers.set("X-Robots-Tag", "noindex, nofollow")
  return response
}
