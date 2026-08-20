const BYPASS_KEY = 'bw-bypass-redesigns';

export const BYPASS_DURATION_MS = 5 * 60 * 1000;

interface BypassState {
  activatedAt: number;
}

function readState(): BypassState | null {
  try {
    const raw = localStorage.getItem(BYPASS_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<BypassState> | null;
    if (!parsed || typeof parsed.activatedAt !== 'number') return null;
    return { activatedAt: parsed.activatedAt };
  } catch {
    return null;
  }
}

function writeState(state: BypassState): void {
  try {
    localStorage.setItem(BYPASS_KEY, JSON.stringify(state));
  } catch {
    // Non-critical
  }
}

function clearState(): void {
  try {
    localStorage.removeItem(BYPASS_KEY);
  } catch {
    // Non-critical
  }
}

export function isBypassActive(): boolean {
  const state = readState();
  if (!state) return false;
  if (Date.now() - state.activatedAt >= BYPASS_DURATION_MS) {
    clearState();
    return false;
  }
  return true;
}

export function armBypass(): void {
  writeState({ activatedAt: Date.now() });
}

export function disableBypass(): void {
  clearState();
}

export function getBypassRemainingMs(): number {
  const state = readState();
  if (!state) return 0;
  const remaining = BYPASS_DURATION_MS - (Date.now() - state.activatedAt);
  return remaining > 0 ? remaining : 0;
}
