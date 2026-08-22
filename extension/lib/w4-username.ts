/** W4 usernames are the UWC id (`nc26jban`). People often paste the school email instead. */
export function normalizeW4Username(raw: string): string {
  const trimmed = raw.trim();
  const at = trimmed.indexOf('@');
  if (at < 0) return trimmed;
  return trimmed.slice(0, at).trim();
}
