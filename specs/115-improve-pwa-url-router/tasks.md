# Tasks: Improve PWA URL Router

**Input**: Design documents from `/specs/115-improve-pwa-url-router/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Manual acceptance testing via `pwa-route-test` diagnostic tool. No automated test tasks included (not requested in spec).

**Organization**: Tasks grouped by user story priority (P1s first, then P2s, then P3s) to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US5)
- Include exact file paths in descriptions

## Path Conventions

**NixOS Configuration Structure:**
- `home-modules/tools/pwa-url-router.nix` - Main router script and config generation
- `home-modules/tools/pwa-launcher.nix` - PWA launch command
- `home-modules/terminal/ghostty.nix` - tmux-url-open binding
- `shared/pwa-sites.nix` - PWA site definitions
- `~/.config/i3/pwa-domains.json` - Generated domain registry
- `~/.local/state/pwa-router-locks/` - Lock files

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and prerequisite validation

- [x] T001 Read existing pwa-url-router.nix to understand current implementation in home-modules/tools/pwa-url-router.nix
- [x] T002 Read existing pwa-launcher.nix to understand launch-pwa-by-name in home-modules/tools/pwa-launcher.nix
- [x] T003 [P] Read pwa-sites.nix to understand current PWA definitions in shared/pwa-sites.nix
- [x] T004 [P] Read tmux-url-open implementation in home-modules/terminal/ghostty.nix
- [x] T005 Verify base-home.nix imports pwa-url-router.nix for all configurations in home-modules/profiles/base-home.nix

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before user story implementation

**CRITICAL**: The following tasks establish the improved auth bypass and loop prevention foundation used by all P1 stories.

- [x] T006 Create expanded AUTH_DOMAINS list constant in pwa-url-router script (accounts.google.com, accounts.youtube.com, login.microsoftonline.com, login.live.com, auth0.com, login.tailscale.com, appleid.apple.com, id.atlassian.com) in home-modules/tools/pwa-url-router.nix
- [x] T007 Create AUTH_PATHS list constant for path-based auth patterns (github.com/login, github.com/session, github.com/oauth, /oauth/authorize, /oauth/callback) in home-modules/tools/pwa-url-router.nix
- [x] T008 Create OAUTH_PARAMS list constant for OAuth callback detection (oauth_token=, code=.*state=) in home-modules/tools/pwa-url-router.nix
- [x] T009 Implement is_auth_bypass() function with hybrid domain + URL path + OAuth param checking in home-modules/tools/pwa-url-router.nix

**Checkpoint**: Foundation ready - auth bypass infrastructure complete for P1 stories

---

## Phase 3: User Story 5 - Infinite Loop Prevention (Priority: P1)

**Goal**: Implement bulletproof 4-layer loop prevention to ensure system never enters infinite routing loops

**Independent Test**: Run `pwa-route-test URL` twice rapidly - second invocation should show "LOOP PREVENTION" bypass

### Implementation for User Story 5

- [x] T010 [US5] Verify Layer 1: I3PM_PWA_URL environment variable check exists at top of pwa-url-router script in home-modules/tools/pwa-url-router.nix
- [x] T011 [US5] Implement Layer 2: Lock file existence and age check (< 30 seconds) in pwa-url-router in home-modules/tools/pwa-url-router.nix
- [x] T012 [US5] Implement Layer 3: Lock file creation BEFORE PWA launch (prevents race conditions) in home-modules/tools/pwa-url-router.nix
- [x] T013 [US5] Implement Layer 4: Lock file cleanup (delete files older than 2 minutes) in pwa-url-router in home-modules/tools/pwa-url-router.nix
- [x] T014 [US5] Add logging for each loop prevention layer trigger in home-modules/tools/pwa-url-router.nix
- [x] T015 [US5] Verify pwa-url-router is NOT registered as xdg-open default handler in home-modules/tools/pwa-url-router.nix (check mimeApps if present)

**Checkpoint**: Loop prevention complete - verify by simulating rapid URL opens

---

## Phase 4: User Story 2 - OAuth/SSO Authentication Flows Work (Priority: P1)

**Goal**: Fix authentication bypass so OAuth/SSO flows complete without being intercepted

**Independent Test**: Test `pwa-route-test https://accounts.google.com/signin` shows "AUTH BYPASS" message

### Implementation for User Story 2

- [x] T016 [US2] Refactor auth domain check to use is_auth_bypass() function (from T009) in home-modules/tools/pwa-url-router.nix
- [x] T017 [US2] Fix github.com/login auth check - ensure URL path is preserved during auth bypass check in home-modules/tools/pwa-url-router.nix
- [x] T018 [US2] Add subdomain matching for auth domains (e.g., *.auth0.com) in is_auth_bypass() in home-modules/tools/pwa-url-router.nix
- [x] T019 [US2] Add logging for auth bypass decisions with reason (domain/path/oauth) in home-modules/tools/pwa-url-router.nix
- [x] T020 [US2] Update pwa-route-test to show auth bypass status and reason in home-modules/tools/pwa-url-router.nix

**Checkpoint**: Auth bypass complete - test GitHub OAuth flow from GitHub PWA

---

## Phase 5: User Story 1 - External Link Opens in Correct PWA (Priority: P1)

**Goal**: Core routing functionality - URLs route to matching PWAs based on domain

**Independent Test**: Run `pwa-route-test https://github.com/user/repo` shows "Would route to: github-pwa"

### Implementation for User Story 1

- [x] T021 [US1] Verify domain extraction from URL preserves protocol handling (http/https) in home-modules/tools/pwa-url-router.nix
- [x] T022 [US1] Verify pwa-domains.json generation from pwa-sites.nix includes all routing_domains in home-modules/tools/pwa-url-router.nix
- [x] T023 [US1] Verify jq lookup of domain in pwa-domains.json returns correct PWA metadata in home-modules/tools/pwa-url-router.nix
- [x] T024 [US1] Verify launch-pwa-by-name integration passes URL via I3PM_PWA_URL env var in home-modules/tools/pwa-url-router.nix
- [x] T025 [US1] Add fallback to Firefox when no PWA match found with log entry in home-modules/tools/pwa-url-router.nix
- [x] T026 [US1] Add fallback to Firefox when launch-pwa-by-name fails with error log in home-modules/tools/pwa-url-router.nix
- [x] T027 [US1] Add fallback to Firefox when PWA profile not installed with warning log in home-modules/tools/pwa-url-router.nix

**Checkpoint**: Core routing complete - test with known PWA domains

---

## Phase 6: User Story 3 - Cross-Configuration Consistency (Priority: P2)

**Goal**: PWA routing works identically on ryzen, thinkpad, hetzner-sway, and m1

**Independent Test**: Run `nixos-rebuild dry-build --flake .#<config>` for all 4 targets, verify pwa-url-router included

### Implementation for User Story 3

- [x] T028 [US3] Verify base-home.nix imports pwa-url-router.nix (already imports) in home-modules/profiles/base-home.nix
- [x] T029 [US3] Verify programs.pwa-url-router.enable = true in base-home.nix in home-modules/profiles/base-home.nix
- [x] T030 [P] [US3] Test dry-build for ryzen configuration (nixos-rebuild dry-build --flake .#ryzen)
- [x] T031 [P] [US3] Test dry-build for thinkpad configuration (nixos-rebuild dry-build --flake .#thinkpad) if config exists
- [x] T032 [P] [US3] Test dry-build for hetzner-sway configuration (nixos-rebuild dry-build --flake .#hetzner-sway)
- [x] T033 [P] [US3] Test dry-build for m1 configuration (nixos-rebuild dry-build --flake .#m1 --impure)
- [x] T034 [US3] Verify pwa-domains.json generation uses shared pwa-sites.nix (not per-config)

**Checkpoint**: Cross-config complete - all 4 configurations build with identical router behavior

---

## Phase 7: User Story 4 - Tmux URL Extraction and Opening (Priority: P2)

**Goal**: Reliable URL extraction from tmux scrollback with PWA routing preview

**Independent Test**: In tmux, echo a URL, press `prefix+o`, verify URL appears in fzf with routing preview

### Implementation for User Story 4

- [x] T035 [US4] Review tmux-url-open implementation in ghostty.nix for current behavior in home-modules/terminal/ghostty.nix
- [x] T036 [US4] Verify tmux-url-scan package is used for URL extraction in home-modules/terminal/ghostty.nix
- [x] T037 [US4] Add PWA routing preview to fzf display (show target PWA name) in home-modules/terminal/ghostty.nix or tmux-url-open script
- [x] T038 [US4] Verify multi-select support (Tab key) opens URLs sequentially in home-modules/terminal/ghostty.nix
- [x] T039 [US4] Add 0.3s delay between multi-URL opens to prevent race conditions in home-modules/terminal/ghostty.nix
- [x] T040 [US4] Verify trailing punctuation stripping (.,;:)!?) in URL extraction

**Checkpoint**: Tmux integration complete - test prefix+o workflow with multiple URLs

---

## Phase 8: User Story 6 - PWA Link Interception from Google/YouTube (Priority: P3)

**Goal**: Intercept Google/YouTube tracking redirects and route to correct PWA

**Independent Test**: In YouTube PWA, click a GitHub link, verify it opens in GitHub PWA (not Firefox)

### Implementation for User Story 6

- [x] T041 [US6] Review googleRedirectInterceptorExtension in firefox-pwas-declarative.nix in home-modules/tools/firefox-pwas-declarative.nix
- [x] T042 [US6] Verify extension extracts real destination from google.com/url?q=... redirects in home-modules/tools/firefox-pwas-declarative.nix
- [x] T043 [US6] Verify extension is installed in PWA profiles (not just main Firefox) in home-modules/tools/firefox-pwas-declarative.nix
- [x] T044 [US6] Verify openOutOfScopeInDefaultBrowser setting triggers xdg-open for external links in home-modules/tools/firefox-pwas-declarative.nix
- [x] T045 [US6] Add same-domain detection to prevent external open for internal YouTube/Google links

**Checkpoint**: Google/YouTube interception complete - test external link flow from PWAs

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T046 [P] Enhance pwa-route-test output to show all routing decision details (domain, match, auth bypass, loop prevention)
- [x] T047 [P] Add --verbose flag to pwa-url-router for debugging
- [x] T048 Add log rotation when pwa-url-router.log exceeds 1MB in home-modules/tools/pwa-url-router.nix
- [x] T049 Update quickstart.md with any new commands or changed behavior in specs/115-improve-pwa-url-router/quickstart.md
- [ ] T050 Run manual acceptance tests from spec.md for all user stories (MANUAL - after nixos-rebuild switch)
- [ ] T051 Commit changes with feature branch message format (MANUAL - user decision)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - read existing code
- **Foundational (Phase 2)**: Depends on Setup - creates auth infrastructure
- **User Story 5 (Phase 3)**: Depends on Foundational - P1 loop prevention (most critical)
- **User Story 2 (Phase 4)**: Depends on Foundational - P1 auth flows (uses is_auth_bypass)
- **User Story 1 (Phase 5)**: Depends on US5, US2 - P1 core routing (uses loop prevention + auth bypass)
- **User Story 3 (Phase 6)**: Depends on US1 - P2 cross-config (validates US1 works everywhere)
- **User Story 4 (Phase 7)**: Depends on US1 - P2 tmux integration (requires working routing)
- **User Story 6 (Phase 8)**: Depends on US1 - P3 Google/YouTube (requires working routing)
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 5 (P1)**: First P1 - enables safe iteration on other stories
- **User Story 2 (P1)**: Can start after Foundational - independent auth implementation
- **User Story 1 (P1)**: Should complete after US5/US2 - benefits from loop/auth protection
- **User Story 3 (P2)**: Validates all P1s work across configs
- **User Story 4 (P2)**: Depends on US1 working - adds tmux UI layer
- **User Story 6 (P3)**: Depends on US1 working - adds browser extension layer

### Within Each User Story

- Review existing code first (T001-T005 setup)
- Foundation tasks must complete before story tasks
- Each story should be testable via pwa-route-test before moving on
- Commit after each story checkpoint

### Parallel Opportunities

- **Phase 1**: T003, T004 can run in parallel (reading different files)
- **Phase 2**: T006, T007, T008 can run in parallel (different constants)
- **Phase 6**: T030, T031, T032, T033 can run in parallel (independent dry-builds)
- **Phase 9**: T046, T047 can run in parallel (different enhancements)

---

## Parallel Example: User Story 3 (Cross-Config)

```bash
# Launch all dry-builds in parallel:
Task: "Test dry-build for ryzen configuration"
Task: "Test dry-build for thinkpad configuration"
Task: "Test dry-build for hetzner-sway configuration"
Task: "Test dry-build for m1 configuration"
```

---

## Implementation Strategy

### MVP First (P1 Stories Only)

1. Complete Phase 1: Setup (read existing code)
2. Complete Phase 2: Foundational (auth infrastructure)
3. Complete Phase 3: User Story 5 (loop prevention) - **CRITICAL SAFETY**
4. Complete Phase 4: User Story 2 (auth flows)
5. Complete Phase 5: User Story 1 (core routing)
6. **STOP and VALIDATE**: Manual test all P1 acceptance scenarios
7. Deploy to current machine and test

### Incremental Delivery

1. P1 Stories (US5, US2, US1) → Core routing + safety → Deploy
2. Add User Story 3 → Validate cross-config → Deploy to all machines
3. Add User Story 4 → Enhanced tmux workflow → Deploy
4. Add User Story 6 → Google/YouTube interception → Deploy
5. Each story adds value without breaking previous stories

### Single Developer Strategy

Recommended order for single developer:
1. Phase 1 + 2: Setup and Foundation (T001-T009)
2. Phase 3: US5 Loop Prevention (T010-T015) - enables safe iteration
3. Phase 4: US2 Auth Flows (T016-T020)
4. Phase 5: US1 Core Routing (T021-T027)
5. Manual test checkpoint for all P1s
6. Phase 6: US3 Cross-Config (T028-T034)
7. Phase 7: US4 Tmux (T035-T040)
8. Phase 8: US6 Google/YouTube (T041-T045)
9. Phase 9: Polish (T046-T051)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable via pwa-route-test
- Loop prevention (US5) is implemented FIRST because previous iterations had loop bugs
- Auth bypass (US2) is implemented SECOND because it's currently broken
- No automated tests - manual acceptance testing per spec.md
- Commit after each phase checkpoint
- Stop at any checkpoint to validate story independently
