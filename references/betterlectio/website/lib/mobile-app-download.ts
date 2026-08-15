import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { detectPlatformFromUserAgent } from "@/lib/platform"

const STUDENT_ID_RE = /^[0-9A-Za-z_-]{1,48}$/

export function isValidStudentId(value: string | null | undefined): value is string {
  return typeof value === "string" && STUDENT_ID_RE.test(value.trim())
}

/** Store destination for a QR request; desktop/unknown devices use the chooser. */
export function mobileAppTargetForUserAgent(userAgent: string): string {
  const platform = detectPlatformFromUserAgent(userAgent)
  if (platform === "ios") return DOWNLOAD_LINKS.ios
  if (platform === "android") return DOWNLOAD_LINKS.android
  return "/download"
}
