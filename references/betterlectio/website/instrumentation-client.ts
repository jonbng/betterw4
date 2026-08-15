import posthog from "posthog-js"

const key = process.env.NEXT_PUBLIC_POSTHOG_KEY
const host = process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://eu.i.posthog.com"
const allowedEvents = new Set([
  "download clicked",
  "uninstall page viewed",
  "uninstall reason submitted",
])
const errorSignatures = new Set<string>()
let errorCount = 0

if (key) {
  posthog.init(key, {
    api_host: host,
    defaults: "2026-01-30",
    // PostHog is deliberately explicit-only: the site keeps just the few
    // conversion events emitted from lib/posthog.ts.
    person_profiles: "never",
    autocapture: false,
    capture_pageview: false,
    capture_pageleave: false,
    capture_heatmaps: false,
    capture_dead_clicks: false,
    capture_exceptions: {
      capture_unhandled_errors: true,
      capture_unhandled_rejections: true,
      capture_console_errors: false,
    },
    disable_session_recording: true,
    disable_surveys: true,
    advanced_disable_feature_flags: true,
    advanced_disable_feature_flags_on_first_load: true,
    before_send: (capture) => {
      if (!capture) return null
      if (allowedEvents.has(capture.event)) return capture
      if (capture.event !== "$exception" || errorCount >= 3) return null

      let signature: string
      try {
        signature = JSON.stringify(
          capture.properties.$exception_list ?? capture.properties,
        ).slice(0, 1000)
      } catch {
        signature = String(
          capture.properties.$exception_message ?? capture.uuid,
        )
      }
      if (errorSignatures.has(signature)) return null
      errorSignatures.add(signature)
      errorCount += 1
      return capture
    },
  })
}
