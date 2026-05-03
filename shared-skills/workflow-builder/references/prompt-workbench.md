# Prompt Workbench

Scope: agent prompt authoring, project prompt presets, compiled prompt preview, and prompt-cache-aware prompt structure for workflow-builder. Use this when editing an agent's persona, applying/saving/updating a prompt preset, or explaining the workflow agent-node compiled prompt preview.

## Current V1 boundary

Prompt Workbench is the primary editor on the agent detail page for:

- `role`
- `goal`
- `systemPrompt`
- `instructions`
- `styleGuidelines`

It replaces the old plain Persona block as the authoring surface, but it does not change provider runtime messages by itself. Applying a preset writes values into the current unsaved `AgentConfig`; saving and publishing still follow the existing agent save/version flow.

Mustache variables are for authoring and preview only in V1. They are not a new runtime interpolation layer.

## Data model

Project prompt presets use an MCP-inspired parent/version model:

- `resource_prompts`: project-owned preset parent with name/title/description, metadata, enabled/archive state, and latest-version pointer.
- `resource_prompt_versions`: immutable rendered-version records for template content changes.
- `messages`: JSONB array shaped as `{ role, content }[]`.
- `arguments`: JSONB array shaped as `{ name, description, required }[]`.
- `template_format`: defaults to `mustache`. Do not expose arbitrary Jinja2 editing in V1.
- `template_hash`: stable hash for auditability and cache/debug comparisons.

Normal picker results should list enabled, non-archived presets for the current project only, returning the latest version by default. Updating preset content creates a new version rather than mutating the old rendered version.

Relevant APIs:

- `GET /api/prompt-presets`
- `POST /api/prompt-presets`
- `PUT /api/prompt-presets/[id]`
- `DELETE /api/prompt-presets/[id]`

## Preview shape

The shared renderer and preview component should make the final prompt boundary obvious:

- System message
- Chat history placeholder
- Appended user message
- Sources and audit fields
- Variable warnings
- `Not sent in v1` labels for preview-only substitutions

The agent editor uses a two-column workbench layout: editable fields and preset actions on the left, live preview on the right. The right side exposes `Rendered`, `Variables`, and `Sources` tabs. Workflow agent-node previews reuse the same preview component and should show selected agent/version/config hash, canonical template name/hash when available, rendered system prompt, `chat_history`, and the appended node prompt.

## Available variables

Variables are copyable Mustache-style chips. Common categories:

- Agent: `{{agent.name}}`, `{{agent.slug}}`, `{{agent.id}}`, `{{agent.version}}`, `{{agent.configHash}}`
- Runtime: `{{runtime.cwd}}`, `{{runtime.sandboxName}}`, `{{runtime.environment}}`, `{{runtime.skills}}`
- Workflow node preview: `{{workflow.id}}`, `{{workflow.name}}`, `{{node.prompt}}`
- Session/run preview: `{{session.id}}`, `{{run.id}}`
- Preset arguments: `{{args.<name>}}`

If a preview value is missing, leave the placeholder unresolved and show a warning. Do not silently blank unresolved variables.

## Runtime boundary

The deployed Dapr prompt path stays canonical:

1. One system message from the compiled instruction bundle.
2. A `chat_history` placeholder.
3. The current user prompt appended by Dapr.

The Prompt Workbench preview can render Mustache values to help authors reason about the prompt, but runtime substitution for these variables is out of scope for V1. In workflow JSON, use SW 1.0 jq expressions such as `${ .trigger.url }` for runtime interpolation. A `{{runtime.cwd}}` placeholder in a workflow node prompt is just literal text at execution time unless another runtime layer explicitly handles it.

## Prompt caching

Treat prompt cacheability as part of prompt design:

- Keep the stable system/preset prefix stable when possible.
- Do not inject volatile values such as cwd, sandbox name, environment, workflow id, run id, session id, or user-specific inputs into the system prompt unless the behavior depends on them being there.
- Prefer putting per-run data in the appended user prompt or workflow input context.
- Avoid changing preset text just to insert sample values; use preview context instead.
- When a provider reports cached tokens, audit `template_hash`, instruction hash, selected preset/version ids, and source fields before assuming the cache is broken.

Dapr Conversation supports provider prompt cache retention and response caching settings, including `promptCacheRetention` and response cache TTL paths. The workflow-builder authoring surface should not make cache misses more likely by parameterizing otherwise stable system content.

## Migration and rollout checks

Prompt preset schema changes need both migration paths in this repo:

- `drizzle/0060_resource_prompt_versions.sql`
- `drizzle/meta/_journal.json`
- `atlas/migrations/20260501090000_add_resource_prompt_versions.sql`

Production `db-migrate` runs Drizzle and is journal-gated; the atlas startup path is mainly effective in source-synced/devspace environments because the production image copies `drizzle/` and excludes `atlas/`.

After a rollout, verify:

```bash
# Inside the workflow-builder DB
SELECT to_regclass('public.resource_prompt_versions');
SELECT id, hash, created_at FROM drizzle.__drizzle_migrations ORDER BY created_at DESC LIMIT 5;

# Public unauthenticated route should not leak project presets
curl -i https://<workflow-builder-host>/api/prompt-presets
```

Then run an authenticated smoke for list/create/update/archive in the target workspace and confirm update creates version 2. Clean up smoke rows afterwards.

## Authoritative files

- `src/lib/agents/prompt-workbench-renderer.ts`
- `src/lib/components/agents/prompt-workbench.svelte`
- `src/lib/components/agents/prompt-preview.svelte`
- `src/lib/server/agents/instruction-bundle.ts`
- `src/routes/api/prompt-presets/`
- `drizzle/0060_resource_prompt_versions.sql`
- `atlas/migrations/20260501090000_add_resource_prompt_versions.sql`
- `services/fn-system/src/steps/dapr-converse-structured-output.ts`
