# Implementation Plan: Fix PWA URL Routing

**Branch**: `118-fix-pwa-url-routing` | **Date**: 2025-12-14 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/118-fix-pwa-url-routing/spec.md`

## Summary

Simplify PWA URL routing by adding path-based matching and configuring PWAs to handle authentication internally via `allowedDomains`. Remove over-engineered components (link interceptor extension, lock file loop prevention, auth bypass lists). Keep Firefox as default system browser with explicit routing via `tmux-url-open` and `pwa-url-router`.

## Technical Context

**Language/Version**: Bash scripts (NixOS modules), Nix expression language
**Primary Dependencies**: Firefox, firefoxpwa, jq, fzf (for tmux-url-open)
**Storage**: JSON registry file (`~/.config/i3/pwa-domains.json`)
**Testing**: Manual testing via `pwa-route-test`, `sway-test` framework for workspace validation
**Target Platform**: NixOS (Hetzner Sway), Wayland/Sway compositor
**Project Type**: NixOS home-manager modules (single project)
**Performance Goals**: Routing decisions < 100ms
**Constraints**: Must not break existing PWA launches, Firefox session restore, or tmux URL workflow
**Scale/Scope**: ~40 PWA sites, single user system

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Composition | ✅ PASS | Changes to existing modules (`pwa-sites.nix`, `pwa-url-router.nix`, `firefox-pwas-declarative.nix`) |
| III. Test-Before-Apply | ✅ PASS | Will use `nixos-rebuild dry-build` before switch |
| VI. Declarative Configuration | ✅ PASS | All config in Nix expressions, JSON generated at build time |
| XII. Forward-Only Development | ✅ PASS | Full replacement of Feature 113 complexity, no backwards compat |
| XIV. Test-Driven Development | ✅ PASS | `pwa-route-test` for routing verification, manual auth flow testing |

**No violations requiring justification.**

## Project Structure

### Documentation (this feature)

```text
specs/118-fix-pwa-url-routing/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (API contracts if any)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
# NixOS Configuration Structure (existing)
shared/
└── pwa-sites.nix              # PWA definitions with routing_paths, auth_domains (MODIFY)

home-modules/tools/
├── pwa-url-router.nix         # URL router with path matching (MODIFY)
├── pwa-launcher.nix           # PWA launch wrapper (MINOR MODIFY)
├── firefox-pwas-declarative.nix  # PWA config with allowedDomains (MODIFY)
└── firefox.nix                # Firefox settings (VERIFY)

home-modules/terminal/
└── tmux.nix                   # tmux-url-open integration (MODIFY)

# Files to DELETE (Feature 113 legacy)
# - googleRedirectInterceptorExtension code in firefox-pwas-declarative.nix
# - pwa-install-link-interceptor script
# - Lock file logic in pwa-url-router.nix
# - Auth bypass domain list in pwa-url-router.nix
```

**Structure Decision**: Modifying existing NixOS home-manager modules. No new directories needed.

## Complexity Tracking

> No violations - no complexity justification needed.
