# Data Model: PWA URL Routing

**Feature**: 118-fix-pwa-url-routing
**Date**: 2025-12-14

## Entities

### 1. PWA Site Configuration (pwa-sites.nix)

The canonical definition of a PWA site with all metadata.

**Location**: `shared/pwa-sites.nix`

```nix
{
  # Core identity
  name = "Google AI";           # Display name
  ulid = "01K665SPD8EPMP3JTW02JM1M0Z";  # Unique identifier (26-char ULID)

  # URLs
  url = "https://google.com/ai";   # Start URL
  domain = "google.com";           # Primary domain
  scope = "https://google.com/";   # PWA scope

  # Metadata
  icon = "/path/to/icon.svg";
  description = "Google AI Mode";
  categories = "Network;Development;";
  keywords = "ai;gemini;google;";

  # App Registry (i3pm integration)
  app_scope = "scoped";            # "scoped" or "global"
  preferred_workspace = 51;        # Workspace number (50+ for PWAs)
  preferred_monitor_role = "secondary";  # Optional: "primary", "secondary", "tertiary"

  # URL Routing (Feature 113/118)
  routing_domains = [ ];           # Domains that route to this PWA
  routing_paths = [ "/ai" ];       # NEW: Path prefixes that route to this PWA

  # Authentication (NEW Feature 118)
  auth_domains = [ "accounts.google.com" ];  # Domains PWA can navigate to for auth
}
```

**Field Descriptions**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Human-readable display name |
| `ulid` | string | Yes | 26-character ULID identifier |
| `url` | string | Yes | PWA start URL |
| `domain` | string | Yes | Primary domain (for fallback routing) |
| `scope` | string | Yes | PWA scope URL (with trailing slash) |
| `icon` | string | Yes | Path to icon file |
| `description` | string | Yes | PWA description |
| `categories` | string | Yes | Desktop entry categories |
| `keywords` | string | Yes | Search keywords |
| `app_scope` | string | Yes | "scoped" or "global" for i3pm |
| `preferred_workspace` | int | Yes | Target workspace number |
| `preferred_monitor_role` | string | No | Monitor preference |
| `routing_domains` | list | Yes | Domains for URL routing (can be empty) |
| `routing_paths` | list | No | **NEW** - Path prefixes for URL routing |
| `auth_domains` | list | No | **NEW** - Auth provider domains |

### 2. Domain/Path Registry (JSON)

Generated at build time from `pwa-sites.nix`.

**Location**: `~/.config/i3/pwa-domains.json`

```json
{
  "github.com": {
    "pwa": "github-pwa",
    "ulid": "01JCYF9A3P8T5W7XH0KMQRNZC6",
    "name": "GitHub"
  },
  "www.github.com": {
    "pwa": "github-pwa",
    "ulid": "01JCYF9A3P8T5W7XH0KMQRNZC6",
    "name": "GitHub"
  },
  "google.com/ai": {
    "pwa": "google-ai-pwa",
    "ulid": "01K665SPD8EPMP3JTW02JM1M0Z",
    "name": "Google AI"
  },
  "mail.google.com": {
    "pwa": "gmail-pwa",
    "ulid": "01JCYF9K4Q9V6X8YJ1MNSPT0D7",
    "name": "Gmail"
  }
}
```

**Key Format**:
- Domain-only: `github.com`
- Domain + path: `google.com/ai` (no protocol, no trailing slash)

**Value Schema**:

| Field | Type | Description |
|-------|------|-------------|
| `pwa` | string | App name for launch (e.g., `github-pwa`) |
| `ulid` | string | PWA ULID for firefoxpwa launch |
| `name` | string | Display name for UI/logging |

### 3. firefoxpwa config.json

Generated configuration for firefoxpwa.

**Location**: `~/.local/share/firefoxpwa/config.json`

**Site Config (partial)**:
```json
{
  "sites": {
    "01K665SPD8EPMP3JTW02JM1M0Z": {
      "ulid": "01K665SPD8EPMP3JTW02JM1M0Z",
      "profile": "01K665SPD8EPMP3JTW02JM1M0Z",
      "config": {
        "name": "Google AI",
        "start_url": "https://google.com/ai/",
        "allowed_domains": ["accounts.google.com"]
      }
    }
  }
}
```

**New Field**: `allowed_domains` - list of domains PWA can navigate to without opening external browser.

### 4. Routing Decision (Runtime)

Internal representation during URL routing.

```bash
# Input
URL="https://google.com/ai/chat?q=hello"

# Parsed
DOMAIN="google.com"
PATH="/ai/chat"
QUERY="?q=hello"

# Match result
MATCH_KEY="google.com/ai"  # Longest prefix match
PWA_ULID="01K665SPD8EPMP3JTW02JM1M0Z"
PWA_NAME="Google AI"

# Output
ACTION="launch_pwa"  # or "open_firefox"
```

## Entity Relationships

```
┌─────────────────────────────────────┐
│         pwa-sites.nix               │
│  (Source of Truth - Nix)            │
├─────────────────────────────────────┤
│ • name, ulid, url, domain           │
│ • routing_domains, routing_paths    │
│ • auth_domains (NEW)                │
└───────────────┬─────────────────────┘
                │
    ┌───────────┴───────────┐
    │                       │
    ▼                       ▼
┌───────────────────┐  ┌───────────────────────┐
│ pwa-domains.json  │  │ firefoxpwa config.json │
│ (URL Router)      │  │ (PWA Runtime)          │
├───────────────────┤  ├───────────────────────┤
│ domain/path → PWA │  │ allowed_domains        │
│ for routing       │  │ for auth flow          │
└───────────────────┘  └───────────────────────┘
```

## Validation Rules

### ULID Validation

```nix
# 26 characters from alphabet [0-9A-HJKMNP-TV-Z]
# Excludes I, L, O, U to avoid ambiguity
validateULID = ulid:
  let
    len = builtins.stringLength ulid;
    isValidChars = builtins.match "[0-9A-HJKMNP-TV-Z]*" ulid != null;
  in
  len == 26 && isValidChars;
```

### No Duplicate ULIDs

```nix
checkDuplicateULIDs = pwas:
  let
    ulids = builtins.map (pwa: pwa.ulid) pwas;
    uniqueULIDs = lib.lists.unique ulids;
  in
  builtins.length ulids == builtins.length uniqueULIDs;
```

### Path Normalization

- Paths in `routing_paths` should NOT have trailing slash
- Paths should start with `/`
- Example: `[ "/ai" ]` not `[ "/ai/" ]` or `[ "ai" ]`

### Auth Domain Format

- Auth domains should be bare hostnames (no protocol, no path)
- Example: `[ "accounts.google.com" ]` not `[ "https://accounts.google.com" ]`

## State Transitions

### URL Routing Flow

```
[Receive URL]
    │
    ▼
[Extract domain + path]
    │
    ▼
[Check I3PM_PWA_URL env var] ──► [Already routing] ──► [Open Firefox]
    │
    ▼ (not set)
[Query registry: domain/path matches]
    │
    ├─► [Match found] ──► [Set I3PM_PWA_URL] ──► [Launch PWA with URL]
    │
    └─► [No match] ──► [Open Firefox]
```

### PWA Auth Flow (New)

```
[User in PWA]
    │
    ▼
[Navigate to auth URL (e.g., accounts.google.com)]
    │
    ▼
[Check allowed_domains in PWA config]
    │
    ├─► [Domain allowed] ──► [Auth happens in PWA] ──► [Return to PWA]
    │
    └─► [Domain not allowed] ──► [Open in Firefox] ──► [Auth in Firefox]
```

## Migration Notes

### From Feature 113 to 118

| Entity | Change |
|--------|--------|
| `pwa-sites.nix` | Add `routing_paths`, `auth_domains` fields |
| `pwa-domains.json` | Add path-based keys (e.g., `google.com/ai`) |
| `config.json` | Add `allowed_domains` to site config |
| Router script | Add path matching, remove lock files |

### Backwards Compatibility

**None required** per Constitution Principle XII. Old entries without new fields will use defaults:
- `routing_paths = []` (no path routing)
- `auth_domains = []` (no internal auth)
