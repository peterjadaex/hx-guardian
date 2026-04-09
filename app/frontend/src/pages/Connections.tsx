import { useEffect, useState } from 'react'
import { RefreshCw, Usb, Bluetooth, Wifi, AlertTriangle } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import { getConnections } from '../lib/api'

export function Connections() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [data, setData] = useState<any>(null)

  useEffect(() => { load() }, [])

  const load = async () => {
    setLoading(true)
    try { setData(await getConnections()) }
    catch (e: any) { setError(e.message) }
    finally { setLoading(false) }
  }

  if (loading) return <Layout><LoadingSpinner /></Layout>

  return (
    <Layout>
      <PageHeader title="Connection Monitor" subtitle="USB, Bluetooth, and network connections">
        <button onClick={load} className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
          <RefreshCw className="w-4 h-4" />
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      {data?.internet_detected && (
        <div className="mx-6 mb-4 p-4 bg-red-900/30 border border-red-700/50 rounded-lg flex items-center gap-3">
          <AlertTriangle className="w-5 h-5 text-red-400 flex-shrink-0" />
          <div>
            <div className="text-red-300 font-medium text-sm">Internet connections detected</div>
            <div className="text-red-400/70 text-xs mt-0.5">
              This device should be airgapped. Review established connections below.
            </div>
          </div>
        </div>
      )}

      <div className="px-6 pb-6 space-y-4">
        {/* USB Devices */}
        <Card className="p-5">
          <div className="flex items-center gap-2 text-slate-400 text-xs font-medium mb-3">
            <Usb className="w-4 h-4" /> USB DEVICES ({data?.usb_devices?.length || 0})
          </div>
          {data?.usb_devices?.length > 0 ? (
            <div className="space-y-2">
              {data.usb_devices.map((d: any, i: number) => (
                <div key={i} className="flex items-center justify-between py-2 border-b border-[#1e2d4a]/50 last:border-0">
                  <div>
                    <div className="text-white text-sm">{d.name}</div>
                    {d.vendor && <div className="text-slate-500 text-xs">{d.vendor}</div>}
                  </div>
                  <div className="text-slate-500 text-xs font-mono">{d.product_id || d.serial || '—'}</div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-slate-600 text-sm">No USB devices detected</div>
          )}
        </Card>

        {/* Bluetooth */}
        <Card className="p-5">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2 text-slate-400 text-xs font-medium">
              <Bluetooth className="w-4 h-4" /> BLUETOOTH
            </div>
            <span className={`text-xs font-medium ${data?.bluetooth_enabled ? 'text-yellow-400' : 'text-green-400'}`}>
              {data?.bluetooth_enabled ? '⚠ Enabled' : '✓ Disabled'}
            </span>
          </div>
          {data?.bluetooth_devices?.length > 0 ? (
            <div className="space-y-2">
              {data.bluetooth_devices.map((d: any, i: number) => (
                <div key={i} className="flex items-center justify-between py-2 border-b border-[#1e2d4a]/50 last:border-0">
                  <div>
                    <div className="text-white text-sm">{d.name}</div>
                    <div className="text-slate-500 text-xs">{d.type}</div>
                  </div>
                  <div className="flex gap-2">
                    {d.paired && <span className="text-xs px-1.5 py-0.5 bg-blue-900/30 text-blue-400 rounded">Paired</span>}
                    {d.connected && <span className="text-xs px-1.5 py-0.5 bg-green-900/30 text-green-400 rounded">Connected</span>}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-slate-600 text-sm">No paired Bluetooth devices</div>
          )}
        </Card>

        {/* Network Interfaces */}
        <Card className="p-5">
          <div className="flex items-center gap-2 text-slate-400 text-xs font-medium mb-3">
            <Wifi className="w-4 h-4" /> NETWORK INTERFACES
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-[#1e2d4a]/50">
                  <th className="text-left text-slate-500 font-medium pb-2 text-xs">Interface</th>
                  <th className="text-left text-slate-500 font-medium pb-2 text-xs">IP Address</th>
                  <th className="text-left text-slate-500 font-medium pb-2 text-xs">Status</th>
                </tr>
              </thead>
              <tbody>
                {(data?.network_interfaces || []).filter((i: any) => !i.name.startsWith('lo')).map((iface: any) => (
                  <tr key={iface.name} className="border-b border-[#1e2d4a]/30 last:border-0">
                    <td className="py-2 font-mono text-slate-300">{iface.name}</td>
                    <td className="py-2 font-mono text-slate-400">{iface.ip.join(', ') || '—'}</td>
                    <td className="py-2">
                      <span className={`text-xs ${iface.status === 'up' || iface.status === 'active' ? 'text-green-400' : 'text-slate-500'}`}>
                        {iface.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        {/* Established Connections */}
        {data?.established_connections?.length > 0 && (
          <Card className="p-5">
            <div className="text-slate-400 text-xs font-medium mb-3">
              ESTABLISHED CONNECTIONS ({data.established_connections.length})
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-xs font-mono">
                <thead>
                  <tr className="border-b border-[#1e2d4a]/50">
                    <th className="text-left text-slate-500 font-medium pb-2">Protocol</th>
                    <th className="text-left text-slate-500 font-medium pb-2">Local</th>
                    <th className="text-left text-slate-500 font-medium pb-2">Remote</th>
                  </tr>
                </thead>
                <tbody>
                  {data.established_connections.map((c: any, i: number) => (
                    <tr key={i} className={`border-b border-[#1e2d4a]/30 last:border-0 ${
                      !c.remote.startsWith('127.') && !c.remote.startsWith('::1') ? 'text-red-400' : 'text-slate-400'
                    }`}>
                      <td className="py-1.5">{c.proto}</td>
                      <td className="py-1.5">{c.local}</td>
                      <td className="py-1.5">{c.remote}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
        )}
      </div>
    </Layout>
  )
}
