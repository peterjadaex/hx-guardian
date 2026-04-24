import { useEffect, useState, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { Search, Play, ChevronRight, Wrench, Loader2, ArrowUpDown, ArrowUp, ArrowDown, AlertTriangle, RotateCcw } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { StatusBadge } from '../components/StatusBadge'
import { getRules, getRuleMeta, startScan, getSession } from '../lib/api'
import { parseServerTime } from '../lib/time'

const STATUSES = ['ALL', 'FAIL', 'PASS', 'NOT_APPLICABLE', 'MDM_REQUIRED', 'EXEMPT', 'ERROR', 'NEVER_SCANNED']

type SortCol = 'rule' | 'category' | 'severity' | 'status' | 'last_scanned'
type SortDir = 'asc' | 'desc'
const SEV_ORDER: Record<string, number> = { high: 0, medium: 1, low: 2 }

const SELECT_CLS = "bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500"

export function Rules() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [rules, setRules] = useState<any[]>([])
  const [meta, setMeta] = useState<{ categories: string[]; standards: string[]; total: number }>({ categories: [], standards: [], total: 0 })
  const [q, setQ] = useState('')
  const [category, setCategory] = useState('')
  const [status, setStatus] = useState('')
  const [standard, setStandard] = useState('')
  const [severity, setSeverity] = useState('')
  const [scanning, setScanning] = useState(false)
  const [sortCol, setSortCol] = useState<SortCol | null>(null)
  const [sortDir, setSortDir] = useState<SortDir>('asc')

  useEffect(() => {
    getRuleMeta().then(setMeta).catch(() => {})
    loadRules()
  }, [])

  useEffect(() => {
    loadRules()
  }, [q, category, status, standard, severity])

  const loadRules = async () => {
    setLoading(true)
    try {
      const params: Record<string, string> = {}
      if (q) params.q = q
      if (category) params.category = category
      if (status && status !== 'ALL') params.status = status
      if (standard) params.standard = standard
      if (severity) params.severity = severity
      const data = await getRules(params)
      setRules(data.rules || [])
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const handleScanCategory = async () => {
    const filter = category ? { category } : standard ? { standard } : undefined
    setScanning(true)
    try {
      const { session_id } = await startScan(filter)
      // Poll until the background scan session finishes, then reload results
      for (let i = 0; i < 300; i++) {
        await new Promise(r => setTimeout(r, 2000))
        const sess = await getSession(session_id)
        if (!sess.is_running) break
      }
      await loadRules()
    } catch (e: any) {
      setError((e.response?.data?.detail) || e.message)
    } finally {
      setScanning(false)
    }
  }

  const handleSort = (col: SortCol) => {
    if (sortCol === col) {
      setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    } else {
      setSortCol(col)
      setSortDir('asc')
    }
  }

  const sortedRules = useMemo(() => {
    if (!sortCol) return rules
    return [...rules].sort((a, b) => {
      let cmp = 0
      if (sortCol === 'rule')         cmp = a.rule.localeCompare(b.rule)
      if (sortCol === 'category')     cmp = (a.category ?? '').localeCompare(b.category ?? '')
      if (sortCol === 'severity')     cmp = (SEV_ORDER[a.severity] ?? 3) - (SEV_ORDER[b.severity] ?? 3)
      if (sortCol === 'status')       cmp = a.current_status.localeCompare(b.current_status)
      if (sortCol === 'last_scanned') {
        const da = a.last_scan?.scanned_at ? +new Date(a.last_scan.scanned_at) : 0
        const db = b.last_scan?.scanned_at ? +new Date(b.last_scan.scanned_at) : 0
        cmp = da - db
      }
      return sortDir === 'asc' ? cmp : -cmp
    })
  }, [rules, sortCol, sortDir])

  const SortIcon = ({ col }: { col: SortCol }) => {
    if (sortCol !== col) return <ArrowUpDown className="w-3 h-3 ml-1 text-slate-600 inline" />
    return sortDir === 'asc'
      ? <ArrowUp   className="w-3 h-3 ml-1 text-blue-400 inline" />
      : <ArrowDown className="w-3 h-3 ml-1 text-blue-400 inline" />
  }

  const thSortable = "text-left text-slate-400 font-medium px-4 py-3 cursor-pointer hover:text-slate-200 select-none whitespace-nowrap"
  const thStatic   = "text-left text-slate-400 font-medium px-4 py-3 whitespace-nowrap"

  return (
    <Layout>
      <PageHeader title="Security Rules" subtitle={`${sortedRules.length} of ${meta.total || sortedRules.length} rules`}>
        <button
          onClick={handleScanCategory}
          disabled={scanning}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-900 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
        >
          {scanning ? <Loader2 className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4" />}
          {scanning ? 'Scanning...' : `Scan ${category || standard || 'All'}`}
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      {/* Filters */}
      <div className="px-6 pb-4 flex flex-wrap gap-3">
        <div className="relative flex-1 min-w-48">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
          <input
            value={q}
            onChange={e => setQ(e.target.value)}
            placeholder="Search rules..."
            className="w-full bg-[#0f1629] border border-[#1e2d4a] rounded-lg pl-9 pr-4 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500"
          />
        </div>

        <select value={status} onChange={e => setStatus(e.target.value)} className={SELECT_CLS}>
          {STATUSES.map(s => <option key={s} value={s === 'ALL' ? '' : s}>{s === 'ALL' ? 'All Statuses' : s}</option>)}
        </select>

        <select value={severity} onChange={e => setSeverity(e.target.value)} className={SELECT_CLS}>
          <option value="">All Severities</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>

        <select value={category} onChange={e => setCategory(e.target.value)} className={SELECT_CLS}>
          <option value="">All Categories</option>
          {meta.categories.map(c => <option key={c} value={c}>{c}</option>)}
        </select>

        <select value={standard} onChange={e => setStandard(e.target.value)} className={SELECT_CLS}>
          <option value="">All Standards</option>
          {meta.standards.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
      </div>

      {loading ? <LoadingSpinner /> : (
        <div className="px-6 pb-6">
          <Card className="overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[#1e2d4a]">
                    <th className={thSortable} onClick={() => handleSort('rule')}>
                      Rule <SortIcon col="rule" />
                    </th>
                    <th className={thSortable} onClick={() => handleSort('category')}>
                      Category <SortIcon col="category" />
                    </th>
                    <th className={thStatic}>Standards</th>
                    <th className={thSortable} onClick={() => handleSort('severity')}>
                      Severity <SortIcon col="severity" />
                    </th>
                    <th className={thSortable} onClick={() => handleSort('status')}>
                      Status <SortIcon col="status" />
                    </th>
                    <th className={thSortable} onClick={() => handleSort('last_scanned')}>
                      Last Scanned <SortIcon col="last_scanned" />
                    </th>
                    <th className={thStatic}>Capabilities</th>
                    <th className="px-4 py-3"></th>
                  </tr>
                </thead>
                <tbody>
                  {sortedRules.map((rule) => (
                    <tr key={rule.rule} className="border-b border-[#1e2d4a]/50 hover:bg-white/[0.02] transition-colors">
                      {/* Rule — ID + full description + impact */}
                      <td className="px-4 py-3 max-w-sm">
                        <div className="text-white font-medium text-xs font-mono">{rule.rule}</div>
                        <div className="text-slate-400 text-xs mt-0.5">{rule.description}</div>
                        {rule.impact && (
                          <div className="flex items-start gap-1 mt-1.5">
                            <AlertTriangle className="w-3 h-3 text-amber-500 flex-shrink-0 mt-0.5" />
                            <span className="text-amber-600/80 text-xs leading-tight">{rule.impact}</span>
                          </div>
                        )}
                      </td>

                      {/* Category */}
                      <td className="px-4 py-3">
                        <span className="text-slate-400 text-xs">{rule.category}</span>
                      </td>

                      {/* Standards */}
                      <td className="px-4 py-3">
                        <div className="flex gap-1 flex-wrap">
                          {rule.standards?.['800-53r5_high'] && (
                            <span className="text-xs px-1.5 py-0.5 bg-purple-900/30 text-purple-400 rounded">NIST</span>
                          )}
                          {rule.standards?.cisv8 && (
                            <span className="text-xs px-1.5 py-0.5 bg-blue-900/30 text-blue-400 rounded">CIS v8</span>
                          )}
                          {rule.standards?.cis_lvl2 && (
                            <span className="text-xs px-1.5 py-0.5 bg-teal-900/30 text-teal-400 rounded">CIS L2</span>
                          )}
                        </div>
                      </td>

                      {/* Severity */}
                      <td className="px-4 py-3">
                        <StatusBadge status={rule.severity} size="sm" />
                      </td>

                      {/* Status */}
                      <td className="px-4 py-3">
                        <StatusBadge status={rule.current_status} size="sm" />
                      </td>

                      {/* Last Scanned */}
                      <td className="px-4 py-3 text-slate-500 text-xs whitespace-nowrap">
                        {rule.last_scan?.scanned_at
                          ? parseServerTime(rule.last_scan.scanned_at)?.toLocaleDateString()
                          : <span className="text-slate-700">—</span>}
                      </td>

                      {/* Capabilities */}
                      <td className="px-4 py-3">
                        <div className="flex gap-1.5">
                          {rule.has_scan && <span className="text-xs px-1.5 py-0.5 bg-slate-700/50 text-slate-400 rounded">Scan</span>}
                          {rule.has_fix && <span className="text-xs px-1.5 py-0.5 bg-green-900/30 text-green-500 rounded flex items-center gap-0.5"><Wrench className="w-2.5 h-2.5" />Fix</span>}
                          {rule.has_undo_fix && <span className="text-xs px-1.5 py-0.5 bg-amber-900/30 text-amber-400 rounded flex items-center gap-0.5"><RotateCcw className="w-2.5 h-2.5" />Undo</span>}
                        </div>
                      </td>

                      {/* Action */}
                      <td className="px-4 py-3">
                        <Link to={`/rules/${rule.rule}`} className="text-slate-500 hover:text-white transition-colors">
                          <ChevronRight className="w-4 h-4" />
                        </Link>
                      </td>
                    </tr>
                  ))}
                  {sortedRules.length === 0 && (
                    <tr>
                      <td colSpan={8} className="px-4 py-12 text-center text-slate-500">
                        No rules match your filters
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </Card>
        </div>
      )}
    </Layout>
  )
}
