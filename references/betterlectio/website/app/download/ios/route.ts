import { NextResponse, type NextRequest } from "next/server"

import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { handleMobileAppDownload } from "@/lib/mobile-app-download-server"

export async function GET(req: NextRequest) {
  // Older extension versions encoded /download/ios?u=... in their QR codes.
  // Keep those codes useful for Android users by handing them to the neutral
  // store selector. Plain website iOS links remain explicitly App Store-only.
  if (req.nextUrl.searchParams.has("u")) {
    return handleMobileAppDownload(req)
  }

  return NextResponse.redirect(DOWNLOAD_LINKS.ios, 307)
}
