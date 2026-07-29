# Compliance rule contract

## Artifact inventory

A rule can be represented by:

- `standards/scripts/manifest.json`
- `standards/scripts/scan/<rule-id>.sh`
- `standards/scripts/fix/<rule-id>.sh`
- `standards/scripts/undo_fix/<rule-id>.sh`
- baseline preference or mapping content under `standards/800-53r5_high/`, `standards/cisv8/`, and `standards/cis_lvl2/`
- per-baseline or unified mobileconfig profiles
- setup exemptions and operator/developer documentation

Not every rule has every artifact. Search by rule ID before deciding scope.

## Scan requirements

- Perform no writes or configuration changes.
- Quote expansions and validate inputs.
- Prefer absolute system binary paths where neighboring scripts do.
- Prefer structured output over parsing localized human-readable text.
- Distinguish compliant, noncompliant, and execution-error cases according to existing runner expectations.
- Fail safely when state cannot be determined; never turn an error into compliance.

## Fix requirements

- Change only the setting named by the rule.
- Be idempotent where practical.
- Check prerequisites and return actionable error output.
- Avoid broad file permission, ownership, account, or service changes.
- Provide undo only when the previous or safe target state is well-defined.

## Manifest requirements

- Keep the object key, `rule`, and script filenames aligned.
- Use repository-relative paths beneath the approved standards script tree.
- Preserve standards membership and source provenance.
- Do not add a path that lets callers escape the allowlisted tree.

## Validation posture

Syntax-check shell and JSON locally. Treat execution of remediation, profile installation, service control, and host security changes as controlled target-device tests requiring explicit authorization.
