<!--
Sync Impact Report:
- Version: 1.0.0 → 1.1.0 (MINOR - New principle added, existing principles expanded)
- Modified principles:
  * Principle II: "Hetzner as Reference Implementation" → "Reference Implementation Flexibility"
    - Relaxed requirement to allow migration away from Hetzner base when necessary
    - Added guidance for evaluating alternative reference configurations
  * Principle VI: "Declarative Configuration Over Imperative" - Updated exception language
    - Removed Plasma-specific mention, generalized to "desktop environment settings capture"
- New principles created:
  * Principle VIII: "Remote Desktop & Multi-Session Standards" (NEW)
    - Addresses xrdp multi-session requirements
    - Session isolation and resource management
    - Authentication and security standards
- Expanded sections:
  * Platform Support Standards - Updated Hetzner testing requirements to reflect i3wm transition
  * Platform Support Standards - Added guidance for evaluating desktop environment changes
- Templates requiring updates:
  ✅ .specify/templates/spec-template.md - no changes needed (principles remain compatible)
  ✅ .specify/templates/plan-template.md - Constitution Check section compatible with new principle
  ✅ .specify/templates/tasks-template.md - task organization aligns with new remote desktop principle
  ⚠ Command files - none found in .specify/templates/commands/
- Follow-up TODOs: Update docs/HETZNER_NIXOS_INSTALL.md to reflect potential i3wm migration path
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

**Current Reference**: Hetzner configuration (`configurations/hetzner.nix`) - full-featured NixOS on standard x86_64 hardware

**Rationale**: Originally, Hetzner provided a stable reference for KDE Plasma desktop deployments. As requirements evolve (e.g., i3wm + multi-session RDP), the reference may need to migrate to a configuration better suited to new architectural patterns. This principle allows flexibility while maintaining the discipline of having a canonical reference.

### III. Test-Before-Apply (NON-NEGOTIABLE)

Every configuration change MUST be tested with `dry-build` before applying.

**Rules**:
- ALWAYS run `nixos-rebuild dry-build --flake .#<target>` before `switch`
- Build failures MUST be resolved before committing
- Breaking changes MUST be documented in commit messages
- Rollback procedures MUST be verified for critical changes

**Rationale**: NixOS is a production system configuration. Untested changes can break system boot, desktop environments, or critical services. The dry-build requirement ensures changes are evaluated before deployment, enabling safe rollbacks via NixOS generations.

### IV. Override Priority Discipline

Module options MUST use appropriate priority levels: `lib.mkDefault` for overrideable defaults, normal assignment for standard configuration, `lib.mkForce` only when override is mandatory.

**Rules**:
- Use `lib.mkDefault` in base modules for options that platforms should override
- Use normal assignment for typical module configuration
- Use `lib.mkForce` ONLY when the value must override all other definitions
- Document every `lib.mkForce` usage with a comment explaining why it's required
- Avoid option conflicts by choosing the appropriate priority level

**Rationale**: Proper priority usage enables the modular composition hierarchy. Incorrect priority levels lead to hard-to-debug option conflicts and prevent platform-specific customization. The 45% file reduction achieved in this project relied on proper override mechanisms.

### V. Platform Flexibility Through Conditional Features

Modules MUST adapt to system capabilities through conditional logic rather than creating separate module variants.

**Rules**:
- Detect system capabilities with `config.services.xserver.enable or false` pattern
- Use `lib.mkIf` for conditional service configuration
- Use `lib.optionals` for conditional package lists
- Distinguish GUI vs headless deployments automatically
- Service modules MUST function correctly with or without desktop environments

**Example**:
```nix
let
  hasGui = config.services.xserver.enable or false;
in {
  environment.systemPackages = with pkgs; [
    package-cli  # Always installed
  ] ++ lib.optionals hasGui [
    package-gui  # Only with GUI
  ];
}
```

**Rationale**: A single module (e.g., `onepassword.nix`) can adapt to WSL (CLI-only), Hetzner (full GUI), and containers (minimal) without duplication. Conditional features maintain consistency while supporting diverse deployment targets.

### VI. Declarative Configuration Over Imperative

All system configuration MUST be declared in Nix expressions; imperative post-install scripts are forbidden except for desktop environment settings capture during migration.

**Rules**:
- System packages MUST be declared in `environment.systemPackages` or module configurations
- Services MUST be configured via NixOS options, not manual systemd files
- User environments MUST use home-manager, not manual dotfile management
- Secrets MUST use 1Password integration or declarative secret management (sops-nix/agenix)
- Desktop environment configurations MUST be declared in home-manager or NixOS modules
- Limited exception: Temporary capture scripts (e.g., `scripts/*-rc2nix.sh`) MAY be used to extract live desktop environment settings during migration, with the intent to refactor captured settings into declarative modules

**Rationale**: Declarative configuration is NixOS's core value proposition. It enables reproducible builds, atomic upgrades, and automatic rollbacks. Imperative changes create configuration drift and break the reproducibility guarantee. Capture scripts serve as a bridge during migrations but should not remain as permanent solutions.

### VII. Documentation as Code

Every module, configuration change, and architectural decision MUST be documented alongside the code.

**Rules**:
- Complex modules MUST include header comments explaining purpose, dependencies, and options
- `docs/` MUST contain architecture documentation, setup guides, and troubleshooting
- `CLAUDE.md` MUST be the primary LLM navigation guide with quick start commands
- Breaking changes MUST update relevant documentation in the same commit
- Migration guides MUST be created for major structural changes

**Rationale**: This project's complexity demands clear documentation. LLM assistants, new contributors, and future maintainers rely on comprehensive guides to navigate the modular architecture effectively.

### VIII. Remote Desktop & Multi-Session Standards

Remote desktop access MUST support multiple concurrent sessions with proper isolation, authentication, and resource management.

**Rules**:
- Multi-session support MUST allow 3-5 concurrent connections per user without disconnecting existing sessions
- Session isolation MUST ensure independent desktop environments (separate window managers, application states)
- Session persistence MUST maintain state across disconnections with automatic cleanup after 24 hours of idle time
- Authentication MUST support password-based access with optional SSH key authentication
- Display server choice MUST prioritize RDP/xrdp compatibility (X11 preferred for mature tooling)
- Remote desktop configuration MUST preserve existing tool integrations (1Password, terminal customizations, browser extensions)
- Resource limits MUST be documented and enforced to prevent system exhaustion

**Configuration**:
- Remote desktop service: xrdp or compatible multi-session RDP server
- Display server: X11 (for mature RDP compatibility and tool support)
- Window manager: Must support multi-session isolation (i3wm, other tiling WMs)
- Session management: Automatic cleanup policies, reconnection handling

**Rationale**: Remote development workstations require seamless multi-device access without workflow interruption. Microsoft Remote Desktop (RDP) is the standard cross-platform protocol. Multi-session support enables users to maintain separate contexts on different devices while sharing a single powerful remote system. Session cleanup prevents resource exhaustion while maintaining reasonable persistence expectations.

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
- Hetzner: Full desktop environment (currently transitioning from KDE Plasma to i3wm), RDP multi-session access, Tailscale VPN, development tools
- M1: ARM64 optimizations, Wayland session, Retina display scaling, requires `--impure` flag
- Containers: Size constraints (<100MB minimal, <600MB development)

**Desktop Environment Transitions**:
When migrating desktop environments (e.g., KDE Plasma → i3wm):
1. Research target environment's compatibility with existing tools and workflows
2. Evaluate reference configuration suitability (may trigger Principle II evaluation)
3. Test migration on reference platform first
4. Document configuration patterns and module structure
5. Validate all critical integrations (1Password, terminal tools, browser extensions)
6. Update platform testing requirements to reflect new environment

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
- Prefer module-specific package definitions for better encapsulation
- Use system packages for tools required by multiple modules
- Use user packages for development tools and personal utilities
- Use target packages ONLY for platform-specific requirements (e.g., wsl.exe on WSL)

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

### Complexity Justification

Any violation of simplicity principles (e.g., adding a 5th platform target, creating deep inheritance hierarchies, introducing abstraction layers) MUST be justified by documenting:
- **Current Need**: Specific problem requiring the complexity
- **Simpler Alternative Rejected**: Why simpler approaches were insufficient
- **Long-term Maintenance**: How the complexity will be managed and documented

**Version**: 1.1.0 | **Ratified**: 2025-10-14 | **Last Amended**: 2025-10-16
