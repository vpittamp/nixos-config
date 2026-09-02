# Native CLI Runtime Contract

`claude-code-cli`, `codex-cli`, `kimi-code-cli`, `agy-cli`, and other
`interactive-cli` runtimes run the official vendor binary, never an SDK
reimplementation, in one of two execution modes. Do not confuse the mode with
the registry field: `capabilities.cliExecutionMode` accepts only `native-tui`
and asserts terminal attachability, which the workflow bridge requires of every
`interactiveTerminal` runtime (agy included) alongside the registry-owned
`cliAdapter`. The per-turn mode is an adapter environment switch, reported back
as `executionMode` in the start result:

- `native-tui`: the binary runs inside Herdr's PTY and prompts are injected into
  it. This is the default for Claude, Codex, and Kimi and is required for
  attached human sessions that need a live terminal.
- `headless-print`: each turn is its own subprocess speaking the vendor's
  structured stdio protocol (Claude `-p --output-format stream-json --verbose`,
  Kimi `--prompt --output-format stream-json`, Codex `exec --json`, and agy
  `-p --output-format stream-json`), with turn continuity through that CLI's own
  resume handle. It is the default and only supported mode for `agy-cli`, whose
  TUI wedges under PTY injection. Opt in for the others with
  `CLI_AGENT_{CLAUDE,KIMI,CODEX}_HEADLESS=1`. No vendor here offers ACP; print
  mode is the structured-transport equivalent.

## Invariants

- Preserve user-scoped subscription OAuth delivery through `cliAuth` and the
  session Secret path. Do not replace it with a provider API key or an SDK
  client. Headless print mode runs the same binary under the same subscription
  token, so the auth contract is unchanged.
- Public `app-live` and `system-live` profiles are `dapr-agent-py`,
  `claude-code-cli`, `codex-cli`, `kimi-code-cli`, and `agy-cli`. Fixture-local
  `*-host` values are internal adapter mappings and must not be caller input.
  `adk-agent-py` is retired.
- In a persistent CLI profile, edit the seeded host checkout and run
  `wfb-development apply`, `observe`, or `verify`. The application reconstructs
  the parent DevelopmentRun and compiler-owned adapter from session identity.
- With supervised watch mode, run `wfb-development await-sync --wait --repo
  <edited-checkout>` and require `applied` before inspection. The verdict covers
  the primary checkout and every imported repository.
- Inspect through the session's Playwright MCP. Submission and cancellation are
  parent-run gates. Arbitrary event payloads and unrelated workflow actions are
  rejected. Never copy an OAuth Secret or CLI pod into the vCluster.
- Kimi Code uses device-login OAuth from
  `$KIMI_CODE_HOME/credentials/kimi-code.json`. Capture and rotate only that
  file; remove Kimi and Moonshot API-key variables before launching the CLI.
- Workflow kickoff is accepted only after the native composer reports a
  positive receipt. Native hooks own completion, failure, permission, and
  compaction events. Transcript ingestion is append-only and retains a durable
  high-water mark so a restarted wrapper does not duplicate events.
- Some CLIs can terminate a turn before emitting a stop hook. After a bounded
  grace period, a transcript terminal failure may fail the turn; a later native
  stop or failure hook cancels that fallback. Terminal pixels remain diagnostic
  evidence, never completion authority.
- Persist native transcripts with prompt, response, and tool content intact.
  Treat them as queryable execution evidence; do not apply blanket content
  redaction.
- A missing kickoff receipt fails the child with
  `native_tui_kickoff_not_accepted`. Dynamic-script `agent()` resolves errored
  journal entries to `null`, so required calls must check and reject `null`.
- `CLI_AGENT_WORKFLOW_BATCH=0` exists only as compatibility configuration for
  older images. Current runtime source has no workflow batch branch.
- Borrow Omnigent's explicit capability declarations, session-scoped homes,
  and supervised high-water transcript ingestion where they strengthen this
  adapter. Do not introduce a second lifecycle, scheduling, or durable-state
  authority beside Dapr, Kueue, the BFF, and JuiceFS.
