# VSCode AI Assistant Configuration

This document explains the AI assistant and MCP server configuration for Visual Studio Code in our NixOS environment.

## Overview

VSCode is configured with multiple AI assistants and MCP servers for browser automation and debugging capabilities.

## Configuration Location

- **NixOS Module**: `/etc/nixos/home-modules/tools/vscode.nix`
- **Generated Settings**: `~/.config/Code/User/profiles/nixos/settings.json`
- **Generated MCP Config**: `~/.config/Code/User/profiles/nixos/mcp.json`
- **Claude Permissions**: `~/.claude/settings.json` (shared with CLI)

## AI Assistants

### 1. Claude Code Extension

**Extension**: `anthropic.claude-code`

**Settings**:
```json
{
  "claude-code.enableTelemetry": true,
  "claude-code.autoCompactEnabled": true,
  "claude-code.todoFeatureEnabled": true,
  "claude-code.includeCoAuthoredBy": true,
  "claude-code.messageIdleNotifThresholdMs": 60000
}
```

**Permissions**:
- ✅ Uses `~/.claude/settings.json` (configured in `claude-code.nix`)
- ✅ 65 permissions in allowlist (same as CLI)
- ⚠️ **Important**: VSCode extension does NOT support `--dangerously-skip-permissions` flag
- ✅ Permissions from `claude-code.nix` are respected

**How It Works**:
The VSCode extension reads permissions from the same `~/.claude/settings.json` file that the Claude Code CLI uses. The comprehensive permission allowlist we configured applies to both CLI and VSCode extension.

**Known Limitations**:
- Cannot pass `--dangerously-skip-permissions` flag to VSCode extension
- Extension runs Claude Code internally, not as a terminal process
- Some users report occasional permission prompts despite allowlist (GitHub issues #2933, #8539)

### 2. GitHub Copilot

**Extensions**:
- `github.copilot`
- `github.copilot-chat`

**Settings**:
```json
{
  "github.copilot.enable": {
    "*": true,
    "yaml": true,
    "plaintext": true,
    "markdown": true
  },
  "github.copilot.editor.enableAutoCompletions": true,
  "github.copilot.chat.followUps.enabled": true
}
```

**Features**:
- Auto-completions in all file types
- Chat interface for code generation
- Follow-up suggestions enabled

### 3. Gemini CLI

**Extension**: `Google.gemini-cli-vscode-ide-companion`

**Settings**:
```json
{
  "gemini.autoStart": true,
  "gemini.enableCodeActions": true
}
```

**Features**:
- Auto-starts with VSCode
- Code actions enabled
- IDE companion integration

### 4. OpenAI ChatGPT/Codex

**Extension**: `openai.chatgpt`

**Features**:
- ChatGPT and Codex integration
- Code generation and assistance
- Custom marketplace extension (version 0.5.15)

## MCP Servers

### Configuration Structure

MCP servers are configured in the `userMcp` section of the profile:

```nix
userMcp = {
  mcpServers = {
    playwright = { ... };
    chrome-devtools = { ... };
  };
};
```

This generates `~/.config/Code/User/profiles/nixos/mcp.json`:

```json
{
  "mcpServers": {
    "playwright": { ... },
    "chrome-devtools": { ... }
  }
}
```

### 1. Playwright MCP Server

**Purpose**: Browser automation and testing

**Configuration**:
```json
{
  "command": "npx",
  "args": [
    "-y",
    "@playwright/mcp@latest",
    "--isolated",
    "--browser",
    "chromium",
    "--executable-path",
    "/nix/store/.../bin/chromium"
  ],
  "env": {
    "PLAYWRIGHT_SKIP_CHROMIUM_DOWNLOAD": "true",
    "PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS": "true",
    "NODE_ENV": "production",
    "LOG_DIR": "/tmp/mcp-playwright-logs"
  }
}
```

**Capabilities**:
- Browser navigation and interaction
- Form filling and submission
- Screenshot capture
- Network request monitoring
- Element clicking and typing
- File uploads
- Tab management

**Usage**:
Claude Code, Copilot Chat, and other AI assistants can use Playwright to:
- Test web applications
- Automate browser workflows
- Capture screenshots for debugging
- Monitor network traffic

### 2. Chrome DevTools MCP Server

**Purpose**: Browser debugging and performance analysis

**Configuration**:
```json
{
  "command": "npx",
  "args": [
    "-y",
    "chrome-devtools-mcp@latest",
    "--isolated",
    "--headless",
    "--executablePath",
    "/nix/store/.../bin/chromium"
  ],
  "env": {
    "NODE_ENV": "production"
  }
}
```

**Capabilities**:
- Console message inspection
- Network request analysis
- Performance profiling
- CPU/Network throttling emulation
- Script evaluation
- Page snapshots
- Performance insights

**Usage**:
AI assistants can use Chrome DevTools to:
- Debug JavaScript errors
- Analyze performance bottlenecks
- Inspect network requests
- Emulate slow connections/devices
- Capture performance traces

## VSCode Profile System

### Current Configuration

**Profile**: `nixos` (primary and only profile)

All VSCode instances use this single unified profile with:
- Extensions: Full development stack
- Settings: Optimized for NixOS + Wayland
- Keybindings: Custom shortcuts
- MCP Servers: Playwright + Chrome DevTools

### Profile Location

```
~/.config/Code/User/profiles/nixos/
├── settings.json
├── keybindings.json
├── mcp.json
├── globalStorage/
└── workspaceStorage/
```

### Settings Sync

Settings Sync is configured to:
- ✅ Sync GitHub-centric extensions (Copilot, GitLens)
- ❌ Don't sync NixOS-specific tooling (Nix IDE, Tailscale)
- ❌ Don't sync 1Password account settings

```json
{
  "settingsSync.ignoredExtensions": [
    "ms-vscode-remote.remote-ssh",
    "tailscale.vscode-tailscale",
    "bbenoist.nix",
    "jnoortheen.nix-ide",
    // ... and others
  ],
  "settingsSync.ignoredSettings": [
    "1password.account",
    "1password.defaultVault",
    "1password.signInAddress"
  ]
}
```

## Permissions and Security

### Claude Code Permissions

Since the VSCode extension uses `~/.claude/settings.json`:

✅ **Automatically Allowed**:
- All file operations: `Read(*)`, `Write(*)`, `Edit(*)`
- All bash commands: `Bash(*)`
- All MCP tools: `mcp__playwright__*`, `mcp__chrome-devtools__*`
- See `/etc/nixos/docs/CLAUDE_CODE_PERMISSIONS.md` for full list

### MCP Server Access

Both Playwright and Chrome DevTools MCP servers:
- Run in isolated mode
- Use system Chromium package
- Log to `/tmp` for debugging
- Skip browser download (use Nix-managed binary)

### Security Model

1. **Sandboxed Environment**: Hetzner VM with network isolation
2. **Version Control**: All changes tracked via git
3. **Nix Store Paths**: Immutable binaries from Nix store
4. **Environment Variables**: Controlled via Nix configuration
5. **User Isolation**: Non-privileged user account

## Testing

### Verify Configuration

```bash
# Check VSCode settings exist
cat ~/.config/Code/User/profiles/nixos/settings.json | jq '.["claude-code"]'

# Check MCP configuration
cat ~/.config/Code/User/profiles/nixos/mcp.json | jq '.mcpServers'

# Check Claude permissions (shared with CLI)
cat ~/.claude/settings.json | jq '.permissions.allow | length'
```

### Test MCP Servers

1. Open VSCode
2. Open Claude Code chat
3. Ask Claude to:
   - "Use Playwright to navigate to example.com and take a screenshot"
   - "Use Chrome DevTools to analyze the performance of a webpage"

Expected: No permission prompts for MCP operations (if allowlist is working)

### Test AI Assistants

1. **Claude Code**: Should respect `~/.claude/settings.json` permissions
2. **Copilot**: Auto-completions should work in all file types
3. **Gemini**: Should auto-start and provide code actions

## Troubleshooting

### Claude Code Still Asking for Permissions

**Issue**: VSCode extension prompts for permissions despite allowlist

**Solutions**:
1. Verify `~/.claude/settings.json` exists with permissions
2. Restart VSCode to reload configuration
3. Check for extension updates (may fix permission bugs)
4. As a workaround, use Claude Code CLI instead: `claude-code`

**Known Issues**:
- GitHub #2933: Extension ignores global settings
- GitHub #8539: Extension doesn't support `--dangerously-skip-permissions`

### MCP Servers Not Available

**Issue**: AI assistants can't access Playwright or Chrome DevTools

**Solutions**:
1. Verify `mcp.json` exists: `cat ~/.config/Code/User/profiles/nixos/mcp.json`
2. Check if npx is available: `which npx`
3. Test MCP server manually:
   ```bash
   npx -y @playwright/mcp@latest --version
   npx -y chrome-devtools-mcp@latest --version
   ```
4. Check extension logs in VSCode Output panel

### Extensions Not Loading

**Issue**: Extensions configured in Nix aren't appearing in VSCode

**Solutions**:
1. Rebuild system: `sudo nixos-rebuild switch --flake .#hetzner`
2. Check extension list: `code --list-extensions`
3. Verify profile directory: `ls ~/.config/Code/User/profiles/nixos/`
4. Reinstall extensions if needed (mutable extensions enabled)

## Modifying Configuration

### Add New MCP Server

Edit `vscode.nix`:

```nix
baseMcpConfig = {
  mcpServers = {
    # ... existing servers ...

    my-new-server = {
      command = "${pkgs.nodejs}/bin/npx";
      args = [
        "-y"
        "my-mcp-server@latest"
      ];
      env = {
        NODE_ENV = "production";
      };
    };
  };
};
```

### Add New AI Assistant Settings

Edit `baseUserSettings`:

```nix
baseUserSettings = {
  # ... existing settings ...

  "my-ai-assistant.setting" = "value";
};
```

### Change Profile Configuration

Edit `nixosProfile`:

```nix
nixosProfile = {
  extensions = baseExtensions;
  userSettings = baseUserSettings // { /* overrides */ };
  keybindings = baseKeybindings;
  userMcp = baseMcpConfig;
};
```

## Best Practices

1. **Use CLI for Full Automation**: For truly uninterrupted workflows, use `claude-code` CLI with permissions
2. **Keep Extensions Updated**: VSCode extension updates may fix permission issues
3. **Monitor Logs**: Check VSCode Output panel for MCP server errors
4. **Test MCP Servers**: Verify MCP tools work before complex automations
5. **Sync Selectively**: Only sync GitHub-related extensions to avoid conflicts
6. **Document Changes**: Note why specific settings were added

## Related Documentation

- **Claude Permissions**: `/etc/nixos/docs/CLAUDE_CODE_PERMISSIONS.md`
- **Codex Configuration**: `/etc/nixos/docs/CODEX_PERMISSIONS.md`
- **AI Agents Summary**: `/etc/nixos/docs/AI_AGENTS_PERMISSIONS_SUMMARY.md`
- **1Password VSCode**: `/etc/nixos/docs/ONEPASSWORD.md`

---

**Created**: 2025-01-09
**Last Updated**: 2025-01-09
**VSCode Version**: Latest (from nixpkgs-unstable)
**Profile**: nixos (unified single profile)
