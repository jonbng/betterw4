import { useEffect, useState } from 'preact/hooks';
import { SettingsModal } from '@/components/SettingsModal';

export function AppOverlays() {
  const [settingsOpen, setSettingsOpen] = useState(false);

  useEffect(() => {
    const open = () => setSettingsOpen(true);
    window.addEventListener('betterw4:openSettings', open);
    return () => window.removeEventListener('betterw4:openSettings', open);
  }, []);

  return <SettingsModal open={settingsOpen} onOpenChange={setSettingsOpen} />;
}
