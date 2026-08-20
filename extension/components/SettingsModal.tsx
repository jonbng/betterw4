import { useState } from 'preact/hooks';
import { Github, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { FeatureToggle } from '@/components/settings/FeatureToggle';
import { SettingsSection } from '@/components/settings/SettingsSection';
import { THEME_PRESETS, type ThemePresetId } from '@/lib/theme-presets';
import {
  applyThemePreferenceToDocument,
  getThemePreference,
  saveThemePreference,
} from '@/lib/theme-storage';
import { armBypass } from '@/lib/bypass-redesigns';
import {
  applySettingsSideEffects,
  clearAllData,
  getSettings,
  resetSettings,
  saveSettings,
  type FeatureSettings,
} from '@/lib/settings-storage';
import { cn } from '@/lib/utils';

interface SettingsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function SettingsModal({ open, onOpenChange }: SettingsModalProps) {
  const [settings, setSettings] = useState<FeatureSettings>(() => getSettings());
  const [themeId, setThemeId] = useState<ThemePresetId>(() => getThemePreference().themeId);
  const version = browser.runtime.getManifest().version;

  const update = <
    K extends keyof Omit<FeatureSettings, 'version'>,
    Field extends keyof FeatureSettings[K],
  >(
    category: K,
    key: Field,
    value: FeatureSettings[K][Field],
  ) => {
    const prev = settings;
    const next = {
      ...prev,
      [category]: { ...(prev[category] as object), [key]: value },
    } as FeatureSettings;
    setSettings(next);
    saveSettings(next);
    applySettingsSideEffects(prev, next);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>BetterW4</DialogTitle>
          <DialogDescription>Appearance for the W4 interface. Navigation stays W4’s.</DialogDescription>
        </DialogHeader>

        <div className="space-y-6">
          <SettingsSection title="Theme">
            <FeatureToggle
              id="dark-mode"
              label="Dark mode"
              description="Use a dark surface palette."
              enabled={settings.visual.darkMode}
              onChange={(enabled) => update('visual', 'darkMode', enabled)}
            />
          </SettingsSection>

          <div className="space-y-2">
            <h3 className="text-sm font-semibold">Colour</h3>
            <div className="grid grid-cols-2 gap-2">
              {THEME_PRESETS.map((preset) => (
                <button
                  key={preset.id}
                  type="button"
                  onClick={() => {
                    setThemeId(preset.id);
                    saveThemePreference({ themeId: preset.id });
                    applyThemePreferenceToDocument({ themeId: preset.id });
                  }}
                  className={cn(
                    'flex items-center gap-2 rounded-lg border px-3 py-2 text-left text-sm',
                    themeId === preset.id ? 'border-primary ring-2 ring-ring/40' : 'border-border',
                  )}
                >
                  <span className="size-4 rounded-full" style={{ background: preset.colors.light.primary }} />
                  {preset.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex flex-wrap gap-2">
            <Button asChild variant="outline" size="sm">
              <a href="https://github.com/jonbng/betterw4" target="_blank" rel="noreferrer">
                <Github className="size-4" />
                Source
              </a>
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                armBypass();
                window.location.reload();
              }}
            >
              Show original W4
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                resetSettings();
                clearAllData();
                toast.success('Cleared BetterW4 data');
                window.location.reload();
              }}
            >
              <Trash2 className="size-4" />
              Clear data
            </Button>
          </div>

          <p className="text-xs text-muted-foreground">v{version} · unofficial</p>
        </div>
      </DialogContent>
    </Dialog>
  );
}
