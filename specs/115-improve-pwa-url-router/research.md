# Research: Improve PWA URL Router

**Date**: 2025-12-13
**Feature**: 115-improve-pwa-url-router

## Current Implementation Analysis

### Architecture Overview

The PWA URL router consists of these components:

1. **pwa-url-router.nix** (`home-modules/tools/pwa-url-router.nix`)
   - Main router script that matches URLs to PWAs
   - Domain registry JSON generation from pwa-sites.nix
   - Desktop entry for potential URL handler registration (but NOT used as default)

2. **pwa-sites.nix** (`shared/pwa-sites.nix`)
   - Centralized PWA definitions with `routing_domains` arrays
   - Currently defines 31 PWAs with various routing configurations
   - Some PWAs have empty routing_domains (disabled routing)

3. **pwa-launcher.nix** (`home-modules/tools/pwa-launcher.nix`)
   - `launch-pwa-by-name` script that resolves PWA name → ULID
   - Handles deep linking via `I3PM_PWA_URL` environment variable
   - Uses `firefoxpwa site launch <ULID> --url <URL>` for deep links

4. **tmux-url-open** (`home-modules/terminal/ghostty.nix:156`)
   - Extracts URLs from tmux scrollback via regex
   - Uses fzf for selection
   - Explicitly calls `pwa-url-router` (not xdg-open)

5. **walker integration** (`home-modules/desktop/walker.nix:899-914`)
   - Browser history opener routes through pwa-url-router

### Current Loop Prevention Mechanisms

The current implementation has 4 layers of loop prevention:

1. **Layer 1: Environment Variable (I3PM_PWA_URL)**
   - If set, immediately bypass to Firefox
   - This indicates we're already in a PWA launch context

2. **Layer 2: Lock File Check**
   - URL hash stored in `~/.local/state/pwa-router-locks/<hash>`
   - If file exists and age < 30 seconds, bypass to Firefox

3. **Layer 3: Lock File Creation**
   - Lock file created BEFORE PWA launch
   - Prevents race conditions

4. **Layer 4: Automatic Cleanup**
   - Lock files older than 2 minutes deleted
   - Prevents directory bloat

### Authentication Bypass

Current bypass list (line 126):
```bash
AUTH_DOMAINS="accounts.google.com accounts.youtube.com login.microsoftonline.com login.live.com github.com/login github.com/session auth0.com login.tailscale.com"
```

**Issue Identified**: The check uses `github.com/login` which is a path, not a domain. The domain extraction strips paths, so this won't match properly.

### Cross-Configuration Support

The module is imported via:
- `home-modules/profiles/base-home.nix:74` → imports pwa-url-router.nix
- `home-modules/profiles/base-home.nix:112` → enables `programs.pwa-url-router.enable = true`

All configurations (ryzen.nix, thinkpad.nix, hetzner-sway.nix, m1.nix) import base-home.nix, so cross-config support is already present.

---

## Research Findings

### Issue 1: Authentication Domain Matching Bug

**Decision**: Fix domain extraction and auth domain matching to handle paths correctly.

**Rationale**: Current code checks `github.com/login` as an auth domain, but the domain extraction (line 117) strips the path. Need to check both the domain and the URL path.

**Alternatives Considered**:
- Full URL matching only → Too brittle, wouldn't match variations
- Domain-only matching → Misses path-specific auth endpoints
- **Selected**: Hybrid approach - check domain first, then check if URL contains auth path patterns

### Issue 2: Missing OAuth Redirect Domains

**Decision**: Expand auth bypass list to include common OAuth callback patterns.

**Rationale**: OAuth flows involve redirects to callback URLs. Need to detect OAuth in-flight.

**Current list**: accounts.google.com, accounts.youtube.com, login.microsoftonline.com, login.live.com, github.com/login, github.com/session, auth0.com, login.tailscale.com

**Expanded list should include**:
- appleid.apple.com (Apple Sign-In)
- id.atlassian.com (Atlassian/Jira SSO)
- login.okta.com, *.okta.com (Okta SSO)
- sso.* patterns (generic SSO)
- OAuth callback detection via URL parameters (code=, state=, oauth_token=)

### Issue 3: PWA Not Found Fallback

**Decision**: Improve error handling when PWA profile doesn't exist.

**Rationale**: If `launch-pwa-by-name` fails (PWA not installed), current code falls back to Firefox. However, error messages could be more informative.

**Alternatives Considered**:
- Silent fallback → Current behavior, but loses debugging info
- **Selected**: Log warning and fallback to Firefox, ensuring URL still opens

### Issue 4: Subdomain Matching

**Decision**: Current subdomain support via explicit `routing_domains` is correct.

**Rationale**: Each PWA defines which subdomains it handles. This is intentional and working:
```nix
routing_domains = [ "youtube.com" "www.youtube.com" "youtu.be" "m.youtube.com" ];
```

**No change needed** - this is the right approach.

### Issue 5: tmux URL Extraction

**Decision**: Review tmux-url-open regex for edge cases.

**Rationale**: Need to verify URL extraction handles:
- URLs with query parameters
- URLs with fragments (#)
- Markdown links [text](url)
- Trailing punctuation

Current implementation in ghostty.nix uses tmux-url-scan package which handles most cases.

### Issue 6: Google/YouTube Link Interception

**Decision**: Browser extension approach is correct but needs verification.

**Rationale**: The `googleRedirectInterceptorExtension` in firefox-pwas-declarative.nix intercepts Google tracking redirects. Need to verify:
1. Extension is installed in PWA profiles
2. Extension correctly extracts destination URL
3. External open triggers pwa-url-router

---

## Technical Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth domain matching | Hybrid: domain + URL path check | Handles both domain-only and path-specific auth endpoints |
| Auth domain list | Expanded with OAuth providers | Covers more SSO scenarios (Okta, Apple, Atlassian) |
| OAuth callback detection | URL parameter matching | Detects OAuth mid-flow via code=, state= params |
| Loop prevention | Keep 4-layer defense | Proven effective, no changes needed |
| xdg-open registration | Keep disabled | Prevents session restore loops (critical) |
| Subdomain routing | Use explicit routing_domains | Already working correctly |
| Error handling | Improved logging | Better debugging without breaking fallback |

---

## Outstanding Questions (Resolved)

1. **Q: Should we register as default URL handler?**
   A: NO. This is explicitly avoided (FR-004a) to prevent Firefox session restore loops.

2. **Q: How to handle PWAs with openOutOfScopeInDefaultBrowser?**
   A: This is handled by the browser extension which opens external links via xdg-open → pwa-url-router.

3. **Q: What about localhost URLs?**
   A: Explicitly disabled in pwa-sites.nix (routing_domains = []) for Home Assistant to prevent conflicts.

---

## Implementation Approach

### Phase 1: Fix Authentication Bypass (P1)

1. Modify auth domain check to handle paths:
```bash
# Check both domain and URL for auth patterns
is_auth_domain() {
  local url="$1"
  local domain="$2"

  # Domain-level auth providers
  AUTH_DOMAINS="accounts.google.com accounts.youtube.com login.microsoftonline.com login.live.com auth0.com login.tailscale.com appleid.apple.com id.atlassian.com"

  for auth_domain in $AUTH_DOMAINS; do
    [[ "$domain" == "$auth_domain" ]] && return 0
    [[ "$domain" == *".$auth_domain" ]] && return 0
  done

  # Path-based auth patterns
  AUTH_PATHS="github.com/login github.com/session github.com/oauth"
  for auth_path in $AUTH_PATHS; do
    [[ "$url" == *"$auth_path"* ]] && return 0
  done

  # OAuth callback detection (mid-flow)
  [[ "$url" == *"oauth_token="* ]] && return 0
  [[ "$url" == *"code="*"state="* ]] && return 0

  return 1
}
```

### Phase 2: Verify Cross-Configuration (P2)

1. Add dry-build test for all configurations
2. Verify pwa-domains.json is generated identically

### Phase 3: Improve Diagnostics (P2)

1. Enhance pwa-route-test to show auth bypass status
2. Add --verbose flag for debugging

### Phase 4: Test Google Redirect Interception (P3)

1. Verify browser extension installation in PWA profiles
2. Test external link opening from YouTube/Google

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Auth bypass too broad | Low | Medium | Keep list explicit, no wildcards |
| Auth bypass too narrow | Medium | High | Expand list based on user reports |
| Loop prevention fails | Low | Critical | 4-layer defense, extensive testing |
| PWA launch timing | Low | Low | Lock file mechanism handles race |
| Cross-config drift | Low | Medium | Shared base-home.nix import |

---

## References

- Feature 113 original implementation
- pwa-sites.nix documentation
- Firefox PWA extension documentation
- firefoxpwa CLI documentation
