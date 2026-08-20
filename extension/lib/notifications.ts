import { w4Url } from '@/lib/w4-url';

export type NotifySeverity = 'normal' | 'new' | 'overdue';
export type NotifyKind = 'task' | 'email';

export interface NotifyItem {
  id: string | null;
  type: string | null;
  kind: NotifyKind;
  group: string;
  title: string;
  href: string | null;
  meta: string | null;
  severity: NotifySeverity;
}

export interface NotifyState {
  count: number;
  badge: NotifySeverity;
  items: NotifyItem[];
}

const EMPTY: NotifyState = { count: 0, badge: 'normal', items: [] };

const ACTION_ROUTES: Record<string, string> = {
  read: 'notifications/read',
  readGroup: 'notifications/readgroup',
  readAll: 'notifications/readall',
  readAllEmails: 'notifications/readallemails',
  clear: 'notifications/clear',
  clearGroup: 'notifications/cleargroup',
  clearAll: 'notifications/clearall',
  refresh: 'notifications/refresh',
};

function pageNotifyUrls(): Record<string, string> | null {
  const raw = (window as unknown as { notification_urls?: Record<string, string> }).notification_urls;
  return raw && typeof raw === 'object' ? raw : null;
}

export function notificationUrl(action: keyof typeof ACTION_ROUTES): string {
  const fromPage = pageNotifyUrls()?.[action];
  if (fromPage) return new URL(fromPage, window.location.origin).href;
  return w4Url(ACTION_ROUTES[action]);
}

function severityOf(el: Element | null): NotifySeverity {
  if (!el) return 'normal';
  if (el.classList.contains('overdue')) return 'overdue';
  if (el.classList.contains('new')) return 'new';
  return 'normal';
}

export function parseNotifications(root: ParentNode | null): NotifyState {
  if (!root) return EMPTY;
  const alert = root.querySelector('.alert');
  const count = Number.parseInt(alert?.textContent?.trim() || '0', 10) || 0;
  const items: NotifyItem[] = [];

  root.querySelectorAll('dd li').forEach((li) => {
    const titleLink = li.querySelector<HTMLAnchorElement>('a[href]:not(.read):not(.clear)');
    const read = li.querySelector<HTMLAnchorElement>('a.read');
    const groupEl = li.closest('dl')?.querySelector('dt');
    const kind: NotifyKind =
      li.closest('dl.email-list') || li.closest('.emails') ? 'email' : 'task';
    const title = (titleLink?.childNodes[0]?.textContent ?? titleLink?.textContent ?? '')
      .replace(/\s+/g, ' ')
      .trim();
    if (!title) return;
    const meta =
      titleLink?.querySelector('.deadline, .duration')?.textContent?.trim() || null;
    items.push({
      id: read?.getAttribute('data-notification-id') ?? li.querySelector('[data-notification-id]')?.getAttribute('data-notification-id') ?? null,
      type: groupEl?.querySelector('[data-notification-type]')?.getAttribute('data-notification-type') ?? null,
      kind,
      group: (groupEl?.childNodes[0]?.textContent ?? kind).replace(/\s+/g, ' ').trim(),
      title,
      href: titleLink?.href ?? null,
      meta,
      severity: severityOf(li),
    });
  });

  return {
    count: count || items.filter((item) => item.severity !== 'normal').length || items.length,
    badge: severityOf(alert) === 'normal' && items.some((item) => item.severity === 'overdue')
      ? 'overdue'
      : severityOf(alert) === 'normal' && items.some((item) => item.severity === 'new')
        ? 'new'
        : severityOf(alert),
    items,
  };
}

export function nativeNotificationsRoot(): Element | null {
  return document.querySelector('#header .notifications');
}

export async function postNotification(
  action: keyof typeof ACTION_ROUTES,
  fields: Record<string, string> = {},
): Promise<void> {
  const body = new URLSearchParams(fields);
  const response = await fetch(notificationUrl(action), {
    method: 'POST',
    credentials: 'include',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Requested-With': 'XMLHttpRequest',
    },
    body,
  });
  const html = await response.text();
  const native = nativeNotificationsRoot();
  if (!native) return;
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const incoming = doc.querySelector('.notifications') ?? doc.body;
  native.innerHTML = incoming.innerHTML;
}

export function currentNotifyState(): NotifyState {
  return parseNotifications(nativeNotificationsRoot());
}
