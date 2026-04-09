import { useEffect, useState } from 'react'
import { RefreshCw, Download } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getAuditLog, exportAuditCsv } from '../lib/api'

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
}

export function AuditLog() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [entries, setEntries] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [offset, setOffset] = useState(0)
  const [actionFilter, setActionFilter] = useState('')
  const LIMIT = 100

  useEffect(() => {
    load()
  }, [offset, actionFilter])

  const load = async () => {
    setLoading(true)
    try {
      const data = await getAuditLog({ limit: LIMIT, offset, action: actionFilter || undefined })
      setEntries(data.entries || [])
      setTotal(data.total || 0)
    } catch (e: any) { setError(e.message) }
    finally { setLoading(false) }
  }

  return (
    <Layout>
      <PageHeader title="Audit Log" subtitle={`${total} total entries`}>
        <a href={exportAuditCsv()} download
          className="flex items-center gap-2 px-3 py-2 bg-slate-700/30 border border-slate-600/50 text-slate-300 text-sm rounded-lg transition-colors hover:bg-slate-700/50">
          <Download className="w-4 h-4" />
          Export CSV
        </a>
        <button onClick={() => load()} className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5">
          <RefreshCw className="w-4 h-4" />
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-4">
        <select value={actionFilter} onChange={e => { setActionFilter(e.target.value); setOffset(0) }}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
          <option value="">All Actions</option>
          {Object.keys(ACTION_COLORS).map(a => <option key={a} value={a}>{a}</option>)}
        </select>
      </div>

      {loading ? <LoadingSpinner /> : (
        <div className="px-6 pb-6">
          <Card className="overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[#1e2d4a]">
                  <th className="text-left text-slate-400 font-medium px-4 py-3 w-44">Timestamp</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Action</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Target</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Detail</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Operator</th>
                </tr>
              </thead>
              <tbody>
                {entries.map((e: any) => (
                  <tr key={e.id} className="border-b border-[#1e2d4a]/50 hover:bg-white/[0.02]">
                    <td className="px-4 py-3 text-slate-500 text-xs whitespace-nowrap">
                      {new Date(e.ts).toLocaleString()}
                    </td>
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
                  </tr>
                ))}
                {entries.length === 0 && (
                  <tr><td colSpan={5} className="px-4 py-12 text-center text-slate-500">No audit log entries yet</td></tr>
                )}
              </tbody>
            </table>
          </Card>

          {/* Pagination */}
          {total > LIMIT && (
            <div className="flex items-center justify-between mt-4">
              <button onClick={() => setOffset(Math.max(0, offset - LIMIT))} disabled={offset === 0}
                className="px-4 py-2 text-sm text-slate-400 hover:text-white disabled:opacity-30 transition-colors">
                ← Previous
              </button>
              <span className="text-slate-500 text-sm">{offset + 1}–{Math.min(offset + LIMIT, total)} of {total}</span>
              <button onClick={() => setOffset(offset + LIMIT)} disabled={offset + LIMIT >= total}
                className="px-4 py-2 text-sm text-slate-400 hover:text-white disabled:opacity-30 transition-colors">
                Next →
              </button>
            </div>
          )}
        </div>
      )}
    </Layout>
  )
}
