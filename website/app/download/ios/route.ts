import { NextResponse } from "next/server"

import { DOWNLOAD_LINKS } from "@/lib/download-links"

export async function GET() {
  return NextResponse.redirect(DOWNLOAD_LINKS.ios, 307)
}
