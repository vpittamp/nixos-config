# Research: M1 Configuration Alignment with Hetzner-Sway

**Feature Branch**: `051-the-hetzner-sway`
**Date**: 2025-10-30

## Overview

This document consolidates research findings on aligning the M1 MacBook Pro configuration with the hetzner-sway reference implementation while respecting architectural differences.

## Key Findings

### 1. System Module Import Gaps

**Decision**: Add missing core service modules to M1 configuration

**Critical Missing Modules**:
- **i3-project-daemon.nix**: MUST be added to M1
  - Both platforms run Sway/Wayland with identical IPC protocol
  - Required for Features 037, 049 (project management, window filtering, workspace intelligence)
  - No architectural reason for exclusion
  - Missing system service configuration in `configurations/m1.nix`

- **onepassword-automation.nix**: SHOULD be added to M1
  - Enables service account automation for Git/CI operations
  - No platform-specific constraints
  - Works identically on both architectures

- **keyd.nix**: CONSIDER for M1
  - CapsLock → F9 mapping for workspace mode (Feature 050)
  - Currently disabled but could improve keyboard ergonomics
  - Works on both platforms

**Correctly Separated Modules**:
- **wayvnc.nix**: Hetzner-specific (headless VNC server)
  - M1 uses physical display + RustDesk for remote access
- **tailscale-audio.nix**: Hetzner-specific (audio streaming to remote device)
  - M1 has local speakers/headphones via PipeWire

**Rationale**: The i3-project-daemon is architecture-independent and critical for i3pm functionality. Its absence on M1 breaks project switching, window filtering, and workspace management features. This is a clear oversight, not an intentional architectural difference.

**Alternatives Considered**:
- Keep M1 without i3pm daemon: Rejected - breaks core productivity workflows
- Use different daemon implementation: Rejected - Python daemon is architecture-independent
- Conditionally enable features: Rejected - adds unnecessary complexity

### 2. Home-Manager Configuration Structure

**Decision**: M1 should adopt hetzner-sway's clean 10-import structure

**Current State**:
- **Hetzner-Sway**: Clean structure with explicit imports in `home-vpittamp.nix`
  - 10 focused imports for desktop applications
  - Does NOT import redundant service modules
  - Clear separation: system services in configuration.nix, user apps in home-manager

- **M1**: Bloated 45+ imports via `base-home.nix`
  - Imports disabled `i3-project-daemon.nix` module (incorrect - this is a system service)
  - Less clear separation between system and user configuration
  - More difficult to identify M1-specific overrides

**Missing from M1**:
- `declarative-cleanup.nix` import in home-vpittamp.nix
- Explicit PipeWire user configuration (currently only in system config)

**Rationale**: Hetzner-sway's structure clearly separates system services (in configuration.nix) from user applications (in home-manager). The i3-project-daemon is a system service requiring root access for /proc namespace traversal - it should NOT be in home-manager imports. M1's structure obscures this distinction.

**Alternatives Considered**:
- Keep M1's base-home.nix approach: Rejected - less maintainable, unclear what's M1-specific
- Create shared home-manager base: Rejected - hetzner-sway already provides the pattern
- Use conditional imports: Rejected - explicit imports are clearer

### 3. Sway Configuration Unification

**Decision**: Current Sway configuration is well-unified; address two implementation issues

**Current Architecture**:
- Single `home-modules/desktop/sway.nix` handles both platforms
- Conditional logic based on hostname detection (`nixos-hetzner-sway` vs `nixos-m1`)
- Template-based dynamic configuration (Feature 047) shared across platforms
- Proper isolation of platform-specific settings (outputs, inputs, environment variables)

**Working Correctly**:
- ✅ Keybindings system (sway-config-manager with TOML configuration)
- ✅ Appearance configuration (JSON-based, shared templates)
- ✅ Window rules and workspace assignments
- ✅ Walker launcher integration (with Wayland mode detection)
- ✅ i3bar status bar (with conditional multi-monitor setup)
- ✅ Core Sway compositor settings (focus behavior, workspace naming)

**Platform-Specific (Correctly Isolated)**:
- Output configuration:
  - Hetzner: HEADLESS-1, HEADLESS-2, HEADLESS-3 (virtual displays for VNC)
  - M1: eDP-1 (built-in Retina), HDMI-A-1 (external monitor)
- Input devices:
  - Hetzner: Disabled (WLR_LIBINPUT_NO_DEVICES=1)
  - M1: libinput with touchpad natural scrolling
- Environment variables:
  - Hetzner: WLR_BACKENDS=headless, WLR_RENDERER=pixman, GSK_RENDERER=cairo
  - M1: Standard Wayland variables without headless backend
- Display scaling:
  - Hetzner: No scaling (virtual 1920x1080 outputs)
  - M1: 2x scaling for Retina display

**Issues Identified**:

**Priority 1 - workspace-mode-handler.sh hardcoded outputs**:
- Location: `home-modules/desktop/sway-config-manager.nix:44-147`
- Problem: Hardcoded HEADLESS-1/2/3 output names
- Impact: M1 workspace modes fail with non-existent outputs
- Fix: Use dynamic output detection via `swaymsg -t get_outputs`
- Effort: 30 minutes

**Priority 2 - Hostname-based platform detection**:
- Locations: Multiple files use `config.networking.hostName == "nixos-hetzner-sway"`
- Problem: Breaks on hostname change, duplicated logic
- Impact: Manual updates required if hostname changes
- Fix: Replace with feature flag system (e.g., `isHeadless` option)
- Effort: 1 hour

**Rationale**: The Sway unification is already well-designed with proper separation of concerns. The two issues are implementation details that should be addressed incrementally, not blockers for M1 alignment. The workspace-mode-handler fix should be prioritized as it directly impacts user workflows.

**Alternatives Considered**:
- Separate sway.nix files per platform: Rejected - leads to duplication
- Complete rewrite with feature flags: Rejected - overkill for working system
- Leave hardcoded outputs: Rejected - breaks M1 functionality

### 4. Service Configuration Alignment

**Decision**: Ensure identical service configurations for shared daemons

**Services That MUST Be Identical**:
- ✅ i3-project-daemon (needs to be added to M1 system config)
- ✅ walker/elephant launcher (already identical)
- ✅ sway-config-manager daemon (already identical)
- ✅ speech-to-text service (already identical using safe module)
- ✅ 1Password integration (already aligned, automation module optional)

**Services That MUST Differ**:
- ✅ WayVNC (hetzner-only - headless VNC streaming)
- ✅ Tailscale Audio (hetzner-only - remote audio streaming)
- ✅ RustDesk (m1-only - peer-to-peer remote desktop)
- ✅ WiFi Recovery (m1-only - BCM4378 firmware workaround)

**Configuration Verification**:
- i3pm CLI tools: Deno TypeScript implementation, architecture-independent ✅
- Application registry: Shared `app-registry.nix`, no platform-specific apps ✅
- Walker bookmarks/commands: User-managed files, sync via Git ✅
- Sway keybindings: Template-based with dynamic reload, platform-agnostic ✅

**Rationale**: Service daemons (i3pm, walker, sway-config-manager) are the core of the daily workflow. They must behave identically on both platforms to maintain muscle memory and productivity. Platform-specific services (VNC, audio streaming, remote desktop) are correctly isolated based on deployment context.

### 5. Package Parity Analysis

**Decision**: Achieve 98%+ package availability across architectures

**Shared Packages (Both Platforms)**:
- Core: neovim, alacritty, tmux, git, gh, lazygit
- Wayland: wl-clipboard, grim, slurp, mako
- Desktop: firefox, firefoxpwa, walker/elephant
- Monitoring: htop, btop, neofetch
- Network: tailscale, openssh
- Development: docker, kubernetes tools (full profile)

**Platform-Specific Packages (Justified)**:
- **Hetzner**: wlr-randr (wlroots compositor management), wayvnc (VNC server CLI)
- **M1**: imagemagick/librsvg (PWA icon processing), rustdesk-flutter (remote access)

**Architecture Compatibility**:
- Python packages: All architecture-independent (i3ipc, pytest, rich, pydantic)
- Deno/TypeScript: Supports aarch64-linux natively
- System tools: All have ARM64 builds in nixpkgs
- No x86-specific packages identified in shared configuration

**Rationale**: Package availability is not a constraint for M1 alignment. NixOS nixpkgs has excellent aarch64-linux support. Platform-specific packages are genuinely different tools for different deployment contexts, not availability workarounds.

### 6. Documentation Parity Requirements

**Decision**: Update CLAUDE.md with comprehensive architectural difference documentation

**Documentation Gaps Identified**:
- ✅ Architectural differences section exists in spec (10 documented differences)
- ⚠️ CLAUDE.md quick reference needs M1-specific sections
- ⚠️ Sway configuration management workflow not differentiated by platform
- ⚠️ i3pm daemon setup instructions assume hetzner-sway configuration

**Required Documentation Updates**:
1. Add M1-specific quick start section to CLAUDE.md
2. Document i3pm daemon service configuration for M1
3. Create troubleshooting section for platform-specific issues
4. Add workspace mode handler limitations (hardcoded outputs)
5. Document hostname-based detection as tech debt

**Maintenance Workflow**:
- Changes to hetzner-sway SHOULD trigger M1 compatibility review
- Architectural differences MUST be documented with rationale
- Module additions MUST specify target platforms explicitly
- Breaking changes MUST update both configurations simultaneously

**Rationale**: Documentation drift is a primary cause of configuration divergence. Clear guidelines and maintenance workflows prevent future misalignment.

## Technology Stack Decisions

### NixOS Configuration
- **Version**: NixOS 24.11+ (both platforms)
- **Flake System**: nixpkgs 24.11, home-manager 24.11
- **Reference**: hetzner-sway (Sway/Wayland, headless VNC, dynamic config management)

### Desktop Environment
- **Compositor**: Sway (Wayland) on both platforms
- **Display Server**: Wayland native (no X11 fallback needed)
- **Session Manager**: greetd (auto-login on hetzner, tuigreet on M1)

### Service Daemons
- **Project Management**: i3-project-daemon (Python 3.11, asyncio, i3ipc.aio)
- **Application Launcher**: walker/elephant (Go, GTK4, Wayland native)
- **Configuration Manager**: sway-config-manager (Python 3.11, file watcher, Git integration)

### Testing & Validation
- **Build Testing**: `nixos-rebuild dry-build --flake .#<target>`
- **Service Testing**: systemd unit status, daemon event streams
- **Functional Testing**: Manual workflow verification on both platforms

## Implementation Constraints

### Must Preserve
- Hetzner-sway headless functionality (WayVNC, virtual outputs)
- M1 physical hardware features (Retina display, touchpad, WiFi)
- Existing user workflows (project switching, window filtering)
- Service daemon behavior consistency

### Must Avoid
- Breaking changes to hetzner-sway during M1 alignment
- X11 dependencies (both platforms are Wayland-only)
- Architecture-specific binaries in shared modules
- Hostname changes (current detection logic depends on it)

### Technical Debt to Address
- Hostname-based platform detection (should use feature flags)
- Hardcoded output names in workspace-mode-handler
- Scattered environment variable definitions
- Duplicate home-manager import structure between platforms

## Performance Considerations

### Build Performance
- M1 ARM64 native compilation is fast (no emulation)
- Shared nixpkgs cache reduces build time
- Flake evaluation overhead is negligible

### Runtime Performance
- Service daemons are lightweight (<15MB each, <1% CPU)
- Sway compositor is efficient on both platforms
- No performance regressions expected from alignment changes

### Resource Constraints
- M1: 16GB RAM, 8GB swap file, battery-aware power management
- Hetzner: 8GB RAM, no swap, fixed cloud VM allocation
- Configuration changes do not impact resource profiles

## Risk Assessment

### Low Risk
- Adding i3-project-daemon to M1 (well-tested, architecture-independent)
- Importing missing home-manager modules (declarative, reversible)
- Documentation updates (no functional changes)

### Medium Risk
- Fixing workspace-mode-handler outputs (requires testing on both platforms)
- Replacing hostname detection with feature flags (affects multiple files)

### High Risk
- None identified - all changes are additive or isolated

## Next Steps

This research phase has resolved all NEEDS CLARIFICATION items from the Technical Context. Proceed to Phase 1 (Design & Contracts) to generate:
1. data-model.md - Configuration entities and relationships
2. contracts/ - Module interface definitions
3. quickstart.md - User implementation guide
