# Feature Specification: Improve PWA URL Router

**Feature Branch**: `115-improve-pwa-url-router`
**Created**: 2025-12-13
**Status**: Draft
**Input**: User description: "review our pwa link router methodology, and improve it and make sure its working. currently authentication doesn't seem to work, and other functionality may not work either. in addition, we're currently on your ryzen machine and we need to make sure that our solution works across configurations (ryzen, thinkpad, hetzner). also make sure our tmux link solution is working and improve it as needed. we want domains (or related constructs) that we specify to intercept links that are launched to use our pwa apps instead of launching a vanilla browser."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - External Link Opens in Correct PWA (Priority: P1)

When a user clicks a link to a domain that has a registered PWA (e.g., clicking a GitHub link from tmux scrollback), the system intercepts the link and opens it in the corresponding PWA instead of launching a vanilla Firefox browser window.

**Why this priority**: This is the core functionality of the PWA URL router. Without this working reliably, the entire feature has no value.

**Independent Test**: Can be fully tested by using `tmux prefix+o` to open a GitHub URL and verifying it opens in the GitHub PWA window rather than Firefox.

**Acceptance Scenarios**:

1. **Given** a tmux session with GitHub URLs in scrollback and GitHub PWA installed, **When** user presses `prefix+o` and selects a github.com URL, **Then** the URL opens in the GitHub PWA window (not a new Firefox tab).

2. **Given** a configured PWA domain mapping (e.g., youtube.com → YouTube PWA), **When** user runs `pwa-route-test https://youtube.com/watch?v=abc123`, **Then** output shows "✓ Would route to: youtube-pwa".

3. **Given** a URL that doesn't match any PWA domain, **When** user opens the link via pwa-url-router, **Then** it opens in the default Firefox browser.

---

### User Story 2 - OAuth/SSO Authentication Flows Work (Priority: P1)

When a PWA requires authentication (e.g., logging into GitHub, Google, or Microsoft services), the auth flow completes successfully without infinite loops, broken sessions, or being stuck in the wrong browser context.

**Why this priority**: Authentication failures make PWAs unusable. Users reported this is currently broken - OAuth flows get intercepted and create loops.

**Independent Test**: Can be tested by opening a PWA that requires login (e.g., GitHub PWA), clicking "Sign in with GitHub/Google", completing the auth flow, and verifying the session is established in the PWA.

**Acceptance Scenarios**:

1. **Given** a user is not logged into GitHub PWA, **When** they click "Sign in" and complete OAuth via Google or GitHub, **Then** the auth callback returns to the GitHub PWA with an active session.

2. **Given** a redirect URL that matches an auth domain (accounts.google.com, login.microsoftonline.com), **When** pwa-url-router receives this URL, **Then** it opens in Firefox (bypasses PWA routing) to allow session cookies to be set.

3. **Given** a PWA opens an out-of-scope auth URL, **When** Firefox opens the auth page, **Then** the user can complete auth without the page being intercepted back to the PWA mid-flow.

---

### User Story 3 - Cross-Configuration Consistency (Priority: P2)

The PWA URL routing works identically across all NixOS configurations (ryzen, thinkpad, hetzner-sway, m1), with no configuration-specific workarounds or manual setup required.

**Why this priority**: Users switch between machines frequently. Inconsistent behavior causes confusion and undermines trust in the system.

**Independent Test**: Can be tested by building configurations for each target (`nixos-rebuild dry-build --flake .#ryzen`, etc.) and verifying pwa-url-router module is included with identical behavior.

**Acceptance Scenarios**:

1. **Given** ryzen, thinkpad, hetzner-sway, and m1 configurations, **When** each is built, **Then** `pwa-url-router` is enabled via `base-home.nix` import for all.

2. **Given** a fresh activation on any configuration, **When** `pwa-route-test https://github.com` is run, **Then** output shows the same PWA routing result on all machines.

3. **Given** a new PWA added to `pwa-sites.nix`, **When** configurations are rebuilt, **Then** the new PWA routing works on all machines without per-machine changes.

---

### User Story 4 - Tmux URL Extraction and Opening (Priority: P2)

Users can reliably extract URLs from tmux scrollback using `prefix+o`, preview which PWA they'll open in, and launch them with proper PWA routing.

**Why this priority**: tmux is the primary workflow for developers, and URL extraction from terminal output is a common need.

**Independent Test**: Can be tested by echoing a URL in tmux, pressing `prefix+o`, selecting it, and verifying correct routing.

**Acceptance Scenarios**:

1. **Given** a tmux pane with various URLs in scrollback, **When** user presses `prefix+o`, **Then** fzf popup displays all extracted URLs with PWA routing preview.

2. **Given** multiple URLs selected in fzf (Tab to multi-select), **When** user presses Enter, **Then** each URL opens in appropriate PWA or Firefox with 0.3s delay between opens.

3. **Given** a URL with trailing punctuation (comma, period, parenthesis), **When** extracted from scrollback, **Then** the punctuation is stripped before routing.

---

### User Story 5 - Infinite Loop Prevention (Priority: P1)

The URL routing system MUST prevent infinite loops under all circumstances, including PWA session restore, rapid URL opens, Firefox internal navigation, and auth flow callbacks.

**Why this priority**: Infinite loops have occurred in previous iterations of this code. A loop causes the system to become unresponsive, spawn cascading windows, and require manual process termination. This is catastrophic UX.

**Independent Test**: Can be tested by simulating loop conditions (rapid reopens, session restore, auth callbacks) and verifying the system breaks the loop correctly.

**Acceptance Scenarios**:

1. **Given** a PWA is launched with a URL, **When** that PWA attempts to open the same URL externally (session restore), **Then** the lock file mechanism detects the recent routing and opens in Firefox instead (breaking the loop).

2. **Given** the I3PM_PWA_URL environment variable is set (indicating we're already in a PWA launch context), **When** pwa-url-router is invoked, **Then** it immediately bypasses to Firefox without PWA lookup.

3. **Given** a URL was routed to a PWA less than 30 seconds ago, **When** the same URL is routed again, **Then** the lock file check detects the hash match and opens in Firefox.

4. **Given** pwa-url-router is invoked during Firefox session restore (multiple URLs rapidly), **When** processing each URL, **Then** each is routed independently with loop protection, no cascading window spawns occur.

5. **Given** a PWA opens an out-of-scope URL that happens to match another PWA's domain, **When** this URL chain occurs (PWA A → Firefox → pwa-url-router → PWA B), **Then** the lock file ensures no circular routing back to PWA A.

---

### User Story 6 - PWA Link Interception from Google/YouTube (Priority: P3)

When a user clicks a link from within a PWA (e.g., clicking a GitHub link from within YouTube or Google search results), the link is intercepted and opened in the appropriate PWA rather than opening a new Firefox tab.

**Why this priority**: Google and YouTube wrap external links in tracking redirects. Without interception, these links break PWA routing.

**Independent Test**: Can be tested by finding a GitHub link in YouTube description, clicking it, and verifying it opens in GitHub PWA.

**Acceptance Scenarios**:

1. **Given** a YouTube PWA showing a video with a GitHub link in description, **When** user clicks the GitHub link, **Then** link opens in GitHub PWA (not Firefox).

2. **Given** a Google search result link wrapped in tracking redirect (google.com/url?q=...), **When** the link interceptor extension processes it, **Then** the real destination URL is extracted and opened externally.

3. **Given** a link to the same domain (e.g., YouTube link within YouTube), **When** clicked, **Then** it navigates within the same PWA (not opened externally).

---

### Edge Cases

- What happens when a URL matches multiple PWA domains (e.g., subdomain conflict)? → First match wins based on domain registry order.
- How does the system handle PWAs that aren't installed yet? → Falls back to Firefox with a log entry.
- What happens during system boot when PWA profiles don't exist? → Lock file detection prevents loops; graceful fallback.
- How are localhost URLs handled (e.g., Home Assistant on port 8123)? → Explicitly disabled in routing to prevent conflicts with other local services.
- What happens if lock file directory doesn't exist? → Created on first use; routing proceeds normally.
- What happens if lock file cleanup fails? → Silent failure; old lock files have 2-minute TTL anyway.
- What happens during rapid succession opens (10+ URLs in 1 second)? → Each URL gets unique hash; no collisions; 0.3s delay in tmux prevents overwhelming.
- What happens if pwa-url-router is set as default URL handler (xdg-open)? → EXPLICITLY AVOIDED. pwa-url-router is invoked explicitly from tmux-url-open to prevent session restore loops. Default handler remains Firefox.
- What happens if launch-pwa-by-name command doesn't exist? → Falls back to Firefox with error log; no loop.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST route HTTP/HTTPS URLs to matching PWAs based on domain when invoked explicitly via `pwa-url-router` command.
- **FR-002**: System MUST fall back to Firefox for URLs that don't match any registered PWA domain.
- **FR-003**: System MUST bypass PWA routing for authentication domains (accounts.google.com, login.microsoftonline.com, github.com/login, login.tailscale.com, auth0.com) to prevent auth flow interruption.
- **FR-004**: System MUST prevent infinite routing loops using multi-layer defense:
  - Layer 1: Environment variable check (I3PM_PWA_URL) - immediate bypass if already in PWA context
  - Layer 2: Lock file check - bypass if same URL hash exists with age < 30 seconds
  - Layer 3: Lock file creation BEFORE launching PWA to prevent race conditions
  - Layer 4: Automatic lock file cleanup (2-minute TTL) to prevent directory bloat
- **FR-004a**: pwa-url-router MUST NOT be registered as the system default URL handler (xdg-open) to prevent Firefox session restore loops.
- **FR-004b**: All loop prevention checks MUST execute before any PWA lookup to minimize processing when bypassing.
- **FR-005**: System MUST provide a diagnostic tool (`pwa-route-test`) that shows routing decision without opening anything.
- **FR-006**: System MUST extract and clean URLs from tmux scrollback (strip trailing punctuation, deduplicate).
- **FR-007**: System MUST support multi-select URL opening from tmux with sequential launch (0.3s delay).
- **FR-008**: System MUST work consistently across all NixOS configurations (ryzen, thinkpad, hetzner-sway, m1) via shared module import.
- **FR-009**: PWA domain registry (`pwa-domains.json`) MUST be auto-generated from `pwa-sites.nix` during activation.
- **FR-010**: System MUST support subdomain routing (e.g., www.youtube.com, m.youtube.com → YouTube PWA).
- **FR-011**: PWAs with `openOutOfScopeInDefaultBrowser` enabled MUST open out-of-scope URLs externally via system browser.
- **FR-012**: Browser extension MUST intercept Google/YouTube tracking redirect URLs and extract real destination for external opening.

### Key Entities *(include if feature involves data)*

- **PWA Domain Registry** (`~/.config/i3/pwa-domains.json`): JSON mapping of domains to PWA metadata (app name, ULID, display name). Generated from `shared/pwa-sites.nix`.
- **Routing Lock File** (`~/.local/state/pwa-router-locks/<url-hash>`): Timestamp file preventing loop detection within 30-second window.
- **PWA Site Definition**: Entry in `shared/pwa-sites.nix` containing domain, routing_domains array, ULID, and app registry metadata.
- **Auth Bypass List**: Hardcoded list of authentication domains in pwa-url-router.sh that bypass PWA routing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of URLs to registered PWA domains open in the correct PWA when invoked via pwa-url-router.
- **SC-002**: OAuth/SSO flows complete successfully for GitHub, Google, and Microsoft authentication within PWAs.
- **SC-003**: All configurations (ryzen, thinkpad, hetzner-sway, m1) produce identical PWA routing behavior.
- **SC-004**: URL extraction from tmux scrollback identifies 95%+ of valid URLs with no false positives.
- **SC-005**: System prevents all infinite routing loops (zero user-observable loop scenarios).
- **SC-006**: PWA launch time from URL click to window focus is under 2 seconds.
- **SC-007**: tmux prefix+o popup appears within 500ms of keypress.

## Assumptions

- Firefox with firefoxpwa extension is installed and configured on all target machines.
- PWA profiles exist in `~/.local/share/firefoxpwa/profiles/` (created via `pwa-install-all` or declarative module).
- Sway window manager is the active compositor (uses `swaymsg exec` for launching).
- User has configured `shared/pwa-sites.nix` with desired PWA domains and routing_domains.
- tmux is the primary terminal multiplexer (prefix key is backtick by default).
- Authentication bypass domains are limited to well-known SSO providers; custom auth domains may need manual addition.
