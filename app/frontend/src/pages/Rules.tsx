import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Search, Play, ChevronRight, Wrench, Loader2 } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { StatusBadge } from '../components/StatusBadge'
import { getRules, getRuleMeta, startScan } from '../lib/api'

const STATUSES = ['ALL', 'FAIL', 'PASS', 'NOT_APPLICABLE', 'MDM_REQUIRED', 'EXEMPT', 'ERROR', 'NEVER_SCANNED']

export function Rules() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [rules, setRules] = useState<any[]>([])
  const [meta, setMeta] = useState<{ categories: string[]; standards: string[] }>({ categories: [], standards: [] })
  const [q, setQ] = useState('')
  const [category, setCategory] = useState('')
  const [status, setStatus] = useState('')
  const [standard, setStandard] = useState('')
  const [scanning, setScanning] = useState(false)

  useEffect(() => {
    getRuleMeta().then(setMeta).catch(() => {})
    loadRules()
  }, [])

  useEffect(() => {
    loadRules()
  }, [q, category, status, standard])

  const loadRules = async () => {
    setLoading(true)
    try {
      const params: Record<string, string> = {}
      if (q) params.q = q
      if (category) params.category = category
      if (status && status !== 'ALL') params.status = status
      if (standard) params.standard = standard
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
      await startScan(filter)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setScanning(false)
    }
  }

  return (
    <Layout>
      <PageHeader title="Security Rules" subtitle={`${rules.length} rules`}>
        <button
          onClick={handleScanCategory}
          disabled={scanning}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-900 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
        >
          {scanning
            ? <Loader2 className="w-4 h-4 animate-spin" />
            : <Play className="w-4 h-4" />}
          {scanning ? 'Starting...' : `Scan ${category || standard || 'All'}`}
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

        <select value={status} onChange={e => setStatus(e.target.value)}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
          {STATUSES.map(s => <option key={s} value={s === 'ALL' ? '' : s}>{s === 'ALL' ? 'All Statuses' : s}</option>)}
        </select>

        <select value={category} onChange={e => setCategory(e.target.value)}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
          <option value="">All Categories</option>
          {meta.categories.map(c => <option key={c} value={c}>{c}</option>)}
        </select>

        <select value={standard} onChange={e => setStandard(e.target.value)}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
          <option value="">All Standards</option>
          {meta.standards.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
      </div>

      {loading ? <LoadingSpinner /> : (
        <div className="px-6 pb-6">
          <Card className="overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[#1e2d4a]">
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Rule</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Category</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Standards</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Status</th>
                  <th className="text-left text-slate-400 font-medium px-4 py-3">Capabilities</th>
                  <th className="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                {rules.map((rule) => (
                  <tr key={rule.rule} className="border-b border-[#1e2d4a]/50 hover:bg-white/[0.02] transition-colors">
                    <td className="px-4 py-3">
                      <div className="text-white font-medium text-xs font-mono">{rule.rule}</div>
                      <div className="text-slate-500 text-xs mt-0.5 max-w-xs truncate">{rule.description}</div>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-slate-400 text-xs">{rule.category}</span>
                    </td>
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
                    <td className="px-4 py-3">
                      <StatusBadge status={rule.current_status} size="sm" />
                      {rule.last_scan?.scanned_at && (
                        <div className="text-slate-600 text-xs mt-1">
                          {new Date(rule.last_scan.scanned_at).toLocaleDateString()}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex gap-1.5">
                        {rule.has_scan && <span className="text-xs px-1.5 py-0.5 bg-slate-700/50 text-slate-400 rounded">Scan</span>}
                        {rule.has_fix && <span className="text-xs px-1.5 py-0.5 bg-green-900/30 text-green-500 rounded flex items-center gap-0.5"><Wrench className="w-2.5 h-2.5" />Fix</span>}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <Link to={`/rules/${rule.rule}`}
                        className="text-slate-500 hover:text-white transition-colors">
                        <ChevronRight className="w-4 h-4" />
                      </Link>
                    </td>
                  </tr>
                ))}
                {rules.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-4 py-12 text-center text-slate-500">
                      No rules match your filters
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </Card>
        </div>
      )}
    </Layout>
  )
}
