# Quickstart: PWA URL Routing Fix

**Feature**: 118-fix-pwa-url-routing
**Date**: 2025-12-14

## Overview

This feature fixes PWA URL routing by:
1. Adding path-based URL matching (e.g., `google.com/ai` → Google AI PWA)
2. Configuring PWAs to handle auth internally via `allowedDomains`
3. Removing over-engineered components (link interceptor extension, lock files)

## Quick Test Commands

```bash
# Test URL routing (without opening)
pwa-route-test https://google.com/ai
pwa-route-test https://github.com/user/repo
pwa-route-test https://mail.google.com

# Check domain registry
cat ~/.config/i3/pwa-domains.json | jq 'keys'

# View router logs
tail -f ~/.local/state/pwa-url-router.log

# Open URL via router
pwa-url-router https://github.com/user/repo
```

## Files Modified

| File | Changes |
|------|---------|
| `shared/pwa-sites.nix` | Add `routing_paths`, `auth_domains` fields |
| `home-modules/tools/pwa-url-router.nix` | Add path matching, remove lock files |
| `home-modules/tools/firefox-pwas-declarative.nix` | Add `allowedDomains`, remove extension |

## Key Changes from Feature 113

### Removed
- `googleRedirectInterceptorExtension` - Browser extension for link interception
- `pwa-install-link-interceptor` - Extension installer script
- Lock file loop prevention - Was overly complex
- Auth bypass domain list - PWAs handle auth internally now

### Added
- `routing_paths` field - Path prefixes for same-domain differentiation
- `auth_domains` field - Auth providers that PWA can navigate to
- `allowedDomains` config - In firefoxpwa config.json per PWA
- Path-based matching - Longest prefix wins

## Usage Patterns

### 1. Terminal URL Opening (tmux-url-open)

```bash
# In tmux, press prefix + o
# URLs extracted from scrollback
# Select with fzf (preview shows routing)
# Opens in matching PWA or Firefox
```

### 2. Direct URL Routing

```bash
# Explicit routing (from terminal)
pwa-url-router "https://github.com/user/repo"

# Test without opening
pwa-route-test "https://google.com/ai/chat"
```

### 3. PWA Authentication

PWAs now handle authentication internally. When navigating to auth domains (e.g., `accounts.google.com`), the auth flow completes within the PWA - no external browser hop.

## Configuration Examples

### Adding Path-Based PWA

```nix
# In shared/pwa-sites.nix
{
  name = "Google AI";
  url = "https://google.com/ai";
  domain = "google.com";
  routing_domains = [ ];  # Empty - domain too broad
  routing_paths = [ "/ai" ];  # NEW: Match google.com/ai/*
  auth_domains = [ "accounts.google.com" ];  # NEW: Internal auth
  # ... other fields
}
```

### Adding Auth Domain

```nix
{
  name = "Microsoft Outlook";
  # ...
  auth_domains = [
    "login.microsoftonline.com"
    "login.live.com"
  ];
}
```

## Troubleshooting

### URL Not Routing to PWA

1. Check registry has the domain/path:
   ```bash
   cat ~/.config/i3/pwa-domains.json | jq '."google.com/ai"'
   ```

2. Check `pwa-route-test` output:
   ```bash
   pwa-route-test "https://google.com/ai"
   ```

3. Rebuild config:
   ```bash
   sudo nixos-rebuild switch --flake .#hetzner-sway
   ```

### Auth Opening in Firefox Instead of PWA

1. Check `auth_domains` is set in `pwa-sites.nix`
2. Verify firefoxpwa config has `allowed_domains`:
   ```bash
   cat ~/.local/share/firefoxpwa/config.json | jq '.sites | to_entries[0].value.config.allowed_domains'
   ```

### Infinite Loop

If seeing "LOOP PREVENTION" in logs:
```bash
tail ~/.local/state/pwa-url-router.log
```

The `I3PM_PWA_URL` environment variable prevents re-routing. This should only trigger if:
- Already inside a PWA launch context
- Something is calling the router recursively

## Rebuild Commands

```bash
# Dry build (test first!)
sudo nixos-rebuild dry-build --flake .#hetzner-sway

# Apply changes
sudo nixos-rebuild switch --flake .#hetzner-sway

# Regenerate PWA registry only (if needed)
# Registry auto-generates on home-manager activation
```

## Testing Checklist

- [ ] `pwa-route-test https://google.com/ai` shows Google AI PWA
- [ ] `pwa-route-test https://github.com/user/repo` shows GitHub PWA
- [ ] `pwa-route-test https://google.com/search` shows Firefox (no match)
- [ ] Opening GitHub PWA to private repo → auth works within PWA
- [ ] Opening Google PWA → Google auth works within PWA
- [ ] `tmux-url-open` shows correct routing preview
- [ ] No lock files in `~/.local/state/pwa-router-locks/`
