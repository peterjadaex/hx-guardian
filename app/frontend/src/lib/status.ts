/**
 * Single source of truth for scan-status presentation.
 *
 * The label/colour mapping used to be duplicated across StatusBadge, the Rules
 * filter, the Dashboard chart and the RuleDetail heatmap, which is how the
 * report and the UI drifted apart. Server-side counterpart: _STATUS_LABELS in
 * app/backend/routers/reports.py — keep both in step.
 */

export interface StatusMeta {
  label: string
  hex: string          // for recharts, which needs a raw colour
  classes: string      // tailwind badge classes
}

export const STATUS_META: Record<string, StatusMeta> = {
  PASS: {
    label: 'PASS', hex: '#22c55e',
    classes: 'bg-green-900/40 text-green-400 border border-green-700/50',
  },
  FAIL: {
    label: 'FAIL', hex: '#ef4444',
    classes: 'bg-red-900/40 text-red-400 border border-red-700/50',
  },
  NOT_APPLICABLE: {
    label: 'N/A', hex: '#475569',
    classes: 'bg-slate-700/40 text-slate-400 border border-slate-600/50',
  },
  MDM_REQUIRED: {
    label: 'Not Scannable', hex: '#3b82f6',
    classes: 'bg-blue-900/40 text-blue-400 border border-blue-700/50',
  },
  EXEMPT: {
    label: 'Exempt', hex: '#eab308',
    classes: 'bg-yellow-900/40 text-yellow-400 border border-yellow-700/50',
  },
  ERROR: {
    label: 'Error', hex: '#f97316',
    classes: 'bg-orange-900/40 text-orange-400 border border-orange-700/50',
  },
  // Purple, deliberately unlike ERROR-orange and Not-Scanned-grey: "we could not
  // look" is a different fact from "the check ran and errored".
  NOT_ASSESSED: {
    label: 'Not Assessed', hex: '#a78bfa',
    classes: 'bg-purple-900/40 text-purple-300 border border-purple-700/50',
  },
  NEVER_SCANNED: {
    label: 'Not Scanned', hex: '#64748b',
    classes: 'bg-slate-800/40 text-slate-500 border border-slate-700/50',
  },
}

/** Order used by the Rules filter dropdown. */
export const STATUS_ORDER = [
  'FAIL', 'PASS', 'NOT_APPLICABLE', 'MDM_REQUIRED', 'NOT_ASSESSED',
  'EXEMPT', 'ERROR', 'NEVER_SCANNED',
]

export const statusLabel = (status: string): string =>
  STATUS_META[status]?.label ?? status

export const statusHex = (status: string): string =>
  STATUS_META[status]?.hex ?? '#64748b'
