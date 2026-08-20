const PROFILE_CACHE_KEY = 'bw-user-profile';
const LOGIN_STATE_KEY = 'bw-login-state';

export interface LoginState {
  isLoggedIn: boolean;
  lastChecked: number;
}

export interface UserProfile {
  name: string;
  fullName: string;
  uwcId: string | null;
  pictureUrl: string | null;
  cachedAt: number;
}

export function getCachedProfile(): UserProfile | null {
  try {
    const stored = localStorage.getItem(PROFILE_CACHE_KEY);
    if (!stored) return null;
    return JSON.parse(stored) as UserProfile;
  } catch {
    return null;
  }
}

export function saveProfile(profile: UserProfile): void {
  try {
    localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(profile));
  } catch {
    // Ignore
  }
}

export function getCachedLoginState(): LoginState | null {
  try {
    const stored = localStorage.getItem(LOGIN_STATE_KEY);
    if (!stored) return null;
    return JSON.parse(stored) as LoginState;
  } catch {
    return null;
  }
}

export function saveLoginState(state: LoginState): void {
  try {
    localStorage.setItem(LOGIN_STATE_KEY, JSON.stringify(state));
  } catch {
    // Ignore
  }
}

export function clearLoginState(): void {
  try {
    localStorage.removeItem(LOGIN_STATE_KEY);
    localStorage.removeItem(PROFILE_CACHE_KEY);
  } catch {
    // Ignore
  }
}

function parseWelcomeName(text: string | null | undefined): string | null {
  if (!text) return null;
  const match = text.replace(/\s+/g, ' ').trim().match(/^Welcome,\s*(.+)$/i);
  return match?.[1]?.trim() || null;
}

function parseUwcId(doc: Document): string | null {
  const hrefs = Array.from(doc.querySelectorAll<HTMLAnchorElement>('a[href*="uwc_id="]'));
  for (const anchor of hrefs) {
    try {
      const id = new URL(anchor.href, window.location.origin).searchParams.get('uwc_id');
      if (id) return id;
    } catch {
      // Ignore malformed hrefs
    }
  }
  const img = doc.querySelector<HTMLImageElement>('img[src*="_thumb."], img[src*="/photos/"]');
  const src = img?.getAttribute('src') ?? '';
  const fileMatch = src.match(/\/([a-z]{2}\d{2}[a-z]+)_thumb\./i);
  return fileMatch?.[1] ?? null;
}

export function extractProfileFromDocument(doc: Document = document): UserProfile | null {
  const panel = doc.querySelector('#user-panel');
  const fullName = parseWelcomeName(panel?.textContent);
  if (!fullName) return null;

  const pictureUrl =
    doc.querySelector<HTMLImageElement>('#user-panel img, .user-photo img, img[src*="_thumb."]')
      ?.src ?? null;

  return {
    name: fullName.split(' ')[0] ?? fullName,
    fullName,
    uwcId: parseUwcId(doc),
    pictureUrl,
    cachedAt: Date.now(),
  };
}

export function updateProfileCache(doc: Document = document): UserProfile | null {
  const extracted = extractProfileFromDocument(doc);
  if (extracted) saveProfile(extracted);
  return extracted ?? getCachedProfile();
}

export function updateLoginState(doc: Document = document): LoginState {
  const loggedIn = Boolean(doc.querySelector('#user-panel') && !doc.querySelector('input[name="LoginForm[username]"]'));
  const state: LoginState = { isLoggedIn: loggedIn, lastChecked: Date.now() };
  saveLoginState(state);
  if (!loggedIn) {
    // Keep the last known profile so the login screen can greet by name.
  }
  return state;
}
