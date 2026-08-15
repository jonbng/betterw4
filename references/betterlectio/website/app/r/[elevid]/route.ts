import { redirect } from "next/navigation"
import type { NextRequest } from "next/server"

const ELEVID_RE = /^[0-9A-Za-z_-]{1,48}$/
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const APP_STORE_URL = "https://apps.apple.com/dk/app/betterlectio/id6761808963"

function isIOS(userAgent: string): boolean {
  return /iPhone|iPad|iPod/i.test(userAgent)
}

function iosLandingHtml(referralUrl: string): string {
  const safeURL = referralUrl.replaceAll("&", "&amp;").replaceAll('"', "&quot;")
  return `<!doctype html>
<html lang="da">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="robots" content="noindex,nofollow">
  <meta name="apple-itunes-app" content="app-id=6761808963, app-clip-bundle-id=dk.echolabs.betterlectio.app.Clip, app-argument=${safeURL}">
  <title>Du er inviteret til BetterLectio</title>
  <style>
    :root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;background:#f4f4f7;color:#111}
    body{margin:0;min-height:100svh;display:grid;place-items:center;padding:24px;box-sizing:border-box;background:radial-gradient(circle at 50% 15%,#dfe8ff 0,transparent 42%),#f4f4f7}
    main{width:min(100%,430px);padding:32px;border-radius:28px;background:rgba(255,255,255,.86);box-shadow:0 24px 70px rgba(35,48,80,.14);backdrop-filter:blur(20px);text-align:center}
    .icon{width:76px;height:76px;margin:auto;border-radius:22px;display:grid;place-items:center;background:#315efb;color:#fff;font-size:34px;font-weight:750;box-shadow:0 12px 26px rgba(49,94,251,.28)}
    h1{font-size:28px;letter-spacing:-.03em;margin:24px 0 10px}p{line-height:1.5;color:#62626a;margin:0 0 26px}
    a{display:block;padding:15px 18px;border-radius:15px;background:#315efb;color:#fff;text-decoration:none;font-weight:700}
    small{display:block;margin-top:16px;color:#85858d}
    @media(prefers-color-scheme:dark){:root{background:#0b0b0e;color:#f6f6f7}body{background:radial-gradient(circle at 50% 15%,#15234f 0,transparent 42%),#0b0b0e}main{background:rgba(27,27,31,.9)}p,small{color:#aaaab2}}
  </style>
</head>
<body><main><div class="icon">B</div><h1>Du er inviteret</h1><p>Åbn BetterLectio App Clip ovenfor, så gemmer vi invitationen sikkert, mens du henter appen.</p><a href="${APP_STORE_URL}">Hent BetterLectio</a><small>Invitationen gælder kun ved din første installation.</small></main></body>
</html>`
}

export async function GET(
  req: NextRequest,
  ctx: { params: Promise<{ elevid: string }> },
) {
  const { elevid } = await ctx.params
  const trimmed = elevid?.trim() ?? ""

  // Anything that isn't a valid-shaped elevid skips the cookie-setting
  // edge function and goes straight to the download page. Better than 404.
  if (!ELEVID_RE.test(trimmed)) {
    redirect("/download")
  }

  // Hand off to the Supabase edge function so the cookie lands on the
  // *.supabase.co domain (where the extension reads it during finalize).
  const supabaseUrl = process.env.SUPABASE_URL
  if (!supabaseUrl) {
    console.error("[r/[elevid]] SUPABASE_URL not set")
    redirect("/download")
  }

  const token = req.nextUrl.searchParams.get("bl_ref")?.trim() ?? ""
  const userAgent = req.headers.get("user-agent") ?? ""

  if (isIOS(userAgent) && UUID_RE.test(token)) {
    return new Response(iosLandingHtml(req.nextUrl.toString()), {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "private, no-store",
        "Referrer-Policy": "no-referrer",
        "X-Robots-Tag": "noindex, nofollow",
      },
    })
  }

  const target = new URL(`${supabaseUrl}/functions/v1/referral-click`)
  target.searchParams.set("ref", trimmed)
  if (isIOS(userAgent)) target.searchParams.set("delivery", "ios")
  redirect(target.toString())
}
