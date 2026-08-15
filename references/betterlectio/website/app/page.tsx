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
import { getSchoolCount } from "@/lib/school-count"
import { cn } from "@/lib/utils"

export default async function HomePage() {
  const schoolCount = await getSchoolCount()

  return (
    <div className="site">
      <JsonLd data={siteJsonLd()} />
      <div className="site-diagonal" aria-hidden="true" />

      <SiteNav />

      <main className={siteMainClass}>
        <Hero schoolCount={schoolCount} />
        <TrustBar />
        <Everywhere />
        <Features />
        <SocialProof schoolCount={schoolCount} />
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
      <span className={siteEyebrow()}>Kom i gang</span>
      <h2 className="mx-auto mt-3 max-w-[15ch] text-[clamp(32px,5vw,60px)] font-extrabold leading-[1] tracking-[-0.04em]">
        Klar til en bedre Lectio?
      </h2>
      <p className="mx-auto mt-4 max-w-[46ch] text-[18px] leading-[1.5] text-ink-muted">
        Gratis, ingen ny konto, installeret på under et minut. Vi finder
        automatisk den rigtige version til din enhed.
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3.5">
        <Link href="/download" className={siteButton("primary")}>
          Hent gratis
        </Link>
        <Link href="/privatliv" className={siteButton("secondary")}>
          Sådan behandler vi data
        </Link>
      </div>
    </section>
  )
}
