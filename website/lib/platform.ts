import { DOWNLOAD_LINKS } from "@/lib/download-links"

/** A concrete platform we can detect from the user agent. */
export type DetectedPlatform =
  | "chrome"
  | "firefox"
  | "edge"
  | "ios"
  | "android"
  | "safari"
  | "unknown"

/** Whether the visitor is most likely on a phone or a computer. */
export type DeviceKind = "mobile" | "desktop" | "unknown"

/** Best-effort platform detection from explicit browser signals. */
export function detectPlatformFromSignals(
  ua: string,
  platform = "",
  maxTouchPoints = 0,
): DetectedPlatform {
  const isIOS =
    /iPad|iPhone|iPod/.test(ua) || (platform === "MacIntel" && maxTouchPoints > 1)
  if (isIOS) return "ios"

  if (/Android/i.test(ua)) return "android"
  if (/Edg\//.test(ua)) return "edge"
  if (/Firefox\//.test(ua)) return "firefox"
  if (/Chrome\//.test(ua) || /Chromium\//.test(ua)) return "chrome"
  if (/Safari\//.test(ua)) return "safari"

  return "unknown"
}

/** Server-safe detection when only the User-Agent header is available. */
export function detectPlatformFromUserAgent(ua: string): DetectedPlatform {
  return detectPlatformFromSignals(ua)
}

/**
 * Client detection with the extra platform/touch signals needed for iPadOS
 * devices that identify themselves as desktop Macs.
 */
export function detectPlatform(): DetectedPlatform {
  if (typeof navigator === "undefined") return "unknown"
  return detectPlatformFromSignals(
    navigator.userAgent,
    navigator.platform || "",
    navigator.maxTouchPoints || 0,
  )
}

export function deviceKind(p: DetectedPlatform): DeviceKind {
  if (p === "ios" || p === "android" || p === "safari") return "mobile"
  if (p === "chrome" || p === "firefox" || p === "edge") return "desktop"
  return "unknown"
}

export type InstallTarget = {
  /** Short button label, e.g. "Add to Chrome". */
  label: string
  href: string
  /** Value used as a key / for tracking. */
  platform: string
  external: boolean
  /**
   * Hint that desktop UIs may open a QR dialog for this target (phones must
   * never do that — they should follow `href` to the store instead).
   */
  appQr?: boolean
}

const BROWSER_TARGETS: Record<"chrome" | "firefox" | "edge", InstallTarget> = {
  chrome: { label: "Add to Chrome", href: DOWNLOAD_LINKS.chrome, platform: "chrome", external: true },
  firefox: { label: "Add to Firefox", href: DOWNLOAD_LINKS.firefox, platform: "firefox", external: true },
  edge: { label: "Add to Edge", href: DOWNLOAD_LINKS.edge, platform: "edge", external: true },
}

const IOS_TARGET: InstallTarget = {
  label: "Get it on the App Store",
  href: "/download/ios",
  platform: "ios",
  external: false,
}
const ANDROID_TARGET: InstallTarget = {
  label: "Get it on Google Play",
  href: DOWNLOAD_LINKS.android,
  platform: "android",
  external: true,
}
const GENERIC_BROWSER: InstallTarget = {
  label: "Get the extension",
  href: "/download",
  platform: "browser",
  external: false,
}
const GENERIC_APP: InstallTarget = {
  label: "Get the app",
  /** Fallback if JS is off; QR dialog is preferred on the marketing site. */
  href: "/download/app",
  platform: "app",
  external: false,
  appQr: true,
}

/**
 * The recommended primary/secondary install pair for a platform. Primary is the
 * obvious install for the current device; secondary points at the other form
 * factor (app ⇄ extension) so both are always one tap away.
 */
export function installFor(p: DetectedPlatform): {
  primary: InstallTarget
  secondary: InstallTarget
} {
  if (p === "ios" || p === "safari") return { primary: IOS_TARGET, secondary: GENERIC_BROWSER }
  if (p === "android") return { primary: ANDROID_TARGET, secondary: GENERIC_BROWSER }
  if (p === "chrome" || p === "firefox" || p === "edge")
    return { primary: BROWSER_TARGETS[p], secondary: GENERIC_APP }
  return { primary: GENERIC_BROWSER, secondary: GENERIC_APP }
}
