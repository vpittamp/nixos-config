# Quickstart: Langfuse-Compatible AI CLI Tracing

**Feature**: 132-langfuse-compatibility
**Date**: 2025-12-22

## Prerequisites

1. Langfuse account (cloud or self-hosted)
2. Langfuse API keys (public key + secret key)
3. Existing NixOS config with AI CLI tracing enabled

---

## Quick Setup

### 1. Get Langfuse Credentials

1. Log in to [Langfuse Cloud](https://cloud.langfuse.com) or your self-hosted instance
2. Navigate to **Settings → API Keys**
3. Create a new API key pair
4. Note down:
   - Public Key: `pk-lf-...`
   - Secret Key: `sk-lf-...`

### 2. Configure NixOS

Add to your configuration (e.g., `configurations/hetzner-sway.nix`):

```nix
{
  services.grafana-alloy = {
    langfuse = {
      enable = true;
      endpoint = "https://cloud.langfuse.com/api/public/otel";
      # For US region: "https://us.cloud.langfuse.com/api/public/otel"
      # For self-hosted: "http://localhost:3000/api/public/otel"
    };
  };

  # API keys via 1Password or environment
  sops.secrets.langfuse-public-key = { };
  sops.secrets.langfuse-secret-key = { };
}
```

### 3. Set API Keys

Option A: Environment variables in shell profile:
```bash
export LANGFUSE_PUBLIC_KEY="pk-lf-..."
export LANGFUSE_SECRET_KEY="sk-lf-..."
```

Option B: 1Password integration (recommended):
```nix
# Already integrated with 1Password in this config
# Keys are automatically fetched from vault
```

### 4. Rebuild and Apply

```bash
sudo nixos-rebuild dry-build --flake .#hetzner-sway
sudo nixos-rebuild switch --flake .#hetzner-sway
```

### 5. Verify

```bash
# Check Alloy status
systemctl status grafana-alloy

# Check AI monitor
systemctl --user status otel-ai-monitor

# Test with a Claude Code session
claude "Hello, this is a test"
```

---

## Verify Traces in Langfuse

1. Open Langfuse UI → **Traces**
2. Look for traces with:
   - Name: `claude.conversation` / `codex.conversation` / `gemini.conversation`
   - Provider: `anthropic` / `openai` / `google`
3. Click a trace to see:
   - Nested generations (assistant turns)
   - Tool calls with inputs/outputs
   - Token usage and costs

---

## Filtering Traces

Use Langfuse filters:

| Filter | Attribute | Example |
|--------|-----------|---------|
| By provider | `gen_ai.system` | `anthropic` |
| By model | `gen_ai.request.model` | `claude-opus-4-5-20251101` |
| By session | `langfuse.session.id` | `project-nixos-config` |
| By user | `langfuse.user.id` | `vpittamp` |
| By tags | `langfuse.trace.tags` | `["feature-132"]` |

---

## Session Grouping

Traces are automatically grouped by session:

- Claude Code: Uses `session.id` from hooks
- Codex CLI: Uses `conversation.id` (normalized)
- Gemini CLI: Uses configured session ID

View sessions in Langfuse → **Sessions** tab.

---

## Token Usage & Costs

Each generation observation shows:
- Input tokens (including cache)
- Output tokens
- Total cost (USD)

Aggregate costs visible in:
- Trace summary (total for conversation)
- Langfuse → **Analytics** → Cost dashboard

---

## Troubleshooting

### No Traces Appearing

```bash
# Check Alloy logs
journalctl -u grafana-alloy -f

# Verify endpoint is reachable
curl -v https://cloud.langfuse.com/api/public/otel

# Check auth header
echo -n "pk-lf-...:sk-lf-..." | base64
```

### Traces Missing Attributes

```bash
# Check interceptor logs
journalctl --user -u claude-code-interceptor -f

# Verify OTEL export
curl -s localhost:4318/v1/traces
```

### Token Counts Missing

Ensure API responses include usage data. Check:
```bash
# In interceptor logs, look for:
# "usage": {"input_tokens": ..., "output_tokens": ...}
```

---

## Advanced Configuration

### Custom Tags

Set environment variables before running AI CLIs:
```bash
export LANGFUSE_TAGS='["production", "my-feature"]'
```

### Custom Session ID

```bash
export LANGFUSE_SESSION_ID="my-custom-session"
```

### Debug Mode

```bash
export OTEL_LOG_LEVEL=debug
```

---

## Related Documentation

- [spec.md](./spec.md) - Full feature specification
- [research.md](./research.md) - Research and decisions
- [data-model.md](./data-model.md) - Data model details
- [contracts/langfuse-otel-mapping.md](./contracts/langfuse-otel-mapping.md) - Attribute mapping contract
- [Langfuse OTEL Docs](https://langfuse.com/integrations/native/opentelemetry)
