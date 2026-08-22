"use client"

import Link from "next/link"
import { Suspense } from "react"

import { SiteFooter } from "@/components/site/site-footer"
import { SiteNav } from "@/components/site/site-nav"
import {
  siteContainerClass,
  siteEyebrow,
  siteMainClass,
  sitePageClass,
} from "@/components/site/styles"
import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { usePlatform } from "@/lib/use-platform"
import { cn } from "@/lib/utils"

type PlatformKey = "chrome" | "ios" | "android" | "firefox" | "edge" | "safari"

type Platform = {
  key: PlatformKey
  name: string
  description: string
  href: string
  cta: string
}

const platforms: Platform[] = [
  {
    key: "chrome",
    name: "Chrome",
    description: "Browser extension for Chrome and Brave",
    href: DOWNLOAD_LINKS.chrome,
    cta: "Chrome Web Store",
  },
  {
    key: "ios",
    name: "iOS",
    description: "Native app for iPhone and iPad",
    href: "/download/ios",
    cta: "App Store",
  },
  {
    key: "safari",
    name: "Safari",
    description: "Native app for iPhone and iPad",
    href: "/download/ios",
    cta: "App Store",
  },
  {
    key: "android",
    name: "Android",
    description: "Native app for Android phones",
    href: DOWNLOAD_LINKS.android,
    cta: "Google Play",
  },
  {
    key: "firefox",
    name: "Firefox",
    description: "Browser extension for Firefox",
    href: DOWNLOAD_LINKS.firefox,
    cta: "Add-ons",
  },
  {
    key: "edge",
    name: "Edge",
    description: "Browser extension for Microsoft Edge",
    href: DOWNLOAD_LINKS.edge,
    cta: "Edge Add-ons",
  },
]

export default function DownloadPage() {
  return (
    <Suspense fallback={null}>
      <DownloadPageInner />
    </Suspense>
  )
}

function DownloadPageInner() {
  const detected = usePlatform()

  const sortedPlatforms =
    detected && detected !== "unknown"
      ? [
          ...platforms.filter((p) => p.key === detected),
          ...platforms.filter((p) => p.key !== detected),
        ]
      : platforms

  return (
    <div className="site">
      <SiteNav />

      <main className={cn(siteMainClass, siteContainerClass, sitePageClass)}>
        <div className="mx-auto max-w-[1000px]">
          <div className="text-center">
            <span className={siteEyebrow()}>Free · no new account</span>
            <h1 className="mt-3.5 mb-4 text-[clamp(44px,7vw,80px)] font-extrabold leading-none tracking-[-0.04em]">
              Get BetterW4
            </h1>
            <p className="text-[19px] font-medium text-ink-muted">
              We've found your platform. Pick where you want to start.
            </p>
          </div>

          <div className="mt-10 grid grid-cols-[repeat(auto-fit,minmax(260px,1fr))] gap-[18px]">
            {sortedPlatforms.map((platform, i) => {
              const isPrimary =
                i === 0 && detected !== null && detected !== "unknown"

              const inner = (
                <>
                  {isPrimary && (
                    <div className="absolute right-5 top-5 rounded-full bg-white/[0.22] px-2.5 py-[5px] font-mono text-[11px] font-bold uppercase tracking-[0.08em] text-white">
                      Recommended
                    </div>
                  )}
                  <div
                    className={cn(
                      "font-extrabold tracking-[-0.02em]",
                      isPrimary ? "text-[34px]" : "text-[26px]",
                    )}
                  >
                    {platform.name}
                  </div>
                  <div
                    className={cn(
                      "flex-1",
                      isPrimary ? "text-base text-white/85" : "text-sm text-ink-muted",
                    )}
                  >
                    {platform.description}
                  </div>
                  <div
                    className={cn(
                      "mt-1.5 inline-flex items-center gap-2 font-mono text-xs font-bold uppercase tracking-[0.06em] [&_svg]:size-3.5",
                      isPrimary ? "text-white" : "text-ink",
                    )}
                  >
                    {platform.cta}
                    <svg viewBox="0 0 24 24" aria-hidden="true">
                      <path
                        d="M5 12h14M13 6l6 6-6 6"
                        stroke="currentColor"
                        strokeWidth="3"
                        fill="none"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                  </div>
                </>
              )

              const className = cn(
                "relative flex flex-col gap-2 rounded-[24px] border border-line bg-white p-7 text-ink no-underline shadow-[0_10px_30px_-18px_rgba(0,0,0,0.25)] transition-[transform,box-shadow] duration-300 hover:-translate-y-1 hover:shadow-[0_24px_44px_-22px_rgba(0,0,0,0.32)]",
                isPrimary &&
                  "col-span-full border-transparent bg-ink text-white shadow-[0_30px_60px_-26px_rgba(0,0,0,0.5)] hover:shadow-[0_40px_70px_-28px_rgba(0,0,0,0.55)]",
              )
              const isExternal = platform.href.startsWith("http")

              if (isExternal) {
                return (
                  <a
                    key={platform.key}
                    href={platform.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className={className}
                  >
                    {inner}
                  </a>
                )
              }

              return (
                <Link key={platform.key} href={platform.href} className={className}>
                  {inner}
                </Link>
              )
            })}
          </div>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}
