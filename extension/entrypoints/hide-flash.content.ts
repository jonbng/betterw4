import '@/styles/hide-flash.css';
import { isBypassActive } from '@/lib/bypass-redesigns';
import { isLoginPage } from '@/lib/w4-url';

const SETTINGS_KEY = 'bw-feature-settings';
const THEME_KEY = 'bw-theme-v1';
const LOGIN_STATE_KEY = 'bw-login-state';

/**
 * Intercept W4's CSS and wrap it in @layer w4 { }.
 *
 * This puts ALL of W4's styles into a low-priority CSS cascade layer,
 * so the extension's CSS (in higher layers or un-layered) automatically wins
 * without needing !important on every declaration.
 *
 * Layer order: w4 < theme < base < components < utilities
 */
function interceptW4CSS() {
  function isW4Stylesheet(href: string): boolean {
    try {
      const url = new URL(href, window.location.href);
      return url.host === window.location.host;
    } catch {
      return false;
    }
  }

  function processNode(node: Node): void {
    if (
      node instanceof HTMLLinkElement &&
      node.rel === 'stylesheet' &&
      node.href &&
      !node.hasAttribute('data-bw-layered') &&
      isW4Stylesheet(node.href)
    ) {
      const href = node.href;
      node.media = 'not all';
      const layered = document.createElement('style');
      layered.setAttribute('data-bw-layered', 'link');
      layered.textContent = `@import url("${href}") layer(w4);`;
      node.parentNode?.insertBefore(layered, node.nextSibling);
      return;
    }

    if (
      node instanceof HTMLStyleElement &&
      !node.hasAttribute('data-bw-layered') &&
      node.textContent
    ) {
      const text = node.textContent;
      if (
        text.includes('@layer') ||
        text.includes('--tw-') ||
        text.includes('@theme') ||
        text.includes('tailwind')
      ) {
        return;
      }
      node.textContent = `@layer w4 { ${text} }`;
      node.setAttribute('data-bw-layered', 'inline');
    }
  }

  const head = document.head || document.documentElement;
  head.querySelectorAll('link[rel="stylesheet"], style').forEach(processNode);

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        processNode(node);
        if (node instanceof Element) {
          node.querySelectorAll('link[rel="stylesheet"], style').forEach(processNode);
        }
      }
    }
  });

  observer.observe(document.documentElement, { childList: true, subtree: true });

  window.addEventListener('DOMContentLoaded', () => {
    setTimeout(() => observer.disconnect(), 200);
  });
}

function applyThemeEarly(): void {
  try {
    const stored = localStorage.getItem(SETTINGS_KEY);
    const isDark = stored ? JSON.parse(stored)?.visual?.darkMode === true : false;
    document.documentElement.classList.toggle('dark', isDark);
  } catch {
    // Ignore
  }

  try {
    const themeStored = localStorage.getItem(THEME_KEY);
    if (themeStored) {
      const themeId = JSON.parse(themeStored)?.themeId;
      if (typeof themeId === 'string') {
        document.documentElement.dataset.bwTheme = themeId;
      }
    }
  } catch {
    // Ignore
  }
}

export default defineContentScript({
  matches: ['*://w4.uwcrcn.no/*'],
  runAt: 'document_start',
  main() {
    if (isBypassActive()) {
      document.documentElement.classList.add('bw-ready');
      return;
    }

    interceptW4CSS();
    applyThemeEarly();

    if (isLoginPage()) {
      // Stay hidden until login.content.tsx paints the redesigned form.
      window.setTimeout(() => document.documentElement.classList.add('bw-ready'), 3000);
      return;
    }

    try {
      const loginState = localStorage.getItem(LOGIN_STATE_KEY);
      if (loginState && JSON.parse(loginState)?.isLoggedIn === false) {
        document.documentElement.classList.add('bw-ready');
        return;
      }
    } catch {
      // Ignore
    }

    // @ts-expect-error document.prerendering is a newer API
    if (document.prerendering) {
      (window as unknown as { __BW_PRERENDERED__?: boolean }).__BW_PRERENDERED__ = true;
      document.documentElement.classList.add('bw-prerendered');
      document.addEventListener('prerenderingchange', () => applyThemeEarly(), { once: true });
    }
  },
});
