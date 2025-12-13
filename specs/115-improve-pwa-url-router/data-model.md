# Data Model: PWA URL Router

**Feature**: 115-improve-pwa-url-router
**Date**: 2025-12-13

## Entities

### 1. PWA Site Definition

**Source**: `shared/pwa-sites.nix`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Display name (e.g., "GitHub") |
| url | string | Yes | Primary URL of the PWA |
| domain | string | Yes | Primary domain (e.g., "github.com") |
| icon | string | Yes | Path to icon file |
| description | string | Yes | Human-readable description |
| categories | string | Yes | XDG categories |
| keywords | string | Yes | Search keywords |
| scope | string | Yes | PWA scope URL |
| ulid | string | Yes | 26-character ULID (cross-machine identifier) |
| app_scope | enum | Yes | "scoped" or "global" |
| preferred_workspace | integer | Yes | Workspace number (50+ for PWAs) |
| preferred_monitor_role | string | No | "primary", "secondary", or "tertiary" |
| routing_domains | list[string] | No | Domains that should open in this PWA (defaults to [domain]) |

**Validation Rules**:
- `ulid`: Must be exactly 26 characters, valid ULID alphabet [0-9A-HJKMNP-TV-Z]
- `preferred_workspace`: Must be >= 50 for PWAs
- `routing_domains`: If empty [], routing is disabled for this PWA

**Example**:
```nix
{
  name = "GitHub";
  url = "https://github.com";
  domain = "github.com";
  ulid = "01JCYF9A3P8T5W7XH0KMQRNZC6";
  routing_domains = [ "github.com" "www.github.com" ];
  # ... other fields
}
```

---

### 2. PWA Domain Registry

**Location**: `~/.config/i3/pwa-domains.json`
**Generated from**: pwa-sites.nix during home-manager activation

| Field | Type | Description |
|-------|------|-------------|
| (key) | string | Domain name (e.g., "github.com") |
| pwa | string | App registry name (e.g., "github-pwa") |
| ulid | string | PWA ULID for firefoxpwa |
| name | string | Display name (e.g., "GitHub") |

**Example**:
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
  }
}
```

**State Transitions**: Regenerated on each `nixos-rebuild switch` or `home-manager switch`.

---

### 3. Routing Lock File

**Location**: `~/.local/state/pwa-router-locks/<url-hash>`
**Purpose**: Prevent infinite routing loops

| Property | Type | Description |
|----------|------|-------------|
| Filename | string | MD5 hash of the URL |
| Content | empty | File existence matters, not content |
| mtime | timestamp | File modification time (for age check) |

**Lifecycle**:
1. **Created**: Before PWA launch (prevents race conditions)
2. **Checked**: On every pwa-url-router invocation
3. **Valid for**: 30 seconds (routing bypass if younger)
4. **Deleted**: Automatically after 2 minutes (cleanup)

**Example**:
```bash
# Lock file for https://github.com/user/repo
~/.local/state/pwa-router-locks/a1b2c3d4e5f6789012345678901234ab
# (no content - only mtime matters)
```

---

### 4. Authentication Bypass List

**Location**: Hardcoded in `pwa-url-router` script
**Purpose**: Domains/patterns that should always open in Firefox

**Current Structure** (to be improved):

| Type | Pattern | Description |
|------|---------|-------------|
| Domain | accounts.google.com | Google OAuth |
| Domain | accounts.youtube.com | YouTube OAuth (uses Google) |
| Domain | login.microsoftonline.com | Microsoft/Azure AD |
| Domain | login.live.com | Microsoft Live |
| Domain | auth0.com | Auth0 SSO |
| Domain | login.tailscale.com | Tailscale admin |
| Path | github.com/login | GitHub login page |
| Path | github.com/session | GitHub session |

**Proposed Enhanced Structure**:

```bash
# Domain-level providers (exact match or subdomain)
AUTH_DOMAINS=(
  "accounts.google.com"
  "accounts.youtube.com"
  "login.microsoftonline.com"
  "login.live.com"
  "auth0.com"
  "login.tailscale.com"
  "appleid.apple.com"
  "id.atlassian.com"
)

# Path patterns (checked against full URL)
AUTH_PATHS=(
  "github.com/login"
  "github.com/session"
  "github.com/oauth"
  "/oauth/authorize"
  "/oauth/callback"
)

# URL parameter patterns (OAuth in-flight detection)
OAUTH_PARAMS=(
  "oauth_token="
  "code=.*state="
)
```

---

### 5. Router Log Entry

**Location**: `~/.local/state/pwa-url-router.log`
**Purpose**: Debugging and diagnostics

| Field | Type | Description |
|-------|------|-------------|
| timestamp | ISO 8601 | When the routing decision was made |
| message | string | Log message describing the action |

**Log Event Types**:
- `Routing URL: <url>` - New URL received
- `Extracted domain: <domain>` - Domain parsed from URL
- `AUTH BYPASS: <domain>` - Bypassed due to auth domain
- `LOOP PREVENTION: <reason>` - Bypassed due to loop detection
- `Match found: <domain> → <pwa>` - PWA match found
- `Launching via launch-pwa-by-name: <ulid>` - PWA launch initiated
- `No PWA match for <domain>` - Fallback to Firefox
- `ERROR: <message>` - Error condition

**Rotation**: When file exceeds 1MB, renamed to `.log.old`

---

## Entity Relationships

```
┌─────────────────────┐
│   pwa-sites.nix     │
│  (Single Source)    │
└──────────┬──────────┘
           │
           │ Nix evaluation
           ▼
┌─────────────────────┐     ┌─────────────────────┐
│ pwa-domains.json    │     │ Desktop Entries     │
│ (Domain Registry)   │     │ (PWA Launchers)     │
└──────────┬──────────┘     └─────────────────────┘
           │
           │ Lookup
           ▼
┌─────────────────────┐
│  pwa-url-router     │◄────┬── Auth Bypass List
│  (Routing Script)   │     │   (hardcoded)
└──────────┬──────────┘     │
           │                │
           │ Create/Check   │
           ▼                │
┌─────────────────────┐     │
│ Lock Files          │     │
│ (Loop Prevention)   │     │
└─────────────────────┘     │
                            │
           ┌────────────────┘
           │
           ▼
┌─────────────────────┐
│ launch-pwa-by-name  │
│ (PWA Launcher)      │
└──────────┬──────────┘
           │
           │ firefoxpwa CLI
           ▼
┌─────────────────────┐
│ Firefox PWA Window  │
└─────────────────────┘
```

---

## Data Flow

### URL Routing Flow

```
1. External Trigger
   ├── tmux prefix+o (explicit)
   ├── walker history open (explicit)
   └── PWA external link (via extension)
              │
              ▼
2. pwa-url-router receives URL
              │
              ▼
3. Loop Prevention Checks
   ├── Layer 1: I3PM_PWA_URL env var set? → Firefox
   ├── Layer 2: Lock file exists & age < 30s? → Firefox
   └── Continue if not blocked
              │
              ▼
4. Auth Bypass Check
   ├── Domain in AUTH_DOMAINS? → Firefox
   ├── URL matches AUTH_PATHS? → Firefox
   └── URL has OAUTH_PARAMS? → Firefox
              │
              ▼
5. Domain Lookup
   ├── Extract domain from URL
   └── Query pwa-domains.json
              │
              ▼
6. Routing Decision
   ├── Match found → Create lock file, launch PWA
   └── No match → Open in Firefox
```

### Lock File Lifecycle

```
State: NONE
       │
       │ pwa-url-router receives URL
       ▼
State: CHECK
       │
       ├── File exists & age < 30s
       │   └── BYPASS to Firefox (loop prevention)
       │
       └── File missing or age >= 30s
           │
           ▼
    State: CREATE
           │ touch $LOCK_DIR/$URL_HASH
           ▼
    State: LAUNCH
           │ launch-pwa-by-name
           ▼
    State: ACTIVE
           │
           │ (30 seconds pass)
           ▼
    State: EXPIRED
           │
           │ (2 minutes pass, cleanup runs)
           ▼
    State: NONE (deleted)
```

---

## Validation Rules Summary

1. **ULID Validation**: 26 chars, alphabet [0-9A-HJKMNP-TV-Z], no duplicates across pwa-sites.nix
2. **Domain Registry**: Auto-generated, no manual edits
3. **Lock Files**: Ephemeral, auto-cleanup, hash-based naming
4. **Auth Bypass**: Hardcoded list, explicit patterns only (no wildcards)
5. **Logging**: Size-limited with rotation
