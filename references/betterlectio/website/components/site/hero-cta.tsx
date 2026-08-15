"use client"

import Link from "next/link"
import { useState } from "react"

import { AppQrDialog } from "@/components/site/app-qr-dialog"
import { Star } from "@/components/site/icons"
import { siteButton, type SiteButtonVariant } from "@/components/site/styles"
import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { deviceKind, type InstallTarget, installFor } from "@/lib/platform"
import { captureDownloadClicked } from "@/lib/posthog"
import { usePlatform } from "@/lib/use-platform"

function CtaButton({
  cta,
  variant,
  source,
  onAppQr,
}: {
  cta: InstallTarget
  variant: SiteButtonVariant
  source: string
  /** Desktop only — phones must never get a QR they can't scan. */
  onAppQr?: () => void
}) {
  const className = siteButton(variant)
  const onClick = () =>
    captureDownloadClicked(cta.platform, { source, cta: cta.label })

  // QR is only offered when the parent confirms desktop (onAppQr set).
  // On mobile, fall through to the normal store/download link.
  if (cta.appQr && onAppQr) {
    return (
      <button
        type="button"
        className={className}
        onClick={() => {
          onClick()
          onAppQr()
        }}
      >
        {cta.label}
      </button>
    )
  }

  if (cta.external) {
    return (
      <a
        href={cta.href}
        className={className}
        target="_blank"
        rel="noreferrer"
        onClick={onClick}
      >
        {cta.label}
      </a>
    )
  }
  return (
    <Link href={cta.href} className={className} onClick={onClick}>
      {cta.label}
    </Link>
  )
}

export function HeroCta() {
  // `null` until hydration → render the platform-neutral default pair.
  const detected = usePlatform()
  const { primary, secondary } = installFor(detected ?? "unknown")
  const [appQrOpen, setAppQrOpen] = useState(false)

  // QR only makes sense on a computer — phones can't scan their own screen.
  // Until platform is known, treat as non-desktop so we never flash a QR CTA
  // on mobile (falls through to the /download/app link instead).
  const showAppQr = detected !== null && deviceKind(detected) === "desktop"
  const openAppQr = showAppQr ? () => setAppQrOpen(true) : undefined

  return (
    <>
      <div className="mt-9 flex flex-wrap gap-3.5">
        <CtaButton
          cta={primary}
          variant="primary"
          source="hero_primary"
          onAppQr={openAppQr}
        />
        <CtaButton
          cta={secondary}
          variant="secondary"
          source="hero_secondary"
          onAppQr={openAppQr}
        />
      </div>

      <a
        href={DOWNLOAD_LINKS.chrome}
        className="mt-[18px] inline-flex items-center gap-2.5 text-sm font-medium text-ink-muted no-underline transition-transform hover:-translate-y-px focus-visible:rounded-md focus-visible:outline-[3px] focus-visible:outline-offset-[3px] focus-visible:outline-brand"
        target="_blank"
        rel="noreferrer"
        onClick={() => captureDownloadClicked("chrome", { source: "hero_rating" })}
      >
        <span className="flex items-center gap-0.5 text-ink [&_svg]:size-[15px]" aria-hidden="true">
          <Star />
          <Star />
          <Star />
          <Star />
          <Star />
        </span>
        <span>
          <b className="font-bold text-ink">4,9</b> i gennemsnit · 1000+ elever
        </span>
      </a>

      {showAppQr ? (
        <AppQrDialog
          open={appQrOpen}
          onClose={() => setAppQrOpen(false)}
          source="hero_secondary"
        />
      ) : null}
    </>
  )
}
