import { useEffect, useRef, useState } from 'react'
import { RefreshCw, Download, Search, Pause, Play } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import {
  getAuditLog,
  getShellLog,
  getBiometricLog,
  exportAuditCsv,
  exportAuditJsonl,
  exportShellJsonl,
  exportBiometricJsonl,
  streamAuditLogUrl,
  streamShellLogUrl,
  streamBiometricLogUrl,
} from '../lib/api'
import { parseServerTime } from '../lib/time'
import { useSSE } from '../lib/sse'

const ACTION_COLORS: Record<string, string> = {
  SCAN_RUN: 'text-blue-400',
  SCAN_COMPLETE: 'text-green-400',
  FIX_APPLIED: 'text-yellow-400',
  EXEMPTION_GRANTED: 'text-orange-400',
  EXEMPTION_REVOKED: 'text-red-400',
  SCHEDULE_CREATED: 'text-blue-400',
  SCHEDULE_DELETED: 'text-red-400',
  SCHEDULE_TRIGGERED: 'text-purple-400',
  REPORT_GENERATED: 'text-teal-400',
  PREFLIGHT_RUN: 'text-green-400',
  SHELL_EXEC: 'text-slate-400',
  SUSPICIOUS_ACTION: 'text-red-500',
  BIOMETRIC_AUTH: 'text-indigo-400',
}

const BIO_CLASS_COLORS: Record<string, string> = {
  FINGER_TOUCH: 'text-green-400',   // the one we trust: sensor physically touched
  SUCCESS: 'text-green-300',
  REQUEST: 'text-blue-400',
  FAILURE: 'text-red-400',
  CANCELLED: 'text-yellow-400',
  TEARDOWN: 'text-slate-600',
  OTHER: 'text-slate-400',
}

export function AuditLog() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [entries, setEntries] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [offset, setOffset] = useState(0)
  const [actionFilter, setActionFilter] = useState('')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')
  const [searchQ, setSearchQ] = useState('')
  const [searchQApplied, setSearchQApplied] = useState('')
  const [bioClass, setBioClass] = useState('')          // BIOMETRIC_AUTH only
  const [includeTeardown, setIncludeTeardown] = useState(false)
  const [streaming, setStreaming] = useState(false)
  const [paused, setPaused] = useState(false)
  const [newIds, setNewIds] = useState<Set<number>>(new Set())
  const newIdTimers = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map())
  const LIMIT = 100

  const isShellView = actionFilter === 'SHELL_EXEC'
  const isBioView = actionFilter === 'BIOMETRIC_AUTH'

  useEffect(() => {
    return () => {
      newIdTimers.current.forEach(t => clearTimeout(t))
      newIdTimers.current.clear()
    }
  }, [])

  useEffect(() => {
    const t = setTimeout(() => setSearchQApplied(searchQ), 250)
    return () => clearTimeout(t)
  }, [searchQ])

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [offset, actionFilter, fromDate, toDate, searchQApplied, bioClass, includeTeardown])

  const load = async () => {
    setLoading(true)
    try {
      if (isShellView) {
        const data = await getShellLog({
          limit: LIMIT, offset,
          source: 'history',
          q: searchQApplied || undefined,
          from: fromDate || undefined,
          to: toDate || undefined,
        })
        setEntries(data.entries || [])
        setTotal(data.total || 0)
      } else if (isBioView) {
        const data = await getBiometricLog({
          limit: LIMIT, offset,
          event_class: bioClass || undefined,
          q: searchQApplied || undefined,
          include_teardown: includeTeardown || undefined,
          from: fromDate || undefined,
          to: toDate || undefined,
        })
        setEntries(data.entries || [])
        setTotal(data.total || 0)
      } else {
        const data = await getAuditLog({
          limit: LIMIT, offset,
          action: actionFilter || undefined,
          from: fromDate || undefined,
          to: toDate || undefined,
        })
        setEntries(data.entries || [])
        setTotal(data.total || 0)
      }
    } catch (e: any) { setError(e.message) }
    finally { setLoading(false) }
  }

  const markNew = (id: number) => {
    setNewIds(prev => {
      const next = new Set(prev)
      next.add(id)
      return next
    })
    const existing = newIdTimers.current.get(id)
    if (existing) clearTimeout(existing)
    const t = setTimeout(() => {
      setNewIds(prev => {
        if (!prev.has(id)) return prev
        const next = new Set(prev)
        next.delete(id)
        return next
      })
      newIdTimers.current.delete(id)
    }, 2500)
    newIdTimers.current.set(id, t)
  }

  const streamPath = !streaming ? null
    : isShellView ? streamShellLogUrl({ source: 'history', q: searchQApplied || undefined })
    : isBioView   ? streamBiometricLogUrl({
        event_class: bioClass || undefined,
        q: searchQApplied || undefined,
        include_teardown: includeTeardown,
      })
    :               streamAuditLogUrl({ action: actionFilter || undefined })

  const { connected: sseConnected } = useSSE<any>(streamPath, (evt, data) => {
    if (evt !== 'row' || paused) return
    setEntries(prev => {
      if (prev.some((e: any) => e.id === data.id)) return prev
      return [data, ...prev].slice(0, 500)
    })
    setTotal(prev => prev + 1)
    if (typeof data.id === 'number') markNew(data.id)
  })

  const csvUrl = exportAuditCsv({ action: actionFilter || undefined, from: fromDate || undefined, to: toDate || undefined })
  const jsonlUrl = isShellView
    ? exportShellJsonl({ source: 'history', q: searchQApplied || undefined, from: fromDate || undefined, to: toDate || undefined })
    : isBioView
    ? exportBiometricJsonl({
        event_class: bioClass || undefined,
        q: searchQApplied || undefined,
        include_teardown: includeTeardown,
        from: fromDate || undefined,
        to: toDate || undefined,
      })
    : exportAuditJsonl({ action: actionFilter || undefined, from: fromDate || undefined, to: toDate || undefined })

  const onFilterChange = (fn: () => void) => {
    fn()
    setOffset(0)
  }

  return (
    <Layout>
      <PageHeader title="Audit Log" subtitle={`${total} total entries`}>
        {streaming && (
          <button onClick={() => setPaused(p => !p)}
            className={`flex items-center gap-2 px-3 py-2 text-sm rounded-lg border transition-colors ${paused
              ? 'bg-green-600/20 border-green-700/50 text-green-400 hover:bg-green-600/30'
              : 'bg-yellow-600/20 border-yellow-700/50 text-yellow-400 hover:bg-yellow-600/30'}`}>
            {paused ? <><Play className="w-3.5 h-3.5" />Resume</> : <><Pause className="w-3.5 h-3.5" />Pause</>}
          </button>
        )}
        <button onClick={() => { setStreaming(s => !s); setPaused(false) }}
          className={`flex items-center gap-2 px-3 py-2 text-sm rounded-lg border transition-colors ${streaming
            ? 'bg-blue-600/20 border-blue-700/50 text-blue-400'
            : 'bg-slate-700/30 border-slate-600/50 text-slate-400 hover:text-white'}`}>
          {streaming ? '● Live' : 'Go Live'}
        </button>
        {!isShellView && !isBioView && (
          <a href={csvUrl} download
            className="flex items-center gap-2 px-3 py-2 bg-slate-700/30 border border-slate-600/50 text-slate-300 text-sm rounded-lg transition-colors hover:bg-slate-700/50">
            <Download className="w-4 h-4" />
            Export CSV
          </a>
        )}
        <a href={jsonlUrl} download
          className="flex items-center gap-2 px-3 py-2 bg-slate-700/30 border border-slate-600/50 text-slate-300 text-sm rounded-lg transition-colors hover:bg-slate-700/50">
          <Download className="w-4 h-4" />
          Export JSONL
        </a>
        <button onClick={() => load()} className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5">
          <RefreshCw className="w-4 h-4" />
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-4 flex flex-wrap gap-3 items-center">
        <select value={actionFilter} onChange={e => onFilterChange(() => setActionFilter(e.target.value))}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
          <option value="">All Actions</option>
          {Object.keys(ACTION_COLORS).map(a => <option key={a} value={a}>{a}</option>)}
        </select>

        <input type="date" value={fromDate}
          onChange={e => onFilterChange(() => setFromDate(e.target.value))}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500"
          title="From date" />
        <span className="text-slate-500 text-sm">→</span>
        <input type="date" value={toDate}
          onChange={e => onFilterChange(() => setToDate(e.target.value))}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500"
          title="To date" />

        {isBioView && (
          <>
            <select value={bioClass} onChange={e => onFilterChange(() => setBioClass(e.target.value))}
              className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
              <option value="">All classes</option>
              {Object.keys(BIO_CLASS_COLORS).map(c => <option key={c} value={c}>{c}</option>)}
            </select>
            <label className="flex items-center gap-2 text-xs text-slate-400 cursor-pointer">
              <input type="checkbox" checked={includeTeardown}
                onChange={e => onFilterChange(() => setIncludeTeardown(e.target.checked))}
                className="accent-blue-500" />
              Include teardown noise
            </label>
          </>
        )}

        {(isShellView || isBioView) && (
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
            <input value={searchQ} onChange={e => { setSearchQ(e.target.value); setOffset(0) }}
              placeholder={isShellView ? 'Search typed command...' : 'Search event message / subsystem...'}
              className="w-full bg-[#0f1629] border border-[#1e2d4a] rounded-lg pl-9 pr-4 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500" />
          </div>
        )}
      </div>

      {loading ? <LoadingSpinner /> : (
        <div className="px-6 pb-6">
          <Card className="overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[#1e2d4a]">
                  <th className="text-left text-slate-400 font-medium px-4 py-3 w-44">Timestamp</th>
                  {isShellView ? (
                    <>
                      <th className="text-left text-slate-400 font-medium px-4 py-3 w-28">User</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Command</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">History File</th>
                    </>
                  ) : isBioView ? (
                    <>
                      <th className="text-left text-slate-400 font-medium px-4 py-3 w-24">Class</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3 w-28">User</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Event</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Requesting Process</th>
                    </>
                  ) : (
                    <>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Action</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Target</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Detail</th>
                      <th className="text-left text-slate-400 font-medium px-4 py-3">Operator</th>
                    </>
                  )}
                </tr>
              </thead>
              <tbody>
                {entries.map((e: any) => (
                  <tr key={e.id} className={`border-b border-[#1e2d4a]/50 hover:bg-white/[0.02] transition-colors duration-[2000ms] ${newIds.has(e.id) ? 'bg-blue-500/10' : ''}`}>
                    <td className="px-4 py-3 text-slate-500 text-xs whitespace-nowrap">
                      {parseServerTime(e.ts)?.toLocaleString()}
                    </td>
                    {isShellView ? (
                      <>
                        <td className="px-4 py-3 text-slate-400 text-xs">{e.user || '—'}</td>
                        <td className="px-4 py-3 text-slate-300 text-xs font-mono max-w-md truncate"
                            title={e.command || ''}>
                          {e.command || '—'}
                        </td>
                        <td className="px-4 py-3 text-slate-500 text-xs font-mono max-w-xs truncate"
                            title={e.process_path || ''}>
                          {e.process_path || '—'}
                        </td>
                      </>
                    ) : isBioView ? (
                      <>
                        <td className="px-4 py-3">
                          <span className={`text-xs font-medium ${BIO_CLASS_COLORS[e.event_class] || 'text-slate-400'}`}>
                            {e.event_class}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-400 text-xs">
                          {e.user || e.console_user || '—'}
                        </td>
                        <td className="px-4 py-3 text-slate-300 text-xs font-mono max-w-lg truncate"
                            title={e.event_message || ''}>
                          {e.event_message || '—'}
                        </td>
                        <td className="px-4 py-3 text-slate-500 text-xs font-mono max-w-xs truncate"
                            title={e.requesting_process || ''}>
                          {e.requesting_process ? e.requesting_process.split('/').pop() : '—'}
                        </td>
                      </>
                    ) : (
                      <>
                        <td className="px-4 py-3">
                          <span className={`text-xs font-medium ${ACTION_COLORS[e.action] || 'text-slate-400'}`}>
                            {e.action}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-400 text-xs font-mono">{e.target || '—'}</td>
                        <td className="px-4 py-3 text-slate-500 text-xs max-w-xs truncate" title={JSON.stringify(e.detail)}>
                          {e.detail ? JSON.stringify(e.detail).slice(0, 80) : '—'}
                        </td>
                        <td className="px-4 py-3 text-slate-500 text-xs">{e.operator}</td>
                      </>
                    )}
                  </tr>
                ))}
                {entries.length === 0 && (
                  <tr><td colSpan={isShellView || isBioView ? 4 : 5} className="px-4 py-12 text-center text-slate-500">
                    No {isShellView ? 'shell exec' : isBioView ? 'biometric' : 'audit log'} entries yet
                  </td></tr>
                )}
              </tbody>
            </table>
          </Card>

          {/* Pagination */}
          {total > 0 && !streaming && (
            <div className="flex items-center justify-between mt-4">
              <button onClick={() => setOffset(Math.max(0, offset - LIMIT))} disabled={offset === 0}
                className="px-4 py-2 text-sm text-slate-400 hover:text-white disabled:opacity-30 transition-colors">
                ← Previous
              </button>
              <span className="text-slate-500 text-sm">
                {offset + 1}–{Math.min(offset + LIMIT, total)} of {total}
                {' '}· page {Math.floor(offset / LIMIT) + 1} of {Math.ceil(total / LIMIT)}
              </span>
              <button onClick={() => setOffset(offset + LIMIT)} disabled={offset + LIMIT >= total}
                className="px-4 py-2 text-sm text-slate-400 hover:text-white disabled:opacity-30 transition-colors">
                Next →
              </button>
            </div>
          )}

          {streaming && (
            <div className="flex items-center justify-end mt-4 text-xs">
              <span className={sseConnected ? 'text-green-500' : 'text-red-400'}>
                {sseConnected ? '● Streaming live' : '○ Reconnecting...'}
                {paused && sseConnected && ' · paused'}
              </span>
            </div>
          )}
        </div>
      )}
    </Layout>
  )
}
