import { useState } from 'preact/hooks';
import { MapPin } from 'lucide-react';
import { toast } from 'sonner';
import {
  CAMPUS_LOCATIONS,
  parseCampusStatus,
  setCampusStatus,
  type CampusStatus,
} from '@/lib/campus-status';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

export function CampusStatusWidget() {
  const [status, setStatus] = useState<CampusStatus>(() => parseCampusStatus());
  const [other, setOther] = useState('');
  const [pending, setPending] = useState(false);

  const apply = async (selection: string, otherText?: string) => {
    setPending(true);
    try {
      await setCampusStatus(selection, otherText);
      setStatus({
        onCampus: selection === 'oncampus',
        location: selection === 'oncampus' ? null : selection === 'other' ? otherText ?? null : selection,
      });
      toast.success(selection === 'oncampus' ? 'Marked on campus' : 'Marked off campus');
    } catch (err) {
      console.error('[BetterW4] campus status', err);
      toast.error('Could not update campus status');
    } finally {
      setPending(false);
    }
  };

  const label = status.onCampus ? 'On campus' : status.location || 'Off campus';

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        disabled={pending}
        className={cn(
          'mx-2 flex items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-sidebar-accent hover:text-sidebar-accent-foreground outline-none',
          pending && 'opacity-60',
        )}
      >
        <span
          className="size-2 shrink-0 rounded-full"
          style={{ background: status.onCampus ? 'var(--campus-on)' : 'var(--campus-off)' }}
        />
        <MapPin className="size-3.5 shrink-0 text-muted-foreground" />
        <span className="truncate">{label}</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent side="right" align="start" className="w-56">
        <DropdownMenuLabel>I am currently</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {CAMPUS_LOCATIONS.map((location) => (
          <DropdownMenuItem
            key={location.value}
            onSelect={(event) => {
              if (location.value === 'other') {
                event.preventDefault();
                return;
              }
              void apply(location.value);
            }}
          >
            {location.label}
          </DropdownMenuItem>
        ))}
        <div className="px-2 pb-1 pt-1">
          <input
            value={other}
            onInput={(event) => setOther((event.target as HTMLInputElement).value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && other.trim()) {
                event.preventDefault();
                void apply('other', other.trim());
              }
            }}
            maxLength={20}
            placeholder="Other…"
            className="h-8 w-full rounded-md border border-input bg-transparent px-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
          />
        </div>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
