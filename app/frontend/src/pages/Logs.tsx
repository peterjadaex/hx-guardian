import { useEffect, useState, useRef } from 'react'
import { RefreshCw, Search, Pause, Play } from 'lucide-react'
import { Layout, PageHeader, Card, ErrorMessage } from '../components/Layout'
import { getSystemLog } from '../lib/api'
import { useSSE } from '../lib/sse'

export function Logs() {
  const [error, setError] = useState('')
  const [lines, setLines] = useState<string[]>([])
  const [filter, setFilter] = useState('')
  const [logFile, setLogFile] = useState('system')
  const [streaming, setStreaming] = useState(false)
  const [paused, setPaused] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)
  const linesBuffer = useRef<string[]>([])

  // Initial load
  useEffect(() => {
    loadLog()
  }, [logFile])

  // Auto-scroll
  useEffect(() => {
    if (!paused) {
      bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
    }
  }, [lines, paused])

  const loadLog = async () => {
    try {
      const data = await getSystemLog({ lines: 200, filter: filter || undefined, log_file: logFile })
      setLines(data.lines || [])
    } catch (e: any) {
      setError(e.message)
    }
  }

  const { connected } = useSSE<{ ts: string; message: string }>(
    streaming ? '/api/stream/logs' : null,
    (_, data) => {
      if (!paused) {
        linesBuffer.current.push(`${data.ts} ${data.message}`)
        setLines(prev => [...prev.slice(-500), ...linesBuffer.current])
        linesBuffer.current = []
      }
    }
  )

  const filtered = filter
    ? lines.filter(l => l.toLowerCase().includes(filter.toLowerCase()))
    : lines

  return (
    <Layout>
      <PageHeader title="Device Logs" subtitle="System log viewer">
        <button onClick={() => setPaused(p => !p)}
          className={`flex items-center gap-2 px-3 py-2 text-sm rounded-lg border transition-colors ${paused
            ? 'bg-green-600/20 border-green-700/50 text-green-400 hover:bg-green-600/30'
            : 'bg-yellow-600/20 border-yellow-700/50 text-yellow-400 hover:bg-yellow-600/30'}`}>
          {paused ? <><Play className="w-3.5 h-3.5" />Resume</> : <><Pause className="w-3.5 h-3.5" />Pause</>}
        </button>
        <button onClick={() => setStreaming(s => !s)}
          className={`flex items-center gap-2 px-3 py-2 text-sm rounded-lg border transition-colors ${streaming
            ? 'bg-blue-600/20 border-blue-700/50 text-blue-400'
            : 'bg-slate-700/30 border-slate-600/50 text-slate-400 hover:text-white'}`}>
          {streaming ? '● Live' : 'Go Live'}
        </button>
        <button onClick={loadLog} className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-white/5 transition-colors">
          <RefreshCw className="w-4 h-4" />
        </button>
      </PageHeader>

      {error && <ErrorMessage message={error} />}

      <div className="px-6 pb-4 flex gap-3">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
          <input value={filter} onChange={e => setFilter(e.target.value)}
            placeholder="Filter log lines..."
            className="w-full bg-[#0f1629] border border-[#1e2d4a] rounded-lg pl-9 pr-4 py-2 text-sm text-white placeholder-slate-600 focus:outline-none focus:border-blue-500" />
        </div>
        <select value={logFile} onChange={e => setLogFile(e.target.value)}
          className="bg-[#0f1629] border border-[#1e2d4a] rounded-lg px-3 py-2 text-sm text-slate-300 focus:outline-none focus:border-blue-500">
          <option value="system">system.log</option>
          <option value="install">install.log</option>
        </select>
      </div>

      <div className="px-6 pb-6">
        <Card className="overflow-hidden">
          <div className="bg-[#050810] rounded-xl overflow-auto" style={{ height: 'calc(100vh - 240px)' }}>
            <div className="p-4 font-mono text-xs text-green-400 space-y-0.5">
              {filtered.length === 0 && (
                <div className="text-slate-600">No log entries. {filter && 'Try a different filter.'}</div>
              )}
              {filtered.map((line, i) => (
                <div key={i} className={`${
                  line.toLowerCase().includes('error') || line.toLowerCase().includes('fault') ? 'text-red-400' :
                  line.toLowerCase().includes('warn') ? 'text-yellow-400' :
                  'text-green-400/80'
                }`}>{line}</div>
              ))}
              <div ref={bottomRef} />
            </div>
          </div>
        </Card>
        <div className="flex items-center justify-between mt-2 text-slate-600 text-xs">
          <span>{filtered.length} lines {filter && `(filtered from ${lines.length})`}</span>
          {streaming && <span className={connected ? 'text-green-500' : 'text-red-400'}>{connected ? '● Connected' : '○ Reconnecting...'}</span>}
        </div>
      </div>
    </Layout>
  )
}
