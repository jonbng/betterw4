/**
 * Store / gallery links for every BetterW4 surface.
 *
 * These are placeholders until the apps and extension are actually published.
 * Replace each URL before launch — the download page, footer, hero CTA and
 * structured data all read from here.
 */
export const DOWNLOAD_LINKS = {
  ios: "https://apps.apple.com/app/betterw4/id0000000000", // TODO: App Store link
  android: "https://play.google.com/store/apps/details?id=dk.jonathanb.w4",
  chrome: "https://chromewebstore.google.com/detail/betterw4/PLACEHOLDER", // TODO: Chrome Web Store link
  firefox: "https://addons.mozilla.org/firefox/addon/betterw4/", // TODO: Firefox Add-ons link
  edge: "https://microsoftedge.microsoft.com/addons/detail/betterw4/PLACEHOLDER", // TODO: Edge Add-ons link
} as const

export type DownloadPlatform = keyof typeof DOWNLOAD_LINKS
