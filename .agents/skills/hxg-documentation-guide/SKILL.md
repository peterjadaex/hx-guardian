---
name: hxg-documentation-guide
description: Create, restructure, review, or update HX-Guardian Markdown documentation, runbooks, setup instructions, architecture explanations, API references, troubleshooting procedures, hardening-control descriptions, security rationale, and release notes. Use when implementation changes require documentation, when instructions are unclear or duplicated, or when editing AGENTS.md, app/app_readme.md, app/frontend/README.md, standards/airgap_readme.md, standards/hardening_controls.md, standards/scripts/README.md, or other repository guides.
---

# HXG Documentation Guide

Write documentation that is accurate for its audience, traceable to implementation, safe to follow, and usable on an air-gapped macOS target.

## Workflow

1. Read `AGENTS.md`.
2. Read [references/documentation-map.md](references/documentation-map.md) to select the canonical guide and audience.
3. Read [references/writing-standard.md](references/writing-standard.md) before adding commands, security claims, procedures, or troubleshooting advice.
4. Inspect the implementation, configuration, or workflow being documented. Do not copy stale behavior from another guide without verifying it.
5. Search all documentation for the affected feature, command, path, service, rule ID, or configuration:

```bash
rg -n '<term>' --glob '*.md' --glob '!app/secret.md'
```

6. Update the canonical guide first. Add concise cross-references elsewhere instead of duplicating long procedures.
7. Separate audience and environment assumptions:
   - developer Mac versus air-gapped target;
   - admin versus day-to-day operator;
   - safe verification versus privileged or state-changing action;
   - source file versus generated bundle versus installed path.
8. For a procedure, state prerequisites, exact working directory, expected result, failure interpretation, and recovery or rollback where appropriate.
9. For implementation changes, update documentation in the same change. For documentation-only corrections, verify every changed command, path, endpoint, and service name against source.
10. Review links, headings, terminology, command safety, duplicated claims, and consistency with related guides.
11. Report what was source-verified and identify any procedure that still requires controlled macOS/root testing.

## Safety

- Never read or cite `app/secret.md`, runtime keys, databases, logs, tokens, or credentials.
- Never invent output, compatibility claims, compliance coverage, or successful test results.
- Never instruct target-device users to fetch runtime or installation dependencies from the network.
- Mark destructive, privileged, security-changing, or irreversible commands clearly and include scope.
- Do not turn documentation work into execution of installers, fixes, profiles, `sudo`, or `launchctl`.
- Do not document bypasses that weaken authentication, auditing, allowlisting, path validation, socket permissions, localhost binding, or privilege separation.
