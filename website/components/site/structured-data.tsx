import { DOWNLOAD_LINKS } from "@/lib/download-links"
import { SITE_NAME, SITE_TAGLINE, SITE_URL } from "@/lib/site"

/**
 * Renders a `<script type="application/ld+json">` block. Schema.org structured
 * data helps Google show rich results (org logo, sitelinks, …). JSON is
 * serialized server-side; no client JS is shipped.
 */
export function JsonLd({ data }: { data: object | object[] }) {
  return (
    <script
      type="application/ld+json"
      // Content is our own static data, safe to inline.
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }}
    />
  )
}

/** Organization + WebSite + SoftwareApplication graph for the landing page. */
export function siteJsonLd(): object {
  const organization = {
    "@type": "Organization",
    "@id": `${SITE_URL}/#organization`,
    name: SITE_NAME,
    url: SITE_URL,
    logo: `${SITE_URL}/logo-512.png`,
  }

  const website = {
    "@type": "WebSite",
    "@id": `${SITE_URL}/#website`,
    url: SITE_URL,
    name: SITE_NAME,
    inLanguage: "en",
    publisher: { "@id": `${SITE_URL}/#organization` },
  }

  const application = {
    "@type": "SoftwareApplication",
    "@id": `${SITE_URL}/#app`,
    name: SITE_NAME,
    description: `${SITE_TAGLINE} A modern interface for W4 — the student system at UWC Red Cross Nordic. Available as an iOS app, an Android app and a browser extension.`,
    url: SITE_URL,
    applicationCategory: "EducationalApplication",
    operatingSystem: "Chrome, Firefox, Edge, iOS, Android",
    inLanguage: "en",
    publisher: { "@id": `${SITE_URL}/#organization` },
    downloadUrl: [
      DOWNLOAD_LINKS.chrome,
      DOWNLOAD_LINKS.firefox,
      DOWNLOAD_LINKS.edge,
      DOWNLOAD_LINKS.ios,
      DOWNLOAD_LINKS.android,
    ],
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
  }

  return {
    "@context": "https://schema.org",
    "@graph": [organization, website, application],
  }
}
