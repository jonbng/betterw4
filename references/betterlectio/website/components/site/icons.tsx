import type { SVGProps } from "react"

/**
 * Shared inline-SVG icon set for the marketing site. Stroke icons inherit
 * `currentColor`; brand glyphs (Apple, Google Play, GitHub) are filled. Kept
 * monochrome on purpose, colour on the site comes from product screenshots.
 */

type IconProps = SVGProps<SVGSVGElement>

function Stroke({ children, ...props }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      {children}
    </svg>
  )
}

export const ArrowRight = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M5 12h14M13 6l6 6-6 6" />
  </Stroke>
)

export const ArrowUpRight = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M7 17 17 7M8 7h9v9" />
  </Stroke>
)

export const Check = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M20 6 9 17l-5-5" />
  </Stroke>
)

export const Close = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M18 6 6 18M6 6l12 12" />
  </Stroke>
)

export const Shield = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M12 3 4 6v6c0 4.5 3.2 7.8 8 9 4.8-1.2 8-4.5 8-9V6z" />
    <path d="M9 12l2 2 4-4" />
  </Stroke>
)

export const EyeOff = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M3 3l18 18M10.6 10.6a2 2 0 0 0 2.8 2.8" />
    <path d="M9.4 5.2A9.6 9.6 0 0 1 12 5c5 0 9 4.5 9 7-.4 1-1.2 2.2-2.4 3.3M6.1 6.6C4 8 2.7 9.9 3 12c.6 1.6 4 5 9 5 .8 0 1.6-.1 2.3-.3" />
  </Stroke>
)

export const Code = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M8 8 4 12l4 4M16 8l4 4-4 4M13.5 6l-3 12" />
  </Stroke>
)

export const Heart = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M12 20s-7-4.3-9.3-8.4C1.3 9 2.5 6 5.5 6c1.9 0 3 1 2.5 1S9.6 6 11.5 6 14 5 16 5c3 0 4.2 3 2.8 5.6C16.9 15.7 12 20 12 20z" />
  </Stroke>
)

export const Zap = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M13 2 4 14h7l-1 8 9-12h-7z" />
  </Stroke>
)

export const Moon = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M21 12.8A8.5 8.5 0 1 1 11.2 3a6.5 6.5 0 0 0 9.8 9.8z" />
  </Stroke>
)

export const Bell = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6M10.5 20a1.7 1.7 0 0 0 3 0" />
  </Stroke>
)

export const ListChecks = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M3 5.5 4.5 7 7 4M3 12.5 4.5 14 7 11M3 19.5 4.5 21 7 18M11 5h10M11 12h10M11 19h10" />
  </Stroke>
)

export const GraduationCap = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M12 4 2 9l10 5 10-5-10-5zM6 11.5V16c0 1.1 2.7 2.5 6 2.5s6-1.4 6-2.5v-4.5" />
  </Stroke>
)

export const Sparkles = (p: IconProps) => (
  <Stroke {...p}>
    <path d="M12 3v5M12 16v5M4.5 12h5M14.5 12h5M6.5 6.5l2.5 2.5M15 15l2.5 2.5M17.5 6.5 15 9M9 15l-2.5 2.5" />
  </Stroke>
)

export const Smartphone = (p: IconProps) => (
  <Stroke {...p}>
    <rect x="7" y="3" width="10" height="18" rx="2.5" />
    <path d="M11 18h2" />
  </Stroke>
)

export const Monitor = (p: IconProps) => (
  <Stroke {...p}>
    <rect x="3" y="4" width="18" height="12" rx="2" />
    <path d="M8 20h8M12 16v4" />
  </Stroke>
)

export const Star = (p: IconProps) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...p}>
    <path d="M12 2.5 15 8.9l7 .9-5.1 4.8 1.3 6.9L12 18.2 5.8 21.5l1.3-6.9L2 9.8l7-.9z" />
  </svg>
)

export const Apple = (p: IconProps) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...p}>
    <path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.8-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7 2-1.1 2.8-2.2c.9-1.3 1.2-2.5 1.3-2.6-.1 0-2.5-1-2.5-3.8zM14.2 5.4c.6-.8 1-1.9.9-3-.9 0-2 .6-2.7 1.4-.6.7-1.1 1.8-.9 2.8 1 .1 2-.5 2.7-1.2z" />
  </svg>
)

export const GooglePlay = (p: IconProps) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...p}>
    <path d="M4 3.2c-.3.2-.5.6-.5 1.1v15.4c0 .5.2.9.5 1.1l8.3-8.8L4 3.2zM14 10.3l2.9-3.1-9.6-5.5c-.4-.2-.8-.2-1.1-.1L14 10.3zm0 3.4-7.8 8.3c.3.1.7.1 1.1-.1l9.6-5.5-2.9-2.7zm5.6-3.5-2.5-1.4-3.2 3.4 3.2 3 2.5-1.4c.9-.5.9-1.7 0-2.2z" />
  </svg>
)

export const GitHub = (p: IconProps) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...p}>
    <path d="M12 2C6.48 2 2 6.58 2 12.25c0 4.53 2.87 8.37 6.84 9.73.5.1.68-.22.68-.49l-.01-1.9c-2.78.62-3.37-1.2-3.37-1.2-.46-1.18-1.11-1.5-1.11-1.5-.9-.63.07-.62.07-.62 1 .07 1.53 1.05 1.53 1.05.9 1.56 2.34 1.11 2.91.85.09-.66.35-1.11.63-1.36-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05a9.34 9.34 0 0 1 5 0c1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.05.36.32.68.94.68 1.9l-.01 2.82c0 .27.18.6.69.49A10.02 10.02 0 0 0 22 12.25C22 6.58 17.52 2 12 2z" />
  </svg>
)
