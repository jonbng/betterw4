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

export function isLoginRoute(route: string | null = getRoute()): boolean {
  return (
    route === 'site/login' ||
    route === 'site/verify2fa' ||
    route === 'site/otp' ||
    route === 'site/forgotpass'
  );
}

export function isLoginPage(doc: Document = document, url: URL | Location = window.location): boolean {
  if (isLoginRoute(getRoute(url))) return true;
  if (doc.querySelector('input[name="LoginForm[username]"]')) return true;
  if (/login site/i.test(doc.title)) return true;
  return false;
}
