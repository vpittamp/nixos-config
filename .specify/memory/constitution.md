<!--
Sync Impact Report:
- Version: 1.1.0 → 1.2.0 (MINOR - New principle added, existing principles expanded with i3wm/X11 focus)
- Modified principles:
  * Principle VIII: "Remote Desktop & Multi-Session Standards" - Enhanced
    - Added explicit X11 preference for RDP compatibility
    - Specified i3wm as reference window manager for multi-session isolation
    - Added clipboard manager integration requirements (clipcat)
  * Platform Support Standards: "Desktop Environment Transitions" - Expanded
    - Updated from KDE Plasma → i3wm migration to generalized tiling WM guidance
    - Added X11 vs Wayland decision criteria for remote desktop scenarios
    - Integrated clipcat clipboard manager as standard tool
- New principles created:
  * Principle IX: "Tiling Window Manager & Productivity Standards" (NEW)
    - Establishes i3wm as the standard tiling window manager
    - Keyboard-first workflow requirements
    - Workspace and session isolation standards
    - Integration requirements (rofi, i3wsr, clipcat, tmux)
- New best practices integrated:
  * Home-manager module structure (explicit imports, conditional features)
  * NixOS module option patterns (mkEnableOption, mkOption with types)
  * Configuration file generation via environment.etc
  * Package scoping discipline (system vs user vs module-specific)
  * Minimal X11 server configuration for headless RDP scenarios
- Updated sections:
  * Platform Support Standards - Changed Hetzner from "Full KDE desktop" to "i3 tiling WM"
  * Desktop Environment Transitions - Replaced KDE Plasma references with i3wm context
  * Testing Requirements - Updated Hetzner to reflect i3wm + xrdp + X11 architecture
- Templates requiring updates:
  ✅ .specify/templates/spec-template.md - no changes needed (principles remain compatible)
  ✅ .specify/templates/plan-template.md - Constitution Check section compatible with new principle
  ✅ .specify/templates/tasks-template.md - task organization aligns with new tiling WM principle
  ✅ .specify/templates/commands/ - no command-specific files requiring updates
- Follow-up TODOs:
  * Update CLAUDE.md to reflect i3wm as standard desktop (remove KDE Plasma references)
  * Update docs/HETZNER_NIXOS_INSTALL.md to document i3wm installation path
  * Consider creating docs/I3WM_SETUP.md for i3wm-specific configuration guidance
-->

# NixOS Modular Configuration Constitution

## Core Principles

### I. Modular Composition

Every configuration MUST be built from composable modules rather than monolithic files.

**Rules**:
- Common functionality MUST be extracted into reusable modules in `modules/`
- Platform-specific configurations MUST compose modules, not duplicate code
- Each module MUST have a single, clear responsibility (services, hardware, desktop)
- Configuration inheritance MUST follow: Base → Hardware → Services → Desktop → Target
- Modules MUST use proper NixOS option patterns: `mkEnableOption` for boolean enables, `mkOption` with explicit types for configuration values

**Rationale**: This project reduced from 46 files with 3,486 lines of duplication to ~25 modular files. Modular composition is the foundation that enables maintainability, consistency, and platform flexibility without code duplication.

### II. Reference Implementation Flexibility

A reference configuration serves as the canonical example for full-featured NixOS installations. The reference implementation MAY change when architectural requirements demand it.

**Rules**:
- Base configuration (`configurations/base.nix`) MUST be extracted from the current reference implementation's common functionality
- New features MUST be validated against the reference configuration first
- When evaluating a new reference configuration:
  * Document the specific technical limitations of the current reference
  * Research and validate the proposed alternative meets all core requirements
  * Test the migration path on at least one platform before full adoption
  * Update documentation to reflect the new reference architecture
- Breaking changes MUST be tested on the reference configuration before other platforms
- Documentation MUST clearly identify the current reference configuration

**Current Reference**: Hetzner configuration (`configurations/hetzner-i3.nix`) - full-featured NixOS with i3 tiling window manager on standard x86_64 hardware, optimized for remote desktop access via xrdp

**Rationale**: Originally, Hetzner provided a stable reference for KDE Plasma desktop deployments. The migration to i3wm + xrdp + X11 reflects the evolution toward keyboard-driven productivity workflows with superior multi-session RDP compatibility. This principle allows flexibility while maintaining the discipline of having a canonical reference.

### III. Test-Before-Apply (NON-NEGOTIABLE)

Every configuration change MUST be tested with `dry-build` before applying.

**Rules**:
- ALWAYS run `nixos-rebuild dry-build --flake .#<target>` before `switch`
- Build failures MUST be resolved before committing
- Breaking changes MUST be documented in commit messages
- Rollback procedures MUST be verified for critical changes
- Use `--show-trace` flag when debugging build errors for detailed stack traces

**Rationale**: NixOS is a production system configuration. Untested changes can break system boot, desktop environments, or critical services. The dry-build requirement ensures changes are evaluated before deployment, enabling safe rollbacks via NixOS generations.

### IV. Override Priority Discipline

Module options MUST use appropriate priority levels: `lib.mkDefault` for overrideable defaults, normal assignment for standard configuration, `lib.mkForce` only when override is mandatory.

**Rules**:
- Use `lib.mkDefault` in base modules for options that platforms should override
- Use normal assignment for typical module configuration
- Use `lib.mkForce` ONLY when the value must override all other definitions
- Document every `lib.mkForce` usage with a comment explaining why it's required
- Avoid option conflicts by choosing the appropriate priority level
- Test module composition with `nix eval` to verify override behavior

**Rationale**: Proper priority usage enables the modular composition hierarchy. Incorrect priority levels lead to hard-to-debug option conflicts and prevent platform-specific customization. The 45% file reduction achieved in this project relied on proper override mechanisms.

### V. Platform Flexibility Through Conditional Features

Modules MUST adapt to system capabilities through conditional logic rather than creating separate module variants.

**Rules**:
- Detect system capabilities with `config.services.xserver.enable or false` pattern
- Use `lib.mkIf` for conditional service configuration
- Use `lib.optionals` for conditional package lists
- Distinguish GUI vs headless deployments automatically
- Service modules MUST function correctly with or without desktop environments
- Desktop modules MUST detect window manager type and adapt accordingly

**Example**:
```nix
let
  hasGui = config.services.xserver.enable or false;
  hasI3 = config.services.i3wm.enable or false;
in {
  environment.systemPackages = with pkgs; [
    package-cli  # Always installed
  ] ++ lib.optionals hasGui [
    package-gui  # Only with GUI
  ] ++ lib.optionals hasI3 [
    rofi         # Only with i3wm
    i3wsr        # i3 workspace renamer
  ];
}
```

**Rationale**: A single module (e.g., `onepassword.nix`) can adapt to WSL (CLI-only), Hetzner (full GUI with i3), and containers (minimal) without duplication. Conditional features maintain consistency while supporting diverse deployment targets.

### VI. Declarative Configuration Over Imperative

All system configuration MUST be declared in Nix expressions; imperative post-install scripts are forbidden except for desktop environment settings capture during migration.

**Rules**:
- System packages MUST be declared in `environment.systemPackages` or module configurations
- Services MUST be configured via NixOS options, not manual systemd files
- User environments MUST use home-manager, not manual dotfile management
- Secrets MUST use 1Password integration or declarative secret management (sops-nix/agenix)
- Desktop environment configurations MUST be declared in home-manager or NixOS modules
- Configuration files MUST be generated via `environment.etc` or home-manager `home.file`
- i3 window manager configuration MUST be declared in `environment.etc."i3/config".text`
- Limited exception: Temporary capture scripts (e.g., `scripts/*-rc2nix.sh`) MAY be used to extract live desktop environment settings during migration, with the intent to refactor captured settings into declarative modules

**Rationale**: Declarative configuration is NixOS's core value proposition. It enables reproducible builds, atomic upgrades, and automatic rollbacks. Imperative changes create configuration drift and break the reproducibility guarantee. Configuration file generation via environment.etc ensures consistency and version control integration.

### VII. Documentation as Code

Every module, configuration change, and architectural decision MUST be documented alongside the code.

**Rules**:
- Complex modules MUST include header comments explaining purpose, dependencies, and options
- `docs/` MUST contain architecture documentation, setup guides, and troubleshooting
- `CLAUDE.md` MUST be the primary LLM navigation guide with quick start commands
- Breaking changes MUST update relevant documentation in the same commit
- Migration guides MUST be created for major structural changes (e.g., KDE Plasma → i3wm)
- Module options MUST include `description` fields for documentation generation

**Rationale**: This project's complexity demands clear documentation. LLM assistants, new contributors, and future maintainers rely on comprehensive guides to navigate the modular architecture effectively. Inline documentation via description fields enables automatic documentation generation.

### VIII. Remote Desktop & Multi-Session Standards

Remote desktop access MUST support multiple concurrent sessions with proper isolation, authentication, and resource management.

**Rules**:
- Multi-session support MUST allow 3-5 concurrent connections per user without disconnecting existing sessions
- Session isolation MUST ensure independent desktop environments (separate window managers, application states)
- Session persistence MUST maintain state across disconnections with automatic cleanup after 24 hours of idle time
- Authentication MUST support password-based access with optional SSH key authentication
- Display server MUST be X11 for mature RDP/xrdp compatibility (Wayland lacks stable multi-session RDP support)
- Window manager MUST support multi-session isolation (i3wm preferred for lightweight resource usage)
- Remote desktop configuration MUST preserve existing tool integrations (1Password, terminal customizations, browser extensions)
- Clipboard integration MUST work across RDP sessions using clipcat or equivalent X11-compatible clipboard manager
- Resource limits MUST be documented and enforced to prevent system exhaustion
- DISPLAY environment variable MUST be properly propagated to user services and applications

**Configuration**:
- Remote desktop service: xrdp with multi-session support enabled
- Display server: X11 (via `services.xserver.enable = true`)
- Window manager: i3wm (via custom `services.i3wm` module)
- Session management: Automatic cleanup policies, reconnection handling
- Clipboard manager: clipcat (started from i3 config to inherit DISPLAY variable)

**Rationale**: Remote development workstations require seamless multi-device access without workflow interruption. Microsoft Remote Desktop (RDP) is the standard cross-platform protocol. Multi-session support enables users to maintain separate contexts on different devices while sharing a single powerful remote system. X11 provides mature, stable RDP compatibility via xrdp, while Wayland's RDP support remains experimental. Session cleanup prevents resource exhaustion while maintaining reasonable persistence expectations.

### IX. Tiling Window Manager & Productivity Standards

Desktop environments MUST prioritize keyboard-driven workflows with efficient window management for developer productivity.

**Rules**:
- Window manager MUST be i3wm or compatible tiling window manager (sway for Wayland, bspwm/awesome as alternatives)
- Keyboard shortcuts MUST be declaratively configured and documented
- Workspace management MUST support dynamic naming with application-aware labels (via i3wsr)
- Application launcher MUST be keyboard-driven (rofi preferred for consistency and extensibility)
- Terminal emulator MUST support transparency, true color, and tmux integration (alacritty preferred)
- Clipboard manager MUST provide history access across all applications with keyboard shortcuts (clipcat via Win+V)
- Workspace naming MUST reflect running applications for context awareness (i3wsr with custom aliases)
- Window management MUST support floating windows for specific applications (e.g., dialogs, popups)
- Multi-monitor support MUST be configurable with declarative xrandr settings
- Session startup MUST be minimal and fast (<5 seconds to usable desktop)

**i3wm Integration Requirements**:
- `rofi`: Application launcher, window switcher, clipboard menu
- `i3wsr`: Dynamic workspace renaming based on window classes
- `clipcat`: Clipboard history manager with rofi integration
- `alacritty`: Primary terminal emulator
- `i3status`: Status bar with system information
- `i3lock`: Screen locking (optional, for physical access scenarios)

**Configuration Structure**:
```nix
# System module: modules/desktop/i3wm.nix
services.i3wm = {
  enable = true;
  package = pkgs.i3;
  extraPackages = [ pkgs.rofi pkgs.i3status ];
};

# Home-manager module: home-modules/desktop/i3.nix
# User-specific keybindings, workspace configuration, theme

# Home-manager module: home-modules/desktop/i3wsr.nix
# Application-aware workspace naming with custom aliases
```

**Keyboard Shortcuts (Standard Bindings)**:
- `Win+Return`: Open terminal
- `Win+D`: Application launcher (rofi)
- `Win+V`: Clipboard history (clipcat)
- `Win+F`: Fullscreen toggle
- `Ctrl+1-9`: Workspace switching (for RDP compatibility, avoids Win key issues)
- `Win+Shift+1-9`: Move window to workspace
- `Win+Shift+Q`: Close window
- `Win+H/V`: Split horizontal/vertical

**Rationale**: Tiling window managers maximize screen real estate and minimize mouse usage, critical for remote desktop scenarios where mouse precision is degraded. i3wm's minimal resource usage enables multiple concurrent sessions on a single server. Keyboard-first workflows improve productivity and reduce dependency on RDP's pointer handling. Dynamic workspace naming via i3wsr provides immediate context awareness across workspaces. Clipboard history via clipcat ensures seamless copy/paste workflow across applications and RDP sessions.

## Platform Support Standards

### Multi-Platform Compatibility

The configuration MUST support WSL2, Hetzner Cloud, Apple Silicon Macs (via Asahi Linux), and container deployments.

**Rules**:
- Target configurations MUST be defined in `configurations/` directory
- Hardware-specific settings MUST be isolated in `hardware/` modules
- Platform-specific packages MUST be added in target configurations with appropriate overrides
- Cross-platform features MUST be tested on at least two platforms before merging
- Containers MUST support minimal, essential, development, and full package profiles

**Testing Requirements**:
- WSL: Docker Desktop integration, VS Code Remote, 1Password CLI
- Hetzner: i3 tiling window manager, xrdp multi-session access, Tailscale VPN, development tools, clipcat clipboard manager
- M1: ARM64 optimizations, Wayland session (for native display), Retina display scaling, requires `--impure` flag
- Containers: Size constraints (<100MB minimal, <600MB development)

**Desktop Environment Transitions**:
When migrating desktop environments (e.g., KDE Plasma → i3wm, X11 → Wayland):
1. Research target environment's compatibility with existing tools and workflows
2. Evaluate display server requirements (X11 vs Wayland) based on remote desktop needs
3. For remote desktop scenarios: Prefer X11 for mature xrdp compatibility
4. For native hardware: Consider Wayland for better HiDPI and modern features
5. Test migration on reference platform first
6. Document configuration patterns and module structure
7. Validate all critical integrations (1Password, terminal tools, browser extensions, clipboard)
8. Update platform testing requirements to reflect new environment
9. Create migration documentation in `docs/MIGRATION.md`

**X11 vs Wayland Decision Criteria**:
- **Choose X11 when**:
  * Primary use case is remote desktop (RDP/xrdp)
  * Multi-session support is required
  * Mature tool compatibility is critical (screen sharing, recording, clipboard managers)
- **Choose Wayland when**:
  * Primary use case is native hardware (laptops, desktops)
  * HiDPI scaling and modern input methods are priorities
  * Security isolation between applications is required
  * Native touchpad gestures are important (e.g., M1 Mac)

## Security & Authentication Standards

### 1Password Integration

Secret management MUST use 1Password for centralized, secure credential storage.

**Rules**:
- SSH keys MUST be stored in 1Password vaults, not filesystem
- Git commit signing MUST use 1Password SSH agent
- GitHub/GitLab authentication MUST use 1Password credential helpers
- GUI installations (Hetzner, M1) MUST include 1Password desktop app
- Headless installations (WSL, containers) MUST use 1Password CLI
- Biometric authentication MUST be enabled where platform supports it
- Remote desktop sessions MUST have access to 1Password without re-authentication
- 1Password browser extension MUST be compatible with Firefox PWAs

**Configuration**:
- Module: `modules/services/onepassword.nix`
- Conditional GUI/CLI support based on `config.services.xserver.enable`
- PAM integration for system authentication
- Polkit rules for desktop authentication
- RDP session integration for persistent authentication state

### SSH Hardening

SSH access MUST use key-based authentication with rate limiting and fail2ban integration.

**Rules**:
- Password authentication MUST be disabled for SSH
- SSH keys MUST be managed via 1Password SSH agent
- Rate limiting MUST be configured on public-facing systems
- Fail2ban MUST be enabled on Hetzner and other exposed servers
- Tailscale VPN MUST be the primary access method for remote systems
- RDP authentication MAY use password-based access (separate from SSH) with optional SSH key support

## Package Management Standards

### Package Profiles

Package installations MUST be controlled by profile levels to manage system size and complexity.

**Profiles** (defined in `shared/package-lists.nix`):
- **minimal** (~100MB): Core utilities only - for containers
- **essential** (~275MB): Basic development tools - for CI/CD environments
- **development** (~600MB): Full development stack - for active development
- **full** (~1GB): Everything including Kubernetes tools - for complete workstations

**Rules**:
- Containers MUST use minimal or essential profiles
- Development systems MUST use development or full profiles
- New packages MUST be added to the appropriate profile level
- Package additions MUST justify their profile placement in commit messages

### Package Organization

Packages MUST be organized by scope: system-wide, user-specific, module-specific, or target-specific.

**Hierarchy**:
1. **System packages** (`system/packages.nix`): System-wide tools available to all users
2. **User packages** (`user/packages.nix`): User-specific tools installed via home-manager
3. **Module packages**: Packages defined within service/desktop modules for specific functionality
4. **Target packages**: Platform-specific additions in target configurations

**Rules**:
- Prefer module-specific package definitions for better encapsulation (e.g., `modules/desktop/i3wm.nix` includes rofi, alacritty)
- Use system packages for tools required by multiple modules
- Use user packages for development tools and personal utilities
- Use target packages ONLY for platform-specific requirements (e.g., wsl.exe on WSL)
- Avoid duplicate package declarations across modules

**Best Practice - Module Package Scoping**:
```nix
# modules/desktop/i3wm.nix
config = mkIf cfg.enable {
  environment.systemPackages = with pkgs; [
    cfg.package      # i3 itself
    alacritty       # Terminal for i3
    rofi            # Application launcher
  ] ++ cfg.extraPackages;  # Allow extension
};
```

## Home-Manager Standards

### Module Structure

Home-manager modules MUST follow consistent structure and import patterns.

**Rules**:
- Each home-manager module MUST declare its inputs: `{ config, lib, pkgs, ... }:`
- User-specific desktop configuration MUST live in `home-modules/desktop/`
- User-specific tool configuration MUST live in `home-modules/tools/`
- Modules MUST use `lib.mkIf` for conditional feature activation
- Modules MUST expose options via home-manager option system when configurable
- Configuration files MUST be generated via `home.file` or `xdg.configFile`

**Example Module Structure**:
```nix
# home-modules/tools/clipcat.nix
{ config, lib, pkgs, ... }:

{
  services.clipcat = {
    enable = true;
    package = pkgs.clipcat;

    daemonSettings = {
      max_history = 100;
      # ... configuration
    };
  };

  # Ensure dependencies available
  home.packages = with pkgs; [ xclip xsel ];
}
```

### Configuration File Generation

Configuration files MUST be generated declaratively, not copied from external sources.

**Rules**:
- i3 config MUST be generated via `environment.etc."i3/config".text` (system-level) or `xdg.configFile."i3/config".text` (user-level)
- Dotfiles MUST be generated via home-manager's `home.file` or `xdg.configFile`
- Template-based generation MUST use Nix string interpolation with `${}` for variable substitution
- Binary paths MUST use `${pkgs.package}/bin/binary` format for reproducibility
- Scripts MUST be generated with proper shebang and execute permissions

**Example**:
```nix
environment.etc."i3/config".text = ''
  # i3 configuration
  set $mod Mod4
  bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
  bindsym $mod+d exec ${pkgs.rofi}/bin/rofi -show drun
'';
```

## Governance

This Constitution supersedes all other development practices and conventions. Any configuration change, module addition, or architectural modification MUST comply with these principles.

### Amendment Procedure

1. **Proposal**: Document proposed change with rationale in a GitHub issue or pull request
2. **Review**: Changes affecting Core Principles require architectural review and testing on all platforms
3. **Approval**: Amendments must be tested via `dry-build` on WSL, Hetzner, M1, and containers
4. **Migration Plan**: Breaking changes require migration documentation in `docs/MIGRATION.md`
5. **Version Update**: Constitution version increments follow semantic versioning
6. **Propagation**: Update dependent templates, documentation, and command files

### Semantic Versioning

- **MAJOR**: Backward incompatible changes (principle removal, governance redefinition)
- **MINOR**: New principles added or materially expanded guidance
- **PATCH**: Clarifications, wording improvements, typo fixes, non-semantic refinements

### Compliance Verification

All pull requests and configuration rebuilds MUST verify compliance with:
- ✅ Modular composition - no code duplication
- ✅ Test-before-apply - `dry-build` executed and passed
- ✅ Override priorities - `mkDefault` and `mkForce` used appropriately
- ✅ Conditional features - modules adapt to system capabilities
- ✅ Declarative configuration - no imperative post-install scripts (except temporary desktop capture)
- ✅ Documentation updates - architectural changes reflected in docs
- ✅ Security standards - secrets via 1Password, SSH hardening maintained
- ✅ Remote desktop standards - multi-session support, session isolation, resource limits
- ✅ Tiling WM standards - i3wm configuration, keyboard-first workflows, workspace isolation

### Complexity Justification

Any violation of simplicity principles (e.g., adding a 5th platform target, creating deep inheritance hierarchies, introducing abstraction layers) MUST be justified by documenting:
- **Current Need**: Specific problem requiring the complexity
- **Simpler Alternative Rejected**: Why simpler approaches were insufficient
- **Long-term Maintenance**: How the complexity will be managed and documented

**Version**: 1.2.0 | **Ratified**: 2025-10-14 | **Last Amended**: 2025-10-17
