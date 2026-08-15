import { randomUUID } from "node:crypto"

import { cookies } from "next/headers"
import { NextResponse } from "next/server"

import { LOGIN_STATE_COOKIE } from "@/lib/auth-constants"

const STATE_MAX_AGE = 60 * 5 // 5 minutes
// Prefer login_list over `/` — Lectio's homepage can strip query params on redirect.
const LECTIO_LOGIN_BASE = "https://www.lectio.dk/lectio/login_list.aspx"

/**
 * Start "Log ind med BetterLectio": set a CSRF state cookie, then send the
 * user to Lectio with ?bl_login=STATE. The extension captures that param and
 * eventually redirects back to /auth/callback.
 */
export async function GET() {
  const state = randomUUID()
  const store = await cookies()
  store.set(LOGIN_STATE_COOKIE, state, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: STATE_MAX_AGE,
  })

  const lectio = new URL(LECTIO_LOGIN_BASE)
  lectio.searchParams.set("bl_login", state)

  return NextResponse.redirect(lectio.toString(), 302)
}
