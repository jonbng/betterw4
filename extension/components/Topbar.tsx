import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { Bell, ChevronDown, KeyRound, LogOut, Settings, User } from 'lucide-react';
import {
  currentNotifyState,
  nativeNotificationsRoot,
  postNotification,
  type NotifyItem,
  type NotifyState,
} from '@/lib/notifications';
import { getCachedProfile, type UserProfile } from '@/lib/profile-cache';
import { w4Url } from '@/lib/w4-url';
import { cn } from '@/lib/utils';

export interface AccountLinks {
  profile: string;
  password: string;
  logout: string;
}

function useDismiss(open: boolean, onClose: () => void, ref: { current: HTMLElement | null }) {
  useEffect(() => {
    if (!open) return;
    const onPointer = (event: MouseEvent) => {
      if (!ref.current?.contains(event.target as Node)) onClose();
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    document.addEventListener('mousedown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onPointer);
      document.removeEventListener('keydown', onKey);
    };
  }, [open, onClose, ref]);
}

function NotificationBell() {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [state, setState] = useState<NotifyState>(() => currentNotifyState());

  useDismiss(open, () => setOpen(false), wrapRef);

  useEffect(() => {
    const native = nativeNotificationsRoot();
    if (!native) return;
    const sync = () => setState(currentNotifyState());
    const observer = new MutationObserver(sync);
    observer.observe(native, { childList: true, subtree: true, characterData: true });
    if (!native.querySelector('.btn-group, .dropdown-menu, li')) {
      void postNotification('refresh').then(sync).catch(() => {});
    }
    return () => observer.disconnect();
  }, []);

  const markRead = (item: NotifyItem) => {
    if (item.id) void postNotification('read', { notification_id: item.id });
  };

  return (
    <div ref={wrapRef} className="relative">
      <button
        type="button"
        className="bw-icon-btn"
        aria-label="Notifications"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <Bell className="size-4" />
        {state.count > 0 && (
          <span
            className={cn(
              'bw-badge',
              state.badge === 'overdue' && 'bw-badge-overdue',
              state.badge === 'new' && 'bw-badge-new',
            )}
          >
            {state.count > 99 ? '99+' : state.count}
          </span>
        )}
      </button>
      {open && (
        <div className="bw-popover bw-popover-notify">
          <div className="flex items-center justify-between gap-2 px-3 py-2">
            <span className="text-sm font-semibold">Notifications</span>
            {state.items.length > 0 && (
              <button
                type="button"
                className="text-xs text-muted-foreground hover:text-foreground"
                onClick={() => void postNotification('readAll')}
              >
                Mark all read
              </button>
            )}
          </div>
          {state.items.length === 0 ? (
            <p className="px-3 py-6 text-center text-sm text-muted-foreground">You are all caught up.</p>
          ) : (
            <ul className="max-h-80 overflow-y-auto py-1">
              {state.items.map((item, index) => (
                <li key={item.id ?? `${item.title}-${index}`}>
                  <a
                    href={item.href || '#'}
                    className="flex flex-col gap-0.5 px-3 py-2 hover:bg-accent"
                    onClick={() => markRead(item)}
                  >
                    <span className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
                      {item.group}
                    </span>
                    <span className="text-sm font-medium text-foreground">{item.title}</span>
                    {item.meta && (
                      <span
                        className={cn(
                          'text-xs',
                          item.severity === 'overdue' ? 'text-destructive' : 'text-muted-foreground',
                        )}
                      >
                        {item.meta}
                      </span>
                    )}
                  </a>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function ProfileMenu({
  profile,
  account,
}: {
  profile: UserProfile | null;
  account: AccountLinks;
}) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [photoFailed, setPhotoFailed] = useState(false);
  useDismiss(open, () => setOpen(false), wrapRef);

  const initials = (profile?.fullName ?? 'W4')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('');

  return (
    <div ref={wrapRef} className="relative">
      <button
        type="button"
        className="bw-profile-btn"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        {profile?.pictureUrl && !photoFailed ? (
          <img
            src={profile.pictureUrl}
            alt=""
            className="size-7 rounded-full object-cover object-top"
            onError={() => setPhotoFailed(true)}
          />
        ) : (
          <span className="flex size-7 items-center justify-center rounded-full bg-secondary text-xs font-semibold">
            {initials}
          </span>
        )}
        <span className="max-w-36 truncate text-sm font-medium">{profile?.fullName ?? 'Account'}</span>
        <ChevronDown className="size-3.5 text-muted-foreground" />
      </button>
      {open && (
        <div className="bw-popover">
          <div className="border-b border-border px-3 py-2">
            <div className="text-sm font-medium">{profile?.fullName ?? 'Student'}</div>
            {profile?.uwcId && (
              <div className="text-xs text-muted-foreground">{profile.uwcId}</div>
            )}
          </div>
          <a href={account.profile} className="bw-menu-item">
            <User className="size-4" />
            Profile
          </a>
          <a href={account.password} className="bw-menu-item">
            <KeyRound className="size-4" />
            Password
          </a>
          <button
            type="button"
            className="bw-menu-item w-full"
            onClick={() => {
              setOpen(false);
              window.dispatchEvent(new CustomEvent('betterw4:openSettings'));
            }}
          >
            <Settings className="size-4" />
            BetterW4
          </button>
          <a href={account.logout} className="bw-menu-item">
            <LogOut className="size-4" />
            Log out
          </a>
        </div>
      )}
    </div>
  );
}

export function Topbar({
  profile,
  account,
}: {
  profile: UserProfile | null;
  account: AccountLinks;
}) {
  const navRef = useRef<HTMLDivElement>(null);
  const campusRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const menu = document.getElementById('main_menu');
    const campus = document.querySelector<HTMLElement>('.status-dropdown');
    const picker = document.querySelector<HTMLElement>('.selection-box');
    if (menu && navRef.current && menu.parentElement !== navRef.current) {
      navRef.current.appendChild(menu);
    }
    if (campus && campusRef.current && campus.parentElement !== campusRef.current) {
      campusRef.current.appendChild(campus);
    }
    if (picker && campusRef.current && picker.parentElement !== campusRef.current) {
      campusRef.current.appendChild(picker);
    }
  }, []);

  const resolved = profile ?? getCachedProfile();

  return (
    <div className="bw-topbar">
      <a href={w4Url('site/index')} className="bw-brand" title="Home">
        <img src={browser.runtime.getURL('/assets/logo.png')} alt="" className="size-7 rounded-md" />
        <span>W4</span>
      </a>
      <div ref={navRef} className="bw-topbar-nav" />
      <div className="bw-topbar-right">
        <div ref={campusRef} className="bw-campus-slot" />
        <NotificationBell />
        <ProfileMenu profile={resolved} account={account} />
      </div>
    </div>
  );
}
