import { w4Url } from '@/lib/w4-url';

export const CAMPUS_LOCATIONS = [
  { value: 'oncampus', label: 'On campus' },
  { value: 'On a walk', label: 'On a walk' },
  { value: 'At Raudbua', label: 'At Raudbua' },
  { value: 'On Jarstadheia', label: 'On Jarstadheia' },
  { value: 'On the island', label: 'On the island' },
  { value: 'In Flekke', label: 'In Flekke' },
  { value: 'In Dale', label: 'In Dale' },
  { value: 'In A building (after 10:30pm)', label: 'In A building (after 10:30pm)' },
  { value: 'In K building (after 10:30pm)', label: 'In K building (after 10:30pm)' },
  { value: 'In Library/Study room (after 10:30pm)', label: 'In Library/Study room (after 10:30pm)' },
  { value: 'other', label: 'Other' },
] as const;

export interface CampusStatus {
  onCampus: boolean;
  location: string | null;
}

export function parseCampusStatus(doc: Document = document): CampusStatus {
  const value = doc.querySelector('.status-dropdown .status-value')?.textContent?.trim() ?? '';
  const locationRaw = doc.querySelector('.status-dropdown .location')?.textContent?.trim() ?? '';
  const location = locationRaw.replace(/^\(|\)$/g, '').trim() || null;
  const onCampus =
    doc.querySelector('.status-dropdown .status')?.classList.contains('oncampus') === true ||
    /^on campus$/i.test(value);
  return { onCampus, location: onCampus ? null : location };
}

export async function setCampusStatus(selection: string, otherText?: string): Promise<void> {
  const status = selection === 'oncampus' ? 'on' : 'off';
  const location =
    selection === 'oncampus' ? undefined : selection === 'other' ? otherText : selection;

  const body = new URLSearchParams();
  body.set('status', status);
  if (location) body.set('location', location);

  const response = await fetch(w4Url('site/setstatus'), {
    method: 'POST',
    credentials: 'include',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Requested-With': 'XMLHttpRequest',
    },
    body,
  });

  if (!response.ok) {
    throw new Error(`Campus status failed (${response.status})`);
  }
}
