import { useLayoutEffect, useRef } from 'preact/hooks';
import { w4Url } from '@/lib/w4-url';

interface LoginPageProps {
  mode: 'login' | 'otp' | 'forgot';
  userName?: string | null;
  form?: HTMLFormElement | null;
  extras?: Node[];
  fallbackNodes?: Node[];
}

export function LoginPage({
  mode,
  userName,
  form = null,
  extras = [],
  fallbackNodes = [],
}: LoginPageProps) {
  const slotRef = useRef<HTMLDivElement>(null);
  const logoUrl = browser.runtime.getURL('/assets/logo.png');
  const title =
    mode === 'otp' ? 'Enter your code' : mode === 'forgot' ? 'Reset password' : 'Sign in to W4';
  const subtitle =
    mode === 'otp'
      ? 'W4 emailed a verification code for this device.'
      : mode === 'forgot'
        ? 'W4 will email a new password to the address on file.'
        : userName
          ? `Welcome back, ${userName.split(' ')[0]}.`
          : 'UWC Red Cross Nordic student system.';

  useLayoutEffect(() => {
    const slot = slotRef.current;
    if (!slot) return;

    for (const node of extras) {
      if (node.parentNode !== slot) slot.appendChild(node);
    }
    if (form && form.parentNode !== slot) slot.appendChild(form);
    if (!form) {
      for (const node of fallbackNodes) {
        if (node.parentNode !== slot) slot.appendChild(node);
      }
    }
  });

  return (
    <div className="flex min-h-svh items-center justify-center bg-background p-6">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center text-center">
          <img src={logoUrl} alt="BetterW4" className="mb-4 size-14 rounded-xl" />
          <h1 className="text-base font-semibold">{title}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>
        </div>

        <div className="rounded-xl border bg-card p-6 shadow-sm">
          <div ref={slotRef} id="bw-login-form-slot" className="min-w-0" />
        </div>

        {mode === 'login' ? (
          <p className="mt-4 text-center text-sm text-muted-foreground">
            <a href={w4Url('site/forgotpass')} className="text-primary underline-offset-4 hover:underline">
              Forgot password
            </a>
          </p>
        ) : mode === 'forgot' ? (
          <p className="mt-4 text-center text-sm text-muted-foreground">
            <a href={w4Url('site/login')} className="text-primary underline-offset-4 hover:underline">
              Back to sign in
            </a>
          </p>
        ) : null}

        <p className="mt-8 text-center text-xs text-muted-foreground">
          Unofficial. Not affiliated with UWC Red Cross Nordic.
        </p>
      </div>
    </div>
  );
}
