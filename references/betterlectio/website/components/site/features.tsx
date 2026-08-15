import Image from "next/image"

import { Bell, ListChecks, Moon, Zap } from "@/components/site/icons"
import { siteContainerClass, siteEyebrow } from "@/components/site/styles"
import { cn } from "@/lib/utils"

const CARD_BASE =
  "overflow-hidden rounded-[28px] p-8 transition-transform duration-300 hover:-translate-y-1 motion-reduce:transition-none min-[720px]:p-10"
const TITLE = "mt-3 mb-3 text-[clamp(23px,2.6vw,31px)] font-extrabold tracking-[-0.02em]"
const BODY = "text-[16px] leading-[1.55]"

export function Features() {
  return (
    <section
      className={cn(siteContainerClass, "py-16 min-[720px]:py-24")}
      id="funktioner"
    >
      <div className="mx-auto mb-12 max-w-[640px] text-center min-[720px]:mb-14">
        <span className={siteEyebrow()}>Det, der gør forskellen</span>
        <h2 className="mt-3 text-[clamp(30px,4.2vw,52px)] font-extrabold tracking-[-0.035em]">
          Små ting, du mærker hver dag.
        </h2>
      </div>

      <div className="grid grid-cols-1 gap-5 min-[720px]:grid-cols-12">
        {/* Grades, signature dark card */}
        <article className={cn(CARD_BASE, "bg-ink text-white min-[720px]:col-span-7")}>
          <span className={siteEyebrow("white")}>Karakterer</span>
          <h3 className={TITLE}>Slut med at regne gennemsnit i hånden.</h3>
          <p className={cn(BODY, "max-w-[42ch] text-white/75")}>
            Alle karakterer samlet, farvekodet og vægtet automatisk. Du kan se
            præcis hvor du står, uden et regneark åbent ved siden af.
          </p>
          <div className="mt-8 overflow-hidden rounded-2xl bg-white/10 p-3">
            <Image
              src="/shots/feat-grades.png"
              alt="Karakteroversigt med automatisk gennemsnit"
              width={1200}
              height={900}
              sizes="(max-width: 720px) 90vw, 560px"
              className="block h-auto w-full rounded-lg"
            />
          </div>
        </article>

        {/* Dark mode */}
        <article className={cn(CARD_BASE, "bg-grey min-[720px]:col-span-5")}>
          <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
            <Moon /> Mørk tilstand
          </span>
          <h3 className={TITLE}>Endelig ordentlig dark mode.</h3>
          <p className={cn(BODY, "text-ink-muted")}>
            Rigtig sort, ikke Lectios triste grå. Perfekt til aftenlektier.
          </p>
          <div className="mt-7 overflow-hidden rounded-2xl border border-line">
            <Image
              src="/shots/web-dark.png"
              alt="BetterLectio i mørk tilstand"
              width={2560}
              height={1600}
              sizes="(max-width: 720px) 90vw, 380px"
              className="block h-auto w-full"
            />
          </div>
        </article>

        {/* Homework */}
        <article className={cn(CARD_BASE, "bg-grey min-[720px]:col-span-5")}>
          <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
            <ListChecks /> Lektier
          </span>
          <h3 className={TITLE}>Alt du skylder, ét sted.</h3>
          <p className={cn(BODY, "text-ink-muted")}>
            Alle afleveringer fra alle hold i én tjekliste. Ikke tre klik pr. hold
            for at finde ud af, hvad der er for.
          </p>
          <div className="mt-7 overflow-hidden rounded-2xl border border-line bg-white">
            <Image
              src="/shots/feat-homework.png"
              alt="Samlet lektie-tjekliste på tværs af hold"
              width={1200}
              height={900}
              sizes="(max-width: 720px) 90vw, 380px"
              className="block h-auto w-full"
            />
          </div>
        </article>

        {/* Speed + notifications, text pair */}
        <article className={cn(CARD_BASE, "flex flex-col gap-8 bg-grey min-[720px]:col-span-7 min-[720px]:flex-row")}>
          <div className="flex-1">
            <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
              <Zap /> Hastighed
            </span>
            <h3 className={TITLE}>Bygget til at være hurtigt.</h3>
            <p className={cn(BODY, "text-ink-muted")}>
              Sider åbner med det samme. Ingen ventetid, ingen genindlæsninger , 
              bare det du skal bruge.
            </p>
          </div>
          <div className="flex-1 min-[720px]:border-l min-[720px]:border-line min-[720px]:pl-8">
            <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
              <Bell /> Beskeder
            </span>
            <h3 className={TITLE}>Gå aldrig glip af en besked.</h3>
            <p className={cn(BODY, "text-ink-muted")}>
              Nye beskeder og lokaleændringer bliver samlet ét sted, så du opdager
              dem, før timen starter.
            </p>
          </div>
        </article>
      </div>
    </section>
  )
}
