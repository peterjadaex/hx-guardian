import { useEffect, useState } from 'react'
import { FileText, Download, ExternalLink } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getHistory, getReportHtml, getReportCsv } from '../lib/api'
import { parseServerTime } from '../lib/time'

export function Reports() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [sessions, setSessions] = useState<any[]>([])
  const [selectedSession, setSelectedSession] = useState<number | undefined>()

  useEffect(() => {
    getHistory({ limit: 20 })
      .then(d => {
        setSessions(d.sessions || [])
        if (d.sessions?.length > 0) setSelectedSession(d.sessions[0].id)
      })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <Layout><LoadingSpinner /></Layout>

  return (
    <Layout>
      <PageHeader title="Reports" subtitle="Generate and export compliance reports" />

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-6 space-y-4">
        {/* Session selector */}
        <Card className="p-5">
          <div className="text-slate-400 text-xs font-medium mb-3">SELECT SCAN SESSION</div>
          <select
            value={selectedSession || ''}
            onChange={e => setSelectedSession(e.target.value ? parseInt(e.target.value) : undefined)}
            className="bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-blue-500 w-full max-w-sm"
          >
            <option value="">Latest Session</option>
            {sessions.map(s => (
              <option key={s.id} value={s.id}>
                Session #{s.id} — {parseServerTime(s.started_at)?.toLocaleString()} ({s.score_pct?.toFixed(1)}% compliant)
              </option>
            ))}
          </select>
        </Card>

        {/* Report types */}
        <div className="grid grid-cols-2 gap-4">
          <Card className="p-5 hover:border-blue-700/50 transition-colors">
            <div className="flex items-start gap-4">
              <div className="w-10 h-10 rounded-lg bg-blue-900/40 border border-blue-800/30 flex items-center justify-center flex-shrink-0">
                <FileText className="w-5 h-5 text-blue-400" />
              </div>
              <div className="flex-1">
                <div className="text-white font-medium">Full HTML Report</div>
                <div className="text-slate-400 text-sm mt-1">
                  Comprehensive compliance report with all 266 rules, device status, category breakdown.
                  Print to PDF from browser.
                </div>
                <a
                  href={getReportHtml(selectedSession)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 mt-3 px-4 py-2 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-700/50 text-blue-400 text-sm rounded-lg transition-colors"
                >
                  <ExternalLink className="w-3.5 h-3.5" />
                  Open Report
                </a>
              </div>
            </div>
          </Card>

          <Card className="p-5 hover:border-blue-700/50 transition-colors">
            <div className="flex items-start gap-4">
              <div className="w-10 h-10 rounded-lg bg-green-900/40 border border-green-800/30 flex items-center justify-center flex-shrink-0">
                <Download className="w-5 h-5 text-green-400" />
              </div>
              <div className="flex-1">
                <div className="text-white font-medium">CSV Export</div>
                <div className="text-slate-400 text-sm mt-1">
                  Export all scan results as CSV. Includes rule name, category, status,
                  result values, and timestamps.
                </div>
                <a
                  href={getReportCsv(selectedSession)}
                  download
                  className="inline-flex items-center gap-2 mt-3 px-4 py-2 bg-green-600/20 hover:bg-green-600/30 border border-green-700/50 text-green-400 text-sm rounded-lg transition-colors"
                >
                  <Download className="w-3.5 h-3.5" />
                  Download CSV
                </a>
              </div>
            </div>
          </Card>
        </div>

        {sessions.length === 0 && (
          <div className="text-center py-8 text-slate-500">
            No completed scans yet. Run a full scan to generate reports.
          </div>
        )}
      </div>
    </Layout>
  )
}
