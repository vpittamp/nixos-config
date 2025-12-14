# Feature Specification: Fix PWA URL Routing and Link Handling

**Feature Branch**: `118-fix-pwa-url-routing`
**Created**: 2025-12-14
**Status**: Draft
**Replaces**: Feature 113 implementation (full replacement, no backwards compatibility)

## Design Philosophy

**Core Goal**: When a user opens a URL, they should end up in the correct PWA with full functionality (including authenticated sessions).

**Key Insight**: We don't care WHERE authentication happens. If auth occurs in Firefox, in the PWA, or via a redirect dance - it doesn't matter as long as the user ends up in the correct PWA with a working session.

**Simplicity Principle**: Remove complexity that doesn't serve the core goal. The Feature 113 implementation tried to be too clever with link interception extensions, auth bypass lists, and complex loop prevention. Replace with a simpler, more reliable architecture.

## Current Problems (Feature 113)

1. **Over-engineered link interception**: Browser extension that tries to intercept links inside PWAs - complex, fragile, doesn't work reliably
2. **Auth flow fragmentation**: `openOutOfScopeInDefaultBrowser` kicks users to Firefox for auth, but they can't get back to the PWA
3. **Domain-only routing**: Can't route `google.com/ai` differently from `google.com/search`
4. **Complex loop prevention**: Lock files with timeouts - adds complexity without solving the real problem
5. **Conflicting settings**: `allowedDomains` was disabled because it "conflicts" with other settings

## Proposed Architecture (Simplified)

### Core Principles

1. **PWAs handle their own auth**: Each PWA is configured with `allowedDomains` for the auth providers it needs. Auth happens inside the PWA, session persists.

2. **Explicit routing only**: Don't intercept all URLs. Route explicitly when user requests it (tmux-url-open, launcher). Firefox remains default system browser.

3. **Path-based matching**: Support `routing_paths` in addition to `routing_domains` for cases like Google AI.

4. **Minimal loop prevention**: Single environment variable check. No lock files, no timeouts.

5. **No cross-PWA interception**: If user clicks a link to another domain inside a PWA, it opens in Firefox. User can then explicitly open in another PWA if desired.

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| `pwa-url-router` | Route URLs to PWAs based on domain/path matching |
| `tmux-url-open` | Extract URLs from terminal, show routing preview, call pwa-url-router |
| `pwa-sites.nix` | Define PWAs with routing rules and auth domains |
| `firefox-pwas-declarative.nix` | Configure PWA profiles with allowedDomains for auth |
| Firefox | Default system browser, fallback for non-PWA URLs |

### What Gets Removed

- `googleRedirectInterceptorExtension` - entire extension deleted
- `pwa-install-link-interceptor` script - deleted
- Auth bypass lists in pwa-url-router - simplified (PWAs handle their own auth)
- Lock file loop prevention - replaced with simple env var check
- `openOutOfScopeInDefaultBrowser` complexity - replaced with proper allowedDomains config

## User Scenarios & Testing

### User Story 1 - Open URL in Correct PWA (Priority: P1)

As a user who encounters a URL (in terminal, chat, email), I want to open it in the appropriate PWA so I can interact with it in my dedicated app context.

**Why this priority**: This is the core use case - everything else supports this.

**Independent Test**: Run `pwa-route-test https://github.com/user/repo` and verify it identifies GitHub PWA. Run `tmux-url-open`, select the URL, verify it opens in GitHub PWA.

**Acceptance Scenarios**:

1. **Given** a GitHub URL in tmux scrollback, **When** user runs `prefix + o` and selects it, **Then** the GitHub PWA opens with that URL
2. **Given** a YouTube URL, **When** routed through pwa-url-router, **Then** the YouTube PWA opens and plays the video
3. **Given** a URL with no PWA match, **When** routed, **Then** Firefox opens with that URL
4. **Given** a Google AI URL (`google.com/ai/*`), **When** routed, **Then** Google AI PWA opens (not Gmail or Calendar)

---

### User Story 2 - PWA Authentication Works (Priority: P1)

As a user opening a PWA that requires login, I want the authentication flow to complete successfully so I can use the authenticated features.

**Why this priority**: PWAs are useless without working auth. But note: we don't care WHERE auth happens, just that it works.

**Independent Test**: Open GitHub PWA, navigate to a private repo, complete auth, verify the repo loads.

**Acceptance Scenarios**:

1. **Given** a GitHub PWA opened to a private repo URL, **When** GitHub prompts for auth, **Then** auth completes within the PWA and the repo loads
2. **Given** a Google PWA (Gmail, Calendar, AI), **When** Google prompts for auth, **Then** the Google login page works within the PWA
3. **Given** a PWA that needs Microsoft auth, **When** login is required, **Then** Microsoft login works within the PWA
4. **Given** any PWA with configured auth domains, **When** navigating to auth pages, **Then** auth happens inline without opening Firefox

---

### User Story 3 - Path-Based Routing (Priority: P1)

As a user with multiple PWAs on the same domain, I want URLs to route to the correct PWA based on the URL path.

**Why this priority**: Required for Google ecosystem (AI, Gmail, Calendar all on google.com subdomains/paths).

**Independent Test**: Run `pwa-route-test https://google.com/ai` → Google AI PWA. Run `pwa-route-test https://mail.google.com` → Gmail PWA.

**Acceptance Scenarios**:

1. **Given** `https://google.com/ai/chat`, **When** routed, **Then** opens in Google AI PWA
2. **Given** `https://mail.google.com/mail/u/0`, **When** routed, **Then** opens in Gmail PWA
3. **Given** `https://calendar.google.com`, **When** routed, **Then** opens in Google Calendar PWA
4. **Given** `https://google.com/search?q=test`, **When** routed, **Then** opens in Firefox (no matching PWA)
5. **Given** `https://www.linkedin.com/learning/course/123`, **When** routed, **Then** opens in LinkedIn Learning PWA

---

### User Story 4 - Terminal URL Extraction (Priority: P2)

As a developer, I want to quickly open URLs from my terminal in the appropriate PWA.

**Why this priority**: Key developer workflow, but depends on routing working (P1).

**Independent Test**: Echo a GitHub URL in terminal, run `prefix + o`, verify GitHub PWA option shown.

**Acceptance Scenarios**:

1. **Given** URLs in tmux scrollback, **When** `prefix + o` pressed, **Then** fzf shows all URLs with PWA indicators
2. **Given** URL selected in fzf, **When** Enter pressed, **Then** URL opens in correct destination
3. **Given** multiple URLs selected, **When** Enter pressed, **Then** all URLs open with brief delay between
4. **Given** preview pane in fzf, **When** URL highlighted, **Then** preview shows routing destination

---

### User Story 5 - Diagnostic Tools (Priority: P3)

As a maintainer, I want to test and debug routing decisions.

**Why this priority**: Maintenance tooling, not user-facing.

**Acceptance Scenarios**:

1. **Given** any URL, **When** `pwa-route-test <url>` run, **Then** shows routing decision without opening
2. **Given** verbose flag, **When** routing occurs, **Then** detailed decision logged
3. **Given** log file, **When** routing occurs, **Then** decision recorded with timestamp

---

### Edge Cases

- **Multiple path matches**: Use longest prefix match (most specific wins)
- **Malformed URLs**: Log warning, open in Firefox
- **Missing firefoxpwa**: Log error, open in Firefox
- **PWA profile missing**: Log error, open in Firefox

## Requirements

### Functional Requirements

**URL Routing:**
- **FR-001**: System MUST match URLs by domain first, then by path prefix
- **FR-002**: System MUST support `routing_paths` configuration (list of path prefixes) for PWAs
- **FR-003**: System MUST use longest-prefix-match when multiple paths could match
- **FR-004**: System MUST pass full URL to PWA for deep linking

**PWA Authentication:**
- **FR-005**: Each PWA configuration MUST include `auth_domains` (auth providers it needs)
- **FR-006**: PWA profiles MUST be configured with `allowedDomains` matching their `auth_domains`
- **FR-007**: Auth flows MUST complete within the PWA without opening external browser

**Loop Prevention (Simplified):**
- **FR-008**: System MUST check `I3PM_PWA_URL` environment variable to prevent re-routing
- **FR-009**: System MUST NOT use lock files or timeouts for loop prevention

**tmux Integration:**
- **FR-010**: `tmux-url-open` MUST extract HTTP/HTTPS URLs from scrollback
- **FR-011**: `tmux-url-open` MUST show PWA routing indicator for each URL
- **FR-012**: `tmux-url-open` MUST call `pwa-url-router` for selected URLs

**Diagnostics:**
- **FR-013**: `pwa-route-test` MUST show routing decision without opening
- **FR-014**: System MUST log routing decisions with timestamps

**Legacy Removal:**
- **FR-015**: System MUST remove the link interceptor extension
- **FR-016**: System MUST remove lock file loop prevention
- **FR-017**: System MUST remove auth bypass domain lists from router (PWAs handle auth internally)

### Key Entities

- **PWA Site Configuration**:
  - `name`: Display name
  - `ulid`: Unique identifier
  - `domain`: Primary domain
  - `routing_domains`: List of domains that route to this PWA
  - `routing_paths`: List of path prefixes that route to this PWA (NEW)
  - `auth_domains`: List of auth provider domains this PWA needs (NEW)
  - `url`: Start URL
  - `scope`: PWA scope

- **Domain/Path Registry**: JSON mapping generated at build time
  ```
  {
    "github.com": { "pwa": "github-pwa", "ulid": "...", "name": "GitHub" },
    "google.com/ai": { "pwa": "google-ai-pwa", "ulid": "...", "name": "Google AI" },
    ...
  }
  ```

## Success Criteria

- **SC-001**: 100% of configured PWAs can be opened via URL routing, including path-differentiated PWAs
- **SC-002**: Authentication flows complete successfully within PWAs (no external browser hops)
- **SC-003**: `pwa-route-test` correctly predicts routing for all tested URLs
- **SC-004**: tmux URL extraction works reliably with PWA routing preview
- **SC-005**: Routing decisions complete within 100ms
- **SC-006**: Zero loop incidents in normal usage

## Implementation Notes

### Auth Domains by PWA Category

PWAs should be configured with the auth domains they need:

| PWA Category | Auth Domains |
|--------------|--------------|
| Google (Gmail, Calendar, AI, YouTube) | `accounts.google.com`, `accounts.youtube.com` |
| Microsoft (Outlook) | `login.microsoftonline.com`, `login.live.com` |
| GitHub | `github.com` (handles its own auth) |
| Tailscale services | `login.tailscale.com` |
| 1Password | `my.1password.com` |

### Path Matching Strategy

For path-based routing, store paths as keys in the registry with trailing slash normalization:
- `google.com/ai` matches `google.com/ai`, `google.com/ai/`, `google.com/ai/chat`
- More specific paths take precedence: `google.com/ai/chat` > `google.com/ai` > `google.com`

### Migration from Feature 113

1. Remove `googleRedirectInterceptorExtension` and related code
2. Remove `pwa-install-link-interceptor` script
3. Remove lock file logic from `pwa-url-router`
4. Remove auth bypass lists from `pwa-url-router`
5. Add `auth_domains` field to `pwa-sites.nix`
6. Add `routing_paths` field to `pwa-sites.nix`
7. Update `firefox-pwas-declarative.nix` to configure `allowedDomains` per PWA
8. Regenerate domain registry with path support

## Assumptions

- Firefox and firefoxpwa installed via NixOS
- PWA profiles at `~/.local/share/firefoxpwa/profiles/`
- Wayland (Sway) display server
- tmux as terminal multiplexer
- User initiates PWA opening explicitly (not automatic interception)

## Out of Scope

- Cross-PWA link interception (intentionally removed)
- Automatic URL handler registration (Firefox remains default)
- Non-Firefox PWA implementations
- Offline PWA functionality
