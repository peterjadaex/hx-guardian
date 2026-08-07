import { clsx } from 'clsx'
import { STATUS_META } from '../lib/status'

const STATUS_CONFIG: Record<string, { label: string; classes: string; hex?: string }> = {
  // Scan statuses come from the shared map so the badge, the charts and the
  // report can never disagree about a label.
  ...STATUS_META,
  GREEN:          { label: '● Ready',      classes: 'bg-green-900/40 text-green-400 border border-green-700/50' },
  YELLOW:         { label: '● Caution',    classes: 'bg-yellow-900/40 text-yellow-400 border border-yellow-700/50' },
  RED:            { label: '● Not Ready',  classes: 'bg-red-900/40 text-red-400 border border-red-700/50' },
  // Severity levels (lowercase keys — no collision with uppercase status strings)
  high:           { label: 'HIGH',         classes: 'bg-red-900/40 text-red-400 border border-red-700/50' },
  medium:         { label: 'MEDIUM',       classes: 'bg-yellow-900/40 text-yellow-400 border border-yellow-700/50' },
  low:            { label: 'LOW',          classes: 'bg-blue-900/40 text-blue-400 border border-blue-700/50' },
}

interface Props {
  status: string
  size?: 'sm' | 'md' | 'lg'
}

export function StatusBadge({ status, size = 'md' }: Props) {
  const config = STATUS_CONFIG[status] || { label: status, classes: 'bg-slate-700/40 text-slate-400 border border-slate-600/50' }
  return (
    <span className={clsx(
      'inline-flex items-center rounded-full font-semibold tracking-wide',
      size === 'sm' && 'px-2 py-0.5 text-xs',
      size === 'md' && 'px-2.5 py-1 text-xs',
      size === 'lg' && 'px-4 py-1.5 text-sm',
      config.classes
    )}>
      {config.label}
    </span>
  )
}
