import { useEffect, useState } from 'react'
import { Plus, Trash2, Play, Power } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getSchedules, createSchedule, deleteSchedule, updateSchedule, runScheduleNow } from '../lib/api'
import { parseServerTime } from '../lib/time'

const CRON_PRESETS = [
  { label: 'Daily at 6 AM', value: '0 6 * * *' },
  { label: 'Daily at midnight', value: '0 0 * * *' },
  { label: 'Every 6 hours', value: '0 */6 * * *' },
  { label: 'Weekly (Monday 9 AM)', value: '0 9 * * 1' },
  { label: 'Every hour', value: '0 * * * *' },
]

export function Schedule() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [schedules, setSchedules] = useState<any[]>([])
  const [showForm, setShowForm] = useState(false)
  const [name, setName] = useState('')
  const [cronExpr, setCronExpr] = useState('0 6 * * *')
  const [category, setCategory] = useState('')

  useEffect(() => { load() }, [])

  const load = async () => {
    setLoading(true)
    try { setSchedules((await getSchedules()).schedules || []) }
    catch (e: any) { setError(e.message) }
    finally { setLoading(false) }
  }

  const handleCreate = async () => {
    if (!name || !cronExpr) return
    try {
      await createSchedule({
        name,
        cron_expr: cronExpr,
        filter: category ? { category } : undefined,
        enabled: true,
      })
      setShowForm(false)
      setName('')
      setCronExpr('0 6 * * *')
      setCategory('')
      await load()
    } catch (e: any) { setError(e.message) }
  }

  const handleToggle = async (s: any) => {
    try { await updateSchedule(s.id, { enabled: !s.enabled }); await load() }
    catch (e: any) { setError(e.message) }
  }

  const handleDelete = async (id: number) => {
    if (!confirm('Delete this schedule?')) return
    try { await deleteSchedule(id); await load() }
    catch (e: any) { setError(e.message) }
  }

  const handleRunNow = async (id: number) => {
    try { await runScheduleNow(id); alert('Scan triggered!') }
    catch (e: any) { setError(e.message) }
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>

  return (
    <Layout>
      <PageHeader title="Scheduled Scans" subtitle="Automated compliance monitoring">
        <button onClick={() => setShowForm(true)}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600/20 border border-blue-700/50 text-blue-400 text-sm rounded-lg transition-colors hover:bg-blue-600/30">
          <Plus className="w-4 h-4" />
          Add Schedule
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      {showForm && (
        <div className="mx-6 mb-4">
          <Card className="p-5">
            <div className="text-slate-300 font-medium mb-4">New Scheduled Scan</div>
            <div className="space-y-3">
              <div>
                <label className="text-slate-400 text-xs mb-1 block">Schedule Name *</label>
                <input value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Daily Compliance Check"
                  className="w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500" />
              </div>
              <div>
                <label className="text-slate-400 text-xs mb-1 block">Cron Expression *</label>
                <div className="flex gap-2">
                  <input value={cronExpr} onChange={e => setCronExpr(e.target.value)} placeholder="0 6 * * *"
                    className="flex-1 bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white font-mono placeholder-slate-600 focus:outline-none focus:border-blue-500" />
                  <select onChange={e => { if (e.target.value) setCronExpr(e.target.value) }}
                    className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300">
                    <option value="">Presets</option>
                    {CRON_PRESETS.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
                  </select>
                </div>
              </div>
              <div>
                <label className="text-slate-400 text-xs mb-1 block">Category Filter (optional)</label>
                <input value={category} onChange={e => setCategory(e.target.value)} placeholder="e.g. Auditing (blank = all rules)"
                  className="w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500" />
              </div>
              <div className="flex gap-2">
                <button onClick={handleCreate} disabled={!name || !cronExpr}
                  className="px-4 py-2 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-700/50 text-blue-400 text-sm rounded-lg transition-colors disabled:opacity-50">
                  Create Schedule
                </button>
                <button onClick={() => setShowForm(false)} className="px-4 py-2 text-slate-400 hover:text-white text-sm">Cancel</button>
              </div>
            </div>
          </Card>
        </div>
      )}

      <div className="px-6 pb-6">
        <Card className="overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2d4a]">
                <th className="text-left text-slate-400 font-medium px-4 py-3">Name</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Schedule</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Scope</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Last Run</th>
                <th className="text-left text-slate-400 font-medium px-4 py-3">Status</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {schedules.map((s: any) => (
                <tr key={s.id} className="border-b border-[#1e2d4a]/50 hover:bg-white/[0.02]">
                  <td className="px-4 py-3 text-white font-medium">{s.name}</td>
                  <td className="px-4 py-3 font-mono text-slate-400 text-xs">{s.cron_expr}</td>
                  <td className="px-4 py-3 text-slate-400 text-xs">{s.filter?.category || s.filter?.standard || 'All Rules'}</td>
                  <td className="px-4 py-3 text-slate-500 text-xs">
                    {s.last_run ? parseServerTime(s.last_run)?.toLocaleString() : 'Never'}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`text-xs font-medium ${s.enabled ? 'text-green-400' : 'text-slate-500'}`}>
                      {s.enabled ? 'Active' : 'Disabled'}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <button onClick={() => handleRunNow(s.id)} title="Run now"
                        className="text-slate-500 hover:text-blue-400 transition-colors">
                        <Play className="w-3.5 h-3.5" />
                      </button>
                      <button onClick={() => handleToggle(s)} title={s.enabled ? 'Disable' : 'Enable'}
                        className={`transition-colors ${s.enabled ? 'text-green-400 hover:text-slate-400' : 'text-slate-500 hover:text-green-400'}`}>
                        <Power className="w-3.5 h-3.5" />
                      </button>
                      <button onClick={() => handleDelete(s.id)} title="Delete"
                        className="text-slate-500 hover:text-red-400 transition-colors">
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {schedules.length === 0 && (
                <tr><td colSpan={6} className="px-4 py-12 text-center text-slate-500">No schedules configured</td></tr>
              )}
            </tbody>
          </table>
        </Card>
      </div>
    </Layout>
  )
}
