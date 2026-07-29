---
name: hxg-compliance-rule
description: Add, modify, review, or remove HX-Guardian macOS compliance controls and their related manifest entries, scan scripts, fix or undo scripts, baseline mappings, preferences, mobileconfig profiles, exemptions, and documentation. Use for NIST 800-53r5 High, CIS Controls v8, CIS Level 2, rule-result semantics, remediation behavior, and manifest allowlist changes under standards/.
---

# HXG Compliance Rule

Keep every representation of a control consistent while treating scan and remediation code as security-sensitive.

## Workflow

1. Read `AGENTS.md`, then read [references/rule-contract.md](references/rule-contract.md).
2. Locate the rule ID everywhere before editing:

```bash
rg -n '<rule-id>' standards app --glob '!app/frontend/dist/**' --glob '!app/dist/**' --glob '!transfer/**'
```

3. Inspect neighboring rules from the same category and source baseline. Follow their output, quoting, binary-path, and error-handling patterns.
4. Maintain the rule contract:
   - Manifest key and `rule` value match the stable rule ID.
   - Script paths are repository-relative, canonical, and allowlisted.
   - Scan scripts are read-only and deterministically report the expected status.
   - Fix scripts are narrowly scoped and idempotent where practical.
   - Undo scripts exist only when rollback is safe and well-defined.
   - Baseline membership and documentation describe the same behavior.
5. Treat missing tools, malformed output, and permission failures explicitly. Never convert uncertainty into a false pass.
6. Do not execute fixes, undo scripts, profiles, installers, `sudo`, or commands that alter macOS security configuration during routine validation.
7. Validate changed artifacts:

```bash
zsh -n standards/scripts/scan/<rule-id>.sh
zsh -n standards/scripts/fix/<rule-id>.sh
python -m json.tool standards/scripts/manifest.json >/dev/null
```

Run only the commands applicable to files that exist. Prefer static or fixture-level checks for scan behavior.
8. Re-run the search from step 2 and review the diff for orphaned files, inconsistent mappings, permissive paths, secrets, and generated outputs.
9. Report exactly what was validated and what requires controlled testing on a disposable macOS target.

## Prohibitions

- Never make a scan script mutate state.
- Never broaden the runner beyond manifest-listed scripts.
- Never interpolate unchecked input into shell commands or filesystem paths.
- Never weaken a control merely to produce a passing result.
- Never apply a profile or remediation on the development machine without explicit authorization and confirmed impact.
