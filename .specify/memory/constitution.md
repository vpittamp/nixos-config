<!--
Sync Impact Report:
- Version: Initial → 1.0.0 (INITIAL RELEASE)
- New principles created: All principles are new
- Added sections: All sections are new
- Templates updated:
  ✅ .specify/templates/spec-template.md - aligned with modular architecture principle
  ✅ .specify/templates/plan-template.md - Constitution Check section references this document
  ✅ .specify/templates/tasks-template.md - task organization aligns with modularity
  ⚠ Command files - none found in .specify/templates/commands/
- Follow-up TODOs: None - all fields completed
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

### II. Hetzner as Reference Implementation

The Hetzner configuration (`configurations/hetzner.nix`) serves as the canonical reference for full-featured NixOS installations.

**Rules**:
- Base configuration (`configurations/base.nix`) MUST be extracted from Hetzner's common functionality
- New features MUST be validated against Hetzner configuration first
- Breaking changes MUST be tested on Hetzner before other platforms
- Documentation MUST reference Hetzner as the primary example

**Rationale**: Hetzner represents a complete NixOS installation with both server and desktop components on standard x86_64 hardware. It provides the most comprehensive reference point for testing and validating new features.

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

All system configuration MUST be declared in Nix expressions; imperative post-install scripts are forbidden except for Plasma user settings capture.

**Rules**:
- System packages MUST be declared in `environment.systemPackages` or module configurations
- Services MUST be configured via NixOS options, not manual systemd files
- User environments MUST use home-manager, not manual dotfile management
- Secrets MUST use 1Password integration or declarative secret management (sops-nix/agenix)
- The ONLY exception: `scripts/plasma-rc2nix.sh` for capturing live Plasma tweaks before refactoring into declarative modules

**Rationale**: Declarative configuration is NixOS's core value proposition. It enables reproducible builds, atomic upgrades, and automatic rollbacks. Imperative changes create configuration drift and break the reproducibility guarantee.

### VII. Documentation as Code

Every module, configuration change, and architectural decision MUST be documented alongside the code.

**Rules**:
- Complex modules MUST include header comments explaining purpose, dependencies, and options
- `docs/` MUST contain architecture documentation, setup guides, and troubleshooting
- `CLAUDE.md` MUST be the primary LLM navigation guide with quick start commands
- Breaking changes MUST update relevant documentation in the same commit
- Migration guides MUST be created for major structural changes

**Rationale**: This project's complexity demands clear documentation. LLM assistants, new contributors, and future maintainers rely on comprehensive guides to navigate the modular architecture effectively.

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
- Hetzner: Full KDE desktop, RDP access, Tailscale VPN, development tools
- M1: ARM64 optimizations, Wayland session, Retina display scaling, requires `--impure` flag
- Containers: Size constraints (<100MB minimal, <600MB development)

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

**Configuration**:
- Module: `modules/services/onepassword.nix`
- Conditional GUI/CLI support based on `config.services.xserver.enable`
- PAM integration for system authentication
- Polkit rules for desktop authentication

### SSH Hardening

SSH access MUST use key-based authentication with rate limiting and fail2ban integration.

**Rules**:
- Password authentication MUST be disabled
- SSH keys MUST be managed via 1Password SSH agent
- Rate limiting MUST be configured on public-facing systems
- Fail2ban MUST be enabled on Hetzner and other exposed servers
- Tailscale VPN MUST be the primary access method for remote systems

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
- ✅ Declarative configuration - no imperative post-install scripts (except Plasma capture)
- ✅ Documentation updates - architectural changes reflected in docs
- ✅ Security standards - secrets via 1Password, SSH hardening maintained

### Complexity Justification

Any violation of simplicity principles (e.g., adding a 5th platform target, creating deep inheritance hierarchies, introducing abstraction layers) MUST be justified by documenting:
- **Current Need**: Specific problem requiring the complexity
- **Simpler Alternative Rejected**: Why simpler approaches were insufficient
- **Long-term Maintenance**: How the complexity will be managed and documented

**Version**: 1.0.0 | **Ratified**: 2025-10-14 | **Last Amended**: 2025-10-14
