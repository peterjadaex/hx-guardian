import { useEffect, useState } from 'react'
import { getRunnerStatus } from './api'

const POLL_MS = 15000

export interface RunnerStatus {
  connected: boolean
  available: boolean
  reason: string | null
  detail: string
  staleManifest: boolean
  /** False until the first probe returns, so nothing renders a scary banner mid-load. */
  loaded: boolean
}

const UNKNOWN: RunnerStatus = {
  connected: true, available: true, reason: null, detail: '',
  staleManifest: false, loaded: false,
}

// One poller shared by every consumer. The sidebar pill and a page banner are
// usually mounted together, and each probe costs a Unix-socket round trip to the
// root runner — so they must not each run their own timer, and they must not be
// able to disagree about the current state.
let current: RunnerStatus = UNKNOWN
const subscribers = new Set<(s: RunnerStatus) => void>()
let timer: ReturnType<typeof setInterval> | null = null

async function probe() {
  try {
    const d = await getRunnerStatus()
    current = {
      connected: !!d.runner_connected,
      available: !!d.available,
      reason: d.reason ?? null,
      detail: d.detail ?? '',
      staleManifest: !!d.stale_manifest,
      loaded: true,
    }
    subscribers.forEach(fn => fn(current))
  } catch {
    // A failed probe says nothing about the runner — it usually means the
    // dashboard itself is unreachable, which the user can already see.
  }
}

/** Tracks whether the privileged runner can actually assess compliance. */
export function useRunnerStatus(): RunnerStatus {
  // Seeded from the shared value, so a consumer mounting after the first probe
  // starts with the current state instead of flashing the optimistic default.
  const [status, setStatus] = useState<RunnerStatus>(current)

  useEffect(() => {
    subscribers.add(setStatus)
    if (timer === null) {
      probe()
      timer = setInterval(probe, POLL_MS)
    }

    return () => {
      subscribers.delete(setStatus)
      if (subscribers.size === 0 && timer !== null) {
        clearInterval(timer)
        timer = null
      }
    }
  }, [])

  return status
}
