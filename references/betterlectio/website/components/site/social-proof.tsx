import { Star } from "@/components/site/icons"
import { siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { cn } from "@/lib/utils"

// Placeholder ratings, swap for live store numbers when wired up.
const RATINGS = [
  { store: "Chrome Web Store", score: "4,9" },
  { store: "Firefox Add-ons", score: "4,8" },
  { store: "Microsoft Edge", score: "4,9" },
  { store: "App Store", score: "4,7" },
  { store: "Google Play", score: "Ny" },
]

// Placeholder testimonials, real student quotes to be gathered before launch.
const QUOTES = [
  {
    quote:
      "Jeg åbner slet ikke Lectio mere uden BetterLectio. Skemaet er faktisk til at læse nu.",
    name: "Emma",
    meta: "3.g",
  },
  {
    quote:
      "Endelig kan jeg se mit gennemsnit uden at regne det ud selv. Og dark mode er bare lækkert.",
    name: "Frederik",
    meta: "2.g",
  },
  {
    quote:
      "Appen er 10 gange hurtigere end Lectios mobilside. Bruger den hver eneste dag.",
    name: "Sofia",
    meta: "1.g",
  },
]

const SCHOOLS = [
  "Gefion Gymnasium",
  "Aarhus Katedralskole",
  "Ørestad Gymnasium",
  "Rysensteen",
  "Egaa Gymnasium",
  "Roskilde Gymnasium",
  "Frederiksberg Gymnasium",
  "Nørre Gymnasium",
  "Odense Katedralskole",
  "Silkeborg Gymnasium",
]

function Stars() {
  return (
    <span className="inline-flex text-ink [&_svg]:size-4" aria-hidden="true">
      <Star />
      <Star />
      <Star />
      <Star />
      <Star />
    </span>
  )
}

export function SocialProof({ schoolCount }: { schoolCount: number }) {
  const stats = [
    { value: "1000+", label: "elever bruger det" },
    { value: `${schoolCount}`, label: "gymnasier" },
    { value: "5", label: "platforme" },
    { value: "100%", label: "open source" },
  ]

  return (
    <section className={cn(siteContainerClass, "py-16 min-[720px]:py-24")} id="anmeldelser">
      <div className="mx-auto mb-12 max-w-[640px] text-center">
        <span className={siteEyebrow()}>Elever kan lide det</span>
        <h2 className="mt-3 text-[clamp(30px,4.2vw,52px)] font-extrabold tracking-[-0.035em]">
          Ikke bare os, der synes det.
        </h2>
      </div>

      {/* Store ratings */}
      <div className="grid grid-cols-2 gap-3 min-[720px]:grid-cols-5">
        {RATINGS.map((r) => (
          <div
            key={r.store}
            className="flex flex-col items-center gap-1.5 rounded-2xl border border-line bg-white px-4 py-5 text-center"
          >
            <span className="text-2xl font-extrabold tracking-[-0.02em]">{r.score}</span>
            <Stars />
            <span className="text-xs font-medium text-ink-muted">{r.store}</span>
          </div>
        ))}
      </div>

      {/* Testimonials */}
      <div className="mt-6 grid grid-cols-1 gap-4 min-[720px]:mt-8 min-[720px]:grid-cols-3">
        {QUOTES.map((q) => (
          <figure
            key={q.name}
            className="flex flex-col gap-4 rounded-[24px] border border-line bg-grey p-7"
          >
            <Stars />
            <blockquote className="flex-1 text-[17px] font-medium leading-[1.5] text-ink">
              &ldquo;{q.quote}&rdquo;
            </blockquote>
            <figcaption className="flex items-center gap-3">
              <span className="flex size-9 items-center justify-center rounded-full bg-white text-sm font-bold text-ink-muted">
                {q.name.charAt(0)}
              </span>
              <span className="text-sm font-semibold text-ink">
                {q.name}
                <span className="font-normal text-ink-muted"> · {q.meta}</span>
              </span>
            </figcaption>
          </figure>
        ))}
      </div>

      {/* Numbers band */}
      <div className="mt-6 grid grid-cols-2 gap-px overflow-hidden rounded-[24px] border border-line bg-line min-[720px]:mt-8 min-[720px]:grid-cols-4">
        {stats.map((s) => (
          <div key={s.label} className="bg-white px-5 py-8 text-center">
            <div className="text-[clamp(30px,4vw,44px)] font-extrabold tracking-[-0.03em]">
              {s.value}
            </div>
            <div className="mt-1 text-sm font-medium text-ink-muted">{s.label}</div>
          </div>
        ))}
      </div>

      {/* Schools marquee */}
      <div className="marquee mt-10">
        <div className="marquee__track">
          {[...SCHOOLS, ...SCHOOLS].map((school, i) => (
            <span
              key={`${school}-${i}`}
              className="mx-5 text-sm font-semibold text-ink-muted"
            >
              {school}
            </span>
          ))}
        </div>
      </div>
    </section>
  )
}
