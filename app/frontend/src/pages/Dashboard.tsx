import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { RefreshCw, Play, CheckCircle, XCircle, Shield, Monitor, AlertTriangle } from 'lucide-react'
import { PieChart, Pie, Cell, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { StatusBadge } from '../components/StatusBadge'
import { getHistory, getTrends, getCategoryBreakdown, startScan, getPreflight, getDeviceStatus } from '../lib/api'
import { useActiveScan } from '../lib/useActiveScan'
import { useRunnerStatus } from '../lib/useRunnerStatus'
import { statusHex, statusLabel } from '../lib/status'
import { parseServerTime } from '../lib/time'


export function Dashboard() {
  const navigate = useNavigate()
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [latestSession, setLatestSession] = useState<any>(null)
  const [categories, setCategories] = useState<any[]>([])
  const [trends, setTrends] = useState<any[]>([])
  const [preflight, setPreflight] = useState<any>(null)
  const [deviceStatus, setDeviceStatus] = useState<any>(null)

  useEffect(() => {
    loadData()
  }, [])

  // quiet skips the full-page spinner, for refreshes the operator did not ask for.
  const loadData = async (quiet = false) => {
    if (!quiet) setLoading(true)
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
      if (!quiet) setLoading(false)
    }
  }

  const { scanning, trackSession } = useActiveScan(() => loadData(true))
  const runner = useRunnerStatus()

  const handleFullScan = async () => {
    try {
      const { session_id } = await startScan()
      trackSession(session_id)
      navigate(`/history?session=${session_id}`)
    } catch (e: any) {
      setError(e.message)
    }
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>

  const score = latestSession?.score_pct ?? null
  // Keyed by raw status so the colour lookup and the label come from one map.
  const pieData = latestSession ? [
    { status: 'PASS', value: latestSession.pass_count },
    { status: 'FAIL', value: latestSession.fail_count },
    { status: 'ERROR', value: latestSession.error_count },
    { status: 'NOT_ASSESSED', value: latestSession.not_assessed_count },
    { status: 'NOT_APPLICABLE', value: latestSession.na_count },
    { status: 'MDM_REQUIRED', value: latestSession.mdm_count },
    { status: 'EXEMPT', value: latestSession.exempt_count },
  ].filter(d => (d.value ?? 0) > 0).map(d => ({ ...d, name: statusLabel(d.status) })) : []

  const scoreColor = score === null ? '#64748b' : score >= 90 ? '#22c55e' : score >= 70 ? '#eab308' : '#ef4444'
  const notAssessed = latestSession?.not_assessed_count ?? 0
  const assessed = latestSession?.assessed ?? 0

  const uptimeStr = deviceStatus?.uptime_secs
    ? `${Math.floor(deviceStatus.uptime_secs / 3600)}h ${Math.floor((deviceStatus.uptime_secs % 3600) / 60)}m`
    : 'Unknown'

  return (
    <Layout>
      <PageHeader title="Security Dashboard" subtitle="Airgap Device Compliance Overview">
        <button
          onClick={() => loadData()}
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
          {scanning ? 'Scan in progress…' : 'Run Full Scan'}
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-6 space-y-6">
        {runner.loaded && !runner.available && (
          <div className="flex items-start gap-3 px-4 py-3 rounded-lg bg-red-900/30 border border-red-700/50">
            <AlertTriangle className="w-4 h-4 text-red-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm">
              <div className="text-red-300 font-medium">
                Privileged runner unavailable — rules cannot be assessed and remediation is unavailable.
              </div>
              <div className="text-red-400/80 text-xs mt-1">{runner.detail}</div>
            </div>
          </div>
        )}

        {/* Pre-flight + Device Strip */}
        <div className="grid grid-cols-6 gap-4">
          {/* Pre-flight */}
          <Card className="p-4 col-span-1">
            <div className="text-slate-400 text-xs font-medium mb-2">SIGNING READINESS</div>
            {preflight ? (
              <div className="flex flex-col gap-1">
                <StatusBadge status={preflight.readiness} size="lg" />
                {preflight.failing_universal_rules?.length > 0 && (
                  <div className="text-xs mt-2">
                    <div className="text-red-400 font-medium">
                      {preflight.failing_universal_rules.length} critical {preflight.failing_universal_rules.length === 1 ? 'failure' : 'failures'}
                    </div>
                    <ul className="mt-1 space-y-0.5">
                      {preflight.failing_universal_rules.slice(0, 5).map((r: string) => (
                        <li key={r}>
                          <button
                            onClick={() => navigate(`/rules/${r}`)}
                            className="text-slate-400 hover:text-slate-200 truncate block max-w-full text-left"
                            title={r}
                          >
                            {r}
                          </button>
                        </li>
                      ))}
                    </ul>
                    {preflight.failing_universal_rules.length > 5 && (
                      <button
                        onClick={() => navigate('/rules')}
                        className="text-slate-500 hover:text-slate-300 mt-0.5"
                      >
                        +{preflight.failing_universal_rules.length - 5} more…
                      </button>
                    )}
                  </div>
                )}
                {preflight.device_issues?.length > 0 && (
                  <div className="text-xs mt-2">
                    <div className="text-orange-400 font-medium">
                      {preflight.device_issues.length} device {preflight.device_issues.length === 1 ? 'issue' : 'issues'}
                    </div>
                    <ul className="mt-1 space-y-0.5 text-orange-300/80">
                      {preflight.device_issues.map((issue: string) => (
                        <li key={issue}>{issue}</li>
                      ))}
                    </ul>
                  </div>
                )}
                {/* Explains why readiness is not green when nothing is failing. */}
                {preflight.unassessed_universal_rules?.length > 0 && (
                  <div className="text-amber-400 text-xs">
                    {preflight.unassessed_universal_rules.length} not assessed
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
            { label: 'Firewall', value: deviceStatus?.firewall_on, ok: true },
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

          {/* Secure Boot reports a level rather than a boolean */}
          <Card className="p-4 flex flex-col gap-1">
            <div className="text-slate-400 text-xs font-medium">Secure Boot</div>
            <div className={`text-sm font-medium ${
              deviceStatus?.secure_boot === 'full' ? 'text-green-400' :
              deviceStatus?.secure_boot === 'medium' ? 'text-yellow-400' :
              deviceStatus?.secure_boot === 'none' ? 'text-red-400' : 'text-slate-500'
            }`}>
              {deviceStatus?.secure_boot
                ? deviceStatus.secure_boot.charAt(0).toUpperCase() + deviceStatus.secure_boot.slice(1)
                : 'Unknown'}
            </div>
          </Card>
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
                        <Cell key={entry.status} fill={statusHex(entry.status)} />
                      ))}
                    </Pie>
                  </PieChart>
                  <div className="absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-3xl font-bold" style={{ color: scoreColor }}>
                      {score === null ? '—' : `${score.toFixed(0)}%`}
                    </span>
                    <span className="text-slate-500 text-xs">compliant</span>
                  </div>
                </div>
                {/* Coverage sits with the score: a 100% over 12 rules must never
                    be mistakable for a 100% over the whole baseline. */}
                <div className="text-slate-500 text-xs mt-2">
                  {assessed} of {latestSession.total_rules} rules assessed
                </div>
                {notAssessed > 0 && (
                  <div className="flex items-center gap-1.5 text-amber-400 text-xs mt-1">
                    <AlertTriangle className="w-3 h-3 flex-shrink-0" />
                    Coverage incomplete — {notAssessed} not assessed
                  </div>
                )}
                <div className="grid grid-cols-2 gap-x-4 gap-y-1 mt-3 text-xs w-full">
                  {pieData.map(d => (
                    <div key={d.status} className="flex items-center gap-1.5">
                      <div className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: statusHex(d.status) }} />
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
                    formatter={(v: unknown) => [v == null ? '— not assessed' : `${v}%`, 'Score']}
                  />
                  <Bar dataKey="score_pct" radius={[0, 4, 4, 0]}>
                    {categories.map((c) => (
                      // Null score = nothing in this category was assessed —
                      // grey, not the red that 0% would imply.
                      <Cell key={c.category} fill={c.score_pct == null ? '#64748b' : c.score_pct >= 90 ? '#22c55e' : c.score_pct >= 70 ? '#eab308' : '#ef4444'} />
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

        {/* Device information */}
        <Card className="p-5">
          <div className="text-slate-400 text-xs font-medium mb-4 flex items-center gap-2">
            <Monitor className="w-4 h-4" /> DEVICE INFORMATION
          </div>
          <div className="grid grid-cols-5 gap-4">
            {[
              ['Model', deviceStatus?.hardware_model],
              ['macOS Version', deviceStatus?.os_version],
              ['Build', deviceStatus?.build_version],
              ['Serial Number', deviceStatus?.serial_number],
              ['Uptime', uptimeStr],
            ].map(([label, val]) => (
              <div key={label} className="flex flex-col gap-1">
                <span className="text-slate-400 text-xs">{label}</span>
                <span className="text-white text-sm font-mono">{val || '—'}</span>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </Layout>
  )
}
