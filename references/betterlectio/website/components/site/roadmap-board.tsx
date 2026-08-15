"use client"

import { useCallback, useState, useTransition } from "react"

import { toggleVote } from "@/app/roadmap/actions"
import type {
  RoadmapCategory,
  RoadmapColumn,
  RoadmapColumnKey,
} from "@/lib/roadmap"
import { cn } from "@/lib/utils"

const COLUMN_ACCENT: Record<RoadmapColumnKey, string> = {
  planned: "bg-[#3b82f6]",
  in_progress: "bg-[#a855f7]",
  done: "bg-[#22c55e]",
}

const CATEGORY_META: Record<RoadmapCategory, { label: string; className: string }> = {
  idea: { label: "Idé", className: "bg-[#eef2ff] text-[#4338ca]" },
  bug: { label: "Fejl", className: "bg-[#fef2f2] text-[#b91c1c]" },
  other: { label: "Andet", className: "bg-grey text-ink-muted" },
}

type VoteState = { voted: boolean; count: number }

function CaretUp() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
      <path
        d="M12 8l6 7H6z"
        fill="currentColor"
      />
    </svg>
  )
}

export function RoadmapBoard({
  columns,
  votedIds,
}: {
  columns: RoadmapColumn[]
  votedIds: string[]
}) {
  const votedSet = new Set(votedIds)
  const initial: Record<string, VoteState> = {}
  for (const col of columns) {
    for (const item of col.items) {
      initial[item.id] = {
        voted: votedSet.has(item.id),
        count: item.voteCount,
      }
    }
  }

  const [votes, setVotes] = useState<Record<string, VoteState>>(initial)
  const [, startTransition] = useTransition()

  const onVote = useCallback((id: string) => {
    setVotes((prev) => {
      const cur = prev[id] ?? { voted: false, count: 0 }
      const nextVoted = !cur.voted
      return {
        ...prev,
        [id]: {
          voted: nextVoted,
          count: Math.max(0, cur.count + (nextVoted ? 1 : -1)),
        },
      }
    })

    startTransition(async () => {
      const res = await toggleVote(id)
      if (res.ok) {
        setVotes((prev) => ({
          ...prev,
          [id]: { voted: res.voted, count: res.count },
        }))
      } else {
        // Revert optimistic change on failure.
        setVotes((prev) => {
          const cur = prev[id]
          if (!cur) return prev
          const revertVoted = !cur.voted
          return {
            ...prev,
            [id]: {
              voted: revertVoted,
              count: Math.max(0, cur.count + (revertVoted ? 1 : -1)),
            },
          }
        })
      }
    })
  }, [])

  return (
    <div className="grid grid-cols-1 gap-6 min-[720px]:grid-cols-3">
      {columns.map((col) => (
        <section key={col.key} className="min-w-0">
          <header className="mb-4 flex items-center gap-2.5">
            <span
              className={cn("size-2.5 rounded-full", COLUMN_ACCENT[col.key])}
            />
            <h2 className="text-[17px] font-bold tracking-[-0.01em] text-ink">
              {col.label}
            </h2>
            <span className="ml-auto rounded-full bg-grey px-2.5 py-0.5 text-xs font-semibold text-ink-muted">
              {col.items.length}
            </span>
          </header>

          {col.items.length === 0 ? (
            <div className="rounded-[20px] border border-dashed border-line bg-grey/40 p-6 text-center text-sm text-ink-muted">
              Ikke noget her endnu.
            </div>
          ) : (
            <ul className="flex flex-col gap-3.5">
              {col.items.map((item) => {
                const vote = votes[item.id] ?? {
                  voted: false,
                  count: item.voteCount,
                }
                const cat = CATEGORY_META[item.category]
                return (
                  <li
                    key={item.id}
                    className="rounded-[20px] border border-line bg-white p-5 transition-shadow duration-300 hover:shadow-[0_12px_28px_-18px_rgba(0,0,0,0.35)]"
                  >
                    <div className="flex items-start gap-3">
                      <button
                        type="button"
                        onClick={() => onVote(item.id)}
                        aria-pressed={vote.voted}
                        aria-label={
                          vote.voted ? "Fjern din stemme" : "Stem på dette"
                        }
                        className={cn(
                          "flex shrink-0 flex-col items-center gap-0.5 rounded-xl border px-2.5 py-1.5 text-xs font-bold transition-colors duration-200",
                          vote.voted
                            ? "border-ink bg-ink text-white"
                            : "border-line bg-white text-ink hover:border-ink/30",
                        )}
                      >
                        <CaretUp />
                        <span className="tabular-nums">{vote.count}</span>
                      </button>

                      <div className="min-w-0 flex-1">
                        <div className="mb-1.5 flex flex-wrap items-center gap-2">
                          <span
                            className={cn(
                              "inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold",
                              cat.className,
                            )}
                          >
                            {cat.label}
                          </span>
                          {item.eta ? (
                            <span className="inline-block rounded-full border border-line px-2 py-0.5 text-[11px] font-medium text-ink-muted">
                              {item.eta}
                            </span>
                          ) : null}
                        </div>
                        <h3 className="text-[15px] font-bold leading-[1.35] text-ink">
                          {item.title}
                        </h3>
                        {item.description ? (
                          <p className="mt-1 text-sm leading-[1.5] text-ink-muted">
                            {item.description}
                          </p>
                        ) : null}
                      </div>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </section>
      ))}
    </div>
  )
}
