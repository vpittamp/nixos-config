# Feature Specification: M1 Configuration Alignment with Hetzner-Sway

**Feature Branch**: `063-the-hetzner-sway`
**Created**: 2025-10-30
**Status**: Draft
**Input**: User description: "the hetzner-sway config is our primary configuration.  we also have an m1 configuration that tries to model the hetzner-sway config, but has different architecture using asahi linux with nixos-m1;  create a new spec that transforms that m1 configuration to be as closely aligned as possibel to the hetzner-sway configuration, while being mindful of the architectural differeneces that may need different config."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified Service Configuration (Priority: P1)

As a system administrator managing both M1 MacBook Pro and Hetzner Cloud infrastructure, I want both configurations to import and enable the exact same core services and modules, so that my development environment is consistent across platforms.

**Why this priority**: Core service alignment is the foundation for a consistent cross-platform experience. Without this, users must learn and maintain two different configurations, leading to confusion and maintenance burden.

**Independent Test**: Can be fully tested by comparing the imports sections and enabled services between both configurations. Success is measured by achieving 95%+ parity in enabled services (excluding hardware-specific services).

**Acceptance Scenarios**:

1. **Given** the hetzner-sway configuration imports a core module (e.g., development.nix, networking.nix), **When** reviewing the M1 configuration, **Then** the same module should be imported unless there's a documented architectural reason for exclusion
2. **Given** both configurations run Sway compositor, **When** comparing home-manager configurations, **Then** both should use identical walker launcher settings, i3pm daemon configuration, and project management tools
3. **Given** user installs a system package on hetzner-sway, **When** switching to M1, **Then** the same package should be available (unless it's x86-specific)

---

### User Story 2 - Consistent Home Manager Configuration (Priority: P1)

As a developer working on multiple machines, I want my user environment (shell, editors, terminal tools) to be identical across M1 and Hetzner platforms, so that muscle memory and workflows transfer seamlessly.

**Why this priority**: User environment consistency directly impacts productivity. Differences in shell configuration, editor setup, or terminal tools force users to context-switch mentally, reducing efficiency.

**Independent Test**: Can be fully tested by comparing home-manager module imports and shell configurations. Success is measured by achieving identical dotfile content (except for hardware-specific environment variables).

**Acceptance Scenarios**:

1. **Given** hetzner-sway uses walker launcher with specific configuration, **When** launching walker on M1, **Then** it should have identical keybindings, search engines, bookmarks, and custom commands
2. **Given** both platforms use Sway compositor, **When** comparing keybindings.toml files, **Then** they should be identical (with exceptions for hardware-specific keys like TouchBar)
3. **Given** user has bash history on hetzner-sway, **When** using Claude Code integration on M1, **Then** the bash history hook should work identically

---

### User Story 3 - Hardware-Aware Platform Differentiation (Priority: P2)

As a system architect, I want platform-specific configurations (audio, display, input devices) to be clearly isolated in separate modules, so that cross-platform changes don't accidentally break hardware-specific features.

**Why this priority**: While consistency is important, attempting to force identical configurations where hardware differs leads to fragile systems. Clear separation allows safe evolution of both platforms.

**Independent Test**: Can be fully tested by identifying hardware-specific settings and verifying they're isolated to hardware/ modules or platform-specific conditionals. Success is measured by zero hardware-related configuration leakage between platforms.

**Acceptance Scenarios**:

1. **Given** M1 has Retina display requiring 2x scaling, **When** configuring Sway outputs, **Then** scaling settings should be in M1-specific conditional blocks without affecting hetzner-sway
2. **Given** hetzner-sway runs headless with WLR_BACKENDS=headless, **When** M1 configuration is evaluated, **Then** it should not inherit headless-specific environment variables
3. **Given** M1 has physical touchpad requiring libinput configuration, **When** hetzner-sway is deployed, **Then** touchpad settings should not be applied (using WLR_LIBINPUT_NO_DEVICES=1)

---

### User Story 4 - Service Daemon Alignment (Priority: P2)

As a power user relying on i3pm project management system, I want the i3pm daemon, walker launcher, and sway-config-manager to function identically on both platforms, so that project switching and window management workflows are portable.

**Why this priority**: These daemons are core to the daily workflow. Differences in daemon behavior between platforms would break project portability and require platform-specific workflows.

**Independent Test**: Can be fully tested by verifying daemon service definitions are identical and by testing project switching/window filtering on both platforms. Success is measured by identical daemon behavior (zero user-visible differences).

**Acceptance Scenarios**:

1. **Given** user creates a project on hetzner-sway, **When** switching to that project on M1, **Then** project directory, scoped applications, and window filtering should work identically
2. **Given** user configures custom walker commands on hetzner-sway, **When** accessing walker on M1, **Then** the same commands should be available with identical behavior
3. **Given** user modifies keybindings.toml on M1, **When** running `swaymsg reload`, **Then** the hot-reload mechanism should work identically to hetzner-sway (<100ms latency)

---

### User Story 5 - Documentation and Maintenance Parity (Priority: P3)

As a configuration maintainer, I want clear documentation of architectural differences and a maintenance workflow that keeps both platforms in sync, so that future updates don't cause configuration drift.

**Why this priority**: Without documented differences and maintenance guidelines, configurations will inevitably drift over time as updates are applied inconsistently.

**Independent Test**: Can be fully tested by reviewing CLAUDE.md documentation and creating a diff report between configurations. Success is measured by comprehensive documentation of all intentional differences.

**Acceptance Scenarios**:

1. **Given** a new feature is added to hetzner-sway configuration, **When** reviewing the change, **Then** documentation should clearly indicate whether it applies to M1 or is platform-specific
2. **Given** architectural differences exist (e.g., headless vs physical display), **When** reading CLAUDE.md, **Then** each difference should have a documented rationale and impact assessment
3. **Given** user wants to add a new service module, **When** determining where to add it, **Then** clear guidelines should exist for choosing between shared base.nix, platform-specific config, or conditional blocks

---

### Edge Cases

- What happens when a new Sway/Wayland feature is added to hetzner-sway that has no M1 equivalent (e.g., headless-specific WayVNC configuration)?
- How does the system handle package availability differences between x86_64 and aarch64 architectures?
- What if a service module has different configuration requirements on different architectures (e.g., GPU drivers)?
- How should home-manager handle platform-specific XDG configuration files (e.g., wayvnc configs that only apply to hetzner-sway)?
- What happens when nixpkgs updates break compatibility on one platform but not the other?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: M1 configuration MUST import the exact same base modules as hetzner-sway (development.nix, networking.nix, onepassword.nix, i3-project-daemon.nix, keyd.nix)
- **FR-002**: M1 configuration MUST import modules/desktop/sway.nix with identical configuration structure to hetzner-sway
- **FR-003**: M1 home-manager configuration MUST enable all user-level services enabled on hetzner-sway (walker, i3pm daemon, sway-config-manager, tmux, neovim)
- **FR-004**: M1 MUST use the same home-modules/ imports as hetzner-sway for shell configuration (bash, starship), editors (neovim), terminal (tmux), and tools (git, ssh)
- **FR-005**: Both configurations MUST use identical walker launcher configuration (bookmarks, search engines, custom commands, keybindings)
- **FR-006**: Both configurations MUST use identical i3pm project management configuration (app-registry.nix, project definitions, window filtering rules)
- **FR-007**: Both configurations MUST use identical sway-config-manager templates (keybindings.toml, window-rules.json, appearance.json defaults)
- **FR-008**: Platform-specific settings (display scaling, audio configuration, input devices) MUST be isolated using conditionals or separate hardware modules
- **FR-009**: M1 configuration MUST document all deviations from hetzner-sway with clear architectural rationale
- **FR-010**: Both configurations MUST use identical Sway compositor settings (focus_follows_mouse, focus_on_window_activation, mouse_warping, workspace naming)
- **FR-011**: M1 MUST include all hetzner-sway system packages (wl-clipboard, grim, slurp, mako, htop, btop, neofetch) where architecturally compatible
- **FR-012**: Both configurations MUST use identical systemd service definitions for i3-project-daemon, walker-daemon, sway-config-manager daemon
- **FR-013**: M1 MUST disable X11-specific services (XRDP, touchegg) that conflict with Sway/Wayland, matching hetzner-sway's lib.mkForce false directives
- **FR-014**: Both configurations MUST use greetd display manager for Sway session management with auto-login on hetzner-sway and tuigreet on M1
- **FR-015**: M1 MUST configure PipeWire audio identically to hetzner-sway (enable alsa, pulse, jack) excluding Tailscale audio streaming which is hetzner-specific

### Key Entities

- **Base Configuration** (`configurations/base.nix`): Shared core system settings inherited by both platforms
- **Platform Configuration** (`configurations/hetzner-sway.nix`, `configurations/m1.nix`): Platform-specific system configuration with hardware imports
- **Hardware Modules** (`hardware/m1.nix`, auto-generated hardware-configuration.nix): Hardware-specific settings isolated from application logic
- **Service Modules** (`modules/services/*.nix`): Reusable system service definitions shared across platforms
- **Desktop Modules** (`modules/desktop/sway.nix`): Desktop environment configuration with conditional platform handling
- **Home Manager Modules** (`home-modules/`): User environment configuration (shell, editors, terminal, desktop applications)
- **Dynamic Configuration Files** (`~/.config/sway/keybindings.toml`, `window-rules.json`, `appearance.json`): Runtime-managed Sway configuration via sway-config-manager
- **Application Registry** (`home-modules/desktop/app-registry.nix`): Centralized application metadata for i3pm project management
- **Architectural Differences**: Documented list of intentional deviations due to hardware/deployment differences (headless vs physical, x86 vs ARM, cloud vs laptop)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 95% or higher configuration parity between hetzner-sway and M1 as measured by module import overlap (excluding hardware-specific modules)
- **SC-002**: 100% home-manager module parity for user environment (shell, editors, terminal tools) as measured by identical XDG configuration files
- **SC-003**: Zero user-visible behavioral differences in i3pm project management workflows (project switching, window filtering, application launching) between platforms
- **SC-004**: 100% walker launcher feature parity (bookmarks, search engines, custom commands) as verified by identical elephant configuration files
- **SC-005**: Sway configuration hot-reload works identically on both platforms with <100ms latency as measured by sway-config-manager daemon logs
- **SC-006**: All intentional architectural differences are documented with rationale, with zero undocumented deviations found during configuration audit
- **SC-007**: System rebuilds succeed on both platforms without errors as verified by `nixos-rebuild dry-build` passing on both hetzner-sway and M1
- **SC-008**: Users can switch between platforms without relearning workflows as measured by zero workflow-related support issues after migration
- **SC-009**: Package availability is consistent (≥98%) across architectures as measured by successful installation of all non-architecture-specific packages
- **SC-010**: Configuration maintenance effort is reduced by 40% as measured by time to propagate a change to both platforms (target: single commit affects both)

## Assumptions

- M1 MacBook Pro is running NixOS with Asahi Linux kernel and Apple Silicon support (nixos-apple-silicon flake input)
- Both platforms use NixOS 24.11 or later with Sway Wayland compositor as primary desktop environment
- hetzner-sway serves as the "source of truth" configuration, with M1 adapting to match unless architecturally impossible
- User has administrative access to both systems and can rebuild configurations
- Hardware-specific differences (display, audio, input) are acceptable and should be clearly documented rather than eliminated
- Both systems have access to same nixpkgs channel/flake revision for consistency
- Architecture-specific packages (x86_64 vs aarch64) are acceptable when no cross-architecture alternative exists
- Headless-specific features (WayVNC multi-display, WLR_BACKENDS=headless) should NOT be applied to M1 physical display configuration
- Physical hardware features on M1 (Retina display, touchpad, WiFi) should NOT be simulated on hetzner-sway
- Service daemons (i3pm, walker, sway-config-manager) are architecture-independent and should behave identically

## Architectural Differences (Documented Exceptions)

The following differences are intentional due to fundamental architectural constraints:

1. **Display Configuration**:
   - Hetzner: Headless with 3 virtual outputs (HEADLESS-1/2/3) for VNC streaming
   - M1: Physical Retina display (eDP-1) with 2x scaling + optional external HDMI
   - Rationale: Deployment context (cloud server vs laptop) requires different display strategies

2. **Audio Configuration**:
   - Hetzner: Tailscale RTP audio streaming to remote device (services.tailscaleAudio)
   - M1: Local PipeWire audio output to built-in speakers/headphones
   - Rationale: Headless server has no local audio hardware, requires network streaming

3. **Boot Loader**:
   - Hetzner: GRUB with EFI support for cloud VM compatibility (nixos-anywhere deployment)
   - M1: systemd-boot for Apple Silicon with Asahi firmware (hardware.asahi.peripheralFirmwareDirectory)
   - Rationale: Different hardware boot requirements (virtual machine vs Apple Silicon)

4. **Network Configuration**:
   - Hetzner: DHCP with predictable interface names disabled (net.ifnames=0)
   - M1: NetworkManager with wpa_supplicant for WiFi management
   - Rationale: Ethernet-only cloud server vs laptop with WiFi requirements

5. **Input Devices**:
   - Hetzner: Disabled (WLR_LIBINPUT_NO_DEVICES=1) for headless operation
   - M1: libinput with touchpad natural scrolling, tap-to-click, gesture support
   - Rationale: Server has no physical input devices, laptop requires touchpad configuration

6. **Remote Access**:
   - Hetzner: WayVNC for Wayland VNC access (3 instances on ports 5900-5902)
   - M1: RustDesk for cross-platform remote desktop with direct IP access
   - Rationale: Different remote access strategies (server VNC vs peer-to-peer desktop sharing)

7. **Environment Variables**:
   - Hetzner: WLR_BACKENDS=headless, WLR_HEADLESS_OUTPUTS=3, WLR_RENDERER=pixman, GSK_RENDERER=cairo
   - M1: Standard Wayland variables without headless backend
   - Rationale: Headless Wayland compositor requirements vs physical display operation

8. **Greetd Configuration**:
   - Hetzner: Auto-login with inline script launching Sway with headless environment
   - M1: tuigreet interactive login prompt with Sway session selection
   - Rationale: Server requires unattended auto-login, laptop requires user authentication

9. **System Packages**:
   - Hetzner: Includes wlr-randr, wayvnc CLI tools for headless management
   - M1: Includes imagemagick, librsvg for PWA icon processing, RustDesk client
   - Rationale: Platform-specific operational requirements

10. **Swap Configuration**:
    - Hetzner: No swap configured (cloud VM with fixed memory allocation)
    - M1: 8GB swap file with vm.swappiness=10 for memory pressure relief
    - Rationale: Cloud VM memory is fixed, laptop benefits from swap for memory-intensive tasks

All other configuration should be identical between platforms. Any undocumented difference is a bug and should be filed as a configuration drift issue.
