// Backend emits naive ISO strings (datetime.utcnow().isoformat()) with no 'Z',
// which JS parses as local time. Append 'Z' when no tz is present so the Date
// is parsed as UTC; .toLocaleString() then renders in the device's system TZ.
export function parseServerTime(s: string | null | undefined): Date | null {
  if (!s) return null
  // Only treat strings with a time component ('T') as datetimes needing a UTC
  // suffix. Plain date strings like '2026-04-24' are left as-is.
  const hasTime = s.includes('T')
  const hasTz = /[Zz]|[+-]\d{2}:?\d{2}$/.test(s)
  return new Date(hasTime && !hasTz ? s + 'Z' : s)
}
