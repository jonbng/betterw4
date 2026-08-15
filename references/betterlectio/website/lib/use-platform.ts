"use client"

import { useEffect, useState } from "react"

import { detectPlatform, type DetectedPlatform } from "@/lib/platform"

/**
 * Detects the visitor's platform after mount. Returns `null` until hydration so
 * callers can render a platform-neutral fallback and avoid hydration mismatch.
 */
export function usePlatform(): DetectedPlatform | null {
  const [platform, setPlatform] = useState<DetectedPlatform | null>(null)

  useEffect(() => {
    // Sync the browser's user-agent (an external system) into React once mounted.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPlatform(detectPlatform())
  }, [])

  return platform
}
