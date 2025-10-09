# AI Agents Permissions Summary

This document provides a quick reference for the permissions configuration of all AI coding agents in our NixOS environment.

## Overview

Both Claude Code and Codex are configured with **full permissions** for use in our sandboxed Hetzner development environment. This eliminates approval prompts while maintaining safety through environment isolation.

## Configuration Comparison

| Aspect | Claude Code | Codex |
|--------|-------------|-------|
| **Permission Mode** | Permission allowlist | YOLO mode (`danger-full-access`) |
| **Config File** | `~/.claude/settings.json` | `~/.codex/config.toml` |
| **NixOS Module** | `home-modules/ai-assistants/claude-code.nix` | `home-modules/ai-assistants/codex.nix` |
| **CLI Equivalent** | `--dangerously-skip-permissions` | `--yolo` |
| **Approval Policy** | Automatic via allowlist | `approval_policy = "never"` |
| **Sandbox** | No native sandbox | Disabled (`sandbox_mode`) |

## Claude Code Configuration

### Permission Method
Uses a comprehensive `permissions.allow` array with glob patterns:

```nix
permissions = {
  allow = [
    "Read(*)"
    "Write(*)"
    "Bash(*)"
    "mcp__playwright__browser_click(*)"
    # ... 100+ permissions
  ];
};
```

### Key Features
- ✅ Granular control per tool
- ✅ Wildcard patterns for broad access
- ✅ All MCP server tools allowed
- ✅ Version controlled allowlist
- ✅ Easy to audit and modify

### Coverage
- Core file operations (Read, Write, Edit, Glob, Grep)
- System operations (Bash, BashOutput, KillShell)
- Development tools (Task, TodoWrite, NotebookEdit)
- Web operations (WebFetch, WebSearch)
- MCP: Context7 (documentation lookup)
- MCP: Playwright (16 browser automation tools)
- MCP: Chrome DevTools (24 debugging tools)
- MCP: IDE integration (diagnostics, code execution)

### Documentation
See: `/etc/nixos/docs/CLAUDE_CODE_PERMISSIONS.md`

## Codex Configuration

### Permission Method
Uses `danger-full-access` sandbox mode + `never` approval policy:

```nix
sandbox_mode = "danger-full-access";  # Disable OS-level sandbox
approval_policy = "never";            # Auto-approve all commands
```

### Key Features
- ✅ Complete sandbox bypass
- ✅ Zero approval prompts
- ✅ Full network access
- ✅ Unrestricted file system
- ✅ Trusted project directories
- ✅ MCP server integration

### Coverage
- Unrestricted file read/write (entire file system)
- Unrestricted command execution
- Network access enabled
- MCP: Playwright (browser automation)
- MCP: Chrome DevTools (debugging)
- Trusted projects: `/etc/nixos`, `/home/vpittamp/*`

### Documentation
See: `/etc/nixos/docs/CODEX_PERMISSIONS.md`

## Security Model

### Environment Isolation
Both agents have full permissions because the environment provides isolation:

1. **Virtual Machine**: Hetzner Cloud VM (dedicated instance)
2. **Network Isolation**: Tailscale VPN, firewall rules
3. **User Isolation**: Dedicated user account
4. **Version Control**: All changes tracked via git
5. **Backups**: NixOS generations for easy rollback
6. **Monitoring**: SSH access, system logs

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| File deletion | Git version control + NixOS rollback |
| Malicious commands | VM isolation, no production data |
| Data exfiltration | Network monitoring, Tailscale audit |
| System corruption | Declarative config, instant rebuild |
| Package installation | Nix store isolation, generations |

## When to Use Each Agent

### Use Claude Code When:
- ✅ You want more explicit permission tracking
- ✅ You prefer granular tool-by-tool control
- ✅ You need detailed audit logs of allowed operations
- ✅ You want to easily add/remove specific permissions
- ✅ Working with complex multi-step tasks
- ✅ Need MCP server integration with fine-grained control

### Use Codex When:
- ✅ You want zero interruptions (true YOLO mode)
- ✅ You prefer simpler configuration
- ✅ You trust the AI completely in this environment
- ✅ Working on quick iterations and experiments
- ✅ Need fast command execution without prompts
- ✅ Want OS-level sandbox controls (when needed)

## Shared MCP Servers

Both agents have access to:

### Playwright
- Browser automation and testing
- Navigation, interaction, screenshots
- Network request monitoring
- Form filling and validation

### Chrome DevTools
- Performance analysis and profiling
- Network debugging
- CPU/network throttling
- Console inspection

## Configuration Updates

### After Adding New Tools

**Claude Code**: Add to allowlist in `claude-code.nix`:
```nix
permissions.allow = [
  # ... existing ...
  "mcp__new-tool__operation(*)"
];
```

**Codex**: Nothing needed - `danger-full-access` allows everything

### After Adding New MCP Server

Both agents: Add to `mcpServers` section in respective config files.

Claude Code also requires: Add permissions for each tool to allowlist.

## Quick Reference

### Check Current Permissions

```bash
# Claude Code
cat ~/.claude/settings.json | jq '.permissions.allow'

# Codex
cat ~/.codex/config.toml | grep -A 2 "sandbox_mode\|approval_policy"
```

### Test Without Permissions

```bash
# Claude Code - temporary restricted mode
claude-code  # Normal mode with prompts

# Codex - temporary safe mode
codex --sandbox workspace-write --ask-for-approval on-request
```

### View Generated Configs

```bash
# Claude Code
cat ~/.claude/settings.json

# Codex
cat ~/.codex/config.toml
```

## Reverting to Safe Mode

### Claude Code
Edit `claude-code.nix`, remove `permissions` block, rebuild.

### Codex
Edit `codex.nix`:
```nix
sandbox_mode = "workspace-write";  # or "read-only"
approval_policy = "on-request";    # or "untrusted"
```

## Best Practices

1. **Regular Commits**: Commit frequently to track AI-generated changes
2. **Review Changes**: Use `git diff` before committing
3. **Monitor Execution**: Keep an eye on terminal output
4. **Backup Data**: Keep important data backed up outside the VM
5. **Update Documentation**: Document why specific permissions were granted
6. **Audit Periodically**: Review what permissions are actually used
7. **Network Awareness**: Be mindful of network requests in AI-generated code

## Emergency Procedures

### If Something Goes Wrong

1. **Stop the agent**: `Ctrl+C` or `pkill claude-code` / `pkill codex`
2. **Review damage**: `git status` and `git diff`
3. **Rollback if needed**: `git restore .` or `sudo nixos-rebuild switch --rollback`
4. **Check system**: `sudo systemctl status` and `journalctl -xe`
5. **Restore from backup**: Use NixOS generation metadata to rebuild exact state

### If Permissions Too Broad

1. **Edit config**: Modify `claude-code.nix` or `codex.nix`
2. **Reduce scope**: Change to more restrictive mode
3. **Rebuild**: `sudo nixos-rebuild switch --flake .#hetzner`
4. **Verify**: Check generated config files

---

**Created**: 2025-01-09
**Environment**: Hetzner Cloud VM (sandboxed)
**Use Case**: Development workstation with full AI automation
**Safety**: Isolated environment, version control, rollback capability
