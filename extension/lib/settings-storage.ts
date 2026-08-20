import { z } from 'zod';

const SETTINGS_KEY = 'bw-feature-settings';
const SETTINGS_VERSION = 1;

const VisualSettingsSchema = z.object({
  darkMode: z.boolean().default(false),
});

const BehaviorSettingsSchema = z.object({
  hideNativeChrome: z.boolean().default(true),
});

const DEFAULT_VISUAL = VisualSettingsSchema.parse({});
const DEFAULT_BEHAVIOR = BehaviorSettingsSchema.parse({});

export const FeatureSettingsSchema = z.object({
  version: z.number().default(SETTINGS_VERSION),
  visual: VisualSettingsSchema.default(DEFAULT_VISUAL),
  behavior: BehaviorSettingsSchema.default(DEFAULT_BEHAVIOR),
});

export type FeatureSettings = z.infer<typeof FeatureSettingsSchema>;

export const SETTINGS_REQUIRING_RELOAD = ['behavior.hideNativeChrome'] as const;

export function getSettings(): FeatureSettings {
  try {
    const stored = localStorage.getItem(SETTINGS_KEY);
    if (!stored) return FeatureSettingsSchema.parse({});
    const parsed = JSON.parse(stored);
    return FeatureSettingsSchema.parse(parsed);
  } catch (err) {
    console.error('[BetterW4] Error loading settings, using defaults:', err);
    return FeatureSettingsSchema.parse({});
  }
}

export function saveSettings(settings: FeatureSettings): void {
  try {
    const validated = FeatureSettingsSchema.parse({
      ...settings,
      version: SETTINGS_VERSION,
    });
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(validated));
  } catch {
    // Ignore storage errors
  }
}

export function updateSetting<
  K extends keyof Omit<FeatureSettings, 'version'>,
  Field extends keyof FeatureSettings[K],
>(category: K, key: Field, value: FeatureSettings[K][Field]): void {
  const settings = getSettings();
  (settings[category] as Record<string, unknown>)[key as string] = value;
  saveSettings(settings);
}

export function resetSettings(): void {
  try {
    localStorage.removeItem(SETTINGS_KEY);
  } catch {
    // Ignore
  }
}

export function clearAllData(): void {
  try {
    for (const key of Object.keys(localStorage)) {
      if (key.startsWith('bw-')) localStorage.removeItem(key);
    }
  } catch {
    // Ignore
  }
}

export function requiresReload(category: string, key: string): boolean {
  return SETTINGS_REQUIRING_RELOAD.includes(
    `${category}.${key}` as (typeof SETTINGS_REQUIRING_RELOAD)[number],
  );
}

export function applySettingsSideEffects(
  prev: FeatureSettings,
  next: FeatureSettings,
): { changed: boolean; requiresReload: boolean } {
  let changed = false;
  let requiresReloadFlag = false;

  if (prev.visual?.darkMode !== next.visual?.darkMode) {
    changed = true;
    document.documentElement.classList.toggle('dark', Boolean(next.visual?.darkMode));
  }

  for (const path of SETTINGS_REQUIRING_RELOAD) {
    const [category, key] = path.split('.') as [keyof FeatureSettings, string];
    const a = (prev[category] as Record<string, unknown> | undefined)?.[key];
    const b = (next[category] as Record<string, unknown> | undefined)?.[key];
    if (a !== b) {
      requiresReloadFlag = true;
      changed = true;
    }
  }

  return { changed, requiresReload: requiresReloadFlag };
}
