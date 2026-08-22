import Link from "next/link"

import { SiteLogoMark } from "@/components/site/site-logo"
import { siteContainerClass } from "@/components/site/styles"
import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { GITHUB_URL } from "@/lib/site"

const FOOTER_LINK_CLASS =
  "font-semibold text-white no-underline opacity-80 transition-[opacity,padding-left] hover:pl-1.5 hover:opacity-100"

export function SiteFooter() {
  return (
    <footer className="site-footer shrink-0 pt-16 pb-10 min-[720px]:pt-20 min-[720px]:pb-11">
      <div className={siteContainerClass}>
        <div className="mb-12 grid grid-cols-1 gap-10 min-[720px]:mb-[70px] min-[720px]:grid-cols-[2fr_1fr_1fr] min-[720px]:gap-[60px]">
          <div>
            <h2 className="mb-4 flex items-center gap-3 text-[32px] font-extrabold tracking-[-1px] min-[720px]:text-[40px]">
              <SiteLogoMark
                size={40}
                className="block shrink-0 rounded-xl [--logo-badge:#fff] [--logo-glyph:var(--ink)]"
              />
              BetterW4
            </h2>
            <p className="max-w-[320px] opacity-80">
              A modern interface for W4. Built by students, for students, so the
              timetable, mail and assessments are actually usable.
            </p>
          </div>

          <div>
            <h4 className="mb-5 text-[13px] uppercase tracking-[2px] text-white/45">
              Product
            </h4>
            <ul className="list-none">
              <li className="mb-3">
                <Link href="/download" className={FOOTER_LINK_CLASS}>
                  Get BetterW4
                </Link>
              </li>
              <li className="mb-3">
                <a
                  href={DOWNLOAD_LINKS.ios}
                  target="_blank"
                  rel="noreferrer noopener"
                  className={FOOTER_LINK_CLASS}
                >
                  iOS app
                </a>
              </li>
              <li className="mb-3">
                <a
                  href={DOWNLOAD_LINKS.android}
                  target="_blank"
                  rel="noreferrer noopener"
                  className={FOOTER_LINK_CLASS}
                >
                  Android app
                </a>
              </li>
              <li className="mb-3">
                <a
                  href={DOWNLOAD_LINKS.chrome}
                  target="_blank"
                  rel="noreferrer noopener"
                  className={FOOTER_LINK_CLASS}
                >
                  Browser extension
                </a>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="mb-5 text-[13px] uppercase tracking-[2px] text-white/45">
              Info
            </h4>
            <ul className="list-none">
              <li className="mb-3">
                <Link href="/privacy" className={FOOTER_LINK_CLASS}>
                  Privacy
                </Link>
              </li>
              <li className="mb-3">
                <a
                  href={GITHUB_URL}
                  target="_blank"
                  rel="noreferrer noopener"
                  className={FOOTER_LINK_CLASS}
                >
                  Source code
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div className="flex flex-wrap justify-between gap-4 border-t border-white/15 pt-8 text-[13px] opacity-75">
          <span>© 2026 BetterW4. Not affiliated with UWC Red Cross Nordic.</span>
          <span>Made for students, by students.</span>
        </div>
      </div>
    </footer>
  )
}
