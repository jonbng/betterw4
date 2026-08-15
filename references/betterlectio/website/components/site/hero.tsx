import { BeforeAfter } from "@/components/site/before-after"
import { HeroCta } from "@/components/site/hero-cta"
import { siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { cn } from "@/lib/utils"

export function Hero({ schoolCount }: { schoolCount: number }) {
  return (
    <section
      className={cn(
        siteContainerClass,
        "grid grid-cols-1 items-center gap-12 pt-8 pb-16 lg:grid-cols-[1.02fr_1fr] lg:gap-14 lg:pt-12 lg:pb-24",
      )}
      id="top"
    >
      <div>
        <span className={siteEyebrow()}>Bygget af elever · helt gratis</span>
        <h1 className="mt-[18px] mb-5 text-[clamp(46px,6.4vw,84px)] font-extrabold leading-[0.97] tracking-[-0.045em]">
          Lectio, <mark className="bg-transparent text-ink-muted">bare bedre.</mark>
        </h1>
        <p className="max-w-[480px] text-[clamp(18px,2.2vw,22px)] font-medium leading-[1.45] text-ink-muted">
          Samme skema, samme karakterer, samme beskeder, bare hurtigere, pænere
          og faktisk til at finde rundt i. På din telefon og i din browser.
        </p>

        <HeroCta />

        <div className="mt-11 flex items-center gap-3.5">
          <div className="flex" aria-hidden="true">
            {["M", "I", "S", "A"].map((c, i) => (
              <span
                key={c}
                className="-ml-2 flex size-8 items-center justify-center rounded-full border-2 border-white bg-grey text-[11px] font-bold text-ink-muted first:ml-0"
                style={{ zIndex: 10 - i }}
              >
                {c}
              </span>
            ))}
          </div>
          <p className="text-sm font-medium text-ink-muted">
            Allerede skiftet: elever på{" "}
            <b className="font-bold text-ink">{schoolCount}</b> gymnasier.
          </p>
        </div>
      </div>

      <div className="relative">
        <BeforeAfter
          beforeSrc="/shots/lectio-before.png"
          afterSrc="/shots/betterlectio-after.png"
          beforeAlt="Lectios standard-skema, gråt og kompakt"
          afterAlt="Det samme skema i BetterLectio: rent og farvekodet"
          className="shadow-[0_50px_100px_-45px_rgba(0,0,0,0.5)]"
        />
        <p className="mt-4 text-center font-mono text-xs uppercase tracking-[0.04em] text-ink-muted">
          Træk i midten: Lectio til venstre, BetterLectio til højre
        </p>
      </div>
    </section>
  )
}
