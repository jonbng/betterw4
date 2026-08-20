"use client"

import Image from "next/image"
import { useCallback, useRef, useState } from "react"

import { cn } from "@/lib/utils"

type BeforeAfterProps = {
  beforeSrc: string
  afterSrc: string
  beforeLabel?: string
  afterLabel?: string
  beforeAlt: string
  afterAlt: string
  className?: string
}

/**
 * Drag-to-compare slider. Bottom layer is the "after" (BetterW4) image; the
 * "before" (plain W4) is clipped from the left up to the handle. Works with
 * pointer/touch and the keyboard (focus the handle, use arrow keys).
 */
export function BeforeAfter({
  beforeSrc,
  afterSrc,
  beforeLabel = "W4 today",
  afterLabel = "BetterW4",
  beforeAlt,
  afterAlt,
  className,
}: BeforeAfterProps) {
  const [pos, setPos] = useState(50)
  const ref = useRef<HTMLDivElement>(null)
  const dragging = useRef(false)

  const setFromClientX = useCallback((clientX: number) => {
    const el = ref.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    const next = ((clientX - rect.left) / rect.width) * 100
    setPos(Math.min(100, Math.max(0, next)))
  }, [])

  return (
    <div
      ref={ref}
      className={cn("ba", className)}
      style={{ "--pos": `${pos}%` } as React.CSSProperties}
      onPointerDown={(e) => {
        dragging.current = true
        e.currentTarget.setPointerCapture(e.pointerId)
        setFromClientX(e.clientX)
      }}
      onPointerMove={(e) => {
        if (dragging.current) setFromClientX(e.clientX)
      }}
      onPointerUp={() => {
        dragging.current = false
      }}
    >
      <Image
        src={afterSrc}
        alt={afterAlt}
        width={2560}
        height={1600}
        priority
        sizes="(max-width: 980px) 100vw, 620px"
        className="ba__img"
      />
      <Image
        src={beforeSrc}
        alt={beforeAlt}
        width={2560}
        height={1600}
        priority
        sizes="(max-width: 980px) 100vw, 620px"
        className="ba__img ba__before"
      />

      <span className="ba__tag ba__tag--before">{beforeLabel}</span>
      <span className="ba__tag ba__tag--after">{afterLabel}</span>

      <div
        className="ba__handle"
        role="slider"
        tabIndex={0}
        aria-label="Compare W4 and BetterW4"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(pos)}
        onKeyDown={(e) => {
          if (e.key === "ArrowLeft") setPos((p) => Math.max(0, p - 4))
          if (e.key === "ArrowRight") setPos((p) => Math.min(100, p + 4))
          if (e.key === "Home") setPos(0)
          if (e.key === "End") setPos(100)
        }}
      >
        <span className="ba__grip" aria-hidden="true">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9 6 4 12l5 6M15 6l5 6-5 6" />
          </svg>
        </span>
      </div>
    </div>
  )
}
