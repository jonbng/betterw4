import Link from "next/link"

import { ArrowRight, Code, EyeOff, GitHub, GraduationCap, Shield } from "@/components/site/icons"
import { siteButton, siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { cn } from "@/lib/utils"

const POINTS = [
  {
    icon: <GraduationCap />,
    title: "Lavet af elever",
    body: "Vi bruger selv Lectio hver dag. BetterLectio er det, vi ville ønske fandtes, så vi byggede det.",
  },
  {
    icon: <Shield />,
    title: "Dine data er dine",
    body: "Vi ser aldrig dit Lectio-login, og vi sælger aldrig dine data. Vi gemmer kun det, en funktion faktisk kræver.",
  },
  {
    icon: <EyeOff />,
    title: "Ingen annoncer",
    body: "Ingen reklamer, ingen sporing på tværs af nettet, ingen datamæglere. Slet og ret.",
  },
  {
    icon: <Code />,
    title: "Åben kildekode",
    body: "Hele koden ligger offentligt på GitHub. Du behøver ikke tro os, du kan tjekke hver linje.",
  },
]

export function TrustSection() {
  return (
    <section className={cn(siteContainerClass, "py-8 min-[720px]:py-12")}>
      <div className="rounded-[32px] bg-ink px-7 py-12 text-white min-[720px]:px-14 min-[720px]:py-16">
        <div className="max-w-[640px]">
          <span className={siteEyebrow("white")}>Til at stole på</span>
          <h2 className="mt-3 mb-4 text-[clamp(28px,3.8vw,46px)] font-extrabold tracking-[-0.035em]">
            Bygget af elever, ikke et firma.
          </h2>
          <p className="text-[18px] leading-[1.55] text-white/75">
            BetterLectio er gratis og open source. Der er ingen skjult forretning,
            ingen annoncer og ingen data, der bliver solgt videre.
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
          <Link href="/privatliv" className={siteButton("secondary")}>
            <Shield /> Læs om privatliv
          </Link>
          <a
            href="https://github.com/jonbng/betterlectio"
            target="_blank"
            rel="noreferrer noopener"
            className={siteButton("ghost")}
          >
            <GitHub /> Se koden på GitHub
            <ArrowRight />
          </a>
        </div>
      </div>
    </section>
  )
}
