import posthog from "posthog-js"

import type { DOWNLOAD_LINKS } from "./download-links"

export type DownloadPlatform = keyof typeof DOWNLOAD_LINKS | "ios"

type Props = Record<string, unknown>

const ALLOWED_EVENTS = new Set([
  "download clicked",
  "uninstall page viewed",
  "uninstall reason submitted",
])

export function capture(event: string, properties?: Props) {
  try {
    if (!ALLOWED_EVENTS.has(event)) return
    posthog.capture(event, properties)
  } catch {
    // posthog not initialized (no env key), drop silently
  }
}

export function captureDownloadClicked(platform: string, properties?: Props) {
  capture("download clicked", { platform, ...properties })
}

export function captureHentNuClicked(properties?: Props) {
  capture("hent nu clicked", properties)
}
