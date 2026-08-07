import { useEffect, useRef, useState } from 'react'
import { getActiveScan, getSession } from './api'

const POLL_MS = 2000
const MAX_CONSECUTIVE_ERRORS = 10
// Backstop for a session that was never finalised (e.g. the server process died
// mid-scan). Without it the button would stay disabled forever, because the
// status request succeeds and simply keeps reporting is_running.
const MAX_TRACK_MS = 15 * 60 * 1000

/**
 * Tracks the scan session that is currently running, independent of which page
 * started it. On mount it asks the backend whether a scan is in flight, so the
 * progress state survives navigation and page reloads. onComplete fires once the
 * tracked session finishes, letting the page refresh its data.
 */
export function useActiveScan(onComplete?: () => void) {
  const [sessionId, setSessionId] = useState<number | null>(null)
  const onCompleteRef = useRef(onComplete)

  useEffect(() => {
    onCompleteRef.current = onComplete
  }, [onComplete])

  useEffect(() => {
    let cancelled = false
    getActiveScan()
      .then(data => {
        if (!cancelled && data?.active) setSessionId(data.session_id)
      })
      .catch(() => {})
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    if (sessionId === null) return

    let errors = 0
    let elapsed = 0
    const timer = setInterval(async () => {
      elapsed += POLL_MS
      if (elapsed > MAX_TRACK_MS) {
        clearInterval(timer)
        setSessionId(null)
        return
      }
      try {
        const sess = await getSession(sessionId)
        errors = 0
        if (!sess.is_running) {
          clearInterval(timer)
          setSessionId(null)
          onCompleteRef.current?.()
        }
      } catch {
        errors += 1
        if (errors >= MAX_CONSECUTIVE_ERRORS) {
          clearInterval(timer)
          setSessionId(null)
        }
      }
    }, POLL_MS)

    return () => clearInterval(timer)
  }, [sessionId])

  return {
    scanning: sessionId !== null,
    sessionId,
    trackSession: (id: number) => setSessionId(id),
  }
}
