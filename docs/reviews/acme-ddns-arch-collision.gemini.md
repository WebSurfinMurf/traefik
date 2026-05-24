---
source: gemini
reviewed: 2026-05-08
context: acme-ddns-arch-collision.md
status: NODE FAILED
---

# Gemini node failed during the verify step

Error returned by `dispatch_to_reviewboard(target="gemini", prompt="Reply with exactly: READY", timeout=30)`:

```
Gemini CLI is not running in a trusted directory. To proceed, either use
`--skip-trust`, set the `GEMINI_CLI_TRUST_WORKSPACE=true` environment variable,
or trust this directory in interactive mode.
```

This is a configuration issue with the Gemini node container's trusted-folder mechanism, not a transient failure. The review board's `gemini` node will need its container env updated (`GEMINI_CLI_TRUST_WORKSPACE=true` or equivalent) before it can be used again.

The review proceeded with codex + claude only. Synthesis flags this as a 2-of-3 review rather than 3-of-3, but the two responses were substantive and largely converged on the architectural question.

**Follow-up:** consider filing this against the review-board project for the gemini-cli trusted-folder env. Likely fix: add `-e GEMINI_CLI_TRUST_WORKSPACE=true` to the gemini node's docker invocation in the reviewboard project.
