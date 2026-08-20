export const THEME_PRESETS = [
  {
    id: 'default',
    label: 'Fjord',
    colors: {
      light: {
        bg: 'oklch(0.985 0.006 210)',
        sidebar: 'oklch(0.97 0.01 210)',
        primary: 'oklch(0.48 0.12 210)',
        accent: 'oklch(0.94 0.02 210)',
      },
      dark: {
        bg: 'oklch(0.17 0.012 220)',
        sidebar: 'oklch(0.14 0.012 220)',
        primary: 'oklch(0.72 0.1 210)',
        accent: 'oklch(0.24 0.02 220)',
      },
    },
  },
  {
    id: 'graphite',
    label: 'Graphite',
    colors: {
      light: {
        bg: 'oklch(0.965 0.003 255)',
        sidebar: 'oklch(0.95 0.005 255)',
        primary: 'oklch(0.62 0.16 235)',
        accent: 'oklch(0.92 0.006 255)',
      },
      dark: {
        bg: 'oklch(0.13 0.003 255)',
        sidebar: 'oklch(0.11 0.003 255)',
        primary: 'oklch(0.72 0.13 235)',
        accent: 'oklch(0.2 0.004 255)',
      },
    },
  },
  {
    id: 'sand',
    label: 'Sand',
    colors: {
      light: {
        bg: 'oklch(0.982 0.006 90)',
        sidebar: 'oklch(0.965 0.012 90)',
        primary: 'oklch(0.72 0.16 85)',
        accent: 'oklch(0.92 0.012 90)',
      },
      dark: {
        bg: 'oklch(0.14 0.004 80)',
        sidebar: 'oklch(0.12 0.004 80)',
        primary: 'oklch(0.78 0.13 85)',
        accent: 'oklch(0.21 0.005 80)',
      },
    },
  },
  {
    id: 'forest',
    label: 'Pine',
    colors: {
      light: {
        bg: 'oklch(0.98 0.006 160)',
        sidebar: 'oklch(0.96 0.012 160)',
        primary: 'oklch(0.45 0.1 160)',
        accent: 'oklch(0.92 0.016 160)',
      },
      dark: {
        bg: 'oklch(0.13 0.005 160)',
        sidebar: 'oklch(0.11 0.005 160)',
        primary: 'oklch(0.7 0.13 160)',
        accent: 'oklch(0.2 0.006 160)',
      },
    },
  },
  {
    id: 'ember',
    label: 'Ember',
    colors: {
      light: {
        bg: 'oklch(0.984 0.008 30)',
        sidebar: 'oklch(0.964 0.016 30)',
        primary: 'oklch(0.55 0.18 25)',
        accent: 'oklch(0.93 0.02 30)',
      },
      dark: {
        bg: 'oklch(0.16 0.01 25)',
        sidebar: 'oklch(0.13 0.01 25)',
        primary: 'oklch(0.7 0.16 25)',
        accent: 'oklch(0.23 0.02 25)',
      },
    },
  },
] as const;

export type ThemePresetId = (typeof THEME_PRESETS)[number]['id'];

export interface ThemePreference {
  themeId: ThemePresetId;
}

export const DEFAULT_THEME_PREFERENCE: ThemePreference = {
  themeId: 'default',
};
