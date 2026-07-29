# Offline release invariants

## Trust and privilege

- The dashboard listens only on `127.0.0.1`.
- The web server runs as the configured unprivileged admin user.
- Runner, USB watcher, and shell watcher privileges remain limited to their documented duties.
- Unix sockets, runtime directories, logs, and installed files retain restrictive ownership and modes.
- The runner executes only validated manifest-listed scripts.

## Offline completeness

The target install must not require internet, package registries, CDNs, telemetry, or external APIs. Required binaries, frontend assets, rules, profiles, and explicitly vendored tools must be present in the prepared bundle.

## Source and generated artifacts

| Source | Generated output |
|---|---|
| `app/frontend/src/` | `app/frontend/dist/` via `npm run build` |
| backend plus PyInstaller specs | `app/dist/` via documented build flow |
| application and standards release inputs | `transfer/` via `app/prepare_sd_card.sh` |

Do not hand-edit generated outputs. Do not regenerate heavyweight distribution artifacts unless the task requests it.

## Release trace

For any artifact, confirm:

1. source location;
2. build or copy step;
3. bundle path;
4. installed path and ownership;
5. launchd or runtime reference;
6. update/rollback behavior;
7. matching developer and operator documentation.

## Validation levels

- Static: shell syntax, plist lint, JSON validation, Python compile, frontend lint/build.
- Bundle: generated inventory, executable presence, architectures, permissions, and no unexpected external dependency.
- Install: authorized disposable macOS target with service, socket, localhost, upgrade, and rollback checks.

State the highest level actually completed.
