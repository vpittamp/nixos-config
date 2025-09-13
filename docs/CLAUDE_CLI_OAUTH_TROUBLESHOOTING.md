# Claude CLI OAuth Authentication Troubleshooting Guide

## Current Situation
- **Server**: Hetzner Cloud VPS running NixOS
- **Access Method**: Windows Remote Desktop (RDP) - full desktop environment with Firefox browser
- **Claude CLI Version**: 1.0.112 (latest, installed via npm at `~/.local/node_modules/.bin/claude`)
- **Problem**: OAuth authentication flow doesn't complete despite successful Google sign-in

## The OAuth Flow Problem

1. User runs `claude` or `claude auth` on Hetzner via RDP
2. Claude CLI starts OAuth server on `localhost:5173`
3. Firefox opens with Google OAuth page
4. User successfully signs into Google account
5. **FAILURE**: OAuth callback to `http://localhost:5173/callback` doesn't complete
6. Claude CLI never receives the authentication token

## What We've Tried

1. **Updated Claude CLI**: From 1.0.105 → 1.0.112 (fixed TTY/crash issues)
2. **Verified browser**: Firefox is default, DISPLAY=:0 is set correctly
3. **Tested functionality**: Claude CLI runs but requires authentication

## Potential Root Causes

1. **Firefox Security**: Browser may be blocking localhost redirects
2. **Port Issues**: Port 5173 might be blocked or already in use
3. **OAuth Implementation**: Claude CLI's OAuth handler might not work properly in RDP environments

## Recommended Troubleshooting Steps

### 1. Check Firefox Settings
- Disable Firefox's Enhanced Tracking Protection for localhost
- Check if Firefox is blocking the redirect
- Try with Chromium instead: `BROWSER=chromium claude auth`

### 2. Test Port Availability
```bash
lsof -i :5173  # Check if port is in use
nc -zv localhost 5173  # Test port connectivity
```

### 3. Alternative Authentication Methods
```bash
claude setup-token  # Try token-based auth instead of OAuth
```

### 4. Manual OAuth Completion
- When OAuth URL opens, check browser console for errors
- After Google sign-in, manually navigate to `http://localhost:5173/callback` if redirect fails
- Check if callback URL contains the auth code parameter

### 5. Debug Mode
```bash
CLAUDE_CODE_VERBOSE=true claude auth  # Run with verbose logging
```

## Alternative Solutions if OAuth Fails

### Option 1: SSH Port Forwarding (from local machine)
```bash
ssh -L 5173:localhost:5173 user@hetzner
# Then run claude auth on Hetzner
```

### Option 2: Use API Key (if available)
- Set up Claude with API key instead of OAuth
- Configure in ~/.claude/config.json

### Option 3: Install via Official Script
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## System Information

- NixOS configuration at `/etc/nixos/`
- Claude is configured via home-manager: `/etc/nixos/home-modules/ai-assistants/claude-code.nix`
- npm-installed version at: `~/.local/node_modules/.bin/claude`
- Config directory: `~/.claude/`

## Key Finding

The OAuth flow works up to Google authentication but fails at the callback stage. This suggests the issue is with the localhost redirect, not the authentication itself. Since RDP provides a full desktop environment, this should theoretically work, indicating a configuration or security setting is blocking the callback.

## Version History

- **NixOS package (1.0.105-1.0.107)**: Has TTY/crash issues in SSH/tmux environments
- **npm latest (1.0.112)**: Fixes TTY issues but OAuth callback still problematic on RDP
- **Installation method**: `npm install --prefix ~/.local @anthropic-ai/claude-code@latest`

## Next Steps

1. Test OAuth with different browsers
2. Check firewall rules for localhost connections
3. Monitor browser developer console during OAuth flow
4. Consider using alternative authentication methods (API key or token)