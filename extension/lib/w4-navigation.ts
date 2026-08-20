import { getRoute } from '@/lib/w4-url';

export interface W4NavigationItem {
  label: string;
  href: string;
  active: boolean;
}

export interface W4SdMenuGroup {
  title: string;
  items: W4NavigationItem[];
}

export interface W4NavigationSnapshot {
  pageTitle: string;
  w4Version: string | null;
  userName: string | null;
  globalItems: W4NavigationItem[];
  sdmenu: W4SdMenuGroup[];
}

function cleanText(value: string | null | undefined): string {
  return (value ?? '').replace(/\s+/g, ' ').trim();
}

function itemFromAnchor(anchor: HTMLAnchorElement): W4NavigationItem | null {
  const label = cleanText(anchor.textContent);
  if (!label) return null;
  return {
    label,
    href: anchor.getAttribute('href') || '#',
    active: anchor.classList.contains('active'),
  };
}

/**
 * Capture W4 chrome before the original DOM is moved under #bw-original-content.
 * The live page is authoritative for the current role's top menu and sdmenu.
 */
export function parseW4Navigation(doc: Document = document): W4NavigationSnapshot {
  const globalItems = Array.from(
    doc.querySelectorAll<HTMLAnchorElement>('#main_menu a'),
  )
    .map(itemFromAnchor)
    .filter((item): item is W4NavigationItem => Boolean(item));

  const sdmenu: W4SdMenuGroup[] = [];
  doc.querySelectorAll<HTMLElement>('.sdmenu > div').forEach((group) => {
    const title = cleanText(group.querySelector(':scope > span')?.textContent);
    const items = Array.from(group.querySelectorAll<HTMLAnchorElement>(':scope > a'))
      .map(itemFromAnchor)
      .filter((item): item is W4NavigationItem => Boolean(item));
    if (title && items.length) sdmenu.push({ title, items });
  });

  const welcome = cleanText(doc.querySelector('#user-panel .right')?.childNodes[0]?.textContent);
  const userName = welcome.replace(/^Welcome,\s*/i, '').replace(/\s+$/, '') || null;

  return {
    pageTitle: cleanText(doc.querySelector('#content_inner h2')?.textContent) || cleanText(doc.title) || 'W4',
    w4Version: cleanText(doc.querySelector('#version a')?.textContent) || null,
    userName,
    globalItems,
    sdmenu,
  };
}

export function currentRouteActive(route: string, params?: Record<string, string>): boolean {
  const current = getRoute();
  if (!current) return false;
  if (current !== route) return false;
  if (!params) return true;
  const search = new URL(window.location.href).searchParams;
  return Object.entries(params).every(([key, value]) => search.get(key) === value);
}
