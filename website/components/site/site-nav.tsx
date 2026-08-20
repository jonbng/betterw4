import Link from "next/link"

import { SiteLogoMark } from "@/components/site/site-logo"
import { siteButton, siteContainerClass } from "@/components/site/styles"
import { cn } from "@/lib/utils"

const NAV_LINKS = [
  { href: "/#everywhere", label: "Everywhere" },
  { href: "/#features", label: "Features" },
  { href: "/privacy", label: "Privacy" },
]

const NAV_LINK_CLASS =
  "text-sm font-bold text-ink-muted no-underline transition-colors hover:text-ink"

export function SiteNav() {
  return (
    <nav
      className={cn(
        siteContainerClass,
        "z-50 flex h-[76px] items-center justify-between gap-5 min-[720px]:h-24",
      )}
      aria-label="Primary"
    >
      <Link
        href="/"
        aria-label="BetterW4: home"
        className="group inline-flex items-center gap-2.5 text-2xl font-extrabold tracking-tight text-ink no-underline"
      >
        <SiteLogoMark
          size={34}
          className="block shrink-0 rounded-[9px] transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover:-rotate-6 group-hover:scale-105 motion-reduce:transition-none motion-reduce:group-hover:rotate-0 motion-reduce:group-hover:scale-100"
        />
        <span>
          Better<span className="text-ink-muted">W4</span>
        </span>
      </Link>

      <div className="hidden items-center gap-7 rounded-full border border-line bg-white/70 px-7 py-3 backdrop-blur-[20px] backdrop-saturate-[1.8] min-[900px]:flex">
        {NAV_LINKS.map((link) => (
          <Link key={link.href} href={link.href} className={NAV_LINK_CLASS}>
            {link.label}
          </Link>
        ))}
      </div>

      <Link
        href="/download"
        className={siteButton("primary", "px-6 py-[11px] text-[15px]")}
      >
        Get it free
      </Link>
    </nav>
  )
}
