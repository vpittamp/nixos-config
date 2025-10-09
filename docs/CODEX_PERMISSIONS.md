# Codex Permissions Configuration

This document explains the comprehensive permissions configuration for Codex coding agent in our sandboxed environment.

## Overview

The configuration grants Codex full system access, equivalent to running with `--yolo` mode, by using `sandbox_mode = "danger-full-access"` and `approval_policy = "never"`.

## ⚠️ Security Warning

**This configuration grants Codex unrestricted access** including:
- Full file system read/write access (no sandbox)
- Arbitrary command execution without approval
- Network access enabled
- Browser automation via MCP servers

**Only use this configuration in:**
- Sandboxed environments (containers, VMs)
- Development workstations where you trust the AI
- Isolated test systems

**Do NOT use this configuration on:**
- Production systems
- Systems with sensitive data
- Shared servers
- Any environment where unrestricted access could cause harm

## Configuration Location

The permissions are configured in:
```
/etc/nixos/home-modules/ai-assistants/codex.nix
```

Applied via home-manager and written to `~/.codex/config.toml`.

## Permission Settings

### Sandbox Mode: `danger-full-access`

```toml
sandbox_mode = "danger-full-access"
```

This completely disables the OS-level sandbox, allowing Codex to:
- Read/write any file on the system
- Execute any command
- Access network resources
- No restrictions whatsoever

**Available sandbox modes:**
- `read-only`: (default) Can read files, requires approval for writes/commands
- `workspace-write`: Allow writes in current directory + temp folders
- `danger-full-access`: No sandbox (YOLO mode)

### Approval Policy: `never`

```toml
approval_policy = "never"
```

Never prompts for permission before executing commands.

**Available approval policies:**
- `untrusted`: Prompt before running untrusted commands
- `on-failure`: Ask only if command fails
- `on-request`: Model decides when to escalate
- `never`: No prompts (auto-approve everything)

### Workspace Write Settings (Fallback)

If you change `sandbox_mode` from `danger-full-access`, these settings control the sandbox:

```toml
[sandbox_workspace_write]
exclude_tmpdir_env_var = false  # Allow $TMPDIR access
exclude_slash_tmp = false       # Allow /tmp access
network_access = true           # Enable network
writable_roots = [              # Additional writable paths
  "/home/vpittamp"
  "/tmp"
  "/etc/nixos"
]
```

### Trusted Projects

Projects marked as trusted reduce prompts in version-controlled workspaces:

```toml
[projects."/etc/nixos"]
trust_level = "trusted"

[projects."/home/vpittamp"]
trust_level = "trusted"
```

All your development directories are pre-configured as trusted.

## MCP Server Integration

Codex is configured with MCP servers for browser automation:

### Playwright
- Full browser automation (navigation, interaction, screenshots)
- Uses system Chromium package
- Isolated mode for security

### Chrome DevTools
- Browser debugging and performance analysis
- Network/CPU throttling
- Performance tracing
- Headless mode

**Note:** MCP servers run with full permissions since `approval_policy = "never"`.

## Configuration Equivalents

This configuration is equivalent to running:

```bash
# CLI equivalent
codex --yolo

# Or with individual flags
codex --sandbox danger-full-access --ask-for-approval never
```

## How to Modify Permissions

### Reduce to Workspace-Only Access

```nix
sandbox_mode = "workspace-write";  # Changed from danger-full-access
approval_policy = "on-request";    # Changed from never
```

This limits writes to the current working directory and restores approval prompts.

### Enable Read-Only Mode (Safest)

```nix
sandbox_mode = "read-only";        # Most restrictive
approval_policy = "untrusted";     # Prompt for untrusted commands
```

### Custom Writable Paths

Keep sandbox but allow specific paths:

```nix
sandbox_mode = "workspace-write";
sandbox_workspace_write = {
  network_access = false;          # Disable network
  writable_roots = [
    "/home/vpittamp/projects"      # Only this path writable
  ];
};
```

## Testing the Configuration

After rebuilding:

```bash
# Rebuild configuration
sudo nixos-rebuild switch --flake .#hetzner

# Check generated config
cat ~/.codex/config.toml

# Test Codex
codex
```

## Reverting to Safe Defaults

Remove or comment out the dangerous settings:

```nix
settings = {
  # sandbox_mode = "danger-full-access";  # Commented out
  # approval_policy = "never";             # Commented out

  # Codex will use safe defaults:
  # - sandbox_mode: read-only
  # - approval_policy: untrusted
};
```

## Comparison with Claude Code

| Feature | Codex (`--yolo`) | Claude Code (`--dangerously-skip-permissions`) |
|---------|------------------|----------------------------------------------|
| **Sandbox** | Disabled via `sandbox_mode` | Not sandboxed, uses permission lists |
| **Approvals** | `approval_policy = "never"` | `permissions.allow = [...]` allowlist |
| **Configuration** | TOML (`~/.codex/config.toml`) | JSON (`~/.claude/settings.json`) |
| **MCP Servers** | Integrated in config | Separate `mcpServers` section |
| **Network** | Controlled via `network_access` | No specific network controls |
| **File Access** | Controlled via `sandbox_mode` | Controlled via `Read(*)/Write(*)` patterns |

## Best Practices

1. **Use in sandboxed environments only**: VMs, containers, isolated dev machines
2. **Review generated commands**: Even with auto-approval, monitor what Codex executes
3. **Version control everything**: Use git to track and revert changes
4. **Limit network access**: Disable `network_access` if not needed
5. **Start restrictive, expand as needed**: Begin with `workspace-write`, upgrade to `danger-full-access` only if necessary
6. **Document why**: Note in comments why specific permissions were granted

## Troubleshooting

### Still Getting Permission Prompts

Check the generated config:
```bash
cat ~/.codex/config.toml | grep -A 2 sandbox_mode
```

Ensure it shows:
```toml
sandbox_mode = "danger-full-access"
approval_policy = "never"
```

### MCP Servers Not Working

Verify Chromium is available:
```bash
which chromium
chromium --version
```

Check MCP server startup:
```bash
npx -y @playwright/mcp@latest --version
npx -y chrome-devtools-mcp@latest --version
```

### Network Access Blocked

If using `workspace-write` instead of `danger-full-access`, ensure:
```toml
[sandbox_workspace_write]
network_access = true
```

### Permission Denied Errors

Check that paths in `writable_roots` exist and are accessible:
```bash
ls -ld /home/vpittamp /tmp /etc/nixos
```

## Security Considerations

### What Can Go Wrong?

With `danger-full-access` and `approval_policy = "never"`, Codex can:

❌ Delete system files
❌ Modify critical configs
❌ Execute malicious commands
❌ Exfiltrate data over network
❌ Install packages
❌ Change permissions

### Mitigation Strategies

1. **Use in isolated environment**: Run on Hetzner VM, not production
2. **Backup regularly**: Keep git commits frequent
3. **Monitor activity**: Review commands in terminal history
4. **Limit scope**: Work in specific project directories
5. **Network isolation**: Consider disabling `network_access` for sensitive work

---

**Created**: 2025-01-09
**Last Updated**: 2025-01-09
**Configuration Version**: NixOS 25.11
**Codex Version**: Latest (via nixpkgs-unstable)
