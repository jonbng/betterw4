import { render } from 'preact';
import { AppOverlays } from '@/components/AppOverlays';
import { AppSidebar } from '@/components/AppSidebar';
import { Toaster } from '@/components/ui/sonner';
import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar';
import { disableBypass, getBypassRemainingMs, isBypassActive } from '@/lib/bypass-redesigns';
import { updatePageTitle } from '@/lib/page-titles';
import { getCachedProfile, updateLoginState, updateProfileCache } from '@/lib/profile-cache';
import { getSettings } from '@/lib/settings-storage';
import { applyTheme } from '@/lib/theme-storage';
import { parseW4Navigation } from '@/lib/w4-navigation';
import { isLoginPage } from '@/lib/w4-url';
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
      document.addEventListener('DOMContentLoaded', initLayout);
    } else {
      initLayout();
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

function DashboardLayout() {
  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <div id="bw-w4-content" />
      </SidebarInset>
      <AppOverlays />
      <Toaster position="bottom-right" />
    </SidebarProvider>
  );
}

function injectBypassReenableButton(): void {
  if (document.getElementById('bw-bypass-reenable')) return;

  const mount = () => {
    if (document.getElementById('bw-bypass-reenable')) return;
    if (!document.body) {
      document.addEventListener('DOMContentLoaded', mount, { once: true });
      return;
    }

    const wrap = document.createElement('div');
    wrap.id = 'bw-bypass-reenable';
    wrap.setAttribute(
      'style',
      [
        'position:fixed',
        'right:16px',
        'bottom:16px',
        'z-index:2147483647',
        'font-family:Geist,Inter,system-ui,sans-serif',
        'font-size:13px',
      ].join(';'),
    );

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = 'Re-enable BetterW4';
    btn.setAttribute(
      'style',
      [
        'all:unset',
        'box-sizing:border-box',
        'display:inline-flex',
        'align-items:center',
        'padding:10px 14px',
        'border-radius:10px',
        'background:oklch(0.48 0.12 210)',
        'color:#fff',
        'font-weight:500',
        'cursor:pointer',
        'box-shadow:0 8px 24px oklch(0 0 0 / 0.25)',
      ].join(';'),
    );
    btn.addEventListener('click', () => {
      disableBypass();
      window.location.reload();
    });

    const checkExpiry = () => {
      if (getBypassRemainingMs() <= 0) {
        wrap.remove();
        clearInterval(timer);
      }
    };
    const timer = window.setInterval(checkExpiry, 1000);

    wrap.appendChild(btn);
    document.body.appendChild(wrap);
  };

  mount();
}

function initLayout() {
  if (isBypassActive()) {
    document.documentElement.classList.add('bw-ready');
    injectBypassReenableButton();
    return;
  }

  if (isLoginPage()) {
    return;
  }

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
  const profile = updateProfileCache();
  (window as unknown as { __BW_CACHED_PROFILE__?: typeof profile }).__BW_CACHED_PROFILE__ =
    profile ?? getCachedProfile();

  updatePageTitle();
  replaceFavicon();
  injectFont();
  parseW4Navigation(document);

  const originalNodes: Node[] = [];
  while (document.body.firstChild) {
    originalNodes.push(document.body.removeChild(document.body.firstChild));
  }

  document.body.classList.add('bw-dashboard-active');
  document.body.classList.toggle('bw-hide-native-chrome', settings.behavior.hideNativeChrome);

  const root = document.createElement('div');
  root.id = 'bw-root';
  document.body.appendChild(root);

  render(<DashboardLayout />, root);

  requestAnimationFrame(() => {
    const contentContainer = document.getElementById('bw-w4-content');
    if (contentContainer) {
      const wrapper = document.createElement('div');
      wrapper.id = 'bw-original-content';
      for (const node of originalNodes) wrapper.appendChild(node);
      contentContainer.appendChild(wrapper);
    }
    document.documentElement.classList.add('bw-ready');
  });
}
