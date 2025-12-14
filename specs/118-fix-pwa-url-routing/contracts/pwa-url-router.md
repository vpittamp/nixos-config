# Contract: PWA URL Router CLI

**Feature**: 118-fix-pwa-url-routing
**Date**: 2025-12-14

## Overview

Shell scripts for URL routing to PWAs. No REST API - these are command-line tools.

---

## pwa-url-router

Routes HTTP/HTTPS URLs to appropriate PWAs or Firefox.

### Usage

```bash
pwa-url-router <url>
```

### Input

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `url` | string | Yes | HTTP or HTTPS URL to route |

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `I3PM_PWA_URL` | If set, bypass routing and open in Firefox (loop prevention) |

### Output

**Side Effects** (no stdout):
- Opens URL in matching PWA via `launch-pwa-by-name`
- OR opens URL in Firefox if no match
- Logs to `~/.local/state/pwa-url-router.log`

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - URL opened |
| (exec) | Does not return - exec's Firefox or launch-pwa-by-name |

### Algorithm

```
1. If I3PM_PWA_URL is set → exec Firefox (loop prevention)
2. If URL is empty → exec Firefox (new window)
3. Extract domain and path from URL
4. Load registry from ~/.config/i3/pwa-domains.json
5. Try matches in order (longest first):
   a. domain/path1/path2/...
   b. domain/path1
   c. domain
6. If match found → set I3PM_PWA_URL, exec launch-pwa-by-name with ULID
7. If no match → exec Firefox
```

---

## pwa-route-test

Tests URL routing without opening anything.

### Usage

```bash
pwa-route-test <url>
```

### Input

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `url` | string | Yes | URL to test |

### Output (stdout)

```
URL: https://google.com/ai/chat
Domain: google.com
Path: /ai/chat

✓ Would route to: google-ai-pwa
  Display name: Google AI
  ULID: 01K665SPD8EPMP3JTW02JM1M0Z
  Match: google.com/ai (path match)
```

OR

```
URL: https://random-site.com/page
Domain: random-site.com
Path: /page

✗ No PWA match - would open in Firefox
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Test completed (regardless of match) |
| 1 | Missing argument or registry not found |

---

## Domain Registry Schema

**File**: `~/.config/i3/pwa-domains.json`

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "additionalProperties": {
    "type": "object",
    "required": ["pwa", "ulid", "name"],
    "properties": {
      "pwa": {
        "type": "string",
        "description": "App name for launch (e.g., github-pwa)"
      },
      "ulid": {
        "type": "string",
        "pattern": "^[0-9A-HJKMNP-TV-Z]{26}$",
        "description": "26-character ULID"
      },
      "name": {
        "type": "string",
        "description": "Display name"
      }
    }
  }
}
```

### Example

```json
{
  "github.com": {
    "pwa": "github-pwa",
    "ulid": "01JCYF9A3P8T5W7XH0KMQRNZC6",
    "name": "GitHub"
  },
  "google.com/ai": {
    "pwa": "google-ai-pwa",
    "ulid": "01K665SPD8EPMP3JTW02JM1M0Z",
    "name": "Google AI"
  }
}
```

### Key Format

- Domain-only: `github.com`, `mail.google.com`
- Domain + path: `google.com/ai`, `linkedin.com/learning`
- No protocol prefix
- No trailing slash on paths

---

## launch-pwa-by-name

Launches a PWA by name or ULID.

### Usage

```bash
launch-pwa-by-name <name-or-ulid> [url]

# Environment variable alternative for URL
I3PM_PWA_URL=<url> launch-pwa-by-name <name-or-ulid>
```

### Input

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name-or-ulid` | string | Yes | PWA display name or 26-char ULID |
| `url` | string | No | URL for deep linking |

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `I3PM_PWA_URL` | URL to open in PWA (takes precedence over argument) |

### Output

**Side Effects**:
- Launches PWA via `firefoxpwa site launch <ulid> [--url <url>]`
- Enables 1Password extension if available

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | PWA not found |
| (exec) | Does not return - exec's firefoxpwa |

---

## Integration Points

### tmux-url-open

Calls `pwa-url-router` for selected URLs:

```bash
# Extract URLs from scrollback
URLS=$(capture_scrollback | grep -oE 'https?://[^ ]+')

# Show in fzf with preview
echo "$URLS" | fzf --preview 'pwa-route-test {}'

# Open selected
pwa-url-router "$SELECTED_URL"
```

### Sway/i3 Keybindings

Not used directly - URLs route through `xdg-open` which uses Firefox (default), then user explicitly calls `pwa-url-router` via `tmux-url-open`.
