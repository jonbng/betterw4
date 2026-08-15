"use client"

import Link from "next/link"
import QRCode from "qrcode"
import { useEffect, useId, useRef, useState } from "react"

import { Apple, Close, GooglePlay, Smartphone } from "@/components/site/icons"
import { cn } from "@/lib/utils"

/** Absolute URL encoded in the QR — routes phones to the right store. */
export const APP_QR_PATH = "/download/app"

type AppQrDialogProps = {
  open: boolean
  onClose: () => void
  /** Analytics / a11y source label, e.g. "hero_secondary". */
  source?: string
}

/**
 * Modal with a QR that points at `/download/app`. When scanned on a phone the
 * server redirects to App Store or Google Play based on User-Agent.
 */
export function AppQrDialog({ open, onClose, source }: AppQrDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const titleId = useId()
  const descId = useId()
  const [qrSvg, setQrSvg] = useState<string | null>(null)
  // Absolute URL for the phone to open after scanning.
  const qrHref =
    typeof window !== "undefined"
      ? `${window.location.origin}${APP_QR_PATH}`
      : `https://betterlectio.dk${APP_QR_PATH}`

  useEffect(() => {
    if (!open) return

    let cancelled = false
    QRCode.toString(qrHref, {
      type: "svg",
      errorCorrectionLevel: "M",
      margin: 2,
      width: 224,
      color: { dark: "#0a0a0a", light: "#ffffff" },
    })
      .then((svg) => {
        if (!cancelled) setQrSvg(svg)
      })
      .catch(() => {
        if (!cancelled) setQrSvg(null)
      })

    return () => {
      cancelled = true
    }
  }, [open, qrHref])

  useEffect(() => {
    const el = dialogRef.current
    if (!el) return

    if (open) {
      if (!el.open) el.showModal()
    } else if (el.open) {
      el.close()
    }
  }, [open])

  return (
    <dialog
      ref={dialogRef}
      aria-labelledby={titleId}
      aria-describedby={descId}
      data-source={source}
      className={cn(
        "fixed inset-0 z-[100] m-auto max-h-[min(100dvh-2rem,640px)] w-[min(calc(100%-2rem),400px]",
        "rounded-[28px] border border-ink/10 bg-white p-0 text-ink shadow-[0_32px_90px_-24px_rgba(0,0,0,0.55)]",
        "open:flex open:flex-col",
        "backdrop:bg-ink/45 backdrop:backdrop-blur-[6px]",
      )}
      onClose={onClose}
    >
      <div className="relative flex flex-col items-center px-6 pb-7 pt-6 text-center min-[400px]:px-8">
        <button
          type="button"
          onClick={onClose}
          aria-label="Luk"
          className="absolute right-3 top-3 flex size-10 items-center justify-center rounded-full text-ink-muted transition-colors hover:bg-grey hover:text-ink [&_svg]:size-[18px]"
        >
          <Close />
        </button>

        <span className="inline-flex size-11 items-center justify-center rounded-2xl bg-ink text-white [&_svg]:size-5">
          <Smartphone />
        </span>

        <h2
          id={titleId}
          className="mt-4 text-[22px] font-extrabold tracking-[-0.03em] min-[400px]:text-2xl"
        >
          Hent BetterLectio-appen
        </h2>
        <p
          id={descId}
          className="mt-2 max-w-[32ch] text-[15px] leading-snug text-ink-muted"
        >
          Scan QR-koden med din telefon. Den åbner automatisk App Store eller
          Google Play.
        </p>

        <div className="mt-6 rounded-[20px] border border-line bg-white p-3 shadow-[0_10px_30px_-18px_rgba(0,0,0,0.35)]">
          {qrSvg ? (
            <div
              role="img"
              aria-label={`QR-kode til ${qrHref}`}
              className="size-56 select-none [&_svg]:size-full"
              // SVG string from the qrcode package — no user input.
              dangerouslySetInnerHTML={{ __html: qrSvg }}
            />
          ) : (
            <div
              className="flex size-56 items-center justify-center bg-grey/60 text-sm text-ink-muted"
              aria-hidden="true"
            >
              Genererer…
            </div>
          )}
        </div>

        <div className="mt-5 flex items-center justify-center gap-4 text-ink-muted">
          <span className="inline-flex items-center gap-1.5 text-xs font-semibold">
            <Apple className="size-4 text-ink" />
            App Store
          </span>
          <span className="size-1 rounded-full bg-line" aria-hidden="true" />
          <span className="inline-flex items-center gap-1.5 text-xs font-semibold">
            <GooglePlay className="size-4 text-ink" />
            Google Play
          </span>
        </div>

        <p className="mt-5 text-sm text-ink-muted">
          Eller{" "}
          <Link
            href="/download"
            onClick={onClose}
            className="font-bold text-ink underline underline-offset-2"
          >
            se alle platforme
          </Link>
        </p>
      </div>
    </dialog>
  )
}
