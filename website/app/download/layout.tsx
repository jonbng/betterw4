import type { Metadata } from "next"

export const metadata: Metadata = {
  title: "Get BetterW4",
  description:
    "Get BetterW4 free for Chrome, Firefox, Edge, iOS and Android. A modern interface for W4 — faster, cleaner and without a new account.",
  alternates: { canonical: "/download" },
  openGraph: {
    title: "Get BetterW4",
    description:
      "Get BetterW4 free for Chrome, Firefox, Edge, iOS and Android. Faster, cleaner and without a new account.",
    url: "/download",
  },
  twitter: {
    title: "Get BetterW4",
    description:
      "Get BetterW4 free for Chrome, Firefox, Edge, iOS and Android. Faster, cleaner and without a new account.",
  },
}

export default function DownloadLayout({ children }: { children: React.ReactNode }) {
  return children
}
