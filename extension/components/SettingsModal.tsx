import { useState } from 'preact/hooks';
import { Github, Info, Palette, Trash2 } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
} from '@/components/ui/sidebar';
import { FeatureToggle } from '@/components/settings/FeatureToggle';
import { SettingsSection } from '@/components/settings/SettingsSection';
import { THEME_PRESETS, type ThemePresetId } from '@/lib/theme-presets';
import {
  applyThemePreferenceToDocument,
  getThemePreference,
  saveThemePreference,
} from '@/lib/theme-storage';
import {
  applySettingsSideEffects,
  clearAllData,
  getSettings,
  requiresReload,
  resetSettings,
  saveSettings,
  type FeatureSettings,
} from '@/lib/settings-storage';
import { cn } from '@/lib/utils';

interface SettingsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

type SectionId = 'appearance' | 'about';

function getBrowserInfo(): string {
  const ua = navigator.userAgent;
  if (ua.includes('Firefox')) return `Firefox ${ua.match(/Firefox\/(\d+)/)?.[1] ?? ''}`.trim();
  if (ua.includes('Edg/')) return `Edge ${ua.match(/Edg\/(\d+)/)?.[1] ?? ''}`.trim();
  if (ua.includes('Chrome')) return `Chrome ${ua.match(/Chrome\/(\d+)/)?.[1] ?? ''}`.trim();
  if (ua.includes('Safari')) return `Safari ${ua.match(/Version\/(\d+)/)?.[1] ?? ''}`.trim();
  return 'Unknown browser';
}

export function SettingsModal({ open, onOpenChange }: SettingsModalProps) {
  const [section, setSection] = useState<SectionId>('appearance');
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
    const { requiresReload: reload } = applySettingsSideEffects(prev, next);
    if (reload) toast.message('Reload the page to apply this setting');
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl overflow-hidden p-0 sm:max-w-3xl">
        <DialogHeader className="sr-only">
          <DialogTitle>Settings</DialogTitle>
          <DialogDescription>BetterW4 appearance and about</DialogDescription>
        </DialogHeader>
        <SidebarProvider className="settings-modal min-h-[28rem]">
          <Sidebar className="border-r">
            <SidebarContent>
              <SidebarGroup>
                <SidebarGroupContent>
                  <SidebarMenu>
                    <SidebarMenuItem>
                      <SidebarMenuButton isActive={section === 'appearance'} onClick={() => setSection('appearance')}>
                        <Palette />
                        <span>Appearance</span>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                    <SidebarMenuItem>
                      <SidebarMenuButton isActive={section === 'about'} onClick={() => setSection('about')}>
                        <Info />
                        <span>About</span>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  </SidebarMenu>
                </SidebarGroupContent>
              </SidebarGroup>
            </SidebarContent>
          </Sidebar>

          <main className="settings-modal-main flex-1">
            <div className="settings-modal-scroll p-6">
              {section === 'appearance' && (
                <div className="space-y-6">
                  <SettingsSection title="Theme" description="Dark mode and colour preset. All colours are OKLCH.">
                    <FeatureToggle
                      id="dark-mode"
                      label="Dark mode"
                      description="Use a dark surface palette."
                      enabled={settings.visual.darkMode}
                      onChange={(enabled) => update('visual', 'darkMode', enabled)}
                    />
                    <FeatureToggle
                      id="hide-chrome"
                      label="Hide native W4 chrome"
                      description="Replace W4's header, top menu and sdmenu with the BetterW4 sidebar."
                      enabled={settings.behavior.hideNativeChrome}
                      onChange={(enabled) => update('behavior', 'hideNativeChrome', enabled)}
                      requiresReload={requiresReload('behavior', 'hideNativeChrome')}
                    />
                  </SettingsSection>

                  <div className="space-y-3">
                    <h3 className="text-sm font-semibold">Colour preset</h3>
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
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
                          <span
                            className="size-4 rounded-full"
                            style={{ background: preset.colors.light.primary }}
                          />
                          {preset.label}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {section === 'about' && (
                <div className="space-y-6">
                  <div>
                    <h3 className="text-sm font-semibold">BetterW4</h3>
                    <p className="mt-1 text-sm text-muted-foreground">
                      Unofficial browser extension for W4 at UWC Red Cross Nordic. Not made by,
                      endorsed by, or affiliated with the college.
                    </p>
                  </div>
                  <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
                    <dt className="text-muted-foreground">Version</dt>
                    <dd>{version}</dd>
                    <dt className="text-muted-foreground">Browser</dt>
                    <dd>{getBrowserInfo()}</dd>
                  </dl>
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
                        resetSettings();
                        clearAllData();
                        toast.success('Cleared BetterW4 data');
                        window.location.reload();
                      }}
                    >
                      <Trash2 className="size-4" />
                      Clear local data
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </main>
        </SidebarProvider>
      </DialogContent>
    </Dialog>
  );
}
