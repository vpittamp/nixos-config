---
name: dapr-agents-workflow
description: "Write, scaffold, review, or debug standalone Python applications built with open-source Dapr Agents and Dapr Workflows. Use for DurableAgent, AgentRunner, workflow/activity decorators, call_agent, multi-agent orchestration, tools or MCP, pub/sub discovery, human approval, durable retries, multi-app dapr.yaml files, actor-state-store errors, and replay determinism. Use workflow-builder for the PittampalliOrg saved-workflow product."
---

# Dapr Agents And Workflows

This skill targets portable Python applications built directly on
`dapr/dapr-agents` and `dapr.ext.workflow`. It does not describe Workflow
Builder's saved scripts, runtime registry, database, or cluster deployment.

## Version Boundary

Inspect the target project's lockfile and installed package signatures before
editing. The bundled templates target `dapr-agents` 1.0.5 with the compatible
Dapr Python SDK 1.18 line. If the project uses another version, inspect that
exact upstream tag and adapt the templates; do not carry APIs across versions
by assumption.

Use the local upstream checkout when available:

```bash
UPSTREAM=/home/vpittamp/repos/PittampalliOrg/dapr-agents/main
git -C "$UPSTREAM" fetch upstream --tags
git -C "$UPSTREAM" show <target-tag>:pyproject.toml
```

## Choose A Pattern

| Need                                                        | Pattern                      | Template                                  |
| ----------------------------------------------------------- | ---------------------------- | ----------------------------------------- |
| One durable agent with tools                                | Single agent                 | `assets/templates/single-agent/`          |
| One agent backed by MCP tools                               | MCP agent                    | `assets/templates/mcp-agent/`             |
| Explicit sequence, fan-out/fan-in, retries, or approval     | Workflow-orchestrated agents | `assets/templates/workflow-orchestrated/` |
| Open-ended round-robin, random, or LLM-routed collaboration | Autonomous multi-agent       | `assets/templates/multi-agent/`           |
| Timers, activities, external events without agents          | Plain Dapr Workflow          | `assets/templates/workflow-primitives/`   |

Prefer explicit workflow orchestration when auditability and deterministic
control flow matter. Use autonomous collaboration only when agents genuinely
need to select and message peers through the framework.

## Authoring Workflow

1. Confirm package versions and the exact imports/signatures in the target
   environment.
2. Define stable agent names, Dapr app IDs, roles, instructions, model clients,
   tools, and communication pattern.
3. Copy the smallest matching template and remove unused components.
4. Put all nondeterministic work in activities or agent calls; keep workflow
   bodies deterministic.
5. Include exactly one actor-enabled state store visible to each workflow app.
6. Add memory, registry, pub/sub, conversation, or MCP components only when the
   selected pattern uses them.
7. Give each app a unique `appID`, command, app directory, and port in the
   multi-app run file.
8. Run import/compile checks, start with `dapr run -f dapr.yaml`, and exercise a
   real request plus restart/resume behavior.

Read only the relevant reference:

- `references/workflow-primitives.md`
- `references/durable-agent.md`
- `references/multi-agent-orchestration.md`
- `references/tools-and-mcp.md`

## Durable Invariants

- Workflow code is replayed. Do not perform I/O, random generation, wall-clock
  reads, environment reads, or mutable global access in the workflow body.
- Yield every scheduled activity, child workflow, timer, external event race,
  and `call_agent` task. An unyielded task is not scheduled.
- Use workflow-safe time/timer APIs and move side effects into activities.
- Exactly one visible state-store Component may set
  `actorStateStore: "true"`. Memory and registry stores remain non-actor.
- Agent `name` and Dapr `appID` are distinct routing identifiers. Keep both
  stable and map them explicitly in `call_agent`.
- `AgentRunner` owns agent lifecycle. Do not invent a `.start()` method on
  `DurableAgent`.
- Current orchestration uses `OrchestrationMode` on an agent execution config;
  removed standalone orchestrator classes must not be restored.
- Tool functions need useful docstrings and type hints because those define the
  model-visible contract.
- Pub/sub and registry components belong to autonomous peer collaboration, not
  every single-agent or explicit child-workflow app.
- Dapr Conversation support and provider-direct clients have different maturity
  and operational boundaries. Select intentionally for the target version.

## Verification

Before presenting generated code as runnable:

```bash
python -m compileall <app-dir>
dapr run -f dapr.yaml
```

Then prove:

- Every sidecar starts without duplicate actor-store errors.
- Health and request routes bind to the configured app port.
- Tools/MCP discovery returns the expected names and schemas.
- Agent-to-agent routing uses the intended name and app ID.
- A timer, activity, approval event, or child-agent step survives a process
  restart and resumes once rather than repeating side effects.
- Shutdown calls the runner cleanup path.

## Bundled Resources

- `assets/templates/` contains minimal runnable starting points.
- `assets/components/` contains optional Dapr component examples.
- `assets/templates/requirements.txt` pins the API line used by the templates.
- `evals/trigger-evals.json` checks skill routing boundaries.

Copy and adapt templates; do not modify the shared assets for a user project.
