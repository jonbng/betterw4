"use client"

import { useEffect } from "react"

export type BlLoginMessage = {
  source: "bl-login"
  status: "ok" | "error"
  reason?: string | null
}

/** If this tab was opened as the Lectio login popup, notify opener and close. */
export function LoginPopupCloser({
  active,
  status,
  reason,
}: {
  active: boolean
  status: "ok" | "error"
  reason?: string | null
}) {
  useEffect(() => {
    if (!active) return
    if (typeof window === "undefined" || !window.opener) return

    const msg: BlLoginMessage = {
      source: "bl-login",
      status,
      reason: reason ?? null,
    }
    try {
      window.opener.postMessage(msg, window.location.origin)
    } catch {
      // Opener may be gone; parent also polls popup.closed.
    }
    try {
      window.opener.location.reload()
    } catch {
      // Cross-origin / closed opener — ignore.
    }
    window.close()
  }, [active, status, reason])

  return null
}
