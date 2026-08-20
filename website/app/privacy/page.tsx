import type { Metadata } from "next"

import { SiteFooter } from "@/components/site/site-footer"
import { SiteNav } from "@/components/site/site-nav"
import {
  siteContainerClass,
  siteEyebrow,
  siteMainClass,
} from "@/components/site/styles"
import { cn } from "@/lib/utils"

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "Your data is yours. How BetterW4 handles your information, in plain English, without legalese.",
  alternates: { canonical: "/privacy" },
}

const LAST_UPDATED = "18 August 2026"

/* --- tiny inline icon set (matches the site's inline-SVG style) ---------- */

function Icon({ children }: { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  )
}

const NoSale = () => (
  <Icon>
    <path d="M12 3 4 6v6c0 4.5 3.2 7.8 8 9 4.8-1.2 8-4.5 8-9V6z" />
    <path d="M4.5 4.5 19.5 19.5" />
  </Icon>
)
const Minimal = () => (
  <Icon>
    <path d="M12 3 3 8l9 5 9-5z" />
    <path d="M3 13l9 5 9-5" />
  </Icon>
)
const OpenCode = () => (
  <Icon>
    <path d="M8 8 4 12l4 4M16 8l4 4-4 4M13.5 6l-3 12" />
  </Icon>
)
const Check = () => (
  <Icon>
    <path d="M20 6 9 17l-5-5" />
  </Icon>
)
const Cross = () => (
  <Icon>
    <path d="M18 6 6 18M6 6l12 12" />
  </Icon>
)
const Lock = () => (
  <Icon>
    <rect x="4.5" y="10" width="15" height="10" rx="2.5" />
    <path d="M8 10V7a4 4 0 0 1 8 0v3" />
    <path d="M12 14v2.5" />
  </Icon>
)

/* -------------------------------------------------------------------------- */

const PROMISES = [
  {
    icon: <NoSale />,
    title: "We never sell your data",
    body: "No ads. No data brokers. No profiling. There's nothing to sell, because we never receive your data in the first place.",
  },
  {
    icon: <Minimal />,
    title: "Only what's needed",
    body: "Everything BetterW4 knows lives on your device. It talks to W4 and nowhere else, and never stores your password.",
  },
  {
    icon: <OpenCode />,
    title: "Everything is open",
    body: "The whole source is public. You don't have to take our word for it — you can check every single line yourself.",
  },
]

const DO = [
  "Shows your timetable, mail, assessments and attendance faster and cleaner",
  "Remembers your settings, theme and subject colours on your device",
  "Caches pages so the app works offline",
  "Lets you log in the same way the W4 website does, with 2FA",
]

const DONT = [
  "Run a backend, database or account system of our own",
  "Collect, upload or store your data",
  "Use analytics, crash reporting or advertising identifiers",
  "Sell or share data",
  "Track you, or save your password",
]

export default function PrivacyPage() {
  return (
    <div className="site">
      <SiteNav />

      <main className={cn(siteMainClass, siteContainerClass, "pt-6 pb-10")}>
        {/* Hero ---------------------------------------------------------- */}
        <section className="mx-auto max-w-[780px] pt-5 pb-2 text-center">
          <span className={siteEyebrow()}>Privacy, in plain English</span>
          <h1 className="mt-4 mb-5 text-[clamp(44px,6.4vw,76px)] font-extrabold leading-none tracking-[-0.045em]">
            Your data is <mark className="bg-transparent text-ink-muted">yours.</mark>
          </h1>
          <p className="mx-auto max-w-[58ch] text-[clamp(18px,2.2vw,21px)] font-medium leading-[1.5] text-ink-muted">
            BetterW4 is built by students who use W4 every day. We built what we
            would trust ourselves, so here is exactly what happens with your
            data. Without legalese.
          </p>

          <div className="mt-[30px] flex flex-wrap justify-center gap-2.5">
            {[
              { icon: <NoSale />, label: "No data sold" },
              { icon: <Minimal />, label: "No tracking" },
              { icon: <OpenCode />, label: "100% open source" },
            ].map((chip) => (
              <span
                key={chip.label}
                className="inline-flex items-center gap-2 rounded-full border border-line bg-white/75 py-[9px] pr-4 pl-[13px] text-sm font-bold text-ink backdrop-blur-[10px] [&_svg]:size-4 [&_svg]:text-ink"
              >
                {chip.icon} {chip.label}
              </span>
            ))}
          </div>

          <p className="mt-[26px] font-mono text-xs uppercase tracking-[0.04em] text-ink-muted">
            Last updated {LAST_UPDATED}
          </p>
        </section>

        {/* Promises ------------------------------------------------------ */}
        <section className="mt-14 grid grid-cols-1 gap-4 min-[900px]:mt-[72px] min-[900px]:grid-cols-3 min-[900px]:gap-5">
          {PROMISES.map((p) => (
            <article
              key={p.title}
              className="rounded-[26px] border border-line bg-grey px-[30px] py-8 transition-[transform,box-shadow] duration-[350ms] hover:-translate-y-1 hover:shadow-[0_24px_44px_-28px_rgba(0,0,0,0.28)] motion-reduce:transition-none"
            >
              <div className="mb-5 flex size-[52px] items-center justify-center rounded-[15px] bg-ink text-white [&_svg]:size-[26px]">
                {p.icon}
              </div>
              <h3 className="mb-2.5 text-[21px] font-extrabold tracking-[-0.02em] text-ink">
                {p.title}
              </h3>
              <p className="text-[15px] leading-[1.55] text-ink-muted">{p.body}</p>
            </article>
          ))}
        </section>

        {/* The honest ledger -------------------------------------------- */}
        <div className="mx-auto mt-[72px] max-w-[640px] text-center min-[900px]:mt-24">
          <span className={siteEyebrow()}>The short version</span>
          <h2 className="my-3 text-[clamp(28px,3.6vw,42px)] font-extrabold tracking-[-0.03em] text-ink">
            What we do, and never do
          </h2>
          <p className="text-[17px] leading-[1.5] text-ink-muted">
            Two lists. No three pages of fine print. This is how it is.
          </p>
        </div>

        <section className="mt-[30px] grid grid-cols-1 gap-5 min-[900px]:grid-cols-2">
          <div className="rounded-[26px] border border-line bg-grey p-8">
            <div className="mb-[22px] flex items-center gap-3">
              <span className="flex size-[34px] shrink-0 items-center justify-center rounded-[11px] bg-ink text-white [&_svg]:size-5">
                <Check />
              </span>
              <h3 className="text-[19px] font-extrabold tracking-[-0.02em] text-ink">
                What BetterW4 does
              </h3>
            </div>
            <ul className="flex list-none flex-col gap-3.5">
              {DO.map((item) => (
                <li
                  key={item}
                  className="flex items-start gap-[11px] text-[15px] font-medium leading-[1.45] text-[#3a3a3c] [&_svg]:mt-px [&_svg]:size-[18px] [&_svg]:shrink-0 [&_svg]:text-ink"
                >
                  <Check />
                  {item}
                </li>
              ))}
            </ul>
          </div>

          <div className="rounded-[26px] border border-line bg-white p-8">
            <div className="mb-[22px] flex items-center gap-3">
              <span className="flex size-[34px] shrink-0 items-center justify-center rounded-[11px] bg-ink-muted text-white [&_svg]:size-5">
                <Cross />
              </span>
              <h3 className="text-[19px] font-extrabold tracking-[-0.02em] text-ink">
                What we never do
              </h3>
            </div>
            <ul className="flex list-none flex-col gap-3.5">
              {DONT.map((item) => (
                <li
                  key={item}
                  className="flex items-start gap-[11px] text-[15px] font-medium leading-[1.45] text-[#3a3a3c] [&_svg]:mt-px [&_svg]:size-[18px] [&_svg]:shrink-0 [&_svg]:text-ink-muted"
                >
                  <Cross />
                  {item}
                </li>
              ))}
            </ul>
          </div>
        </section>

        {/* No backend, up front ----------------------------------------- */}
        <section className="mt-[30px] flex flex-col items-start gap-[22px] rounded-[30px] bg-ink p-9 text-white min-[900px]:flex-row min-[900px]:items-center min-[900px]:gap-8 min-[900px]:px-[clamp(32px,5vw,64px)] min-[900px]:py-12">
          <div className="flex size-[84px] shrink-0 items-center justify-center rounded-3xl bg-white/10 text-white [&_svg]:size-11">
            <Lock />
          </div>
          <div className="max-w-[52ch]">
            <h3 className="text-[24px] font-extrabold tracking-[-0.03em]">
              BetterW4 has no servers of its own.
            </h3>
            <p className="mt-2 text-[16px] leading-[1.6] text-white/75">
              No backend, no database, no account, no analytics. Using the app
              is the same as using W4 in a browser: your login and everything
              you see travels between your device and{" "}
              <code className="font-mono text-white/90">w4.uwcrcn.no</code>, and
              nowhere else.
            </p>
          </div>
        </section>

        {/* What stays on device ----------------------------------------- */}
        <div className="site-details mt-12 max-w-[780px] mx-auto">
          <details className="site-detail" open>
            <summary>What stays on your device</summary>
            <div className="site-detail__body">
              <p>Everything BetterW4 knows lives on the device you are holding.</p>
              <ul>
                <li>
                  <span>
                    <strong>Your W4 session.</strong> The session cookie and a
                    random device identifier stay on the device so you don't
                    have to complete 2FA on every launch. Your password is never
                    saved.
                  </span>
                </li>
                <li>
                  <span>
                    <strong>Cached W4 pages.</strong> Timetable, mail,
                    assessments, attendance, directory and similar pages are
                    cached so the app works offline. You can clear the cache at
                    any time.
                  </span>
                </li>
                <li>
                  <span>
                    <strong>Your settings.</strong> Theme, calendar style,
                    subject names and colours, and notification choices.
                  </span>
                </li>
              </ul>
              <p>
                Logging out removes the session and every cached page for that
                account.
              </p>
            </div>
          </details>
          <details className="site-detail">
            <summary>W4 itself</summary>
            <div className="site-detail__body">
              <p>
                BetterW4 does not change what W4 already knows about you. Grades,
                mail, timetable and attendance are stored by the college on{" "}
                <code>w4.uwcrcn.no</code>, just as they are when you use the
                website. Questions about that data belong with the college, not
                with BetterW4.
              </p>
            </div>
          </details>
          <details className="site-detail">
            <summary>Changes and contact</summary>
            <div className="site-detail__body">
              <p>
                If this policy changes, the date at the top will be updated.
                Questions about it: open an issue on the BetterW4 repository, or
                write to the maintainer who published the app.
              </p>
            </div>
          </details>
        </div>
      </main>

      <SiteFooter />
    </div>
  )
}
