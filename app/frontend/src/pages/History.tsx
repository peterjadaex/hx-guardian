import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { RefreshCw, ChevronRight, Download } from 'lucide-react'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getHistory, getTrends, getReportCsv } from '../lib/api'
import { parseServerTime } from '../lib/time'

export function History() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [sessions, setSessions] = useState<any[]>([])
  const [trends, setTrends] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [searchParams] = useSearchParams()
  const highlightSession = searchParams.get('session') ? parseInt(searchParams.get('session')!) : null

  useEffect(() => { load() }, [])

  const load = async () => {
    setLoading(true)
    try {
      const [histData, trendsData] = await Promise.all([
        getHistory({ limit: 50 }),
        getTrends(30),
      ])
      setSessions(histData.sessions || [])
      setTotal(histData.total || 0)
      setTrends(trendsData.data || [])
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>

  return (
    <Layout>
      <PageHeader title="Scan History" subtitle={`${total} total scans`}>
        <button onClick={load} className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5">
          <RefreshCw className="w-4 h-4" />
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-6 space-y-6">
        {/* Trend Chart */}
        {trends.length > 1 && (
          <Card className="p-5">
            <div className="text-slate-400 text-xs font-medium mb-4">COMPLIANCE SCORE TREND (30 DAYS)</div>
            <ResponsiveContainer width="100%" height={150}>
              <LineChart data={trends}>
                <XAxis dataKey="date" tickFormatter={d => new Date(d).toLocaleDateString()}
                  tick={{ fill: '#475569', fontSize: 10 }} axisLine={false} tickLine={false} />
                <YAxis domain={[0, 100]} tick={{ fill: '#475569', fontSize: 10 }} axisLine={false} tickLine={false}
                  tickFormatter={v => `${v}%`} />
                <Tooltip
                  contentStyle={{ background: '#0f1629', border: '1px solid #1e2d4a', borderRadius: 8, color: '#e2e8f0' }}
                  formatter={(v: unknown) => [`${v}%`, 'Score']}
                  labelFormatter={d => new Date(d).toLocaleString()}
                />
                <ReferenceLine y={90} stroke="#22c55e" strokeDasharray="3 3" opacity={0.4} />
                <ReferenceLine y={70} stroke="#eab308" strokeDasharray="3 3" opacity={0.4} />
                <Line type="monotone" dataKey="score_pct" stroke="#3b82f6" strokeWidth={2}
                  dot={{ fill: '#3b82f6', r: 3 }} activeDot={{ r: 5 }} />
              </LineChart>
            </ResponsiveContainer>
          </Card>
        )}

        {/* Sessions table */}
        <Card className="overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2d4a]">
                <th className="text-left text-slate-400 font-medium px-4 py-3">Date</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Triggered By</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Score</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Results</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              {sessions.map((s: any) => (
                <tr key={s.id}
                  className={`border-b border-[#1e2d4a]/50 hover:bg-white/[0.02] ${s.id === highlightSession ? 'bg-blue-900/10' : ''}`}>
                  <td className="px-4 py-3 text-white">
                    {parseServerTime(s.started_at)?.toLocaleString()}
                    {s.id === highlightSession && (
                      <span className="ml-2 text-xs text-blue-400 bg-blue-900/30 px-1.5 py-0.5 rounded">Latest</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-slate-400 text-xs capitalize">{s.triggered_by}</span>
                  </td>
                  <td className="px-4 py-3">
                    <span className={`font-semibold ${
                      (s.score_pct || 0) >= 90 ? 'text-green-400' :
                      (s.score_pct || 0) >= 70 ? 'text-yellow-400' : 'text-red-400'
                    }`}>
                      {s.score_pct?.toFixed(1) ?? '—'}%
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex gap-3 text-xs">
                      <span className="text-green-400">{s.pass_count} pass</span>
                      <span className="text-red-400">{s.fail_count} fail</span>
                      <span className="text-slate-500">{s.na_count} n/a</span>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Link to={`/history/${s.id}`}
                        className="flex items-center gap-1 text-xs text-slate-400 hover:text-white">
                        View <ChevronRight className="w-3 h-3" />
                      </Link>
                      <a href={getReportCsv(s.id)} download
                        className="flex items-center gap-1 text-xs text-slate-400 hover:text-white">
                        <Download className="w-3 h-3" />
                      </a>
                    </div>
                  </td>
                </tr>
              ))}
              {sessions.length === 0 && (
                <tr><td colSpan={5} className="px-4 py-12 text-center text-slate-500">No scan history yet. Run a full scan.</td></tr>
              )}
            </tbody>
          </table>
        </Card>
      </div>
    </Layout>
  )
}
