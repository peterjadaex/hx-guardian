# Documentation map

Choose one canonical home for each fact or procedure. Cross-link instead of maintaining several full copies.

| Guide | Primary audience | Canonical content |
|---|---|---|
| `AGENTS.md` | coding agents and contributors | repository-wide policy, safety constraints, validation baseline, skill routing |
| `app/app_readme.md` | application developers and release builders | architecture, development setup, backend/frontend behavior, packaging workflow, API overview |
| `app/frontend/README.md` | frontend developers | React structure, frontend-only commands, UI-specific conventions |
| `standards/airgap_readme.md` | target-device admins and operators | offline installation, hardening, daily operations, recovery, target troubleshooting |
| `standards/scripts/README.md` | compliance-rule and backend integrators | rule/script interface, manifest schema, status contract, integration patterns |
| `standards/hardening_controls.md` | security reviewers and maintainers | control intent, platform setting, enforcement approach, exceptions, verification rationale |
| `standards/hardening_test_checklist.md` | testers, security reviewers, and device administrators | repeatable hardening verification cases, actual results, evidence, status, and sign-off |
| `standards/security_standards_comparison.md` | security and compliance reviewers | baseline comparison and coverage distinctions |
| focused troubleshooting guides | developers or support engineers | one bounded incident or diagnostic flow not suitable for the main runbook |

## Routing rules

- Put developer commands and source-tree behavior in `app/app_readme.md`.
- Put target-device steps and installed paths in `standards/airgap_readme.md`.
- Put scan/fix interface details in `standards/scripts/README.md`.
- Put why a control exists and how it is enforced in `standards/hardening_controls.md`.
- Put narrow frontend details in `app/frontend/README.md`; link to the application guide for shared setup.
- Keep `AGENTS.md` concise and normative. Move detailed task procedures into repository skills.
- Avoid adding a new top-level guide when an existing canonical guide can own the material cleanly.

## Consistency triggers

Update related documentation when changing:

- API endpoint, request, response, or authentication behavior;
- dashboard page, operator action, loading/error state, or navigation;
- service name, plist, installed path, ownership, socket, or port;
- build command, bundle inventory, dependency, installer, update, or rollback;
- compliance rule, exemption, baseline membership, profile, scan, fix, or result semantics;
- supported macOS/Python/Node version or environment assumption.
