type SiteLogoProps = {
  className?: string
  /** Pixel size of the badge. Defaults to 32. */
  size?: number
}

/**
 * The BetterW4 badge: a brand-teal rounded square with a white "W4" monogram.
 * Render on its own or alongside the wordmark via the nav / footer.
 */
export function SiteLogoMark({ className, size = 32 }: SiteLogoProps) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 512 512"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <rect width="512" height="512" rx="128" fill="var(--logo-badge, var(--brand))" />
      <text
        x="256"
        y="266"
        fill="var(--logo-glyph, #fff)"
        fontFamily="var(--font-sans), ui-sans-serif, system-ui, sans-serif"
        fontSize="212"
        fontWeight="800"
        letterSpacing="-0.05em"
        textAnchor="middle"
        dominantBaseline="central"
      >
        W4
      </text>
    </svg>
  )
}
