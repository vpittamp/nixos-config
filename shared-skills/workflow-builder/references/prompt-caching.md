# Prompt Caching (Anthropic + OpenAI)

Scope: how the dapr-agent-py adapter wires per-provider prompt caching, what telemetry to read, and when to flip TTL/key knobs. Use this when an agent's `agent.llm_usage` event reports unexpected `cache_read_input_tokens`, when deciding whether to enable Anthropic 1h TTL, or when reading `[instruction-bundle]` log lines.

## Eligibility threshold

The static prefix (everything before the `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` sentinel rendered by `instruction_bundle.py`) must be ≥4000 chars (≈1024 tokens, Anthropic's published minimum and OpenAI's automatic-cache minimum). Below that:

- The Anthropic adapter forwards `system` as a plain string with no `cache_control` blocks.
- The OpenAI adapter still passes `instructions`, but prefix-cache hits are unlikely.
- `prompt_cache_eligible: false` on the `agent.llm_usage` session event.

The threshold is configurable via `DAPR_AGENT_PY_SYSTEM_PROMPT_CACHE_THRESHOLD_CHARS` and is shared between providers so cross-provider dashboards are apples-to-apples.

## Anthropic — `cacheTtl: "5m" | "1h"`

Field on `AgentConfig` (`src/lib/types/agents.ts`). Defaults to `"5m"`. UI control on agent detail → Model tab → "Prompt cache TTL".

| TTL | When | Cost |
|---|---|---|
| `5m` (default) | Short interactive sessions, chat UI, single-turn evaluators, score_model labelers | Cache write 1.25× base, read 0.1× base. Breakeven ≈ 1.4 reads. |
| `1h` (opt-in) | **Dapr durable agents that pause >5 min between turns**: workflows yielding on `ctx.create_timer`, approval gates, long-running benchmark loops, multi-step research, `CallAgent` peer chains | Cache write **2.0× base**, read 0.1× base. Breakeven ≈ 2.2 reads. |

The TTL is part of the cache key — flipping `5m` ↔ `1h` invalidates the cached prefix exactly once.

When `cacheTtl: "1h"`, the adapter automatically attaches the beta header to outgoing requests:

```
anthropic-beta: extended-cache-ttl-2025-04-11
```

`cacheTtl` is silently ignored on OpenAI components (no API surface). It still rides on the agent profile so the field is forward-looking.

## OpenAI — automatic + `prompt_cache_key`

OpenAI's prompt cache is automatic (no `cache_control` blocks, no TTL knob — server picks 5–10 min, longer off-peak). The one knob the adapter does set is `prompt_cache_key`, which pins all requests for the same logical workload to the same cache shard.

Derivation (`derive_openai_cache_key` in `services/dapr-agent-py/src/openai_adapter.py`):

1. `<agent_id>:<version>` — primary, stable per published agent version
2. `<slug>:<version>` — fallback when id is missing
3. `cfg:<configHash[:16]>` — last resort
4. `None` (field omitted) for ephemeral inline workflow agents — defaults to OpenAI's `(org_id, prompt_prefix)` routing

Without it, k8s round-robin across BFF/agent pods could hash different replicas to different cache backends and cold-start each one.

`store: true` + `previous_response_id` is **not** used — that breaks Dapr durable-task replay because the conversation history would live on OpenAI's servers instead of in our `session_events` durable log.

## Cross-provider telemetry on `agent.llm_usage`

| Field | Anthropic | OpenAI |
|---|---|---|
| `cache_read_input_tokens` | from `usage.cache_read_input_tokens` | from `usage.input_tokens_details.cached_tokens` |
| `cache_creation_input_tokens` | from `usage.cache_creation_input_tokens` | always `0` (writes implicit, not billed separately) |
| `prompt_prefix_chars` | char count of static-prefix block | char count before boundary sentinel |
| `prompt_tail_chars` | char count of dynamic tail | char count after sentinel |
| `prompt_cache_eligible` | prefix ≥ threshold | prefix ≥ threshold |
| `prompt_cache_breakpoints` | 1 (system) + 1 (last tool) when eligible | 1 (implicit prefix) when eligible |
| `prompt_cache_ttl` | `"5m"` or `"1h"` | always `"auto"` |

Phoenix span attributes mirror these as `prompt.cache_ttl`, `prompt.cache_eligible`, `prompt.cache_breakpoints`, `prompt.prefix_chars`, `prompt.tail_chars`, `prompt.tools_hash`. The OpenAI adapter additionally sets `prompt.cache_key` when configured.

## Greppable log line

Both adapters emit one per LLM call:

```
[instruction-bundle] mode=<sectioned|prefix|legacy> breakpoints=N prefix_chars=X tail_chars=Y cache_ttl=<5m|1h|auto> [provider=openai]
```

- `sectioned` (Anthropic, eligible) — explicit `cache_control` blocks attached
- `prefix` (OpenAI, eligible) — implicit prefix-match cache will fire
- `legacy` — under threshold, no caching breakpoint

`provider=openai` is appended on the OpenAI side; absent for Anthropic.

## Tool list determinism

Both adapters sort tool list by name before each call (`anthropic_tools.sort(...)` / `_convert_tools_for_openai` sort step). Without this, MCP reconnects or hooks/plugins adding/removing tools shuffle the list and silently invalidate prefix caches. The Anthropic adapter additionally puts `cache_control` on the **last tool block** so a stable tool tail gets its own cache breakpoint.

## When to look at this telemetry

- **Cache hit rate dropped after an edit** — diff the `templateHash` and `instructionHash` on `agent.llm_usage` events from before/after; if `prompt.tools_hash` changed, an MCP/plugin reshuffle invalidated the tool-tail breakpoint.
- **Tokens look high despite a long prompt** — check `prompt_cache_eligible`. If `false`, the prefix didn't cross threshold (or the boundary sentinel was missing from `rendered.system`).
- **1h TTL not paying back** — sample `agent.llm_usage` by agent over a week; if `cache_read_input_tokens / (cache_read_input_tokens + cache_creation_input_tokens) < 0.5`, 5m would have been cheaper.

## What NOT to put in the static prefix

These churn the cache key and tank hit rate:

- `cwd`, `sandboxName`, `executionId`, `sessionId`, `runId`
- Workflow input values (`{{trigger.foo}}` substituted at the system level)
- Per-turn timestamps
- User-specific inputs
- Sample values inserted "to make the preview clearer"

These belong on the **dynamic tail** (after the sentinel) or the **appended user message**.

## Authoritative files

- `services/dapr-agent-py/src/anthropic_adapter.py` — `_build_system_param`, `_cache_control`, `_call_anthropic_sdk`
- `services/dapr-agent-py/src/openai_adapter.py` — `_measure_openai_prompt`, `derive_openai_cache_key`, `_call_openai_responses`
- `services/dapr-agent-py/src/instruction_bundle.py` — `SYSTEM_PROMPT_DYNAMIC_BOUNDARY`, bundle composition
- `services/dapr-agent-py/src/main.py` — `_apply_instruction_prompt_state` stashes `_cache_ttl` + `_cache_key` on the LLM client per turn
- `src/lib/types/agents.ts` — `AgentConfig.cacheTtl`
- `services/dapr-agent-py/tests/test_anthropic_adapter_cache.py` + `tests/test_openai_adapter.py` — the unit tests are the most concise spec
