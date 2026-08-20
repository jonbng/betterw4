export const W4_ORIGIN = 'https://w4.uwcrcn.no';
export const W4_HOST = 'w4.uwcrcn.no';

/** Yii `r=` value from the current (or given) URL, e.g. `site/login`. */
export function getRoute(url: URL | Location = window.location): string | null {
  const raw = new URL(url.href).searchParams.get('r');
  return raw?.trim() || null;
}

export function isW4Host(url: URL | Location = window.location): boolean {
  return url.host === W4_HOST;
}

/** Absolute W4 URL for a Yii route. Extra query params are appended after `r`. */
export function w4Url(route: string, params?: Record<string, string>): string {
  const url = new URL('/index.php', W4_ORIGIN);
  url.searchParams.set('r', route);
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      url.searchParams.set(key, value);
    }
  }
  return url.href;
}

export function routeMatches(route: string | null, prefix: string): boolean {
  if (!route) return false;
  return route === prefix || route.startsWith(`${prefix}/`) || route.startsWith(`${prefix}&`);
}

export function isOtpRoute(route: string | null = getRoute()): boolean {
  if (!route) return false;
  const value = route.toLowerCase();
  if (value === 'site/verify2fa' || value === 'site/otp') return true;
  if (!value.startsWith('site/')) return false;
  return value.includes('otp') || value.includes('2fa') || value.includes('verify');
}

export function isLoginRoute(route: string | null = getRoute()): boolean {
  const value = route?.toLowerCase() ?? null;
  return value === 'site/login' || value === 'site/forgotpass' || isOtpRoute(value);
}

export function isLoginPage(doc: Document = document, url: URL | Location = window.location): boolean {
  if (isLoginRoute(getRoute(url))) return true;
  if (doc.querySelector('#otp-form, input[name^="OtpModel"], input[name="LoginForm[username]"]')) {
    return true;
  }
  if (/login site|additional verification/i.test(doc.title)) return true;
  return false;
}
