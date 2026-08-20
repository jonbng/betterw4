import { render } from 'preact';
import { AppOverlays } from '@/components/AppOverlays';
import { Topbar, type AccountLinks } from '@/components/Topbar';
import { Toaster } from '@/components/ui/sonner';
import { disableBypass, getBypassRemainingMs, isBypassActive } from '@/lib/bypass-redesigns';
import { updateLoginState, updateProfileCache } from '@/lib/profile-cache';
import { getSettings } from '@/lib/settings-storage';
import { applyTheme } from '@/lib/theme-storage';
import { isLoginPage, w4Url } from '@/lib/w4-url';
import '@/styles/globals.css';

export default defineContentScript({
  matches: ['*://w4.uwcrcn.no/*'],
  async main() {
    browser.runtime.onMessage.addListener((message) => {
      if (message?.action === 'openSettings') {
        window.dispatchEvent(new CustomEvent('betterw4:openSettings'));
      }
    });

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init);
    } else {
      init();
    }
  },
});

function injectFont() {
  const preconnect1 = document.createElement('link');
  preconnect1.rel = 'preconnect';
  preconnect1.href = 'https://fonts.googleapis.com';

  const preconnect2 = document.createElement('link');
  preconnect2.rel = 'preconnect';
  preconnect2.href = 'https://fonts.gstatic.com';
  preconnect2.crossOrigin = 'anonymous';

  const font = document.createElement('link');
  font.rel = 'stylesheet';
  font.href = 'https://fonts.googleapis.com/css2?family=Geist:wght@100..900&display=swap';

  document.head.append(preconnect1, preconnect2, font);
}

function replaceFavicon() {
  document.querySelectorAll('link[rel="icon"], link[rel="shortcut icon"]').forEach((el) => el.remove());
  const favicon = document.createElement('link');
  favicon.rel = 'icon';
  favicon.type = 'image/png';
  favicon.href = browser.runtime.getURL('/assets/logo.png');
  document.head.appendChild(favicon);
}

function polishMainMenu(): void {
  const menu = document.getElementById('main_menu');
  if (!menu || menu.dataset.bwPolished) return;
  menu.dataset.bwPolished = '1';
  for (const node of Array.from(menu.childNodes)) {
    if (node.nodeType === Node.TEXT_NODE && (node.textContent ?? '').includes('|')) {
      node.textContent = '';
    }
  }
}

function accountLinks(): AccountLinks {
  const panel = document.getElementById('user-panel');
  const href = (selector: string, fallback: string) =>
    panel?.querySelector<HTMLAnchorElement>(selector)?.href || w4Url(fallback);
  return {
    profile: href('a[href*="site/profile"]', 'site/profile'),
    password: href('a[href*="site/password"]', 'site/password'),
    logout: href('a[href*="site/logout"]', 'site/logout'),
  };
}

function mountTopbar(): void {
  const header = document.getElementById('header');
  if (!header || document.getElementById('bw-topbar-root')) return;

  const root = document.createElement('div');
  root.id = 'bw-topbar-root';
  header.insertBefore(root, header.firstChild);

  render(
    <Topbar profile={updateProfileCache()} account={accountLinks()} />,
    root,
  );

  for (const child of Array.from(header.children)) {
    if (child.id === 'bw-topbar-root') continue;
    if (child.classList.contains('notifications')) continue;
    if (child.classList.contains('status-dropdown')) continue;
    if (child.classList.contains('selection-box')) continue;
    (child as HTMLElement).hidden = true;
  }

  const panel = document.getElementById('user-panel');
  if (panel) panel.hidden = true;
}

function Overlays() {
  return (
    <>
      <AppOverlays />
      <Toaster position="bottom-right" />
    </>
  );
}

function injectBypassReenableButton(): void {
  if (document.getElementById('bw-bypass-reenable')) return;

  const mount = () => {
    if (document.getElementById('bw-bypass-reenable') || !document.body) return;
    const btn = document.createElement('button');
    btn.id = 'bw-bypass-reenable';
    btn.type = 'button';
    btn.textContent = 'Re-enable BetterW4';
    btn.addEventListener('click', () => {
      disableBypass();
      window.location.reload();
    });
    const timer = window.setInterval(() => {
      if (getBypassRemainingMs() <= 0) {
        btn.remove();
        clearInterval(timer);
      }
    }, 1000);
    document.body.appendChild(btn);
  };

  if (document.body) mount();
  else document.addEventListener('DOMContentLoaded', mount, { once: true });
}

function init() {
  if (isBypassActive()) {
    document.documentElement.classList.add('bw-ready');
    injectBypassReenableButton();
    return;
  }

  if (isLoginPage()) return;

  const hasUserPanel = Boolean(document.querySelector('#user-panel'));
  if (!hasUserPanel) {
    updateLoginState();
    document.documentElement.classList.add('bw-ready');
    return;
  }

  const settings = getSettings();
  document.documentElement.classList.toggle('dark', settings.visual.darkMode);
  applyTheme();
  updateLoginState();
  updateProfileCache();

  replaceFavicon();
  injectFont();
  polishMainMenu();
  document.body.classList.add('bw-themed');
  mountTopbar();

  if (!document.getElementById('bw-root')) {
    const root = document.createElement('div');
    root.id = 'bw-root';
    document.body.appendChild(root);
    render(<Overlays />, root);
  }

  document.documentElement.classList.add('bw-ready');
}
