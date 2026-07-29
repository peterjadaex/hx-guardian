# Application map

## Request path

Typical dashboard work crosses these layers:

1. `app/frontend/src/pages/` renders routes and user states.
2. `app/frontend/src/lib/api.ts` owns HTTP calls; `sse.ts` owns streaming behavior.
3. `app/backend/routers/` defines API boundaries and authorization checks.
4. `app/backend/core/models.py` and `database.py` define persisted state and initialization.
5. `app/backend/core/audit.py` records operator and security events.
6. `app/backend/core/runner_client.py` talks to the privileged runner over a Unix socket.
7. `app/backend/runner/protocol.py` validates runner messages.
8. `app/backend/runner/executor.py` resolves and executes allowlisted scripts.

Inspect actual imports and callers; this map is orientation, not a substitute for tracing.

## Security boundaries

- Browser to FastAPI: validate input and preserve 2FA gates for sensitive actions.
- FastAPI to database: keep installed data compatible and audit meaningful changes.
- FastAPI to runner: accept structured operations only; never accept an arbitrary command.
- Runner to scripts: resolve only manifest entries and validated paths.
- Service to host: keep FastAPI on `127.0.0.1` and preserve restrictive Unix-socket permissions.

## Change matrix

| Change | Inspect together |
|---|---|
| New/changed API response | Router, Pydantic model, frontend API types/caller, page states |
| Persistent field | SQLAlchemy model, initialization/migration, serialization, UI |
| Sensitive action | 2FA/auth check, input validation, runner boundary, audit event |
| Scan progress | scans router, runner client/protocol, SSE or polling, history UI |
| New page | route registration, layout/navigation, API client, loading/error/empty states |
