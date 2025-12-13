# Quickstart: PWA URL Router

**Feature**: 115-improve-pwa-url-router
**Status**: Complete

## Overview

The PWA URL Router intercepts URLs from external sources (tmux, walker, PWA external links) and routes them to the appropriate PWA instead of opening in vanilla Firefox.

**Key Features** (Feature 115):
- 3-layer auth bypass (domain, path, OAuth params) - OAuth/SSO flows work correctly
- 4-layer loop prevention - no more infinite routing loops
- Enhanced diagnostic tool with full routing decision details
- Verbose mode for debugging

## Quick Usage

### Open URL from tmux

```bash
# In tmux, press prefix+o (usually `+o)
# Select URL from fzf popup
# Preview pane shows PWA routing decision
# URL opens in matching PWA or Firefox
```

### Test routing decision

```bash
# Test without opening anything - shows complete routing decision
pwa-route-test https://github.com/user/repo

# Example output:
# URL: https://github.com/user/repo
# Domain: github.com
#
# === Loop Prevention ===
# ✓ I3PM_PWA_URL not set
# ✓ No recent lock file
#
# === Auth Bypass Check ===
# ✓ Not an auth domain/path
#
# === PWA Lookup ===
# ✓ Match found in domain registry
#   PWA: github-pwa
#   Display name: GitHub
#   ULID: 01JCYF9A3P8T5W7XH0KMQRNZC6
#
# === Final Decision ===
# ✓ Would route to: github-pwa (GitHub)

# Test auth bypass detection
pwa-route-test https://accounts.google.com/signin
# Output shows: ⚠ AUTH BYPASS: Would open in Firefox
```

### Manually route a URL

```bash
# Route URL through PWA router
pwa-url-router https://github.com/user/repo

# With verbose output (prints decisions to stderr)
pwa-url-router --verbose https://github.com/user/repo
```

## Configuration

### Add a new PWA with routing

Edit `shared/pwa-sites.nix`:

```nix
{
  name = "MyApp";
  url = "https://myapp.com";
  domain = "myapp.com";
  ulid = "01XXXXXXXXXXXXXXXXXXXXXXXXXX";  # Generate with: ulidgen
  # Enable routing for these domains:
  routing_domains = [ "myapp.com" "www.myapp.com" "app.myapp.com" ];
  # ... other fields
}
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#ryzen  # or thinkpad, hetzner-sway, m1
```

### Disable routing for a PWA

Set `routing_domains = []` in pwa-sites.nix:

```nix
{
  name = "LocalService";
  # ...
  routing_domains = [];  # Disabled - won't intercept URLs
}
```

## Troubleshooting

### Check log file

```bash
# View recent routing decisions
tail -50 ~/.local/state/pwa-url-router.log

# Follow logs in real-time
tail -f ~/.local/state/pwa-url-router.log
```

### Check domain registry

```bash
# View all configured PWA domains
cat ~/.config/i3/pwa-domains.json | jq .

# Check specific domain
jq '.["github.com"]' ~/.config/i3/pwa-domains.json
```

### Clear lock files (if stuck)

```bash
# Remove all lock files
rm -rf ~/.local/state/pwa-router-locks/*
```

### Verify PWA is installed

```bash
# List installed PWAs
pwa-list

# Or directly via firefoxpwa
firefoxpwa profile list
```

### Force Firefox (bypass routing)

```bash
# If you want to open in Firefox despite routing match
firefox https://github.com/user/repo
```

## Architecture

```
┌─────────────────┐
│  tmux prefix+o  │     ┌──────────────┐
│  walker history │────▶│ pwa-url-router│
│  PWA ext link   │     └──────┬───────┘
└─────────────────┘            │
                               ▼
                    ┌─────────────────────┐
                    │ Loop Prevention     │
                    │ (4-layer defense)   │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Auth Bypass Check   │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Domain Lookup       │
                    │ (pwa-domains.json)  │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              ▼                                 ▼
      ┌───────────────┐                ┌───────────────┐
      │ Match: Launch │                │ No Match:     │
      │ PWA via ULID  │                │ Open Firefox  │
      └───────────────┘                └───────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `shared/pwa-sites.nix` | PWA definitions (routing_domains) |
| `home-modules/tools/pwa-url-router.nix` | Router script and config |
| `home-modules/tools/pwa-launcher.nix` | PWA launch command |
| `~/.config/i3/pwa-domains.json` | Generated domain registry |
| `~/.local/state/pwa-router-locks/` | Loop prevention lock files |
| `~/.local/state/pwa-url-router.log` | Routing decision log |

## Important Notes

1. **pwa-url-router is NOT the default URL handler** - It's called explicitly from tmux-url-open to prevent session restore loops.

2. **Authentication domains bypass routing** - OAuth/SSO flows always open in Firefox to prevent login loops.

3. **Lock files prevent infinite loops** - Same URL can't be routed twice within 30 seconds.

4. **Cross-machine consistency** - ULIDs ensure PWAs work identically on ryzen, thinkpad, hetzner-sway, and m1.
