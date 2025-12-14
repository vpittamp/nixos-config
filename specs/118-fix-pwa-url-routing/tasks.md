# Tasks: Fix PWA URL Routing

**Input**: Design documents from `/specs/118-fix-pwa-url-routing/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/pwa-url-router.md

**Tests**: No automated tests requested. Manual verification via `pwa-route-test` and quickstart.md scenarios.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

NixOS configuration project structure:
- `shared/` - Shared definitions (pwa-sites.nix)
- `home-modules/tools/` - User tools and PWA modules
- `home-modules/terminal/` - Terminal integration (tmux)
- `~/.config/i3/` - Runtime registry files

---

## Phase 1: Setup (Schema Changes)

**Purpose**: Add new fields to PWA site configuration schema

- [X] T001 Add `routing_paths` field (list of strings, default `[]`) to PWA site schema in `shared/pwa-sites.nix`
- [X] T002 [P] Add `auth_domains` field (list of strings, default `[]`) to PWA site schema in `shared/pwa-sites.nix`
- [X] T003 Update Google AI PWA entry with `routing_paths = [ "/ai" ]` and `auth_domains = [ "accounts.google.com" ]` in `shared/pwa-sites.nix`
- [X] T004 [P] Update other Google PWAs (Gmail, Calendar, YouTube) with `auth_domains = [ "accounts.google.com" ]` in `shared/pwa-sites.nix`
- [X] T005 [P] Update Microsoft PWAs (Outlook) with `auth_domains = [ "login.microsoftonline.com" "login.live.com" ]` in `shared/pwa-sites.nix`

---

## Phase 2: Foundational (Legacy Removal)

**Purpose**: Remove Feature 113 over-engineered components - MUST complete before new implementation

**⚠️ CRITICAL**: Legacy code must be removed before new features can be implemented cleanly

- [X] T006 Delete `googleRedirectInterceptorExtension` browser extension code (lines 18-116) in `home-modules/tools/firefox-pwas-declarative.nix`
- [X] T007 [P] Delete `pwa-install-link-interceptor` script code (lines 118-192) in `home-modules/tools/firefox-pwas-declarative.nix`
- [X] T008 Remove lock file loop prevention code (lines 89-106) in `home-modules/tools/pwa-url-router.nix`
- [X] T009 [P] Remove auth bypass domain list code (lines 122-133) in `home-modules/tools/pwa-url-router.nix`
- [X] T010 Remove any references to deleted components in other files

**Checkpoint**: Legacy code removed - new implementation can now begin

---

## Phase 3: User Story 1 - Open URL in Correct PWA (Priority: P1) 🎯 MVP

**Goal**: Route URLs to the appropriate PWA based on domain matching

**Independent Test**: Run `pwa-route-test https://github.com/user/repo` and verify it identifies GitHub PWA. Open tmux-url-open, select URL, verify GitHub PWA opens.

### Implementation for User Story 1

- [X] T011 [US1] Update domain registry generation to include `pwa`, `ulid`, and `name` fields in `home-modules/tools/pwa-url-router.nix`
- [X] T012 [US1] Implement domain extraction function in `pwa-url-router` script in `home-modules/tools/pwa-url-router.nix`
- [X] T013 [US1] Implement registry lookup by domain key in `pwa-url-router` script in `home-modules/tools/pwa-url-router.nix`
- [X] T014 [US1] Implement exec to `launch-pwa-by-name` with ULID when match found in `home-modules/tools/pwa-url-router.nix`
- [X] T015 [US1] Implement fallback to Firefox when no match in `home-modules/tools/pwa-url-router.nix`
- [X] T016 [US1] Implement `I3PM_PWA_URL` environment variable check for loop prevention in `home-modules/tools/pwa-url-router.nix`
- [X] T017 [US1] Add logging to `~/.local/state/pwa-url-router.log` with timestamps in `home-modules/tools/pwa-url-router.nix`

**Checkpoint**: Domain-based routing works. `pwa-route-test https://github.com/user/repo` returns GitHub PWA.

---

## Phase 4: User Story 2 - PWA Authentication Works (Priority: P1)

**Goal**: PWAs handle authentication internally via `allowedDomains` configuration

**Independent Test**: Open GitHub PWA to private repo, complete auth within PWA, verify repo loads.

### Implementation for User Story 2

- [X] T018 [US2] Add `allowed_domains` to site config generation in firefoxpwa config.json in `home-modules/tools/firefox-pwas-declarative.nix`
- [X] T019 [US2] Map `auth_domains` from pwa-sites.nix to `allowed_domains` in config.json generation in `home-modules/tools/firefox-pwas-declarative.nix`
- [X] T020 [US2] Remove or update conflicting `openOutOfScopeInDefaultBrowser` setting if present in `home-modules/tools/firefox-pwas-declarative.nix`
- [X] T021 [US2] Verify generated config.json includes `allowed_domains` for each PWA site

**Checkpoint**: PWA auth flows complete within PWA. Google login works in Gmail PWA without opening Firefox.

---

## Phase 5: User Story 3 - Path-Based Routing (Priority: P1)

**Goal**: Route URLs to correct PWA based on domain + path prefix (e.g., `google.com/ai` → Google AI PWA)

**Independent Test**: Run `pwa-route-test https://google.com/ai` → Google AI PWA. Run `pwa-route-test https://mail.google.com` → Gmail PWA.

### Implementation for User Story 3

- [X] T022 [US3] Update registry generation to create path-based keys (e.g., `google.com/ai`) from `routing_paths` in `home-modules/tools/pwa-url-router.nix`
- [X] T023 [US3] Implement path extraction function in `pwa-url-router` script in `home-modules/tools/pwa-url-router.nix`
- [X] T024 [US3] Implement longest-prefix-match algorithm: try `domain/path1/path2`, then `domain/path1`, then `domain` in `home-modules/tools/pwa-url-router.nix`
- [X] T025 [US3] Update registry JSON output to sort keys by length (longest first) for efficient matching in `home-modules/tools/pwa-url-router.nix`
- [X] T026 [US3] Add LinkedIn Learning PWA with `routing_paths = [ "/learning" ]` in `shared/pwa-sites.nix` (if not already configured)

**Checkpoint**: Path-based routing works. `pwa-route-test https://google.com/ai` returns Google AI PWA. `pwa-route-test https://google.com/search` returns Firefox.

---

## Phase 6: User Story 4 - Terminal URL Extraction (Priority: P2)

**Goal**: Extract URLs from tmux scrollback and route through PWA system

**Independent Test**: Echo a GitHub URL in terminal, run `prefix + o`, verify GitHub PWA option shown with correct indicator.

### Implementation for User Story 4

- [X] T027 [US4] Update `tmux-url-open` to show PWA routing indicator in fzf preview using `pwa-route-test` in `home-modules/terminal/ghostty.nix`
- [X] T028 [US4] Update `tmux-url-open` to call `pwa-url-router` for selected URLs in `home-modules/terminal/ghostty.nix`
- [X] T029 [US4] Add brief delay (200ms) between multiple URL opens if batch selection supported in `home-modules/terminal/ghostty.nix`
- [X] T030 [US4] Verify fzf preview shows correct routing destination (PWA name or "Firefox")

**Checkpoint**: tmux-url-open shows routing preview and opens URLs in correct destinations.

---

## Phase 7: User Story 5 - Diagnostic Tools (Priority: P3)

**Goal**: Provide tools for testing and debugging routing decisions

**Independent Test**: Run `pwa-route-test https://google.com/ai` and verify output shows domain, path, match, and PWA details.

### Implementation for User Story 5

- [X] T031 [US5] Implement `pwa-route-test` script with formatted output showing URL, domain, path, match result in `home-modules/tools/pwa-url-router.nix`
- [X] T032 [US5] Show matched registry key and PWA details (name, ULID) in `pwa-route-test` output
- [X] T033 [US5] Show "No PWA match - would open in Firefox" when no match found
- [X] T034 [US5] Add verbose mode flag (`-v`) to `pwa-url-router` for detailed decision logging

**Checkpoint**: `pwa-route-test` correctly shows routing decision without opening anything.

---

## Phase 8: Polish & Validation

**Purpose**: Final verification and cleanup

- [X] T035 Run `nixos-rebuild dry-build --flake .#hetzner` to verify build succeeds
- [ ] T036 Run `nixos-rebuild switch --flake .#hetzner` to apply changes (user action required)
- [ ] T037 Execute quickstart.md testing checklist:
  - [ ] `pwa-route-test https://google.com/ai` shows Google AI PWA
  - [ ] `pwa-route-test https://github.com/user/repo` shows GitHub PWA
  - [ ] `pwa-route-test https://google.com/search` shows Firefox
  - [ ] GitHub PWA auth to private repo works within PWA
  - [ ] Google PWA auth works within PWA
  - [ ] `tmux-url-open` shows correct routing preview
  - [ ] No lock files in `~/.local/state/pwa-router-locks/`
- [ ] T038 Verify no regressions in existing PWA launches
- [ ] T039 Update CLAUDE.md if any new commands or workflows added

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Can run in parallel with Setup - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Setup + Foundational completion
- **User Story 2 (Phase 4)**: Depends on Setup completion (needs `auth_domains` field)
- **User Story 3 (Phase 5)**: Depends on US1 completion (extends routing logic)
- **User Story 4 (Phase 6)**: Depends on US1 completion (uses `pwa-url-router`)
- **User Story 5 (Phase 7)**: Depends on US3 completion (tests path matching)
- **Polish (Phase 8)**: Depends on all user stories

### User Story Dependencies

```
Phase 1 (Setup) ─────────────────────────────────────────┐
                                                          │
Phase 2 (Foundational) ────────────────────────────────┐ │
                                                        │ │
                                                        ▼ ▼
                                           ┌────────────────────┐
                                           │    US1: Domain     │
                                           │    Routing (P1)    │
                                           └─────────┬──────────┘
                                                     │
                              ┌───────────────────────┼───────────────────────┐
                              │                       │                       │
                              ▼                       ▼                       ▼
                    ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
                    │   US2: Auth     │     │   US3: Path     │     │  US4: tmux      │
                    │   (P1)          │     │   Routing (P1)  │     │  (P2)           │
                    └─────────────────┘     └────────┬────────┘     └─────────────────┘
                                                     │
                                                     ▼
                                           ┌─────────────────┐
                                           │ US5: Diagnostics│
                                           │     (P3)        │
                                           └─────────────────┘
```

### Parallel Opportunities

Within each phase, tasks marked [P] can run in parallel:
- **Phase 1**: T002, T004, T005 can run together (different PWA entries)
- **Phase 2**: T007, T009 can run together (different removal targets)
- **Phase 3-7**: Most user story tasks are sequential (same files)

---

## Parallel Example: Phase 1 Setup

```bash
# Launch schema field additions together:
Task: "T001 Add routing_paths field in shared/pwa-sites.nix"
Task: "T002 Add auth_domains field in shared/pwa-sites.nix"

# Launch PWA entry updates together:
Task: "T004 Update Google PWAs with auth_domains"
Task: "T005 Update Microsoft PWAs with auth_domains"
```

---

## Implementation Strategy

### MVP First (User Stories 1-3)

1. Complete Phase 1: Setup (schema changes)
2. Complete Phase 2: Foundational (legacy removal)
3. Complete Phase 3: User Story 1 (domain routing)
4. Complete Phase 4: User Story 2 (auth config)
5. Complete Phase 5: User Story 3 (path routing)
6. **STOP and VALIDATE**: Run quickstart.md checklist
7. This is the MVP - core routing + auth + path matching

### Incremental Delivery

1. After MVP: Add Phase 6 (tmux integration)
2. After tmux: Add Phase 7 (diagnostics polish)
3. Final: Phase 8 (validation)

---

## Notes

- [P] tasks = different files or independent changes
- [Story] label maps task to specific user story
- US1, US2, US3 are all P1 priority (core functionality)
- US4 (tmux) and US5 (diagnostics) are lower priority but still valuable
- Legacy removal (Phase 2) is critical - don't skip
- Test with `pwa-route-test` after each routing change
- Use `nixos-rebuild dry-build` before switch
