import { z } from 'zod';

const SETTINGS_KEY = 'bw-feature-settings';
const SETTINGS_VERSION = 1;

const VisualSettingsSchema = z.object({
  darkMode: z.boolean().default(false),
});

const DEFAULT_VISUAL = VisualSettingsSchema.parse({});

export const FeatureSettingsSchema = z.object({
  version: z.number().default(SETTINGS_VERSION),
  visual: VisualSettingsSchema.default(DEFAULT_VISUAL),
});

export type FeatureSettings = z.infer<typeof FeatureSettingsSchema>;

export const SETTINGS_REQUIRING_RELOAD: string[] = [];

export function getSettings(): FeatureSettings {
  try {
    const stored = localStorage.getItem(SETTINGS_KEY);
    if (!stored) return FeatureSettingsSchema.parse({});
    return FeatureSettingsSchema.parse(JSON.parse(stored));
  } catch (err) {
    console.error('[BetterW4] Error loading settings, using defaults:', err);
    return FeatureSettingsSchema.parse({});
  }
}

export function saveSettings(settings: FeatureSettings): void {
  try {
    localStorage.setItem(
      SETTINGS_KEY,
      JSON.stringify(FeatureSettingsSchema.parse({ ...settings, version: SETTINGS_VERSION })),
    );
  } catch {
    // Ignore
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

export function requiresReload(_category: string, _key: string): boolean {
  return false;
}

export function applySettingsSideEffects(
  prev: FeatureSettings,
  next: FeatureSettings,
): { changed: boolean; requiresReload: boolean } {
  let changed = false;
  if (prev.visual?.darkMode !== next.visual?.darkMode) {
    changed = true;
    document.documentElement.classList.toggle('dark', Boolean(next.visual?.darkMode));
  }
  return { changed, requiresReload: false };
}
