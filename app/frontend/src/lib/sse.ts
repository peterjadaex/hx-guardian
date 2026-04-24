import { useEffect, useRef, useState } from 'react'

export function useSSE<T = unknown>(
  path: string | null,
  onMessage?: (eventType: string, data: T) => void
) {
  const [error, setError] = useState<string | null>(null)
  const [connected, setConnected] = useState(false)
  const esRef = useRef<EventSource | null>(null)

  useEffect(() => {
    if (!path) return

    const es = new EventSource(path)
    esRef.current = es

    es.onopen = () => {
      setConnected(true)
      setError(null)
    }

    es.onerror = () => {
      setError('SSE connection lost')
      setConnected(false)
    }

    // Generic message handler — routes by event type
    const handler = (eventType: string) => (e: MessageEvent) => {
      try {
        const data = JSON.parse(e.data) as T
        onMessage?.(eventType, data)
      } catch {
        // ignore parse errors
      }
    }

    const eventTypes = ['result', 'complete', 'error', 'log_line', 'device_update', 'message', 'profile_install', 'row', 'ready']
    const listeners: Array<[string, (e: MessageEvent) => void]> = []
    for (const et of eventTypes) {
      const fn = handler(et)
      es.addEventListener(et, fn as EventListener)
      listeners.push([et, fn])
    }

    return () => {
      for (const [et, fn] of listeners) {
        es.removeEventListener(et, fn as EventListener)
      }
      es.close()
      esRef.current = null
      setConnected(false)
    }
  }, [path])

  return { connected, error, close: () => esRef.current?.close() }
}
