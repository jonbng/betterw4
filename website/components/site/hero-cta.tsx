"use client"

import Link from "next/link"
import { useState } from "react"

import { AppQrDialog } from "@/components/site/app-qr-dialog"
import { siteButton, type SiteButtonVariant } from "@/components/site/styles"
import { deviceKind, type InstallTarget, installFor } from "@/lib/platform"
import { usePlatform } from "@/lib/use-platform"

function CtaButton({
  cta,
  variant,
  onAppQr,
}: {
  cta: InstallTarget
  variant: SiteButtonVariant
  /** Desktop only — phones must never get a QR they can't scan. */
  onAppQr?: () => void
}) {
  const className = siteButton(variant)

  // QR is only offered when the parent confirms desktop (onAppQr set).
  // On mobile, fall through to the normal store/download link.
  if (cta.appQr && onAppQr) {
    return (
      <button type="button" className={className} onClick={onAppQr}>
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
      >
        {cta.label}
      </a>
    )
  }
  return (
    <Link href={cta.href} className={className}>
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
  const showAppQr = detected !== null && deviceKind(detected) === "desktop"
  const openAppQr = showAppQr ? () => setAppQrOpen(true) : undefined

  return (
    <>
      <div className="mt-9 flex flex-wrap gap-3.5">
        <CtaButton cta={primary} variant="primary" onAppQr={openAppQr} />
        <CtaButton cta={secondary} variant="secondary" onAppQr={openAppQr} />
      </div>

      <p className="mt-[18px] text-sm font-medium text-ink-muted">
        Free · no new account · installed in under a minute
      </p>

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
