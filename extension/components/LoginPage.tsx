import { w4Url } from '@/lib/w4-url';

interface LoginPageProps {
  mode: 'login' | 'otp' | 'forgot';
  userName?: string | null;
}

export function LoginPage({ mode, userName }: LoginPageProps) {
  const logoUrl = browser.runtime.getURL('/assets/logo.png');
  const title =
    mode === 'otp' ? 'Enter your code' : mode === 'forgot' ? 'Reset password' : 'Sign in to W4';
  const subtitle =
    mode === 'otp'
      ? 'W4 sent a two-factor code for this device.'
      : mode === 'forgot'
        ? 'W4 will email a new password to the address on file.'
        : userName
          ? `Welcome back, ${userName.split(' ')[0]}.`
          : 'UWC Red Cross Nordic student system.';

  return (
    <div className="flex min-h-svh items-center justify-center bg-background p-6">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center text-center">
          <img src={logoUrl} alt="BetterW4" className="mb-4 size-14 rounded-xl" />
          <h1 className="text-base font-semibold">{title}</h1>
          <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>
        </div>

        <div className="rounded-xl border bg-card p-6 shadow-sm">
          <div id="bw-login-form-slot" />
        </div>

        {mode === 'login' ? (
          <p className="mt-4 text-center text-sm text-muted-foreground">
            <a href={w4Url('site/forgotpass')} className="text-primary underline-offset-4 hover:underline">
              Forgot password
            </a>
          </p>
        ) : (
          <p className="mt-4 text-center text-sm text-muted-foreground">
            <a href={w4Url('site/login')} className="text-primary underline-offset-4 hover:underline">
              Back to sign in
            </a>
          </p>
        )}

        <p className="mt-8 text-center text-xs text-muted-foreground">
          Unofficial. Not affiliated with UWC Red Cross Nordic.
        </p>
      </div>
    </div>
  );
}
