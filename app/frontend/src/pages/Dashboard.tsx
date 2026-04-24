import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { RefreshCw, Play, CheckCircle, XCircle, Shield } from 'lucide-react'
import { PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { StatusBadge } from '../components/StatusBadge'
import { getHistory, getTrends, getCategoryBreakdown, startScan, getPreflight, getDeviceStatus } from '../lib/api'
import { parseServerTime } from '../lib/time'

const STATUS_COLORS: Record<string, string> = {
  PASS: '#22c55e',
  FAIL: '#ef4444',
  NOT_APPLICABLE: '#475569',
  MDM_REQUIRED: '#3b82f6',
  EXEMPT: '#eab308',
  ERROR: '#f97316',
}

export function Dashboard() {
  const navigate = useNavigate()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [latestSession, setLatestSession] = useState<any>(null)
  const [categories, setCategories] = useState<any[]>([])
  const [trends, setTrends] = useState<any[]>([])
  const [preflight, setPreflight] = useState<any>(null)
  const [deviceStatus, setDeviceStatus] = useState<any>(null)
  const [scanning, setScanning] = useState(false)

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    setLoading(true)
    try {
      const [histData, trendsData, catData, preflightData, deviceData] = await Promise.allSettled([
        getHistory({ limit: 1 }),
        getTrends(30),
        getCategoryBreakdown(),
        getPreflight(),
        getDeviceStatus(),
      ])

      if (histData.status === 'fulfilled' && histData.value.sessions?.length > 0) {
        setLatestSession(histData.value.sessions[0])
      }
      if (trendsData.status === 'fulfilled') {
        setTrends(trendsData.value.data || [])
      }
      if (catData.status === 'fulfilled') {
        setCategories(catData.value.categories || [])
      }
      if (preflightData.status === 'fulfilled') {
        setPreflight(preflightData.value)
      }
      if (deviceData.status === 'fulfilled') {
        setDeviceStatus(deviceData.value)
      }
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const handleFullScan = async () => {
    setScanning(true)
    try {
      const { session_id } = await startScan()
      navigate(`/history?session=${session_id}`)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setScanning(false)
    }
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>

  const score = latestSession?.score_pct ?? null
  const pieData = latestSession ? [
    { name: 'PASS', value: latestSession.pass_count },
    { name: 'FAIL', value: latestSession.fail_count },
    { name: 'N/A', value: latestSession.na_count },
    { name: 'Not Scannable', value: latestSession.mdm_count },
    { name: 'Exempt', value: latestSession.exempt_count },
  ].filter(d => d.value > 0) : []

  const scoreColor = score === null ? '#64748b' : score >= 90 ? '#22c55e' : score >= 70 ? '#eab308' : '#ef4444'

  return (
    <Layout>
      <PageHeader title="Security Dashboard" subtitle="Airgap Device Compliance Overview">
        <button
          onClick={loadData}
          className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
        <button
          onClick={handleFullScan}
          disabled={scanning}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-900 text-white text-sm font-medium rounded-lg transition-colors"
        >
          <Play className="w-4 h-4" />
          {scanning ? 'Starting...' : 'Run Full Scan'}
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-6 space-y-6">
        {/* Pre-flight + Device Strip */}
        <div className="grid grid-cols-4 gap-4">
          {/* Pre-flight */}
          <Card className="p-4 col-span-1">
            <div className="text-slate-400 text-xs font-medium mb-2">SIGNING READINESS</div>
            {preflight ? (
              <div className="flex flex-col gap-1">
                <StatusBadge status={preflight.readiness} size="lg" />
                {preflight.failing_universal_rules?.length > 0 && (
                  <div className="text-slate-400 text-xs mt-2">
                    {preflight.failing_universal_rules.length} critical {preflight.failing_universal_rules.length === 1 ? 'failure' : 'failures'}
                  </div>
                )}
                {preflight.device_issues?.length > 0 && (
                  <div className="text-orange-400 text-xs">
                    {preflight.device_issues.length} device {preflight.device_issues.length === 1 ? 'issue' : 'issues'}
                  </div>
                )}
              </div>
            ) : (
              <div className="text-slate-500 text-sm">No data</div>
            )}
          </Card>

          {/* Device status strip */}
          {[
            { label: 'SIP', value: deviceStatus?.sip_enabled, ok: true },
            { label: 'FileVault', value: deviceStatus?.filevault_on, ok: true },
            { label: 'Gatekeeper', value: deviceStatus?.gatekeeper_on, ok: true },
          ].map(({ label, value, ok }) => (
            <Card key={label} className="p-4 flex flex-col gap-1">
              <div className="text-slate-400 text-xs font-medium">{label}</div>
              <div className="flex items-center gap-2">
                {value === undefined || value === null ? (
                  <span className="text-slate-500 text-sm">Unknown</span>
                ) : value === ok ? (
                  <><CheckCircle className="w-4 h-4 text-green-400" /><span className="text-green-400 text-sm font-medium">Enabled</span></>
                ) : (
                  <><XCircle className="w-4 h-4 text-red-400" /><span className="text-red-400 text-sm font-medium">Disabled</span></>
                )}
              </div>
            </Card>
          ))}
        </div>

        {/* Score + Category breakdown */}
        <div className="grid grid-cols-3 gap-6">
          {/* Compliance score donut */}
          <Card className="p-5 flex flex-col items-center">
            <div className="text-slate-400 text-xs font-medium mb-4 self-start">COMPLIANCE SCORE</div>
            {latestSession ? (
              <>
                <div className="relative">
                  <PieChart width={160} height={160}>
                    <Pie data={pieData} cx={80} cy={80} innerRadius={55} outerRadius={75} dataKey="value" strokeWidth={0}>
                      {pieData.map((entry) => (
                        <Cell key={entry.name} fill={STATUS_COLORS[entry.name] || STATUS_COLORS[entry.name.toUpperCase()] || '#64748b'} />
                      ))}
                    </Pie>
                  </PieChart>
                  <div className="absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-3xl font-bold" style={{ color: scoreColor }}>{score?.toFixed(0)}%</span>
                    <span className="text-slate-500 text-xs">compliant</span>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-x-4 gap-y-1 mt-3 text-xs w-full">
                  {pieData.map(d => (
                    <div key={d.name} className="flex items-center gap-1.5">
                      <div className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: STATUS_COLORS[d.name] || STATUS_COLORS[d.name.toUpperCase()] || '#64748b' }} />
                      <span className="text-slate-400">{d.name}: <span className="text-white">{d.value}</span></span>
                    </div>
                  ))}
                </div>
                {latestSession.started_at && (
                  <div className="text-slate-600 text-xs mt-3">
                    Last scan: {parseServerTime(latestSession.started_at)?.toLocaleString()}
                  </div>
                )}
              </>
            ) : (
              <div className="flex flex-col items-center gap-3 py-8">
                <Shield className="w-12 h-12 text-slate-700" />
                <div className="text-slate-500 text-sm text-center">No scans yet.<br />Run a full scan to see results.</div>
              </div>
            )}
          </Card>

          {/* Category bar chart */}
          <Card className="p-5 col-span-2">
            <div className="text-slate-400 text-xs font-medium mb-4">COMPLIANCE BY CATEGORY</div>
            {categories.length > 0 ? (
              <ResponsiveContainer width="100%" height={categories.length * 32 + 20}>
                <BarChart data={categories} layout="vertical" barSize={10} barCategoryGap={8} margin={{ top: 0, right: 10, bottom: 0, left: 0 }}>
                  <XAxis type="number" domain={[0, 100]} tick={{ fill: '#475569', fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={v => `${v}%`} />
                  <YAxis
                    type="category"
                    dataKey="category"
                    width={140}
                    interval={0}
                    axisLine={false}
                    tickLine={false}
                    tick={({ x, y, payload }: any) => (
                      <text x={x} y={y} dy={4} textAnchor="end" fill="#94a3b8" fontSize={11}>
                        {payload.value}
                      </text>
                    )}
                  />
                  <Tooltip
                    contentStyle={{ background: '#0f1629', border: '1px solid #1e2d4a', borderRadius: 8, color: '#e2e8f0' }}
                    formatter={(v: unknown) => [`${v}%`, 'Score']}
                  />
                  <Bar dataKey="score_pct" radius={[0, 4, 4, 0]}>
                    {categories.map((c) => (
                      <Cell key={c.category} fill={c.score_pct >= 90 ? '#22c55e' : c.score_pct >= 70 ? '#eab308' : '#ef4444'} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="flex items-center justify-center h-40 text-slate-600 text-sm">
                Run a scan to see category breakdown
              </div>
            )}
          </Card>
        </div>

        {/* Trend chart */}
        {trends.length > 1 && (
          <Card className="p-5">
            <div className="text-slate-400 text-xs font-medium mb-4">COMPLIANCE TREND (30 DAYS)</div>
            <ResponsiveContainer width="100%" height={120}>
              <BarChart data={trends}>
                <XAxis dataKey="date" tickFormatter={d => new Date(d).toLocaleDateString()} tick={{ fill: '#475569', fontSize: 10 }} axisLine={false} tickLine={false} />
                <YAxis domain={[0, 100]} tick={{ fill: '#475569', fontSize: 10 }} axisLine={false} tickLine={false} tickFormatter={v => `${v}%`} />
                <Tooltip
                  contentStyle={{ background: '#0f1629', border: '1px solid #1e2d4a', borderRadius: 8, color: '#e2e8f0' }}
                  formatter={(v: unknown) => [`${v}%`, 'Score']}
                  labelFormatter={d => new Date(d).toLocaleString()}
                />
                <Bar dataKey="score_pct" fill="#3b82f6" radius={[2, 2, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Card>
        )}
      </div>
    </Layout>
  )
}
