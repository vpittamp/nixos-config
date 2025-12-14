# Research: PWA URL Routing Fix

**Feature**: 118-fix-pwa-url-routing
**Date**: 2025-12-14

## Research Questions

1. How to configure `allowedDomains` in firefoxpwa?
2. Path-based URL matching strategies
3. What to remove from Feature 113 implementation

---

## 1. firefoxpwa `allowedDomains` Configuration

### Decision

Configure `allowedDomains` in each PWA site's config section within `config.json`, enabling PWAs to navigate to authentication domains without opening external browser.

### Rationale

- **Current Status**: `allowedDomains` was explicitly disabled (see `firefox-pwas-declarative.nix` lines 296-300) due to conflict with `openOutOfScopeInDefaultBrowser = true`
- **The Conflict**: Setting `allowedDomains` keeps URLs within the PWA, preventing them from being routed to the external browser - breaking the SSO-to-Firefox-and-back flow
- **New Approach**: Remove `openOutOfScopeInDefaultBrowser` reliance, let PWAs handle auth internally

### Configuration Syntax

**In `config.json` (site config section)**:
```json
{
  "sites": {
    "<ULID>": {
      "config": {
        "allowed_domains": ["accounts.google.com", "accounts.youtube.com"]
      }
    }
  }
}
```

**Alternative - In `user.js` (Firefox prefs)**:
```javascript
user_pref("firefoxpwa.allowedDomains", "accounts.google.com;accounts.youtube.com");
```

### Auth Domains by PWA Category

| PWA Category | Auth Domains |
|--------------|--------------|
| Google (Gmail, Calendar, AI, YouTube) | `accounts.google.com` |
| Microsoft (Outlook) | `login.microsoftonline.com`, `login.live.com` |
| GitHub | N/A (handles auth within scope) |
| Tailscale services | `login.tailscale.com` |
| 1Password | `my.1password.com` |
| Generic OAuth | `auth0.com` (if needed) |

### Alternatives Considered

1. **Keep external auth flow with pwa-url-router redirect**: Rejected - too complex, breaks session flow
2. **Use browser extension for auth interception**: Rejected - Feature 113 proved this is fragile

---

## 2. Path-Based URL Matching

### Decision

Extend domain registry to support path prefixes as keys, with longest-prefix-match resolution.

### Rationale

- **Problem**: Google AI (`google.com/ai`) shares domain with other Google services
- **Current**: `routing_domains = []` disabled for Google AI because `google.com` is too broad
- **Solution**: Add `routing_paths` field and modify registry generation

### Registry Format (Enhanced)

**Current format** (domain-only):
```json
{
  "github.com": { "pwa": "github-pwa", "ulid": "...", "name": "GitHub" }
}
```

**New format** (domain + path):
```json
{
  "github.com": { "pwa": "github-pwa", "ulid": "...", "name": "GitHub" },
  "google.com/ai": { "pwa": "google-ai-pwa", "ulid": "...", "name": "Google AI" },
  "mail.google.com": { "pwa": "gmail-pwa", "ulid": "...", "name": "Gmail" }
}
```

### Matching Algorithm

```bash
# 1. Extract domain from URL
DOMAIN=$(extract_domain "$URL")  # e.g., "google.com"
PATH=$(extract_path "$URL")       # e.g., "/ai/chat"

# 2. Try domain+path matches (longest prefix first)
# Sort registry keys by length (descending) and try each
for key in $(sort_by_length_desc "$REGISTRY_KEYS"); do
  if [[ "$DOMAIN/$PATH" == "$key"* ]] || [[ "$DOMAIN" == "$key" ]]; then
    return "$key"
  fi
done

# 3. Fallback to domain-only match
# 4. Fallback to Firefox
```

### Configuration in pwa-sites.nix

```nix
{
  name = "Google AI";
  domain = "google.com";
  routing_domains = [ ];  # Keep empty (domain too broad)
  routing_paths = [ "/ai" "/ai/" ];  # NEW: Path prefixes
}
```

### Alternatives Considered

1. **Subdomain-only matching**: Rejected - Google AI uses path, not subdomain
2. **Regex patterns**: Rejected - Over-complex, Nix string matching simpler
3. **Separate registry for paths**: Rejected - single registry simpler to query

---

## 3. Feature 113 Components to Remove

### Decision

Remove the following components entirely (per Constitution Principle XII: Forward-Only Development):

### Components to DELETE

| Component | Location | Reason for Removal |
|-----------|----------|-------------------|
| `googleRedirectInterceptorExtension` | `firefox-pwas-declarative.nix` lines 18-116 | Over-engineered, doesn't work reliably |
| `pwa-install-link-interceptor` script | `firefox-pwas-declarative.nix` lines 118-192 | No longer needed without extension |
| Lock file loop prevention | `pwa-url-router.nix` lines 89-106 | Over-complex, env var check sufficient |
| Auth bypass domain list | `pwa-url-router.nix` lines 122-133 | PWAs handle auth internally now |
| `openOutOfScopeInDefaultBrowser` workarounds | Various comments | Replaced by allowedDomains |

### Components to KEEP

| Component | Reason |
|-----------|--------|
| `pwa-url-router` (modified) | Core routing logic - add path matching |
| `pwa-route-test` | Diagnostic tool - update for paths |
| `tmux-url-open` | Terminal URL extraction - works well |
| Domain registry generation | Core feature - extend for paths |
| `I3PM_PWA_URL` env var check | Simple loop prevention |

### Code Size Impact

- **Before**: ~600 lines in `firefox-pwas-declarative.nix` for extension + installer
- **After**: ~0 lines (remove entirely)
- **Net**: ~600 lines removed, ~50 lines added for allowedDomains config

---

## 4. Implementation Strategy

### Phase 1: Schema Changes (pwa-sites.nix)

1. Add `auth_domains` field (list of auth provider domains)
2. Add `routing_paths` field (list of path prefixes)
3. Update Google AI entry with `routing_paths = [ "/ai" ]`

### Phase 2: Registry Generation (pwa-url-router.nix)

1. Modify `domainMapping` to include path entries
2. Update registry generation to output both domain and domain/path keys
3. Remove lock file logic
4. Remove auth bypass logic

### Phase 3: PWA Configuration (firefox-pwas-declarative.nix)

1. Delete extension and installer code (~200 lines)
2. Add allowedDomains to site config generation
3. Update profile generation to include auth domains

### Phase 4: Router Logic (pwa-url-router script)

1. Implement path-based matching (longest prefix wins)
2. Update `pwa-route-test` for path output
3. Keep I3PM_PWA_URL env var check

### Phase 5: Testing

1. Verify `pwa-route-test https://google.com/ai` → Google AI PWA
2. Verify auth flows complete in PWAs (GitHub, Google, Microsoft)
3. Verify tmux-url-open shows correct routing
4. Verify no infinite loops

---

## Summary

| Research Question | Decision | Confidence |
|-------------------|----------|------------|
| allowedDomains configuration | Enable in config.json per PWA | High |
| Path-based matching | Longest-prefix-match on domain+path keys | High |
| Legacy removal | Delete extension, installer, lock files, auth bypass | High |
| Loop prevention | Keep only I3PM_PWA_URL env var check | High |
