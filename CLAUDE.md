# CLAUDE.md

## Project

HX-Guardian is a localhost-only security compliance dashboard for an air-gapped
macOS signing device: a React frontend, a FastAPI backend, privileged macOS
daemons, and NIST/CIS scan and remediation scripts. Treat the repository as
security-sensitive. The unprivileged web server and the privileged runner are
separate processes for a reason; keep them that way.

## Authoritative policy

[AGENTS.md](AGENTS.md) is the controlling repository policy — read it before
editing. It wins over anything here.

Task-specific workflows live in `.agents/skills/`. Use the matching skill when
its trigger applies:

- `hxg-full-stack-change/` — features, API/UI changes, database evolution,
  auth-sensitive flows, runner integration.
- `hxg-compliance-rule/` — manifest, scan/fix/undo scripts, baselines, profiles,
  exemptions.
- `hxg-offline-release/` — builds, installers, launchd, PyInstaller, offline
  bundles, deployment.
- `hxg-documentation-guide/` — developer and operator docs, API references.

## Repository map

- `app/backend/` — FastAPI server, routers, `core/` models and database,
  privileged runner, USB and shell watchers.
- `app/frontend/src/` — React and TypeScript source. API calls belong in
  `src/lib/`.
- `app/frontend/dist/` — generated build, committed for offline deployment.
  Never hand-edit; rebuild with `npm run build`.
- `standards/scripts/` — `manifest.json` allowlist plus `scan/` and `fix/`
  scripts.
- `transfer/`, `app/dist/`, `*.zip` — generated distribution outputs. Do not
  edit by hand.

See `app/app_readme.md` for development and packaging, and
`standards/airgap_readme.md` for target-device installation.

## Commands

```bash
source .venv/bin/activate
python -m compileall -q app/backend            # backend syntax check

cd app/frontend && npm run lint && npm run build   # TS check, Vite, regenerates dist/

zsh -n path/to/script.sh                       # each changed shell script
python -m json.tool standards/scripts/manifest.json >/dev/null
```

Prefer syntax checks and targeted validation. Many integration paths need macOS
services, root, or the air-gapped device and must not be exercised casually.

## Hard rules

- The device is air-gapped: no CDN assets, telemetry, external API calls, or
  dependencies fetched at install or runtime.
- Keep the server bound to `127.0.0.1` and the web server unprivileged. The
  runner may execute only scripts allowlisted in `manifest.json` — never an
  arbitrary command.
- Never read, print, or commit secrets or runtime state: `app/secret.md`,
  `app/data/hxg.key`, database files, logs, tokens, credentials.
- Do not run fix scripts, installers, `sudo`, `launchctl`, or `profiles` unless
  the user explicitly asks and the target and impact are confirmed.
- Database changes must stay backward-compatible with installed databases and
  must not delete operator history.

When in doubt, AGENTS.md wins.
