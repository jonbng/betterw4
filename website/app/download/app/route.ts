import { NextResponse, type NextRequest } from "next/server"

import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { mobileAppTargetForUserAgent } from "@/lib/mobile-app-download"

export async function GET(req: NextRequest) {
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
