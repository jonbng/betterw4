import type { Metadata } from "next"

import { readVoterId } from "@/app/roadmap/actions"
import { Sparkles } from "@/components/site/icons"
import { RoadmapBoard } from "@/components/site/roadmap-board"
import { RoadmapIdeaCta } from "@/components/site/roadmap-idea-cta"
import { LoginPopupCloser } from "@/components/site/login-popup-closer"
import { SiteFooter } from "@/components/site/site-footer"
import { SiteNav } from "@/components/site/site-nav"
import {
  siteContainerClass,
  siteEyebrow,
  siteMainClass,
} from "@/components/site/styles"
import { getRoadmap, getVotedIds } from "@/lib/roadmap"
import {
  getLinkedStudent,
  getWebsiteSession,
} from "@/lib/supabase-auth"
import { cn } from "@/lib/utils"

export const metadata: Metadata = {
  title: "Roadmap",
  description:
    "Se hvad vi planlægger, arbejder på og har færdiggjort i BetterLectio, og stem på det, du vil have mest.",
  alternates: { canonical: "/roadmap" },
}

// Votes bust the "roadmap" cache tag; keep the page dynamic so voter state and
// counts stay fresh per request.
export const dynamic = "force-dynamic"

export default async function RoadmapPage({
  searchParams,
}: {
  searchParams: Promise<{ login?: string; reason?: string }>
}) {
  const sp = await searchParams
  const [columns, voterId, user] = await Promise.all([
    getRoadmap(),
    readVoterId(),
    getWebsiteSession(),
  ])
  const votedIds = [...(await getVotedIds(voterId))]
  const hasItems = columns.some((c) => c.items.length > 0)

  const student = user ? await getLinkedStudent(user.id) : null
  const displayName = student
    ? [student.firstName, student.lastName].filter(Boolean).join(" ") || null
    : null

  const loginStatus =
    sp.login === "ok" ? "ok" : sp.login === "error" ? "error" : null

  return (
    <div className="site">
      {loginStatus ? (
        <LoginPopupCloser
          active
          status={loginStatus}
          reason={sp.reason ?? null}
        />
      ) : null}
      <SiteNav />

      <main className={cn(siteMainClass, siteContainerClass, "pt-6 pb-24")}>
        <section className="mx-auto max-w-[720px] py-12 text-center min-[720px]:py-16">
          <span className="mx-auto mb-6 flex size-16 items-center justify-center rounded-2xl bg-grey text-ink [&_svg]:size-8">
            <Sparkles />
          </span>
          <span className={siteEyebrow()}>Roadmap</span>
          <h1 className="mt-4 mb-5 text-[clamp(36px,5vw,60px)] font-extrabold leading-[1.02] tracking-[-0.045em]">
            Hvad der er på vej.
          </h1>
          <p className="mx-auto max-w-[54ch] text-[clamp(17px,2vw,20px)] font-medium leading-[1.5] text-ink-muted">
            Vi bygger i det åbne. Følg med i, hvad der er planlagt, i gang og
            færdigt. Stem på det, du synes er vigtigst.
          </p>
        </section>

        {hasItems ? (
          <RoadmapBoard columns={columns} votedIds={votedIds} />
        ) : (
          <div className="mx-auto max-w-[520px] rounded-[24px] border border-dashed border-line bg-grey/40 p-10 text-center">
            <p className="text-[17px] font-bold text-ink">
              Intet på roadmapen endnu.
            </p>
            <p className="mt-2 text-sm leading-[1.5] text-ink-muted">
              Når vi planlægger og går i gang med feedback, dukker det op her.
              Log ind nedenfor for at sende en idé imens.
            </p>
          </div>
        )}

        <RoadmapIdeaCta
          signedIn={Boolean(user && student)}
          displayName={displayName}
          loginStatus={loginStatus}
          loginReason={sp.reason ?? null}
        />
      </main>

      <SiteFooter />
    </div>
  )
}
