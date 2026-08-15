export const DOWNLOAD_LINKS = {
  ios: "https://apps.apple.com/dk/app/betterlectio/id6761808963",
  android:
    "https://play.google.com/store/apps/details?id=dk.betterlectio.android",
  chrome:
    "https://chromewebstore.google.com/detail/betterlectio/cbopfnaegoknpplkngoppmmomppimhkh?authuser=0&hl=en",
  firefox: "https://addons.mozilla.org/en-US/firefox/addon/betterlectio/",
  edge: "https://microsoftedge.microsoft.com/addons/detail/better-lectio/kkchnogenoakbemocdflbkmbibhllggp",
} as const

export type DownloadPlatform = keyof typeof DOWNLOAD_LINKS

const BL_REF_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Play Store URL with Install Referrer so Android can attribute the invite. */
export function androidPlayUrlWithReferrer(cookieId: string | null | undefined): string {
  const base = DOWNLOAD_LINKS.android
  const id = cookieId?.trim() ?? ""
  if (!BL_REF_UUID_RE.test(id)) return base
  const referrer = encodeURIComponent(`bl_ref=${id}`)
  return `${base}&referrer=${referrer}`
}
