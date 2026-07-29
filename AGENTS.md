# AGENTS.md

## Project purpose

HX-Guardian is a localhost-only security compliance dashboard for an air-gapped
macOS signing device. It combines a React frontend, a FastAPI backend, privileged
macOS daemons, and NIST/CIS scan and remediation scripts.

Treat this repository as security-sensitive. Preserve the separation between the
unprivileged web server and privileged runner, keep the dashboard bound to
`127.0.0.1`, and do not introduce network dependencies into the target-device
runtime or installation flow.

## Repository map

- `app/backend/`: FastAPI server, API routers, database code, privileged runner,
  USB watcher, and shell watcher.
- `app/frontend/src/`: React and TypeScript source.
- `app/frontend/dist/`: generated frontend build served by the backend and
  intentionally committed for offline deployment.
- `app/launchd/` and `standards/launchd/`: macOS launchd service definitions.
- `standards/scripts/manifest.json`: allowlist and metadata for compliance rules.
- `standards/scripts/scan/`: read-only compliance checks.
- `standards/scripts/fix/`: privileged remediation scripts.
- `standards/unified/`: unified macOS configuration profiles.
- `transfer/`, `app/dist/`, and `*.zip`: generated offline distribution outputs;
  do not edit them by hand.

Read `app/app_readme.md` for development and packaging details. Read
`standards/airgap_readme.md` for target-device installation and operations.

## Repository skills and knowledge

Repository-local skills live under `.agents/skills/`. Use the matching skill
whenever its trigger applies; its references contain task-specific knowledge
that should be loaded only as directed by the skill.

- `.agents/skills/hxg-full-stack-change/`: application features, API/UI changes,
  database evolution, authentication-sensitive flows, and runner integration.
- `.agents/skills/hxg-compliance-rule/`: compliance manifest, scan/fix/undo
  scripts, baseline mappings, profiles, exemptions, and rule documentation.
- `.agents/skills/hxg-offline-release/`: builds, installers, launchd, PyInstaller,
  offline bundles, updates, and deployment documentation.
- `.agents/skills/hxg-documentation-guide/`: developer and operator guides,
  architecture/API references, troubleshooting, hardening-control documentation,
  and documentation consistency reviews.

`AGENTS.md` remains the controlling repository policy. A skill may add a narrower
workflow but must not weaken these security or safety rules. If multiple skills
apply, use the smallest set that covers the task and reconcile all of their
validation requirements.

## Working rules

- Inspect the relevant call path before editing. API changes commonly require
  coordinated updates to a router, Pydantic model, frontend API client, and page.
- Make focused changes and preserve unrelated local modifications.
- Never read, print, modify, or commit secrets or runtime state, including
  `app/secret.md`, `app/data/hxg.key`, database files, logs, tokens, or credentials.
- Do not weaken authentication, audit logging, manifest allowlisting, path
  validation, Unix-socket permissions, localhost binding, or privilege separation.
- Never add an arbitrary-command execution path to the runner. It may execute
  only validated scripts listed in `standards/scripts/manifest.json`.
- Do not run fix scripts, installers, `sudo`, `launchctl`, `profiles`, destructive
  system commands, or scripts that alter macOS security settings unless the user
  explicitly asks and the exact target and impact have been confirmed.
- Scan scripts should have no side effects. Fix scripts must be idempotent where
  practical, narrowly scoped, and return useful status and error output.
- When changing a rule, keep the manifest, scan script, fix script (if present),
  baseline mapping, and documentation consistent.
- The target device is air-gapped. Do not add runtime CDN assets, telemetry,
  external API calls, online installers, or dependencies fetched during install.
- Do not manually edit generated frontend files in `app/frontend/dist/`.
  Rebuild them from `app/frontend/src/`.
- Do not manually edit generated files under `transfer/` or `app/dist/`; regenerate
  them through the documented build scripts only when requested.

## Development commands

Run commands from the repository root unless noted otherwise.

### Backend

```bash
source .venv/bin/activate
python -m compileall -q app/backend
```

For local development, follow `app/app_readme.md`. The privileged runner requires
macOS root access and should not be started as part of routine validation.

### Frontend

```bash
cd app/frontend
npm run lint
npm run build
```

`npm run build` runs TypeScript checks and Vite, and updates the committed
`app/frontend/dist/` artifacts.

### Shell and data validation

For each changed shell script:

```bash
zsh -n path/to/script.sh
```

For a changed manifest:

```bash
python -m json.tool standards/scripts/manifest.json >/dev/null
```

Prefer syntax checks and targeted unit-level validation. Many integration paths
depend on macOS services, root privileges, or security settings and must not be
exercised casually on a development machine.

## Implementation conventions

- Python: follow the existing FastAPI, Pydantic, SQLAlchemy, and async patterns;
  use explicit error handling at privilege and process boundaries.
- TypeScript/React: keep API access in `app/frontend/src/lib/`, reuse existing
  components, and preserve loading, empty, and error states.
- Shell: quote expansions, use absolute system binary paths where the surrounding
  scripts do, validate all inputs, and avoid parsing fragile human-readable output
  when a structured macOS output format is available.
- Database changes must account for existing installed databases. Provide a
  backward-compatible migration path and do not delete operator history.
- Security-relevant actions must remain represented in the append-only audit log.

## Completion checklist

Before handing off a change:

1. Review the diff for secrets, generated noise, and unintended security changes.
2. Run the narrowest applicable backend, frontend, JSON, and shell validations.
3. Confirm documentation when install, operator, API, or packaging behavior changed.
4. State what was tested and identify any macOS/root-dependent validation that was
   intentionally not run.
