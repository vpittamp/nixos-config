# Claude Code Permissions Configuration

This document explains the comprehensive permissions configuration for Claude Code in our sandboxed environment.

## Overview

The configuration grants broad permissions to Claude Code, equivalent to running with `--dangerously-skip-permissions` but with more granular control through the `permissions.allow` list in the settings.

## ⚠️ Security Warning

**This configuration grants Claude Code extensive permissions** including:
- Full file system read/write access
- Arbitrary bash command execution
- Browser automation and debugging
- Network requests

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
/etc/nixos/home-modules/ai-assistants/claude-code.nix
```

Applied via home-manager and built into your NixOS configuration.

## Granted Permissions

### Core Operations
- **Read(*)**: Read any file
- **Write(*)**: Create/overwrite any file
- **Edit(*)**: Modify existing files
- **Glob(*)**: Search for files by pattern
- **Grep(*)**: Search file contents
- **Bash(*)**: Execute any bash command

### Development Tools
- **NotebookEdit(*)**: Modify Jupyter notebooks
- **Task(*)**: Launch autonomous agents
- **TodoWrite(*)**: Manage task lists
- **SlashCommand(*)**: Execute custom commands

### Web Operations
- **WebFetch(*)**: Fetch web content
- **WebSearch(*)**: Perform web searches

### Background Operations
- **BashOutput(*)**: Monitor background processes
- **KillShell(*)**: Terminate background shells

### MCP Servers

#### Context7 (Documentation)
- `mcp__context7__resolve-library-id(*)`: Find library IDs
- `mcp__context7__get-library-docs(*)`: Fetch documentation

#### Playwright (Browser Automation)
Full browser automation capabilities:
- Navigation, clicking, typing, form filling
- Screenshot and snapshot capture
- Network request monitoring
- Dialog handling
- Tab management
- File uploads

#### Chrome DevTools (Browser Debugging)
Complete debugging and performance analysis:
- Console message inspection
- CPU/network throttling emulation
- Form interactions
- Network request analysis
- Page navigation and management
- Performance tracing and insights
- Script evaluation
- Screenshot capture

#### IDE Integration
- `mcp__ide__getDiagnostics(*)`: Get language diagnostics
- `mcp__ide__executeCode(*)`: Execute code in Jupyter kernels

## How It Works

The `permissions.allow` array uses glob patterns to match tool calls:
- `Read(*)` matches any Read tool call regardless of parameters
- `mcp__playwright__browser_click(*)` matches any Playwright click operation
- `Bash(*)` matches any bash command execution

This provides the same effect as `--dangerously-skip-permissions` but with:
1. **Declarative configuration**: Version controlled and reproducible
2. **Granular control**: Can remove specific permissions if needed
3. **Documentation**: Clear record of what's allowed
4. **Auditability**: Changes tracked in git history

## How to Modify Permissions

### Remove a Specific Permission

Edit `/etc/nixos/home-modules/ai-assistants/claude-code.nix` and comment out the permission:

```nix
allow = [
  "Read(*)"
  # "Write(*)"  # Disabled: prevent file writes
  "Edit(*)"
  # ...
];
```

### Add Path-Specific Restrictions

Replace wildcard with specific paths:

```nix
allow = [
  "Read(/home/*/src/**)"  # Only read from src directories
  "Write(/tmp/**)"        # Only write to /tmp
];
```

### Restrict MCP Server Access

Remove specific MCP tool permissions:

```nix
allow = [
  # Remove all Playwright permissions
  # "mcp__playwright__browser_navigate(*)"
  # "mcp__playwright__browser_click(*)"
  # ...

  # Keep Chrome DevTools
  "mcp__chrome-devtools__take_screenshot(*)"
];
```

## Testing the Configuration

After modifying permissions:

```bash
# Rebuild your configuration
sudo nixos-rebuild switch --flake .#hetzner

# Test Claude Code permissions
claude-code --version
```

## Reverting to Default Permissions

To restore normal permission prompts, remove the entire `permissions` block:

```nix
settings = {
  theme = "dark";
  editorMode = "vim";
  # ... other settings ...

  # Remove this entire block:
  # permissions = {
  #   allow = [ ... ];
  # };
};
```

## Alternative: Project-Specific Permissions

For project-level permissions, create `.claude/settings.local.json` in your project:

```json
{
  "permissions": {
    "allow": [
      "Read(*)",
      "Write(src/**)",
      "Bash(npm:*)",
      "Bash(git:*)"
    ]
  }
}
```

This overrides global settings for that specific project.

## Best Practices

1. **Use in sandboxed environments only**: VMs, containers, isolated dev machines
2. **Review periodically**: Audit what permissions are actually needed
3. **Restrict in production**: Never use broad permissions on production systems
4. **Document changes**: Note why specific permissions were granted/revoked
5. **Version control**: Keep configuration in git for auditability

## Troubleshooting

### Permissions still being requested

Check that the configuration was properly applied:
```bash
cat ~/.config/claude-code/settings.json | grep -A 5 permissions
```

### Too permissive for your use case

Start with minimal permissions and add as needed:
```nix
allow = [
  "Read(*)"    # Start with read-only
  "Grep(*)"    # Add search
  # Expand as needed
];
```

### MCP server permissions not working

Ensure the MCP server name matches exactly:
```bash
# List available MCP tools
claude-code --list-mcp-tools
```

---

**Created**: 2025-01-09
**Last Updated**: 2025-01-09
**Configuration Version**: NixOS 25.11
