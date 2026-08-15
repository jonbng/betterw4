import { createServerClient } from "@supabase/ssr"
import { NextResponse, type NextRequest } from "next/server"

/**
 * Refresh Supabase SSR auth cookies on authed marketing routes so access
 * tokens don't silently expire between visits to /roadmap.
 */
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: { headers: request.headers },
  })

  const url = process.env.SUPABASE_URL
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anonKey) {
    // Don't break the public site if auth env isn't configured yet.
    return response
  }

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value)
        }
        response = NextResponse.next({
          request: { headers: request.headers },
        })
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options)
        }
      },
    },
  })

  // Touch the session so expired access tokens are refreshed and rewritten.
  await supabase.auth.getUser()

  return response
}

export const config = {
  matcher: ["/roadmap", "/roadmap/:path*", "/auth/:path*"],
}
