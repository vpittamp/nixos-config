<!--
  ============================================================================
  Sync Impact Report
  ============================================================================
  Version: 0.0.0 → 1.0.0 (INITIAL RATIFICATION)

  Changes:
  - Initial constitution creation for nixos-config project
  - Established 7 core principles for NixOS configuration management
  - Defined governance structure

  Principles Created:
  1. Declarative Configuration
  2. Test-First Deployment (Non-Negotiable)
  3. Modular Composition
  4. Platform Compatibility
  5. Documentation Completeness
  6. Single Source of Truth
  7. Reproducible Builds

  Template Status:
  ✅ plan-template.md - Constitution Check section verified
  ✅ spec-template.md - Requirements alignment verified
  ✅ tasks-template.md - Task categorization aligned
  ⚠️  No command files found in .specify/templates/commands/

  Follow-up TODOs:
  - None - all placeholders filled

  ============================================================================
-->

# NixOS Configuration Constitution

## Core Principles

### I. Declarative Configuration

All system state MUST be declared in Nix configuration files. No imperative system modifications outside of Nix declarations are permitted in production configurations.

**Rationale**: Declarative configuration ensures reproducibility, version control, and prevents configuration drift. This is fundamental to NixOS philosophy and enables reliable multi-platform deployments.

**Requirements**:
- All packages declared in appropriate module files
- All services configured through NixOS options
- User environment managed via home-manager
- No manual system modifications that cannot be reproduced from flake

### II. Test-First Deployment (NON-NEGOTIABLE)

All configuration changes MUST be tested with `nixos-rebuild dry-build` before applying with `switch` or `boot`. No exceptions.

**Rationale**: NixOS configurations can break boot or critical system functionality. Dry builds catch syntax errors, missing dependencies, and option conflicts before they affect running systems. This is especially critical for remote systems (Hetzner) and multi-platform configurations where debugging is costly.

**Requirements**:
- Run `nixos-rebuild dry-build --flake .#<target>` before every `switch`
- For remote deployments, test locally first when possible
- Document any `--impure` flag requirements (e.g., M1 firmware access)
- Use `--show-trace` for debugging when dry-build fails

### III. Modular Composition

Configuration MUST follow the established modular hierarchy. Each module serves a single purpose and can be independently enabled/disabled.

**Rationale**: The project reduced from 46 to 25 .nix files by eliminating duplication through modularity. This architecture enables platform-specific configurations to share common base functionality while maintaining clear separation of concerns.

**Requirements**:
- Base configuration (`configurations/base.nix`) provides core settings
- Hardware modules (`hardware/*.nix`) contain platform-specific settings only
- Service modules (`modules/services/*.nix`) are independently toggleable
- Desktop modules (`modules/desktop/*.nix`) are optional and conditional
- Use `lib.mkDefault` for overrideable defaults, `lib.mkForce` only when mandatory
- No duplication - extract common patterns into shared modules

### IV. Platform Compatibility

Changes MUST maintain compatibility across all supported platforms unless explicitly scoped to one platform.

**Supported Platforms**:
- WSL2 (Windows Subsystem for Linux)
- Hetzner Cloud (x86_64 server)
- Apple Silicon M1/M2 (aarch64-linux via Asahi)
- Containers (Docker/Kubernetes)
- Darwin (macOS via home-manager only)

**Requirements**:
- Test changes on target platform before committing
- Use conditional logic for platform-specific features (e.g., GUI vs headless)
- Document platform-specific requirements in module comments
- Keep platform-agnostic logic in base modules

### V. Documentation Completeness

All significant configuration changes MUST be documented in appropriate files.

**Documentation Requirements**:
- `CLAUDE.md` - LLM-optimized navigation and common tasks (MUST be updated for major changes)
- `README.md` - User-facing overview and quick start
- Module comments - Explain purpose and key options for each module
- `docs/*.md` - Platform-specific guides and troubleshooting

**Rationale**: This is a complex multi-platform configuration. Documentation ensures maintainability, helps users understand the system, and provides context for future changes (including AI assistants).

### VI. Single Source of Truth

Avoid duplication by extracting common patterns into modules. When the same configuration appears in multiple places, it belongs in a shared module.

**Requirements**:
- Shared packages in `shared/package-lists.nix` organized by profile
- Common service configurations in reusable modules
- Platform-specific overrides only in platform modules
- No copy-paste between configurations

**Rationale**: Duplication leads to inconsistency and maintenance burden. The 2024-09 consolidation eliminated 3,486 lines of duplicate code - this principle prevents regression.

### VII. Reproducible Builds

All builds MUST be reproducible from the flake. Track sufficient metadata to recreate any deployed configuration.

**Requirements**:
- Flake inputs pinned with lock file
- Git commit metadata tracked in build (`system.configurationRevision`)
- Build metadata available at `/etc/nixos-metadata`
- Document nixpkgs revision for each deployment

**Rationale**: Enables rollback, debugging, and exact reproduction of any deployed system. Critical for production systems and troubleshooting platform-specific issues.

## Development Workflow

### Configuration Changes

1. **Branch**: Create feature branch with descriptive name
2. **Edit**: Modify appropriate module(s) following modular hierarchy
3. **Test**: Run `nixos-rebuild dry-build --flake .#<target>`
4. **Document**: Update CLAUDE.md, README.md, or module comments as needed
5. **Apply**: Run `nixos-rebuild switch --flake .#<target>` after successful dry-build
6. **Verify**: Confirm system functionality after switch
7. **Commit**: Commit with clear message explaining change and rationale

### Adding New Features

1. **Scope**: Determine which platforms need the feature
2. **Module**: Create new module or extend existing in `modules/`
3. **Import**: Add module import to relevant platform configurations
4. **Options**: Use proper option types and defaults (`lib.mkDefault` for overrides)
5. **Test**: Dry-build on all affected platforms
6. **Document**: Add to CLAUDE.md with usage examples

### Multi-Platform Changes

1. **Base First**: Add to `configurations/base.nix` if applies to all platforms
2. **Conditional Logic**: Use `osConfig`, `lib.mkIf`, or platform checks for platform-specific behavior
3. **Test All**: Dry-build on each affected platform before committing
4. **Document Platform Differences**: Note any platform-specific requirements

## Quality Gates

### Pre-Commit Requirements

- [ ] All affected platforms pass `dry-build`
- [ ] No syntax errors (`nix flake check` passes)
- [ ] Documentation updated if needed
- [ ] Commit message explains "why" not just "what"

### Pre-Deployment Requirements

- [ ] Dry-build successful on target platform
- [ ] No breaking changes to other platforms
- [ ] Rollback plan identified (previous generation or git commit)
- [ ] Remote systems: Test locally first when possible

## Governance

### Constitution Authority

This constitution supersedes all other development practices. All configuration changes, code reviews, and architectural decisions MUST verify compliance with these principles.

### Amendment Process

1. **Proposal**: Document proposed change with rationale
2. **Review**: Discuss impact on existing configurations and principles
3. **Update**: Modify constitution with version increment (see versioning rules below)
4. **Propagate**: Update dependent templates and documentation
5. **Ratify**: Commit with clear amendment message

### Versioning Rules

Constitution version follows semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Backward-incompatible changes (removing/redefining principles, changing fundamental architecture)
- **MINOR**: New principles added or materially expanded guidance (e.g., adding new platform requirements)
- **PATCH**: Clarifications, wording improvements, typo fixes (no semantic change to rules)

### Complexity Justification

Any violation of these principles (e.g., duplication, imperative configuration, untested deployment) MUST be justified with:
1. Specific technical reason why principle cannot be followed
2. Simpler alternatives considered and why they're insufficient
3. Plan to resolve violation in future (if temporary)

### Compliance Review

- All PRs/commits reviewed for constitutional compliance
- Unjustified complexity rejected
- Platform-breaking changes require multi-platform testing evidence

**Version**: 1.0.0 | **Ratified**: 2025-10-13 | **Last Amended**: 2025-10-13
