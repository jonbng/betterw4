import { render } from 'preact';
import { LoginPage } from '@/components/LoginPage';
import { getCachedProfile } from '@/lib/profile-cache';
import { getSettings } from '@/lib/settings-storage';
import { applyTheme } from '@/lib/theme-storage';
import { getRoute, isLoginPage } from '@/lib/w4-url';
import '@/styles/globals.css';

export default defineContentScript({
  matches: ['*://w4.uwcrcn.no/*'],
  runAt: 'document_end',
  main() {
    if (!isLoginPage()) return;
    initLoginPage();
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

function loginMode(): 'login' | 'otp' | 'forgot' {
  const route = getRoute();
  if (route === 'site/forgotpass') return 'forgot';
  if (route === 'site/verify2fa' || route === 'site/otp') return 'otp';
  if (document.querySelector('input[name*="code" i], input[name*="otp" i], input[name*="token" i]')) {
    return 'otp';
  }
  return 'login';
}

function initLoginPage() {
  const settings = getSettings();
  document.documentElement.classList.toggle('dark', settings.visual.darkMode);
  applyTheme();
  injectFont();

  const nativeForm = document.querySelector<HTMLFormElement>('form');
  const originalNodes: Node[] = [];
  while (document.body.firstChild) {
    originalNodes.push(document.body.removeChild(document.body.firstChild));
  }

  document.body.classList.add('bw-login-active');

  const root = document.createElement('div');
  root.id = 'bw-root';
  document.body.appendChild(root);

  const profile = getCachedProfile();
  render(<LoginPage mode={loginMode()} userName={profile?.fullName} />, root);

  requestAnimationFrame(() => {
    const slot = document.getElementById('bw-login-form-slot');
    if (slot && nativeForm) {
      slot.appendChild(nativeForm);
    } else if (slot) {
      for (const node of originalNodes) slot.appendChild(node);
    }
    document.documentElement.classList.add('bw-ready');
  });
}
