import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { detectPlatformFromUserAgent } from "@/lib/platform"

/**
 * Store destination for a QR request. Phones are sent straight to their store;
 * desktop/unknown devices land on the platform chooser.
 */
export function mobileAppTargetForUserAgent(userAgent: string): string {
  const platform = detectPlatformFromUserAgent(userAgent)
  if (platform === "ios") return DOWNLOAD_LINKS.ios
  if (platform === "android") return DOWNLOAD_LINKS.android
  return "/download"
}
