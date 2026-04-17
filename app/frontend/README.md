# HX-Guardian Frontend

React + TypeScript + Vite single-page application.
Served as static files by the FastAPI backend — no separate server needed for normal use.

---

## Structure

```
src/
├── pages/
│   ├── Dashboard.tsx        # Compliance score, device strip, trend charts, Run Full Scan
│   ├── Rules.tsx            # All 266 rules with filter/sort/scan; polls scan session until done
│   ├── RuleDetail.tsx       # Per-rule scan now, apply fix, history, exemptions
│   ├── History.tsx          # Past scan sessions, trend chart, CSV export
│   ├── Device.tsx           # macOS device status (SIP, FileVault, Gatekeeper, etc.)
│   ├── Connections.tsx      # USB devices, Bluetooth, network interfaces, TCP connections
│   ├── MdmProfiles.tsx      # MDM profile install status
│   ├── Exemptions.tsx       # Manage rule exemptions
│   ├── Schedule.tsx         # Recurring scan schedule (cron-based)
│   ├── Reports.tsx          # HTML / CSV compliance report download
│   ├── AuditLog.tsx         # Append-only operator action log
│   └── Logs.tsx             # System log viewer
├── components/
│   ├── Layout.tsx           # Shell, sidebar nav, PageHeader, Card, LoadingSpinner
│   └── StatusBadge.tsx      # Coloured status pill (PASS / FAIL / MDM_REQUIRED / …)
└── lib/
    └── api.ts               # Typed axios client; all API calls go through here
```

---

## Development

Requires Node.js 18+.

```bash
cd app/frontend
npm install
npm run dev      # Vite dev server with HMR on http://localhost:5173
```

The backend must be running at `http://127.0.0.1:8000` for API calls to work.
Configure the proxy in `vite.config.ts` if you use a different port.

### Build for production

```bash
npm run build    # outputs to dist/; served by the FastAPI backend
```

Commit `dist/` so the backend can serve it without requiring Node.js on the target device.

### Lint

```bash
npm run lint
```

---

## Key Behaviours

**Full scan polling** — `Rules.tsx` calls `POST /api/scans`, then polls
`GET /api/scans/{session_id}` every 2 seconds until `is_running` is false, then reloads
the rule list. The scan button shows "Scanning…" throughout.

**Individual scan** — `RuleDetail.tsx` calls `POST /api/rules/{rule}/scan` (synchronous),
shows the raw JSON result in a terminal-style output block, and reloads the rule detail.
If the runner is not running, the server error message is shown directly in the output.

**Authentication** — the session token is stored in `localStorage` under `hxg_token`.
All requests include it as `Authorization: Bearer <token>`. A 401 response clears the
token and redirects to `/login`.
