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

/** First text node of `#user-panel .right` is `Welcome, {name}` — before <br> and the links. */
export function parseWelcomeName(doc: Document = document): string | null {
  const panel = doc.querySelector('#user-panel .right');
  if (!panel) return null;
  for (const node of Array.from(panel.childNodes)) {
    if (node.nodeType !== Node.TEXT_NODE) continue;
    const text = (node.textContent ?? '').replace(/\s+/g, ' ').trim();
    const match = text.match(/^Welcome,\s*(.+)$/i);
    if (match?.[1]) return match[1].trim();
  }
  return null;
}

/**
 * Own UWC id comes from Home's `#hello` public-profile link.
 * Do not scrape birthday thumbs or other people links — those are other students.
 */
export function parseOwnUwcId(doc: Document = document): string | null {
  const hello = doc.querySelector('#hello a[href*="uwc_id="]');
  if (!hello) return null;
  try {
    return new URL((hello as HTMLAnchorElement).href, window.location.origin).searchParams.get('uwc_id');
  } catch {
    return null;
  }
}

export function photoUrlForUwcId(uwcId: string): string {
  return new URL(`/files/user_photos/${uwcId}_thumb.jpg`, window.location.origin).href;
}

export function extractProfileFromDocument(doc: Document = document): UserProfile | null {
  const fullName = parseWelcomeName(doc);
  if (!fullName) return null;

  const cached = getCachedProfile();
  const uwcId = parseOwnUwcId(doc) ?? cached?.uwcId ?? null;

  return {
    name: fullName.split(' ')[0] ?? fullName,
    fullName,
    uwcId,
    pictureUrl: uwcId ? photoUrlForUwcId(uwcId) : cached?.pictureUrl ?? null,
    cachedAt: Date.now(),
  };
}

export function updateProfileCache(doc: Document = document): UserProfile | null {
  const extracted = extractProfileFromDocument(doc);
  if (extracted) saveProfile(extracted);
  return extracted ?? getCachedProfile();
}

export function updateLoginState(doc: Document = document): LoginState {
  const loggedIn = Boolean(
    doc.querySelector('#user-panel') && !doc.querySelector('input[name="LoginForm[username]"]'),
  );
  const state: LoginState = { isLoggedIn: loggedIn, lastChecked: Date.now() };
  saveLoginState(state);
  return state;
}
