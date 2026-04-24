import { useEffect, useRef, useState } from 'react'
import { RefreshCw, Usb, Bluetooth, Wifi, AlertTriangle, Plus, Trash2, ShieldCheck, HardDrive, Lock } from 'lucide-react'
import { Layout, PageHeader, Card, LoadingSpinner, ErrorMessage } from '../components/Layout'
import {
  getConnections, getUsbWhitelist, addUsbWhitelist, removeUsbWhitelist,
  getUsbSecurityEvents, get2faStatus, verify2fa,
} from '../lib/api'
import { parseServerTime } from '../lib/time'

const INPUT_CLS = "w-full bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500"

type WhitelistEntry = {
  id: number
  name: string
  vendor: string | null
  product_id: string | null
  serial: string | null
  volume_uuid: string | null
  notes: string | null
  added_by: string
  added_at: string
}

type UsbDevice = {
  name: string
  vendor: string
  product_id: string
  serial: string
  whitelisted: boolean
}

type UsbVolume = {
  vol_name: string
  bsd_name: string
  mount_point: string
  file_system: string
  size: string
  volume_uuid: string
  parent_name: string
  parent_vendor: string
  parent_product_id: string
  parent_serial: string
  whitelisted: boolean
}

const emptyForm = { name: '', vendor: '', product_id: '', serial: '', volume_uuid: '', notes: '' }

// ─── Inline OTP prompt ───────────────────────────────────────────────────────

function OtpPrompt({
  onVerified,
  onCancel,
}: {
  onVerified: (token: string) => void
  onCancel: () => void
}) {
  const [otp, setOtp] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { inputRef.current?.focus() }, [])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = e.target.value.replace(/\D/g, '').slice(0, 6)
    setOtp(v)
    if (v.length === 6) setTimeout(() => submit(v), 50)
  }

  const submit = async (code: string) => {
    setLoading(true)
    setError('')
    try {
      const res = await verify2fa(code)
      if (res.valid && res.session_token) {
        onVerified(res.session_token)
      } else {
        setError('Invalid code — try again')
        setOtp('')
        inputRef.current?.focus()
      }
    } catch {
      setError('Verification failed')
      setOtp('')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="mb-4 p-4 bg-blue-950/30 border border-blue-700/40 rounded-lg flex items-start gap-3">
      <Lock className="w-4 h-4 text-blue-400 flex-shrink-0 mt-2.5" />
      <div className="flex-1 space-y-3">
        <div>
          <p className="text-blue-300 text-sm font-medium">2FA verification required</p>
          <p className="text-slate-400 text-xs mt-0.5">Enter the 6-digit code from your authenticator app to modify the whitelist</p>
        </div>
        <div className="flex items-center gap-3">
          <input
            ref={inputRef}
            type="text"
            inputMode="numeric"
            maxLength={6}
            value={otp}
            onChange={handleChange}
            disabled={loading}
            placeholder="000000"
            className="w-28 bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg px-3 py-2 text-white text-center text-lg font-mono tracking-widest focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
          <button
            onClick={() => submit(otp)}
            disabled={otp.length !== 6 || loading}
            className="px-3 py-2 bg-blue-600/30 border border-blue-500/40 text-blue-300 text-sm rounded-lg hover:bg-blue-600/40 transition-colors disabled:opacity-40"
          >
            {loading ? 'Verifying…' : 'Verify'}
          </button>
          <button
            onClick={onCancel}
            className="px-3 py-2 text-slate-500 hover:text-slate-300 text-sm transition-colors"
          >
            Cancel
          </button>
        </div>
        {error && <p className="text-red-400 text-xs">{error}</p>}
      </div>
    </div>
  )
}

// ─── Main page ────────────────────────────────────────────────────────────────

export function Connections() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [data, setData] = useState<any>(null)
  const [whitelist, setWhitelist] = useState<WhitelistEntry[]>([])
  const [usbEvents, setUsbEvents] = useState<any[]>([])
  const [eventsPage, setEventsPage] = useState(0)
  const [eventsTotal, setEventsTotal] = useState(0)
  const [showAddForm, setShowAddForm] = useState(false)
  const [addForm, setAddForm] = useState(emptyForm)
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState('')

  // 2FA state
  const [twoFaEnabled, setTwoFaEnabled] = useState(false)
  const [twoFaToken, setTwoFaToken] = useState('')
  const [pendingAction, setPendingAction] = useState<(() => Promise<void>) | null>(null)
  const [showOtpPrompt, setShowOtpPrompt] = useState(false)

  useEffect(() => {
    load()
    get2faStatus()
      .then(d => setTwoFaEnabled(d.enabled))
      .catch(() => {})
  }, [])

  const load = async () => {
    setLoading(true)
    setError('')
    try {
      const [conn, wl, evts] = await Promise.all([getConnections(), getUsbWhitelist(), getUsbSecurityEvents(0)])
      setData(conn)
      setWhitelist(wl)
      setUsbEvents(evts?.entries ?? [])
      setEventsTotal(evts?.total ?? 0)
      setEventsPage(0)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const loadEventsPage = async (page: number) => {
    try {
      const evts = await getUsbSecurityEvents(page)
      setUsbEvents(evts?.entries ?? [])
      setEventsTotal(evts?.total ?? 0)
      setEventsPage(page)
    } catch (e: any) {
      setError(e.message)
    }
  }

  const refreshWhitelist = async () => {
    const wl = await getUsbWhitelist()
    setWhitelist(wl)
  }

  // ── 2FA helper ─────────────────────────────────────────────────────────────
  // Runs `action` immediately if no 2FA gate is needed, otherwise queues it
  // behind an OTP prompt.  The prompt calls onVerified → stores token → runs.
  const withTwoFa = (action: () => Promise<void>) => {
    if (!twoFaEnabled || twoFaToken) {
      action()
      return
    }
    setPendingAction(() => action)
    setShowOtpPrompt(true)
    setFormError('')
  }

  const handleOtpVerified = async (token: string) => {
    setTwoFaToken(token)
    setShowOtpPrompt(false)
    if (pendingAction) {
      await pendingAction()
      setPendingAction(null)
    }
  }

  const handleOtpCancel = () => {
    setShowOtpPrompt(false)
    setPendingAction(null)
    setSaving(false)
  }

  // When the server returns 403 (session expired), clear the stored token and
  // re-prompt so the user can get a fresh one before retrying.
  const handleAuthExpired = (retryFn: () => Promise<void>) => {
    setTwoFaToken('')
    setPendingAction(() => retryFn)
    setShowOtpPrompt(true)
  }

  // ── Prefill helpers ────────────────────────────────────────────────────────

  const prefillFormFromVolume = (vol: UsbVolume) => {
    setAddForm({
      name:        vol.parent_name || '',
      vendor:      vol.parent_vendor || '',
      product_id:  vol.parent_product_id || '',
      serial:      vol.parent_serial || '',
      volume_uuid: vol.volume_uuid || '',
      notes:       '',
    })
    setShowAddForm(true)
    setFormError('')
  }

  const prefillFormFromEvent = (e: any) => {
    setAddForm({
      name:        e.target || e.detail?.name || '',
      vendor:      e.detail?.vendor || '',
      product_id:  e.detail?.product_id || '',
      serial:      e.detail?.serial || '',
      volume_uuid: '',
      notes:       '',
    })
    setShowAddForm(true)
    setFormError('')
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const isEventWhitelisted = (e: any) => {
    const pid = e.detail?.product_id || ''
    const serial = e.detail?.serial || ''
    return whitelist.some(w => {
      if (w.volume_uuid) return false
      const checks = []
      if (w.product_id) checks.push(pid === w.product_id)
      if (w.serial) checks.push(serial === w.serial)
      return checks.length > 0 && checks.every(Boolean)
    })
  }

  const prefillForm = (dev: UsbDevice) => {
    setAddForm({
      name: dev.name || '',
      vendor: dev.vendor || '',
      product_id: dev.product_id || '',
      serial: dev.serial || '',
      volume_uuid: '',
      notes: '',
    })
    setShowAddForm(true)
    setFormError('')
  }

  // ── Write actions (wrapped with 2FA) ───────────────────────────────────────

  const handleAdd = () => {
    if (!addForm.name.trim()) { setFormError('Name is required'); return }
    const snapshot = { ...addForm }   // capture form at click time
    const doAdd = async () => {
      setSaving(true)
      setFormError('')
      try {
        await addUsbWhitelist({
          name:       snapshot.name.trim(),
          vendor:     snapshot.vendor.trim() || undefined,
          product_id: snapshot.product_id.trim() || undefined,
          serial:     snapshot.serial.trim() || undefined,
          volume_uuid: snapshot.volume_uuid.trim() || undefined,
          notes:      snapshot.notes.trim() || undefined,
        }, twoFaToken)
        setAddForm(emptyForm)
        setShowAddForm(false)
        await refreshWhitelist()
        const conn = await getConnections()
        setData(conn)
      } catch (e: any) {
        if (e.response?.status === 403) {
          handleAuthExpired(doAdd)
        } else {
          setFormError(e.response?.data?.detail || e.message)
        }
      } finally {
        setSaving(false)
      }
    }
    withTwoFa(doAdd)
  }

  const handleRemove = (id: number) => {
    const doRemove = async () => {
      try {
        await removeUsbWhitelist(id, twoFaToken)
        await refreshWhitelist()
        const conn = await getConnections()
        setData(conn)
      } catch (e: any) {
        if (e.response?.status === 403) {
          handleAuthExpired(doRemove)
        } else {
          setError(e.response?.data?.detail || e.message)
        }
      }
    }
    withTwoFa(doRemove)
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
              {data.usb_devices.map((d: UsbDevice, i: number) => (
                <div key={i} className="flex items-center justify-between py-2 border-b border-[#1e2d4a]/50 last:border-0">
                  <div>
                    <div className="text-white text-sm">{d.name}</div>
                    {d.vendor && <div className="text-slate-500 text-xs">{d.vendor}</div>}
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-slate-500 text-xs font-mono">{d.product_id || d.serial || '—'}</div>
                    {d.whitelisted ? (
                      <span className="text-xs px-1.5 py-0.5 bg-green-900/30 text-green-400 rounded">Whitelisted</span>
                    ) : (
                      <>
                        <span className="text-xs px-1.5 py-0.5 bg-red-900/30 text-red-400 rounded">Unauthorized</span>
                        <button
                          onClick={() => prefillForm(d)}
                          className="text-xs px-2 py-0.5 bg-blue-600/20 border border-blue-700/50 text-blue-400 rounded hover:bg-blue-600/30 transition-colors"
                        >
                          Add to Whitelist
                        </button>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-slate-600 text-sm">No USB devices detected</div>
          )}
        </Card>

        {/* USB Volumes */}
        <Card className="p-5">
          <div className="flex items-center gap-2 text-slate-400 text-xs font-medium mb-3">
            <HardDrive className="w-4 h-4" /> USB VOLUMES ({data?.usb_volumes?.length || 0})
          </div>
          {data?.usb_volumes?.length > 0 ? (
            <div className="space-y-2">
              {data.usb_volumes.map((v: UsbVolume, i: number) => (
                <div key={i} className="flex items-center justify-between py-2 border-b border-[#1e2d4a]/50 last:border-0">
                  <div>
                    <div className="text-white text-sm">{v.vol_name || v.bsd_name}</div>
                    <div className="text-slate-500 text-xs">
                      {v.mount_point}
                      {v.file_system && <span className="ml-2 text-slate-600">{v.file_system}</span>}
                      {v.size && <span className="ml-2 text-slate-600">{v.size}</span>}
                    </div>
                    <div className="text-slate-600 text-xs mt-0.5">via {v.parent_name}</div>
                    {v.volume_uuid && <div className="text-slate-700 text-xs font-mono mt-0.5">{v.volume_uuid}</div>}
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="text-slate-500 text-xs font-mono">{v.bsd_name}</div>
                    {v.whitelisted ? (
                      <span className="text-xs px-1.5 py-0.5 bg-green-900/30 text-green-400 rounded">Whitelisted</span>
                    ) : (
                      <>
                        <span className="text-xs px-1.5 py-0.5 bg-red-900/30 text-red-400 rounded">Unauthorized</span>
                        <button
                          onClick={() => prefillFormFromVolume(v)}
                          className="text-xs px-2 py-0.5 bg-blue-600/20 border border-blue-700/50 text-blue-400 rounded hover:bg-blue-600/30 transition-colors"
                        >
                          Add to Whitelist
                        </button>
                      </>
                    )}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-slate-600 text-sm">No USB storage volumes mounted</div>
          )}
        </Card>

        {/* USB Whitelist Management */}
        <Card className="p-5">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2 text-slate-400 text-xs font-medium">
              <ShieldCheck className="w-4 h-4" /> USB WHITELIST ({whitelist.length})
              {twoFaEnabled && (
                <span className="flex items-center gap-1 px-1.5 py-0.5 bg-blue-900/30 border border-blue-700/40 text-blue-400 rounded text-xs">
                  <Lock className="w-3 h-3" /> 2FA protected
                </span>
              )}
            </div>
            <button
              onClick={() => { setShowAddForm(v => !v); setAddForm(emptyForm); setFormError('') }}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600/20 border border-blue-700/50 text-blue-400 text-xs rounded-lg hover:bg-blue-600/30 transition-colors"
            >
              <Plus className="w-3.5 h-3.5" /> Add Device
            </button>
          </div>

          {/* 2FA OTP prompt — shown above the form when verification is needed */}
          {showOtpPrompt && (
            <OtpPrompt onVerified={handleOtpVerified} onCancel={handleOtpCancel} />
          )}

          {showAddForm && !showOtpPrompt && (
            <div className="mb-4 p-4 bg-[#0a0e1a] border border-[#1e2d4a] rounded-lg space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-slate-500 mb-1">Name *</label>
                  <input
                    className={INPUT_CLS}
                    placeholder="e.g. YubiKey 5C"
                    value={addForm.name}
                    onChange={e => setAddForm(f => ({ ...f, name: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="block text-xs text-slate-500 mb-1">Vendor</label>
                  <input
                    className={INPUT_CLS}
                    placeholder="e.g. Yubico"
                    value={addForm.vendor}
                    onChange={e => setAddForm(f => ({ ...f, vendor: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="block text-xs text-slate-500 mb-1">Product ID</label>
                  <input
                    className={INPUT_CLS}
                    placeholder="e.g. 0x0407"
                    value={addForm.product_id}
                    onChange={e => setAddForm(f => ({ ...f, product_id: e.target.value }))}
                  />
                </div>
                <div>
                  <label className="block text-xs text-slate-500 mb-1">Serial Number</label>
                  <input
                    className={INPUT_CLS}
                    placeholder="Device serial"
                    value={addForm.serial}
                    onChange={e => setAddForm(f => ({ ...f, serial: e.target.value }))}
                  />
                </div>
                {addForm.volume_uuid && (
                  <div className="col-span-2">
                    <label className="block text-xs text-slate-500 mb-1">Volume UUID <span className="text-slate-600">(locks to this specific SD card)</span></label>
                    <input
                      className={INPUT_CLS + ' font-mono'}
                      value={addForm.volume_uuid}
                      onChange={e => setAddForm(f => ({ ...f, volume_uuid: e.target.value }))}
                    />
                  </div>
                )}
              </div>
              <div>
                <label className="block text-xs text-slate-500 mb-1">Notes</label>
                <input
                  className={INPUT_CLS}
                  placeholder="Optional — operator name, purpose, etc."
                  value={addForm.notes}
                  onChange={e => setAddForm(f => ({ ...f, notes: e.target.value }))}
                />
              </div>
              {formError && <div className="text-red-400 text-xs">{formError}</div>}
              <div className="flex gap-2 pt-1">
                <button
                  onClick={handleAdd}
                  disabled={saving}
                  className="px-4 py-1.5 bg-blue-600/30 border border-blue-600/50 text-blue-300 text-sm rounded-lg hover:bg-blue-600/40 transition-colors disabled:opacity-50"
                >
                  {saving ? 'Saving…' : 'Add to Whitelist'}
                </button>
                <button
                  onClick={() => { setShowAddForm(false); setAddForm(emptyForm); setFormError('') }}
                  className="px-4 py-1.5 bg-slate-700/30 border border-slate-600/30 text-slate-400 text-sm rounded-lg hover:bg-slate-700/50 transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          {whitelist.length > 0 ? (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[#1e2d4a]/50">
                    <th className="text-left text-slate-500 font-medium pb-2 text-xs">Name</th>
                    <th className="text-left text-slate-500 font-medium pb-2 text-xs">Vendor</th>
                    <th className="text-left text-slate-500 font-medium pb-2 text-xs">Product ID</th>
                    <th className="text-left text-slate-500 font-medium pb-2 text-xs">Serial</th>
                    <th className="text-left text-slate-500 font-medium pb-2 text-xs">Volume UUID</th>
                    <th className="text-left text-slate-500 font-medium pb-2 text-xs">Notes</th>
                    <th className="pb-2" />
                  </tr>
                </thead>
                <tbody>
                  {whitelist.map(e => (
                    <tr key={e.id} className="border-b border-[#1e2d4a]/30 last:border-0 hover:bg-white/[0.02]">
                      <td className="py-2 text-white">{e.name}</td>
                      <td className="py-2 text-slate-400 text-xs">{e.vendor || '—'}</td>
                      <td className="py-2 font-mono text-slate-400 text-xs">{e.product_id || '—'}</td>
                      <td className="py-2 font-mono text-slate-400 text-xs">{e.serial || '—'}</td>
                      <td className="py-2 font-mono text-slate-600 text-xs">{e.volume_uuid || '—'}</td>
                      <td className="py-2 text-slate-500 text-xs">{e.notes || '—'}</td>
                      <td className="py-2 text-right">
                        <button
                          onClick={() => handleRemove(e.id)}
                          className="p-1 text-slate-600 hover:text-red-400 transition-colors"
                          title="Remove from whitelist"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="text-slate-600 text-sm">No devices whitelisted yet</div>
          )}
        </Card>

        {/* USB Security Events */}
        {eventsTotal > 0 && (
          <Card className="p-5 border border-red-900/40">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2 text-red-400 text-xs font-medium">
                <AlertTriangle className="w-4 h-4" /> UNAUTHORIZED USB EVENTS ({eventsTotal})
              </div>
              {eventsTotal > 10 && (
                <div className="flex items-center gap-2">
                  <span className="text-slate-600 text-xs">
                    {eventsPage * 10 + 1}–{Math.min((eventsPage + 1) * 10, eventsTotal)} of {eventsTotal}
                  </span>
                  <button
                    onClick={() => loadEventsPage(eventsPage - 1)}
                    disabled={eventsPage === 0}
                    className="px-2 py-0.5 text-xs text-slate-400 border border-[#1e2d4a] rounded hover:border-slate-500 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  >
                    ‹
                  </button>
                  <button
                    onClick={() => loadEventsPage(eventsPage + 1)}
                    disabled={(eventsPage + 1) * 10 >= eventsTotal}
                    className="px-2 py-0.5 text-xs text-slate-400 border border-[#1e2d4a] rounded hover:border-slate-500 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  >
                    ›
                  </button>
                </div>
              )}
            </div>
            <div className="space-y-2">
              {usbEvents.map((e: any, i: number) => (
                <div key={i} className="flex items-start justify-between py-2 border-b border-[#1e2d4a]/50 last:border-0">
                  <div>
                    <div className="text-red-300 text-sm font-medium">{e.target}</div>
                    <div className="text-slate-500 text-xs mt-0.5">
                      {e.detail?.vendor && <span>{e.detail.vendor} · </span>}
                      {e.detail?.product_id && <span className="font-mono">{e.detail.product_id}</span>}
                      {e.detail?.ejected_volumes?.length > 0 && (
                        <span className="ml-2 text-orange-400">Storage ejected</span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-3 ml-4 flex-shrink-0">
                    <div className="text-slate-600 text-xs font-mono whitespace-nowrap">
                      {e.ts ? parseServerTime(e.ts)?.toLocaleString() : '—'}
                    </div>
                    {isEventWhitelisted(e) ? (
                      <span className="text-xs px-1.5 py-0.5 bg-green-900/30 text-green-400 rounded">Whitelisted</span>
                    ) : (
                      <button
                        onClick={() => prefillFormFromEvent(e)}
                        className="text-xs px-2 py-0.5 bg-blue-600/20 border border-blue-700/50 text-blue-400 rounded hover:bg-blue-600/30 transition-colors whitespace-nowrap"
                      >
                        Add to Whitelist
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

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
