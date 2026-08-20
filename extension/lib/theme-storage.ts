import {
  DEFAULT_THEME_PREFERENCE,
  THEME_PRESETS,
  type ThemePreference,
  type ThemePresetId,
} from '@/lib/theme-presets';

const THEME_KEY = 'bw-theme-v1';

function isValidThemeId(value: unknown): value is ThemePresetId {
  return typeof value === 'string' && THEME_PRESETS.some((preset) => preset.id === value);
}

function normalizeThemePreference(value: unknown): ThemePreference {
  const parsed = value as Partial<ThemePreference> | null | undefined;
  return {
    themeId: isValidThemeId(parsed?.themeId)
      ? parsed.themeId
      : DEFAULT_THEME_PREFERENCE.themeId,
  };
}

export function getThemePreference(): ThemePreference {
  try {
    const stored = localStorage.getItem(THEME_KEY);
    if (!stored) return DEFAULT_THEME_PREFERENCE;
    return normalizeThemePreference(JSON.parse(stored));
  } catch {
    return DEFAULT_THEME_PREFERENCE;
  }
}

export function saveThemePreference(preference: ThemePreference): void {
  try {
    localStorage.setItem(THEME_KEY, JSON.stringify(normalizeThemePreference(preference)));
  } catch {
    // Ignore storage quota/private mode errors.
  }
}

export function applyThemePreferenceToDocument(preference: ThemePreference): void {
  document.documentElement.dataset.bwTheme = preference.themeId;
}

export function applyTheme(): ThemePreference {
  const preference = getThemePreference();
  applyThemePreferenceToDocument(preference);
  return preference;
}
