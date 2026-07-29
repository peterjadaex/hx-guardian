# Documentation writing standard

## Accuracy

- Verify behavior against source, manifests, plists, or build scripts.
- Use the exact file path, endpoint, service label, rule ID, and command currently implemented.
- Distinguish observed behavior from an expectation or recommendation.
- Do not claim a command or install was tested unless it was actually run in the stated environment.
- Add dates or version qualifiers only where behavior is genuinely version-dependent.

## Procedures

Write operational steps in execution order. Include:

1. audience and environment;
2. prerequisites and current working directory;
3. copyable command or UI path;
4. concise expected result;
5. what failure means;
6. safe recovery or rollback, when available.

Keep destructive or security-changing actions out of routine verification sections. Label required privilege and expected impact immediately before such an action.

## Air-gap clarity

Always distinguish:

- development machine paths from target installed paths;
- repository source from `app/dist/`, `transfer/`, and SD-card contents;
- tools allowed only during development from dependencies available on the target;
- optional connected testing posture from production air-gapped posture.

Never introduce a target instruction that depends on a CDN, package registry, remote API, telemetry service, or online installer.

## Security language

- Explain trust boundaries and why a safeguard exists when its purpose may not be obvious.
- Do not disclose secrets, secret locations beyond existing policy, credentials, tokens, or sensitive runtime contents.
- Do not recommend disabling authentication, auditing, allowlisting, validation, localhost binding, or privilege separation to troubleshoot.
- Prefer a bounded diagnostic check over a broad permission or ownership change.

## Markdown

- Use one descriptive H1 per guide and a predictable H2/H3 hierarchy.
- Use tables for stable mappings, not long prose.
- Use fenced code blocks with the correct language.
- Keep commands copyable; put placeholders in angle brackets and explain them.
- Use relative links between repository documents.
- Keep examples free of real credentials, device identifiers, usernames, or host-specific secrets.
