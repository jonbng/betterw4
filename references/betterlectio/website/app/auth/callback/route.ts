import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"
import { NextResponse, type NextRequest } from "next/server"

import { LOGIN_STATE_COOKIE } from "@/lib/auth-constants"

function completionResponse(
  status: "ok" | "error",
  reason?: string,
): NextResponse {
  const destination =
    status === "ok"
      ? "/roadmap?login=ok"
      : `/roadmap?login=error&reason=${encodeURIComponent(reason ?? "unknown")}`
  const payload = JSON.stringify({
    source: "bl-login",
    status,
    reason: reason ?? null,
  }).replaceAll("<", "\\u003c")
  const safeDestination = JSON.stringify(destination).replaceAll("<", "\\u003c")

  return new NextResponse(
    `<!doctype html>
<html lang="da">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>BetterLectio login</title>
    <style>
      * { box-sizing: border-box }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center;
        font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: #111827; background: #fff }
      main { display: flex; flex-direction: column; align-items: center; gap: 18px; text-align: center; padding: 32px }
      strong { font-size: 20px; letter-spacing: -.03em }
      .spinner { width: 30px; height: 30px; border: 3px solid #e5e7eb;
        border-top-color: #111827; border-radius: 999px; animation: spin .7s linear infinite }
      p { margin: 0; color: #4b5563; font-size: 15px; font-weight: 600 }
      @keyframes spin { to { transform: rotate(360deg) } }
    </style>
  </head>
  <body>
    <main>
      <strong>BetterLectio</strong>
      <div class="spinner" aria-hidden="true"></div>
      <p>${status === "ok" ? "Login gennemført…" : "Login mislykkedes…"}</p>
    </main>
    <script>
      const payload = ${payload};
      const destination = ${safeDestination};
      if (window.opener && !window.opener.closed) {
        try { window.opener.postMessage(payload, window.location.origin); } catch {}
        try { window.opener.location.reload(); } catch {}
        setTimeout(() => window.close(), 50);
      } else {
        window.location.replace(destination);
      }
    </script>
  </body>
</html>`,
    {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  )
}

/**
 * Consume the extension-minted magic-link token_hash and establish a
 * Supabase SSR session on betterlectio.dk.
 */
export async function GET(req: NextRequest) {
  const url = req.nextUrl
  const tokenHash = url.searchParams.get("token_hash")
  const type = url.searchParams.get("type")
  const state = url.searchParams.get("state")

  if (!tokenHash || type !== "magiclink" || !state) {
    return completionResponse("error", "missing_params")
  }

  const store = await cookies()
  const expected = store.get(LOGIN_STATE_COOKIE)?.value

  if (!expected || expected !== state) {
    const response = completionResponse("error", "invalid_state")
    response.cookies.delete(LOGIN_STATE_COOKIE)
    return response
  }

  const supabaseUrl = process.env.SUPABASE_URL
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!supabaseUrl || !anonKey) {
    console.error("[auth/callback] missing SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY")
    const response = completionResponse("error", "config")
    response.cookies.delete(LOGIN_STATE_COOKIE)
    return response
  }

  const response = completionResponse("ok")
  const supabase = createServerClient(supabaseUrl, anonKey, {
    cookies: {
      getAll() {
        return store.getAll()
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options)
        }
      },
    },
  })

  const { error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: "magiclink",
  })

  if (error) {
    console.error("[auth/callback] verifyOtp failed", error.message)
    const errorResponse = completionResponse("error", "verify_failed")
    errorResponse.cookies.delete(LOGIN_STATE_COOKIE)
    return errorResponse
  }

  response.cookies.delete(LOGIN_STATE_COOKIE)
  return response
}
