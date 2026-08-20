import Link from "next/link"

import { ArrowRight, Code, EyeOff, GitHub, GraduationCap, Shield } from "@/components/site/icons"
import { siteButton, siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { GITHUB_URL } from "@/lib/site"
import { cn } from "@/lib/utils"

const POINTS = [
  {
    icon: <GraduationCap />,
    title: "Made by students",
    body: "We use W4 every day. BetterW4 is what we wished existed, so we built it.",
  },
  {
    icon: <Shield />,
    title: "Your data stays yours",
    body: "There's no backend, no account and no analytics. Everything lives on your device and talks only to W4.",
  },
  {
    icon: <EyeOff />,
    title: "No ads",
    body: "No advertising, no cross-site tracking, no data brokers. Plain and simple.",
  },
  {
    icon: <Code />,
    title: "Open source",
    body: "All of the code is public. You don't have to take our word for it — you can check every line.",
  },
]

export function TrustSection() {
  return (
    <section className={cn(siteContainerClass, "py-8 min-[720px]:py-12")}>
      <div className="rounded-[32px] bg-ink px-7 py-12 text-white min-[720px]:px-14 min-[720px]:py-16">
        <div className="max-w-[640px]">
          <span className={siteEyebrow("white")}>Worth trusting</span>
          <h2 className="mt-3 mb-4 text-[clamp(28px,3.8vw,46px)] font-extrabold tracking-[-0.035em]">
            Built by students, not a company.
          </h2>
          <p className="text-[18px] leading-[1.55] text-white/75">
            BetterW4 is free and open source. There's no hidden business, no
            server of ours, and no data that ever leaves your device.
          </p>
        </div>

        <div className="mt-10 grid grid-cols-1 gap-x-10 gap-y-8 min-[560px]:grid-cols-2 min-[900px]:grid-cols-4">
          {POINTS.map((p) => (
            <div key={p.title}>
              <div className="mb-4 flex size-11 items-center justify-center rounded-xl bg-white/10 text-white [&_svg]:size-[22px]">
                {p.icon}
              </div>
              <h3 className="mb-2 text-lg font-bold tracking-[-0.01em]">{p.title}</h3>
              <p className="text-[15px] leading-[1.55] text-white/70">{p.body}</p>
            </div>
          ))}
        </div>

        <div className="mt-11 flex flex-wrap gap-3.5">
          <Link href="/privacy" className={siteButton("secondary")}>
            <Shield /> Read about privacy
          </Link>
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noreferrer noopener"
            className={siteButton("ghost")}
          >
            <GitHub /> See the code on GitHub
            <ArrowRight />
          </a>
        </div>
      </div>
    </section>
  )
}
