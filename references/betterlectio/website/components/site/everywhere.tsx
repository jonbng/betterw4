"use client"

import Link from "next/link"

import { BrowserFrame, PhoneFrame } from "@/components/site/device-frames"
import { Apple, ArrowUpRight, GooglePlay } from "@/components/site/icons"
import { siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { deviceKind } from "@/lib/platform"
import { captureDownloadClicked } from "@/lib/posthog"
import { usePlatform } from "@/lib/use-platform"
import { cn } from "@/lib/utils"

function StoreLink({
  href,
  platform,
  children,
  variant = "solid",
}: {
  href: string
  platform: string
  children: React.ReactNode
  variant?: "solid" | "outline"
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      onClick={() => captureDownloadClicked(platform, { source: "everywhere" })}
      className={cn(
        "inline-flex items-center gap-2 rounded-full px-5 py-3 text-sm font-bold no-underline transition-[transform,background,border-color] duration-300 hover:-translate-y-px [&_svg]:size-[18px]",
        variant === "solid"
          ? "bg-ink text-white hover:opacity-90"
          : "border border-line bg-white text-ink hover:border-ink/25",
      )}
    >
      {children}
    </a>
  )
}

function MobilePanel({ reverse, isFirst }: { reverse: boolean; isFirst: boolean }) {
  return (
    <Panel
      reverse={reverse}
      eyebrow="BetterLectio Mobile"
      title={isFirst ? "En rigtig app i lommen." : "Og i lommen."}
      body="Ikke Lectios mobilside, der ser ud som om den giver op. Skema, beskeder, lektier og karakterer åbner med det samme, til både iPhone og Android."
      visual={
        <div className="flex items-end justify-center">
          <PhoneFrame
            src="/shots/mobile-skema.png"
            alt="BetterLectio-appen: ugens skema"
            className="z-10 w-[52%] max-w-[230px] -rotate-3"
          />
          <PhoneFrame
            src="/shots/mobile-beskeder.png"
            alt="BetterLectio-appen: beskeder"
            className="-ml-8 mb-10 w-[46%] max-w-[200px] rotate-3 opacity-95"
          />
        </div>
      }
      actions={
        <>
          <StoreLink href={DOWNLOAD_LINKS.ios} platform="ios">
            <Apple /> App Store
          </StoreLink>
          <StoreLink href={DOWNLOAD_LINKS.android} platform="android" variant="outline">
            <GooglePlay /> Google Play
          </StoreLink>
        </>
      }
    />
  )
}

function WebPanel({ reverse, isFirst }: { reverse: boolean; isFirst: boolean }) {
  return (
    <Panel
      reverse={reverse}
      eyebrow="BetterLectio for Web"
      title={isFirst ? "I din browser." : "Og i din browser."}
      body="En udvidelse, der lægger sig oven på Lectio og gør hele oplevelsen pænere og hurtigere. Virker i Chrome, Firefox og Edge, installeret på under et minut."
      visual={
        <BrowserFrame
          src="/shots/web-skema.png"
          alt="BetterLectio i browseren: ugeskema oven på Lectio"
        />
      }
      actions={
        <>
          <StoreLink href={DOWNLOAD_LINKS.chrome} platform="chrome">
            Chrome
          </StoreLink>
          <StoreLink href={DOWNLOAD_LINKS.firefox} platform="firefox" variant="outline">
            Firefox
          </StoreLink>
          <StoreLink href={DOWNLOAD_LINKS.edge} platform="edge" variant="outline">
            Edge
          </StoreLink>
        </>
      }
    />
  )
}

function Panel({
  eyebrow,
  title,
  body,
  visual,
  actions,
  reverse,
}: {
  eyebrow: string
  title: string
  body: string
  visual: React.ReactNode
  actions: React.ReactNode
  reverse: boolean
}) {
  return (
    <article className="grid grid-cols-1 items-center gap-10 rounded-[32px] border border-line bg-white p-7 min-[860px]:grid-cols-2 min-[860px]:gap-14 min-[860px]:p-12">
      <div className={cn(reverse && "min-[860px]:order-2")}>
        <span className={siteEyebrow()}>{eyebrow}</span>
        <h3 className="mt-3 mb-3.5 text-[clamp(26px,3.4vw,40px)] font-extrabold tracking-[-0.03em]">
          {title}
        </h3>
        <p className="max-w-[46ch] text-[17px] leading-[1.55] text-ink-muted">
          {body}
        </p>
        <div className="mt-7 flex flex-wrap gap-3">{actions}</div>
      </div>
      <div className={cn("min-[860px]:px-2", reverse && "min-[860px]:order-1")}>
        {visual}
      </div>
    </article>
  )
}

export function Everywhere() {
  const detected = usePlatform()
  // Default to desktop-first; put the visitor's own form factor first once known.
  const mobileFirst = detected ? deviceKind(detected) === "mobile" : false

  return (
    <section
      className={cn(siteContainerClass, "py-16 min-[720px]:py-24")}
      id="overalt"
    >
      <div className="mx-auto max-w-[680px] text-center">
        <span className={siteEyebrow()}>Én oplevelse, overalt</span>
        <h2 className="mt-3 mb-4 text-[clamp(30px,4.2vw,52px)] font-extrabold tracking-[-0.035em]">
          BetterLectio følger med dig.
        </h2>
        <p className="mx-auto max-w-[52ch] text-[18px] leading-[1.5] text-ink-muted">
          Det er ikke to forskellige produkter, det er den samme moderne Lectio,
          uanset om du sidder ved computeren eller tjekker skemaet i bussen.
        </p>
      </div>

      <div className="mt-12 flex flex-col gap-6 min-[720px]:mt-14">
        {mobileFirst ? (
          <>
            <MobilePanel reverse={false} isFirst />
            <WebPanel reverse isFirst={false} />
          </>
        ) : (
          <>
            <WebPanel reverse={false} isFirst />
            <MobilePanel reverse isFirst={false} />
          </>
        )}
      </div>

      <p className="mt-8 flex items-center justify-center gap-1.5 text-sm text-ink-muted">
        <Link
          href="/download"
          className="inline-flex items-center gap-1 font-semibold text-ink no-underline underline-offset-4 hover:underline"
        >
          Se alle platforme og hjælp til installation
          <ArrowUpRight className="size-4" />
        </Link>
      </p>
    </section>
  )
}
