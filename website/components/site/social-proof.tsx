import { Star } from "@/components/site/icons"
import { siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { cn } from "@/lib/utils"

// Placeholder ratings, swap for live store numbers once the apps are published.
const RATINGS = [
  { store: "App Store", score: "New" },
  { store: "Google Play", score: "New" },
  { store: "Chrome Web Store", score: "New" },
  { store: "Firefox Add-ons", score: "New" },
  { store: "Microsoft Edge", score: "New" },
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

export function SocialProof() {
  const stats = [
    { value: "~200", label: "students, one college" },
    { value: "3", label: "platforms" },
    { value: "0", label: "servers of ours" },
    { value: "100%", label: "open source" },
  ]

  return (
    <section className={cn(siteContainerClass, "py-16 min-[720px]:py-24")} id="reviews">
      <div className="mx-auto mb-12 max-w-[640px] text-center">
        <span className={siteEyebrow()}>Simple by design</span>
        <h2 className="mt-3 text-[clamp(30px,4.2vw,52px)] font-extrabold tracking-[-0.035em]">
          One college, every device.
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
    </section>
  )
}
