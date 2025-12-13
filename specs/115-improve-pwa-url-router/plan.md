# Implementation Plan: Improve PWA URL Router

**Branch**: `115-improve-pwa-url-router` | **Date**: 2025-12-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/115-improve-pwa-url-router/spec.md`

## Summary

Improve and fix the PWA URL router system to reliably intercept URLs from tmux and route them to installed PWAs instead of vanilla Firefox. Primary focus areas: fix broken OAuth/SSO authentication flows, implement robust multi-layer infinite loop prevention, ensure cross-configuration consistency (ryzen, thinkpad, hetzner-sway, m1), and improve tmux URL extraction and opening.

## Technical Context

**Language/Version**: Bash 5.0+ (pwa-url-router script), Nix (home-manager modules), Python 3.11+ (if daemon integration needed)
**Primary Dependencies**: firefoxpwa (PWA runtime), Firefox 120+ (browser), tmux 3.3+ (terminal multiplexer), fzf (fuzzy finder), jq (JSON processing), swaymsg (Sway IPC)
**Storage**: JSON files (`~/.config/i3/pwa-domains.json`, `~/.local/state/pwa-router-locks/`)
**Testing**: Manual acceptance testing with `pwa-route-test` diagnostic tool, sway-test framework for window management validation
**Target Platform**: NixOS on x86_64-linux (ryzen, thinkpad, hetzner-sway), aarch64-linux (m1)
**Project Type**: Single project (shell scripts + Nix modules)
**Performance Goals**: PWA launch <2s, tmux popup <500ms, loop detection <10ms
**Constraints**: No xdg-open registration (prevents session restore loops), 30s lock file cooldown, 2-min lock file TTL
**Scale/Scope**: ~20 PWA domains, 4 machine configurations, single user

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | PASS | pwa-url-router.nix is composable module in home-modules/tools/ |
| II. Reference Implementation | PASS | Hetzner Sway is reference; testing on all platforms required |
| III. Test-Before-Apply | PASS | dry-build required before switch |
| VI. Declarative Configuration | PASS | All config via Nix modules, no imperative scripts |
| X. Python Standards | PASS | Python 3.11+ if daemon integration needed |
| XII. Forward-Only Development | PASS | Complete replacement of broken auth/loop logic |
| XIII. Deno CLI Standards | N/A | No Deno CLI components in this feature |
| XIV. Test-Driven Development | PASS | Acceptance scenarios define test cases |
| XV. Sway Test Framework | PASS | Will use sway-test for window management validation |

**Gate Result**: PASS - No constitution violations. Proceed with Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/115-improve-pwa-url-router/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (API contracts if any)
│   └── pwa-domains-schema.json
├── checklists/          # Quality validation
│   └── requirements.md
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
# NixOS Configuration - PWA URL Router Components

shared/
└── pwa-sites.nix          # Centralized PWA site definitions (domain, routing_domains, ULID)

home-modules/
├── profiles/
│   └── base-home.nix      # Imports pwa-url-router.nix for all configs
├── tools/
│   ├── pwa-url-router.nix # Main router script and domain registry generation
│   ├── firefox-pwas-declarative.nix  # PWA installation module
│   └── pwa-helpers.nix    # PWA utility scripts (pwa-install-all, pwa-list)
└── terminal/
    ├── tmux.nix           # tmux configuration
    └── ghostty.nix        # Terminal config with tmux-url-open binding

tests/
└── 115-pwa-url-router/
    ├── test_routing.json         # sway-test: PWA window opens on correct workspace
    ├── test_loop_prevention.json # sway-test: no infinite loops
    └── test_auth_bypass.json     # sway-test: auth domains bypass to Firefox
```

**Structure Decision**: Single project structure - shell scripts with Nix modules. No separate frontend/backend. All components are declaratively configured via home-manager.

## Complexity Tracking

> No constitution violations requiring justification.

| Decision | Rationale |
|----------|-----------|
| Multi-layer loop prevention | Required due to history of infinite loops. 4 layers (env var, lock file check, lock file create, cleanup) is necessary defense in depth. |
| Auth domain bypass list | Hardcoded list preferred over dynamic detection for reliability and simplicity. |
| Lock file mechanism | Simple file-based locking preferred over daemon state for crash resilience. |
