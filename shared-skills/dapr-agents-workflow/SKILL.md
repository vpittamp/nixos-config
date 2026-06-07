---
name: dapr-agents-workflow
description: "Use this skill to write, scaffold, review, or debug Python code built on the open-source Dapr Agents framework (`dapr/dapr-agents`) and Dapr Workflows (`dapr.ext.workflow`) — durable AI agents you run yourself, not a hosted product. Reach for it whenever the user names DurableAgent, AgentRunner, `@workflow`, `call_agent`, OrchestrationMode, `@tool`/MCP tools, or a `dapr run -f` multi-app layout, OR describes the intent in plain words: building a 'dapr agents' app, making agents take turns / debate / round-robin, having an LLM pick which agent responds next, a team of agents discovering each other and talking over pub/sub, a deterministic workflow that runs agents as retrying durable steps, or scaffolding orchestrator + agent apps each with their own appID/port. Also covers their Dapr wiring — the 'duplicate actor state store' / `actorStateStore: true` rule, required components, determinism pitfalls. NOT for the SW 1.0 workflow-builder canvas/spec/deployed services — that's the workflow-builder skill."
---

# Dapr Agents + Dapr Workflow (Python)

Turn a user prompt into a valid, runnable Dapr application that coordinates one or more
durable AI agents. Grounded in upstream `dapr/dapr-agents` GA **v1.0.3** and
`dapr-ext-workflow` **1.17.x** — every API in this skill was verified against the repo's
main branch and docs.dapr.io.

## Mental model in one paragraph

A **Dapr Workflow** is a deterministic, replayable generator that orchestrates **activities**
(your side-effecting code) via `yield ctx.call_activity(...)`; it runs on Dapr actors and
must persist its history in a state store marked `actorStateStore: "true"`. The **Dapr Agents**
framework builds ON that: a **`DurableAgent`** runs its whole agent loop (LLM turns + tool
calls) as a checkpointed workflow, so it survives restarts and resumes deterministically. You
**serve** an agent as a Dapr app with **`AgentRunner`** (`serve()` for HTTP, `subscribe()` for
pub/sub, `workflow()` for pure-workflow), and you launch several agent apps + an orchestrator
together with a **multi-app run file** (`dapr run -f dapr.yaml`, one `appID` per app). There
are **two ways to coordinate multiple agents**: (A) a deterministic workflow you write that
invokes agents as durable child workflows with `call_agent(ctx, name, input, app_id=...)`, or
(B) autonomous agent-to-agent collaboration where a `DurableAgent` orchestrator runs an
`OrchestrationMode` (ROUNDROBIN / RANDOM / AGENT) over a team that discovers each other through
a shared registry and talks over pub/sub. Agents get capabilities from **`@tool`** functions
and/or **MCP** servers (`MCPClient.get_all_tools()`), both passed as `tools=[...]`. The agent's
model comes from a chat client — `OpenAIChatClient()` (provider-direct, GA) or
`DaprChatClient(component_name=...)` (the still-ALPHA Conversation API). Code in the workflow
body must never do I/O, use clocks, or skip a `yield`; that is the cardinal rule.

## When to use this skill

Trigger on any of: "write a Dapr agent / DurableAgent", "build a durable agentic workflow",
"orchestrate multiple agents", "agents that call each other / collaborate / debate", "round
robin agents", "agent that uses MCP / tools", "Dapr workflow that calls an LLM", "multi-app
dapr run", "human approval step in an agent workflow", "fan out work across agents". If the
user is instead editing the local **SW 1.0 workflow-builder** product — the canvas, a
`durable/run` step, `agentConfig`, an SW 1.0 JSON spec, the `workflow-orchestrator` /
`openshell-agent-runtime` services, Prompt Workbench, ActivePieces piece MCP, or a failed
workflow run in that repo — use the **workflow-builder** skill. This skill is about the
*upstream framework* (`dapr/dapr-agents` + `dapr.ext.workflow`) and is portable to any Dapr
project; it never references that product's orchestrator, DB, or cluster.

## Pick the pattern first (decision tree)

| The user wants… | Pattern | Start from |
|---|---|---|
| One agent that answers using some tools/MCP | **Single agent** | `assets/templates/single-agent/` (+ `mcp-agent/` for MCP) |
| A **known sequence / DAG** of agent steps; fan-out then aggregate; a **human approval** gate between steps; auditable pipeline | **A — Workflow-orchestrated** | `assets/templates/workflow-orchestrated/` |
| **Open-ended collaboration** — a team of agents that talk to each other, take turns, debate, or route work among themselves | **B — Autonomous** | `assets/templates/multi-agent/` |
| A durable **non-agent** workflow (timers, retries, external events) | plain workflow | `assets/templates/workflow-primitives/` |
| Several apps launched together (any of the above) | **multi-app run** | the `dapr.yaml` in each template |

**A vs B is the key call.** A = *you* hold the control flow (deterministic, explicit, great for
human-in-the-loop and fan-out/fan-in). B = the *framework + agents* hold it (emergent, pub/sub,
great for collaboration). When unsure, prefer A — it is easier to reason about and audit. Full
comparison: `references/multi-agent-orchestration.md`.

## Authoring recipe (prompt → runnable app)

1. **Classify** the request into a pattern (table above). State which one and why.
2. **Enumerate the agents**: for each, decide `name`, `role`, `goal`, `instructions`, its
   `tools` (native `@tool` and/or MCP), and its `llm`. One agent ⇒ skip the orchestrator.
3. **Write each agent file** from the matching template. Keep `name` stable — it is how the
   orchestrator addresses the agent.
4. **Write the orchestrator** (Pattern A: a `@wfr.workflow` that `yield`s `call_agent(...)`;
   Pattern B: a `DurableAgent` with `execution=AgentExecutionConfig(orchestration_mode=...)`).
   None for a single agent.
5. **Assemble the component set** (copy the ones you need from `assets/components/` into a
   `./components` dir next to your `dapr.yaml`):
   - always: `agent-workflow.yaml` (the one with `actorStateStore: "true"`);
   - if any agent sets `memory=`: `agent-memory.yaml` (recommended for chat agents, optional);
   - if any agent uses `DaprChatClient`: `llm-provider.yaml`;
   - Pattern B only: `agent-pubsub.yaml` + `agentregistrystore.yaml`.
6. **Write `dapr.yaml`**: one `apps:` entry per app with its `appID`, `command`, and `appPort`
   (HTTP-served apps only — orchestrator clients and pub/sub workers have none). `appDirPath`
   is relative to the `dapr.yaml`; point `common.resourcesPath` at your `./components` dir.
7. **Check the invariants** (next section), export the LLM key (e.g. `OPENAI_API_KEY` for
   `OpenAIChatClient`), then run: `dapr run -f dapr.yaml`. Trigger an HTTP-served agent or
   orchestrator with `POST /agent/run` and body `{"task": "<prompt>"}`; a Pattern-A workflow
   app instead schedules itself in-process (`schedule_new_workflow`).

Read the reference for whichever surface you are writing — don't guess signatures:
`references/workflow-primitives.md`, `references/durable-agent.md`,
`references/multi-agent-orchestration.md`, `references/tools-and-mcp.md`. For a fast
import/signature lookup use `references/api-cheatsheet.md`.

## Critical gotchas (each with the *why* — these cost the most time)

- **The workflow body must be deterministic.** It is replayed from the top on every event, so
  any I/O, `datetime.now()`, `random`, `uuid4()`, or env read there produces wrong/corrupt
  results. Put all of that in **activities** (or in the agents). Use `ctx.current_utc_datetime`
  for time and `ctx.create_timer(...)` for delays. *Why:* durability is achieved by re-running
  the orchestrator and replaying recorded results; non-deterministic bodies break replay.

- **Always `yield` a scheduled task.** `ctx.call_activity(...)`, `ctx.call_child_workflow(...)`,
  `call_agent(...)`, `ctx.create_timer(...)`, and `when_all/when_any` only run when yielded. A
  forgotten `yield` silently no-ops. *Why:* the generator drives the durable scheduler; an
  unyielded coroutine/task is never handed to it.

- **`when_all` / `when_any` are module-level functions**, `wf.when_all([...])` — not methods on
  the context. For a race, build the event task and timer task *first*, then yield `when_any`.

- **Exactly ONE actor state store.** The durable store needs `actorStateStore: "true"`
  (`agent-workflow.yaml`). If a sidecar sees **two** such components it refuses to start
  ("detected duplicate actor state store"). Keep memory/registry/pubsub stores as plain
  (non-actor) components. *Why:* Dapr placement assumes a single actor state store per app.

- **`name` (agent) ≠ `appID` (Dapr).** `call_agent(ctx, "triage_agent", app_id="triage-agent")`
  uses *two different ids*: `"triage_agent"` is the `DurableAgent(name=...)` (→ workflow name);
  `"triage-agent"` is the `appID` in `dapr.yaml` (→ routing). Mismatching either is the #1
  Pattern-A bug. Keep a consistent convention (e.g. snake_case name, kebab-case appID).

- **`DurableAgent` has no `.start()`.** The lifecycle is owned by `AgentRunner`. Serve with
  `runner.serve(agent, port=...)` (HTTP), `runner.subscribe(agent)` (pub/sub worker, then
  `await wait_for_shutdown()`), or `runner.workflow(agent)` (pure workflow). Always
  `finally: runner.shutdown(agent)`. *Why:* the runner wires the workflow runtime, routes, and
  pub/sub subscriptions; the agent object is just configuration.

- **Orchestrators are a MODE, not a class (v1.0.3).** `RoundRobinOrchestrator` /
  `RandomOrchestrator` / `LLMOrchestrator` were **removed**. Configure
  `AgentExecutionConfig(orchestration_mode=OrchestrationMode.ROUNDROBIN|RANDOM|AGENT)` on a
  `DurableAgent`. AGENT mode additionally **requires `llm=`** on the orchestrator. If you write
  the old class names, the code will not import.

- **`@tool` functions require a docstring.** Missing it raises `ToolError`. The docstring is the
  tool description the LLM sees; arg schema is inferred from type hints. *Why:* the framework has
  nothing else to describe the tool to the model.

- **The Conversation API is ALPHA.** `DaprChatClient(component_name="llm-provider")` routes
  through Dapr's still-ALPHA Conversation building block. For production prefer a provider-direct
  client (`OpenAIChatClient()` etc.) — then you don't even need `llm-provider.yaml`.

- **Pub/sub is for Pattern B only.** A single agent and the Pattern-A `call_agent` flow need NO
  pub/sub — only state stores. Adding pub/sub where it isn't needed just adds a failure surface.

- **Pin versions deliberately.** `dapr-agents==1.0.3`, `dapr-ext-workflow` 1.17.x, Dapr runtime
  1.17.x. These move fast and APIs have churned (see the removed-orchestrators note). If you
  target a different version, re-verify the surface in `references/api-cheatsheet.md`.

## What's in this skill

- `references/` — deep, primary-sourced API docs: `workflow-primitives.md`, `durable-agent.md`,
  `multi-agent-orchestration.md`, `tools-and-mcp.md`, `api-cheatsheet.md` (quick lookup).
- `assets/components/` — the 5 Dapr component YAMLs (copy the ones a pattern needs).
- `assets/templates/` — runnable skeletons per pattern: `single-agent/`, `workflow-orchestrated/`
  (Pattern A), `multi-agent/` (Pattern B), `mcp-agent/`, `workflow-primitives/`. Each carries its
  own `dapr.yaml`.

Prefer **copying a template and adapting it** over writing from a blank file — the templates
already encode the invariants above.
