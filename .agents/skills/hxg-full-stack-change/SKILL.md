---
name: hxg-full-stack-change
description: Implement or review HX-Guardian dashboard changes spanning FastAPI, Pydantic/SQLAlchemy models, the privileged-runner client, React/TypeScript pages, or the frontend API layer. Use for features, bug fixes, API changes, UI changes, database evolution, authentication-sensitive flows, audit events, and cross-layer refactors under app/backend or app/frontend/src.
---

# HXG Full-Stack Change

Preserve HX-Guardian's localhost-only, least-privilege architecture while making the smallest coherent change across affected layers.

## Workflow

1. Read `AGENTS.md` and inspect the full call path before editing.
2. Read [references/application-map.md](references/application-map.md) when the change crosses layers or touches a security boundary.
3. Trace the current behavior from UI page through `app/frontend/src/lib/`, API router, model/database code, and runner protocol where applicable.
4. Define invariants before implementation:
   - Bind the server only to `127.0.0.1`.
   - Keep the web server unprivileged.
   - Send privileged operations only through the Unix-socket runner.
   - Execute only manifest-allowlisted scripts.
   - Require existing authorization controls for sensitive operations.
   - Append security-relevant actions to the audit log.
5. Implement a focused change. Preserve loading, empty, error, and partial-progress states in the UI.
6. For database changes, add a backward-compatible initialization or migration path. Preserve installed history.
7. If frontend source changes, rebuild `app/frontend/dist/`; never edit generated assets directly.
8. Validate only safe development paths:

```bash
source .venv/bin/activate
python -m compileall -q app/backend
cd app/frontend
npm run lint
npm run build
```

9. Review the diff for secrets, network dependencies, weakened validation, missing audit events, and unrelated generated noise.
10. Report checks run and any macOS/root-dependent behavior intentionally not exercised.

## Boundaries

- Do not start the root runner as routine validation.
- Do not read runtime secrets, keys, databases, logs, tokens, or credentials.
- Do not create arbitrary command, path traversal, or caller-supplied script execution.
- Do not add runtime CDNs, telemetry, external APIs, or install-time downloads.
- Do not silently change API contracts; update frontend callers and states together.
