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
      id="features"
    >
      <div className="mx-auto mb-12 max-w-[640px] text-center min-[720px]:mb-14">
        <span className={siteEyebrow()}>What makes the difference</span>
        <h2 className="mt-3 text-[clamp(30px,4.2vw,52px)] font-extrabold tracking-[-0.035em]">
          Little things you feel every day.
        </h2>
      </div>

      <div className="grid grid-cols-1 gap-5 min-[720px]:grid-cols-12">
        {/* Timetable, signature dark card */}
        <article className={cn(CARD_BASE, "bg-ink text-white min-[720px]:col-span-7")}>
          <span className={siteEyebrow("white")}>Timetable</span>
          <h3 className={TITLE}>The whole week at a glance.</h3>
          <p className={cn(BODY, "max-w-[42ch] text-white/75")}>
            Academics and extra-academics in one view, with rotation days (Day
            1–5), subject colours and the &quot;now&quot; line. No more switching
            between tabs to find where you should be.
          </p>
          <div className="mt-8 overflow-hidden rounded-2xl bg-white/10 p-3">
            <Image
              src="/shots/feat-timetable.png"
              alt="Combined timetable with rotation days and subject colours"
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
            <Moon /> Dark mode
          </span>
          <h3 className={TITLE}>A real dark mode.</h3>
          <p className={cn(BODY, "text-ink-muted")}>
            Proper black, not W4's tired grey. Perfect for late-night homework.
          </p>
          <div className="mt-7 overflow-hidden rounded-2xl border border-line">
            <Image
              src="/shots/web-dark.png"
              alt="BetterW4 in dark mode"
              width={2560}
              height={1600}
              sizes="(max-width: 720px) 90vw, 380px"
              className="block h-auto w-full"
            />
          </div>
        </article>

        {/* Assessments */}
        <article className={cn(CARD_BASE, "bg-grey min-[720px]:col-span-5")}>
          <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
            <ListChecks /> Assessments
          </span>
          <h3 className={TITLE}>Everything you owe, one list.</h3>
          <p className={cn(BODY, "text-ink-muted")}>
            W4's assessment calendar, list or month view. Confirm done and move
            on — no digging through every subject.
          </p>
          <div className="mt-7 overflow-hidden rounded-2xl border border-line bg-white">
            <Image
              src="/shots/feat-assessments.png"
              alt="Assessment calendar grouped by date"
              width={1200}
              height={900}
              sizes="(max-width: 720px) 90vw, 380px"
              className="block h-auto w-full"
            />
          </div>
        </article>

        {/* Offline + notifications, text pair */}
        <article className={cn(CARD_BASE, "flex flex-col gap-8 bg-grey min-[720px]:col-span-7 min-[720px]:flex-row")}>
          <div className="flex-1">
            <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
              <Zap /> Offline
            </span>
            <h3 className={TITLE}>Works without Wi-Fi.</h3>
            <p className={cn(BODY, "text-ink-muted")}>
              Every surface is cached on your device. A warm cache opens in
              airplane mode; a cold one fetches.
            </p>
          </div>
          <div className="flex-1 min-[720px]:border-l min-[720px]:border-line min-[720px]:pl-8">
            <span className={cn(siteEyebrow(), "[&_svg]:size-4 inline-flex items-center gap-1.5")}>
              <Bell /> Notifications
            </span>
            <h3 className={TITLE}>Never miss a message.</h3>
            <p className={cn(BODY, "text-ink-muted")}>
              New mail and campus-status changes gathered in one place, so you
              spot them before class starts.
            </p>
          </div>
        </article>
      </div>
    </section>
  )
}
