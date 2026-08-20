import { getRoute } from '@/lib/w4-url';

const ROUTE_TITLES: Record<string, string> = {
  'site/index': 'Home',
  'site/profile': 'Profile',
  'site/password': 'Password',
  'site/login': 'Sign in',
  'site/verify2fa': 'Two-factor',
  'academics/deadlines': 'Assessments',
  'academics/timetable/mytimetable': 'Timetable',
  'mailer/inbox': 'Inbox',
  'mailer/archive': 'Sent',
  'mailer/send': 'Compose',
  documents: 'Documents',
};

export function updatePageTitle(): void {
  const route = getRoute();
  const mapped = route ? ROUTE_TITLES[route] : null;
  const heading = document.querySelector('#content_inner h2')?.textContent?.trim();
  const title = mapped || heading || document.title.replace(/^UWCRCN W4[:\s-]*/i, '').trim() || 'W4';
  document.title = `${title} · BetterW4`;
}
