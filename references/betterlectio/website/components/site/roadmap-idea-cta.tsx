"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useCallback, useEffect, useRef, useState, useTransition } from "react"

import { signOutWebsite, submitRoadmapIdea } from "@/app/roadmap/actions"
import type { BlLoginMessage } from "@/components/site/login-popup-closer"
import { siteButton } from "@/components/site/styles"
import { cn } from "@/lib/utils"

type Props = {
  signedIn: boolean
  displayName: string | null
  loginStatus: "ok" | "error" | null
  loginReason: string | null
}

function loginReasonMessage(reason: string | null | undefined): string {
  switch (reason) {
    case "invalid_state":
      return "Login-sessionen udløb. Prøv igen."
    case "verify_failed":
      return "Kunne ikke bekræfte login."
    case "missing_params":
      return "Login-svaret var ufuldstændigt. Prøv igen."
    case "config":
      return "Login er midlertidigt utilgængeligt."
    default:
      return "Prøv igen."
  }
}

export function RoadmapIdeaCta({
  signedIn,
  displayName,
  loginStatus,
  loginReason,
}: Props) {
  if (signedIn) {
    return <SignedInIdeaForm displayName={displayName} />
  }
  return (
    <SignedOutLogin
      loginStatus={loginStatus}
      loginReason={loginReason}
    />
  )
}

function SignedOutLogin({
  loginStatus,
  loginReason,
}: {
  loginStatus: "ok" | "error" | null
  loginReason: string | null
}) {
  const router = useRouter()
  const [waiting, setWaiting] = useState(false)
  const [showInstallHint, setShowInstallHint] = useState(false)
  const [messageError, setMessageError] = useState<string | null>(null)
  const popupRef = useRef<Window | null>(null)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pollRef = useRef<number | null>(null)

  const urlError =
    loginStatus === "error" ? loginReasonMessage(loginReason) : null
  const displayError = messageError ?? urlError

  const clearWaitingTimers = useCallback(() => {
    if (timerRef.current) {
      clearTimeout(timerRef.current)
      timerRef.current = null
    }
    if (pollRef.current != null) {
      window.clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  useEffect(() => {
    return () => {
      clearWaitingTimers()
    }
  }, [clearWaitingTimers])

  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== window.location.origin) return
      const data = event.data as BlLoginMessage | null
      if (!data || data.source !== "bl-login") return

      clearWaitingTimers()
      setWaiting(false)
      if (data.status === "error") {
        setMessageError(loginReasonMessage(data.reason))
      } else {
        setMessageError(null)
      }
      router.refresh()
    }
    window.addEventListener("message", onMessage)
    return () => window.removeEventListener("message", onMessage)
  }, [clearWaitingTimers, router])

  const startLogin = useCallback(() => {
    setWaiting(true)
    setShowInstallHint(false)
    setMessageError(null)
    clearWaitingTimers()

    // Fresh name each time so we don't reuse a stale popup where Chrome
    // skipped content-script injection.
    const popup = window.open(
      "/auth/login",
      `bl-login-${Date.now()}`,
      "popup=yes,width=520,height=780",
    )

    if (!popup) {
      window.location.href = "/auth/login"
      return
    }

    popupRef.current = popup
    try {
      popup.focus()
    } catch {
      // Ignore.
    }
    timerRef.current = setTimeout(() => {
      setShowInstallHint(true)
    }, 15_000)

    pollRef.current = window.setInterval(() => {
      if (popup.closed) {
        clearWaitingTimers()
        setWaiting(false)
        router.refresh()
      }
    }, 500)
  }, [clearWaitingTimers, router])

  return (
    <div className="mx-auto mt-16 max-w-[620px] rounded-[24px] border border-line bg-grey/50 p-8 text-center">
      <h2 className="text-[20px] font-extrabold tracking-[-0.02em] text-ink">
        Mangler du noget?
      </h2>
      <p className="mx-auto mt-2 max-w-[46ch] text-sm leading-[1.5] text-ink-muted">
        Log ind med BetterLectio (browser-udvidelsen) for at sende en idé.
        Den ender i vores feedback-kø, og på roadmappet, hvis vi tager den med.
      </p>

      {displayError ? (
        <p className="mt-4 text-sm font-medium text-red-700">
          Login mislykkedes. {displayError}
        </p>
      ) : null}

      <div className="mt-6 flex flex-wrap justify-center gap-3">
        <button
          type="button"
          onClick={startLogin}
          disabled={waiting}
          className={siteButton("primary")}
        >
          {waiting ? "Logger ind…" : "Log ind med BetterLectio"}
        </button>
      </div>

      <p className="mx-auto mt-4 max-w-[42ch] text-xs leading-[1.45] text-ink-muted">
        Kræver at BetterLectio-udvidelsen er installeret, og at du er logget
        ind på Lectio.{" "}
        <Link href="/download" className="font-bold underline underline-offset-2">
          Installér
        </Link>
      </p>

      {showInstallHint ? (
        <p className="mx-auto mt-3 max-w-[42ch] text-sm text-ink">
          Har du ikke udvidelsen endnu?{" "}
          <Link href="/download" className="font-bold underline underline-offset-2">
            Installér BetterLectio
          </Link>
        </p>
      ) : null}
    </div>
  )
}

function SignedInIdeaForm({ displayName }: { displayName: string | null }) {
  const router = useRouter()
  const [title, setTitle] = useState("")
  const [message, setMessage] = useState("")
  const [status, setStatus] = useState<"idle" | "ok" | "error">("idle")
  const [error, setError] = useState<string | null>(null)
  const [pending, start] = useTransition()

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    setStatus("idle")
    setError(null)
    start(async () => {
      const res = await submitRoadmapIdea({ title, message })
      if (!res.ok) {
        setStatus("error")
        setError(
          res.error === "rate_limited"
            ? "Du har sendt for mange ønsker. Prøv igen om lidt."
            : res.error === "not_signed_in"
              ? "Du er ikke logget ind længere. Log ind igen."
              : "Kunne ikke sende. Prøv igen.",
        )
        return
      }
      setStatus("ok")
      setTitle("")
      setMessage("")
    })
  }

  const onSignOut = () => {
    start(async () => {
      await signOutWebsite()
      router.refresh()
    })
  }

  return (
    <div className="mx-auto mt-16 max-w-[620px] rounded-[24px] border border-line bg-grey/50 p-8">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-[20px] font-extrabold tracking-[-0.02em] text-ink">
            Send en idé
          </h2>
          <p className="mt-1 text-sm text-ink-muted">
            {displayName
              ? `Logget ind som ${displayName}`
              : "Du er logget ind med BetterLectio"}
          </p>
        </div>
        <button
          type="button"
          onClick={onSignOut}
          disabled={pending}
          className="text-xs font-semibold text-ink-muted underline-offset-2 hover:underline"
        >
          Log ud
        </button>
      </div>

      {status === "ok" ? (
        <p className="mt-5 rounded-2xl border border-line bg-white px-4 py-3 text-sm font-medium text-ink">
          Tak, vi kigger på det. Hvis vi tager ideen med, dukker den op på
          roadmappet.
        </p>
      ) : (
        <form onSubmit={onSubmit} className="mt-5 space-y-3.5 text-left">
          <label className="block">
            <span className="mb-1.5 block text-xs font-semibold text-ink-muted">
              Titel (valgfri)
            </span>
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              maxLength={200}
              disabled={pending}
              placeholder="Kort overskrift"
              className="w-full rounded-xl border border-line bg-white px-3.5 py-2.5 text-sm text-ink outline-none focus:border-ink/30"
            />
          </label>
          <label className="block">
            <span className="mb-1.5 block text-xs font-semibold text-ink-muted">
              Din idé
            </span>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              required
              rows={4}
              maxLength={4000}
              disabled={pending}
              placeholder="Hvad mangler, eller hvad kunne være bedre?"
              className="w-full resize-y rounded-xl border border-line bg-white px-3.5 py-2.5 text-sm leading-[1.5] text-ink outline-none focus:border-ink/30"
            />
          </label>
          {status === "error" && error ? (
            <p className="text-sm font-medium text-red-700">{error}</p>
          ) : null}
          <button
            type="submit"
            disabled={pending || !message.trim()}
            className={cn(siteButton("primary"), "w-full min-[480px]:w-auto")}
          >
            {pending ? "Sender…" : "Send idé"}
          </button>
        </form>
      )}
    </div>
  )
}
