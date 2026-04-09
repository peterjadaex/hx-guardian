import { useEffect, useState } from 'react'
import { RefreshCw, CheckCircle, XCircle, HelpCircle, Monitor } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getDeviceStatus } from '../lib/api'

function StatusRow({ label, value }: { label: string; value: boolean | null | undefined }) {
  const isOk = value === true
  return (
    <div className="flex items-center justify-between py-3 border-b border-[#1e2d4a]/50 last:border-0">
      <span className="text-slate-300 text-sm">{label}</span>
      {value === null || value === undefined ? (
        <span className="flex items-center gap-1.5 text-slate-500 text-sm"><HelpCircle className="w-4 h-4" />Unknown</span>
      ) : isOk ? (
        <span className="flex items-center gap-1.5 text-green-400 text-sm font-medium"><CheckCircle className="w-4 h-4" />Enabled</span>
      ) : (
        <span className="flex items-center gap-1.5 text-red-400 text-sm font-medium"><XCircle className="w-4 h-4" />Disabled</span>
      )}
    </div>
  )
}

export function Device() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [status, setStatus] = useState<any>(null)

  useEffect(() => { load() }, [])

  const load = async () => {
    setLoading(true)
    try {
      setStatus(await getDeviceStatus())
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>

  const uptimeStr = status?.uptime_secs
    ? `${Math.floor(status.uptime_secs / 3600)}h ${Math.floor((status.uptime_secs % 3600) / 60)}m`
    : 'Unknown'

  return (
    <Layout>
      <PageHeader title="Device Status" subtitle="macOS security configuration">
        <button onClick={load} className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
          <RefreshCw className="w-4 h-4" />
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-6 grid grid-cols-2 gap-6">
        {/* Device Info */}
        <Card className="p-5">
          <div className="text-slate-400 text-xs font-medium mb-4 flex items-center gap-2">
            <Monitor className="w-4 h-4" /> DEVICE INFORMATION
          </div>
          <div className="space-y-3">
            {[
              ['Model', status?.hardware_model],
              ['macOS Version', status?.os_version],
              ['Build', status?.build_version],
              ['Serial Number', status?.serial_number],
              ['Uptime', uptimeStr],
            ].map(([label, val]) => (
              <div key={label} className="flex items-center justify-between py-1 border-b border-[#1e2d4a]/50 last:border-0">
                <span className="text-slate-400 text-sm">{label}</span>
                <span className="text-white text-sm font-mono">{val || '—'}</span>
              </div>
            ))}
          </div>
        </Card>

        {/* Security Status */}
        <Card className="p-5">
          <div className="text-slate-400 text-xs font-medium mb-4">SECURITY POSTURE</div>
          <div>
            <StatusRow label="System Integrity Protection (SIP)" value={status?.sip_enabled} />
            <StatusRow label="FileVault Disk Encryption" value={status?.filevault_on} />
            <StatusRow label="Gatekeeper" value={status?.gatekeeper_on} />
            <StatusRow label="Firewall" value={status?.firewall_on} />
            <div className="flex items-center justify-between py-3 border-b border-[#1e2d4a]/50">
              <span className="text-slate-300 text-sm">Secure Boot</span>
              <span className={`text-sm font-medium ${
                status?.secure_boot === 'full' ? 'text-green-400' :
                status?.secure_boot === 'medium' ? 'text-yellow-400' :
                status?.secure_boot === 'none' ? 'text-red-400' : 'text-slate-500'
              }`}>
                {status?.secure_boot ? status.secure_boot.charAt(0).toUpperCase() + status.secure_boot.slice(1) : 'Unknown'}
              </span>
            </div>
          </div>
        </Card>
      </div>
    </Layout>
  )
}
