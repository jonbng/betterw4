import { render } from 'preact';
import { LoginPage } from '@/components/LoginPage';
import { getCachedProfile } from '@/lib/profile-cache';
import { getSettings } from '@/lib/settings-storage';
import { applyTheme } from '@/lib/theme-storage';
import { normalizeW4Username } from '@/lib/w4-username';
import { getRoute, isLoginPage, isOtpRoute } from '@/lib/w4-url';
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
  if (isOtpRoute(route)) return 'otp';
  if (
    document.querySelector(
      '#otp-form, input[name^="OtpModel"], input[name*="otp" i], input[name*="code" i], input[name*="token" i]',
    )
  ) {
    return 'otp';
  }
  if (/additional verification/i.test(document.title)) return 'otp';
  return 'login';
}

function findAuthForm(): HTMLFormElement | null {
  return (
    document.querySelector<HTMLFormElement>('#otp-form') ??
    document.querySelector<HTMLFormElement>('form[action*="verify2fa"]') ??
    document.querySelector<HTMLFormElement>('form[action*="otp"]') ??
    document.querySelector<HTMLFormElement>('form:has(input[name^="OtpModel"])') ??
    document.querySelector<HTMLFormElement>('form:has(input[name^="LoginForm"])') ??
    document.querySelector<HTMLFormElement>('form:has(input[name^="ForgotPassForm"])') ??
    document.querySelector<HTMLFormElement>('form')
  );
}

function collectAuthExtras(form: HTMLFormElement): Node[] {
  const extras: Node[] = [];
  const error = document.querySelector('.errorSummary, .errorMessage, .flash-error');
  if (error && !form.contains(error)) extras.push(error);

  const parent = form.parentElement;
  if (parent) {
    for (const child of Array.from(parent.children)) {
      if (child === form) continue;
      if (child.tagName === 'P' || child.tagName === 'A' || child.querySelector?.('a[href*="otp"]')) {
        extras.push(child);
      }
    }
  }
  return extras;
}

/**
 * Only flatten W4's dedicated 200px `#login_table`. The 2FA page is Yii
 * `div.form > .row` (and may sit inside layout tables from main.css) — never
 * strip those.
 */
function normalizeLoginForm(form: HTMLFormElement): void {
  const table = form.querySelector<HTMLTableElement>('table#login_table');
  if (table) {
    const pieces: Node[] = [];
    table.querySelectorAll('tr').forEach((row) => {
      const submit = row.querySelector<HTMLInputElement>('input[type="submit"]');
      if (submit) {
        styleSubmit(submit);
        pieces.push(submit);
        return;
      }

      const input = row.querySelector<HTMLInputElement>(
        'input[type="text"], input[type="password"], input:not([type="hidden"]):not([type="submit"]):not([type="checkbox"])',
      );
      if (!input) return;

      const label = row.querySelector('label');
      const wrap = document.createElement('div');
      wrap.className = 'bw-login-field';
      if (label) wrap.appendChild(label);
      styleField(input, label?.textContent);
      wrap.appendChild(input);
      pieces.push(wrap);
    });
    table.remove();
    for (const piece of pieces) form.appendChild(piece);
    return;
  }

  form
    .querySelectorAll<HTMLInputElement>(
      'input[type="text"], input[type="password"], input[type="tel"], input[type="number"]',
    )
    .forEach((input) => styleField(input));
  form.querySelectorAll<HTMLInputElement>('input[type="submit"]').forEach(styleSubmit);
}

function styleField(input: HTMLInputElement, labelText?: string | null): void {
  input.classList.add('bw-login-input');
  input.removeAttribute('size');
  input.removeAttribute('style');

  const name = (input.getAttribute('name') ?? '').toLowerCase();
  const type = (input.getAttribute('type') ?? 'text').toLowerCase();
  if (type === 'password' && !name.includes('otp') && !name.includes('code')) {
    input.autocomplete = 'current-password';
    if (!input.placeholder) input.placeholder = 'Password';
  } else if (name.includes('username') || name.includes('[user')) {
    input.autocomplete = 'username';
    if (!input.placeholder) input.placeholder = 'Username';
    bindUsernameEmailStrip(input);
  } else if (name.includes('otp') || name.includes('code') || name.includes('token') || name.includes('verify')) {
    input.autocomplete = 'one-time-code';
    input.inputMode = 'numeric';
    if (!input.placeholder) input.placeholder = labelText?.trim() || 'Verification code';
  } else if (labelText && !input.placeholder) {
    input.placeholder = labelText.trim();
  }
}

function styleSubmit(input: HTMLInputElement): void {
  input.classList.add('bw-login-submit');
  input.removeAttribute('style');
}

const usernameFieldsBound = new WeakSet<HTMLInputElement>();

/** W4 ids are `nc26jban`; strip `@uwcrcn.no` (and any other domain) if pasted or autofilled. */
function bindUsernameEmailStrip(input: HTMLInputElement): void {
  if (usernameFieldsBound.has(input)) return;
  usernameFieldsBound.add(input);
  input.removeAttribute('maxlength');
  const apply = () => {
    const next = normalizeW4Username(input.value);
    if (next !== input.value) input.value = next;
  };
  apply();
  input.addEventListener('input', apply);
  input.addEventListener('change', apply);
  input.form?.addEventListener('submit', apply);
}

function initLoginPage() {
  const settings = getSettings();
  document.documentElement.classList.toggle('dark', settings.visual.darkMode);
  applyTheme();
  injectFont();

  const mode = loginMode();
  const nativeForm = findAuthForm();
  if (nativeForm) {
    normalizeLoginForm(nativeForm);
    nativeForm
      .querySelectorAll<HTMLInputElement>('input[name="LoginForm[username]"], input[name*="username" i]')
      .forEach(bindUsernameEmailStrip);
  }
  const extras = nativeForm ? collectAuthExtras(nativeForm) : [];

  const originalNodes: Node[] = [];
  while (document.body.firstChild) {
    originalNodes.push(document.body.removeChild(document.body.firstChild));
  }

  document.body.classList.add('bw-login-active');

  const root = document.createElement('div');
  root.id = 'bw-root';
  document.body.appendChild(root);

  const profile = getCachedProfile();
  render(
    <LoginPage
      mode={mode}
      userName={profile?.fullName}
      form={nativeForm}
      extras={extras}
      fallbackNodes={nativeForm ? [] : originalNodes}
    />,
    root,
  );

  document.documentElement.classList.add('bw-ready');
}
