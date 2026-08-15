import type { NextRequest } from "next/server"

import { handleMobileAppDownload } from "@/lib/mobile-app-download-server"

export async function GET(req: NextRequest) {
  return handleMobileAppDownload(req)
}
