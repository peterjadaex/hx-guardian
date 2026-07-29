---
name: hxg-offline-release
description: Implement, review, or validate HX-Guardian build, installer, updater, launchd, PyInstaller, SD-card bundle, offline dependency, and air-gapped deployment changes. Use for app/build.sh, app/prepare_sd_card.sh, install/start/stop/restart/update scripts, spec files, launchd plists, vendor artifacts, app/dist, transfer, or operator/developer packaging documentation.
---

# HXG Offline Release

Preserve a deterministic, self-contained target-device install with no network requirement and clear privilege boundaries.

## Workflow

1. Read `AGENTS.md`, `app/app_readme.md`, and the relevant sections of `standards/airgap_readme.md`.
2. Read [references/release-invariants.md](references/release-invariants.md).
3. Trace each changed source artifact through build, bundle assembly, install destination, launchd ownership, runtime lookup, update behavior, and documentation.
4. Keep generated-output ownership clear:
   - Edit source scripts, specs, plists, and frontend source.
   - Rebuild `app/frontend/dist/` from `app/frontend/src/`.
   - Regenerate `app/dist/` and `transfer/` only through documented build scripts and only when requested.
5. Preserve offline operation. Every runtime or installer dependency must already be in the bundle or macOS base system; do not fetch during install.
6. Preserve service roles: the server remains unprivileged and localhost-only; privileged daemons expose only narrow validated operations with restrictive file and socket permissions.
7. Use syntax and structural checks first. Do not run installers, `sudo`, `launchctl`, `profiles`, fix scripts, or destructive cleanup as routine validation.
8. If a full bundle build is requested, verify expected binaries, scripts, manifest, profiles, permissions, and documented paths after generation.
9. Review the diff for copied secrets/runtime state, machine-specific paths, missing artifacts, architecture assumptions, external URLs used at runtime, and hand-edited generated output.
10. Report static validation separately from macOS installation or root-service validation.

## Safe Validation

Run only checks relevant to changed files:

```bash
zsh -n app/<changed-script>.sh
plutil -lint app/launchd/<changed-plist>.plist
plutil -lint standards/launchd/<changed-plist>.plist
source .venv/bin/activate
python -m compileall -q app/backend
cd app/frontend
npm run lint
npm run build
```

Do not claim a release is install-verified unless it was tested in an authorized disposable macOS environment.
