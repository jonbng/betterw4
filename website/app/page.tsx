import Link from "next/link"

import { Everywhere } from "@/components/site/everywhere"
import { Features } from "@/components/site/features"
import { Hero } from "@/components/site/hero"
import { SiteFooter } from "@/components/site/site-footer"
import { SiteNav } from "@/components/site/site-nav"
import { SocialProof } from "@/components/site/social-proof"
import { StickyCta } from "@/components/site/sticky-cta"
import {
  siteButton,
  siteContainerClass,
  siteEyebrow,
  siteMainClass,
} from "@/components/site/styles"
import { JsonLd, siteJsonLd } from "@/components/site/structured-data"
import { TrustBar } from "@/components/site/trust-bar"
import { TrustSection } from "@/components/site/trust-section"
import { cn } from "@/lib/utils"

export default function HomePage() {
  return (
    <div className="site">
      <JsonLd data={siteJsonLd()} />
      <div className="site-diagonal" aria-hidden="true" />

      <SiteNav />

      <main className={siteMainClass}>
        <Hero />
        <TrustBar />
        <Everywhere />
        <Features />
        <SocialProof />
        <TrustSection />
        <FinalCta />
      </main>

      <SiteFooter />
      <StickyCta />
    </div>
  )
}

function FinalCta() {
  return (
    <section className={cn(siteContainerClass, "py-20 text-center min-[720px]:py-28")}>
      <span className={siteEyebrow()}>Get started</span>
      <h2 className="mx-auto mt-3 max-w-[15ch] text-[clamp(32px,5vw,60px)] font-extrabold leading-[1] tracking-[-0.04em]">
        Ready for a better W4?
      </h2>
      <p className="mx-auto mt-4 max-w-[46ch] text-[18px] leading-[1.5] text-ink-muted">
        Free, no new account, installed in under a minute. We&apos;ll find the
        right version for your device automatically.
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3.5">
        <Link href="/download" className={siteButton("primary")}>
          Get it free
        </Link>
        <Link href="/privacy" className={siteButton("secondary")}>
          How we handle data
        </Link>
      </div>
    </section>
  )
}
