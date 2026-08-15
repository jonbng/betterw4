"use client"

import Link from "next/link"
import { useEffect, useState } from "react"

import { Close } from "@/components/site/icons"
import { siteButton } from "@/components/site/styles"
import { installFor } from "@/lib/platform"
import { captureDownloadClicked } from "@/lib/posthog"
import { usePlatform } from "@/lib/use-platform"
import { cn } from "@/lib/utils"

const DISMISS_KEY = "bl-sticky-cta-dismissed"

/**
 * Slim, dismissible, platform-aware install prompt. Appears only after the
 * visitor scrolls past the hero, and stays hidden for the session once closed.
 */
export function StickyCta() {
  const detected = usePlatform()
  const [scrolledPast, setScrolledPast] = useState(false)
  const [dismissed, setDismissed] = useState(true)

  useEffect(() => {
    // Read the per-session dismissal + subscribe to scroll (external systems).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setDismissed(sessionStorage.getItem(DISMISS_KEY) === "1")
    const onScroll = () => setScrolledPast(window.scrollY > window.innerHeight * 0.9)
    onScroll()
    window.addEventListener("scroll", onScroll, { passive: true })
    return () => window.removeEventListener("scroll", onScroll)
  }, [])

  const dismiss = () => {
    setDismissed(true)
    try {
      sessionStorage.setItem(DISMISS_KEY, "1")
    } catch {
      // storage unavailable, dismissal just won't persist
    }
  }

  const visible = scrolledPast && !dismissed
  const { primary } = installFor(detected ?? "unknown")

  const onInstall = () =>
    captureDownloadClicked(primary.platform, { source: "sticky_cta" })

  return (
    <div
      className={cn(
        "fixed bottom-5 left-1/2 z-50 w-[min(calc(100%-2rem),560px)] -translate-x-1/2 transition-[opacity,transform] duration-300 min-[720px]:bottom-6",
        visible
          ? "translate-y-0 opacity-100"
          : "pointer-events-none translate-y-8 opacity-0",
      )}
      aria-hidden={!visible}
      role="region"
      aria-label="Hent BetterLectio"
    >
      <div className="flex items-center gap-3 rounded-[20px] border border-ink/10 bg-white/95 px-4 py-3.5 shadow-[0_24px_70px_-18px_rgba(0,0,0,0.55)] ring-1 ring-black/[0.04] backdrop-blur-xl min-[720px]:gap-4 min-[720px]:px-6 min-[720px]:py-4">
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-extrabold tracking-[-0.01em] text-ink min-[720px]:text-base">
            Hent BetterLectio gratis
          </p>
          <p className="mt-0.5 text-xs font-medium text-ink-muted">
            Gratis · ingen ny konto
          </p>
        </div>

        {primary.external ? (
          <a
            href={primary.href}
            target="_blank"
            rel="noreferrer"
            onClick={onInstall}
            className={siteButton(
              "primary",
              "shrink-0 px-5 py-2.5 text-sm min-[720px]:px-6 min-[720px]:py-3",
            )}
          >
            {primary.label}
          </a>
        ) : (
          <Link
            href={primary.href}
            onClick={onInstall}
            className={siteButton(
              "primary",
              "shrink-0 px-5 py-2.5 text-sm min-[720px]:px-6 min-[720px]:py-3",
            )}
          >
            {primary.label}
          </Link>
        )}

        <button
          type="button"
          onClick={dismiss}
          aria-label="Luk"
          className="flex size-9 shrink-0 items-center justify-center rounded-full text-ink-muted transition-colors hover:bg-grey hover:text-ink [&_svg]:size-4"
        >
          <Close />
        </button>
      </div>
    </div>
  )
}
