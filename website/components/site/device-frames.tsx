import Image from "next/image"

import { cn } from "@/lib/utils"

/**
 * Hardware-style frames that wrap product screenshots.
 * Files live in `public/shots` — mobile App Store shots at ~1170×2532,
 * desktop captures at ~2560×1600.
 */

type FrameProps = {
  src: string
  alt: string
  className?: string
  priority?: boolean
  sizes?: string
}

/** iPhone-style frame. Expects a ~1170x2532 (portrait) screenshot. */
export function PhoneFrame({ src, alt, className, priority, sizes }: FrameProps) {
  return (
    <div
      className={cn(
        "relative rounded-[2.6rem] border border-white/10 bg-ink p-2.5 shadow-[0_40px_80px_-40px_rgba(0,0,0,0.6)]",
        className,
      )}
    >
      <div className="relative overflow-hidden rounded-[2rem] bg-white">
        <Image
          src={src}
          alt={alt}
          width={1170}
          height={2532}
          priority={priority}
          sizes={sizes ?? "(max-width: 720px) 60vw, 320px"}
          className="block h-auto w-full"
        />
      </div>
    </div>
  )
}

/** Desktop browser chrome. Expects a ~2560x1600 (16:10) screenshot. */
export function BrowserFrame({ src, alt, className, priority, sizes }: FrameProps) {
  return (
    <div
      className={cn(
        "overflow-hidden rounded-[16px] border border-line bg-white shadow-[0_40px_90px_-50px_rgba(0,0,0,0.5)]",
        className,
      )}
    >
      <div className="flex h-10 items-center gap-2 border-b border-line bg-grey px-4">
        <span className="size-3 rounded-full bg-[#e3e3e6]" />
        <span className="size-3 rounded-full bg-[#e3e3e6]" />
        <span className="size-3 rounded-full bg-[#e3e3e6]" />
        <span className="ml-3 hidden h-5 w-1/2 max-w-[320px] items-center rounded-full bg-white px-3 text-[11px] font-medium text-ink-muted sm:flex">
          w4.uwcrcn.no
        </span>
      </div>
      <Image
        src={src}
        alt={alt}
        width={2560}
        height={1600}
        priority={priority}
        sizes={sizes ?? "(max-width: 980px) 100vw, 640px"}
        className="block h-auto w-full"
      />
    </div>
  )
}
