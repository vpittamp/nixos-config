# Feature Specification: NixOS Configuration Cleanup and Consolidation

**Feature Branch**: `089-nixos-home-manager-cleanup`
**Created**: 2025-11-22
**Status**: Draft
**Input**: User description: "Transform our full nixos / home-manager / supporting modules by exploring dependencies, structure of our code, and identifying modules/code/commands that are legacy/outdated/unused and are not necessary in our project. Once we do a full, comprehensive analysis, we should look at fully discarding files/modules/code that are not needed in our project. We don't care about backwards compatibility. Remove fully items that are not needed. We should test by rebuilding and making sure we didn't lose functionality. Also, we should identify duplicate code, and opportunities to consolidate, and streamline aspects of our configuration."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove Deprecated Legacy Modules (Priority: P1)

As a system maintainer, I need to remove all deprecated modules supporting obsolete features (i3wm, X11/RDP, KDE Plasma, WSL) so that the codebase only contains code relevant to the current Sway/Wayland-based systems, reducing maintenance burden and confusion.

**Why this priority**: Highest impact on codebase clarity and lowest risk. These modules are completely unused by active configurations (hetzner-sway, m1). Removal represents 1,000+ LOC of dead code with zero functional impact.

**Independent Test**: Can be fully tested by removing the identified modules, running `sudo nixos-rebuild dry-build --flake .#hetzner-sway` and `sudo nixos-rebuild dry-build --flake .#m1 --impure`, and verifying both succeed without errors. Delivers immediate value through reduced codebase size and clearer architecture.

**Acceptance Scenarios**:

1. **Given** the system contains 11 unused modules supporting deprecated features, **When** all deprecated modules are deleted from the repository, **Then** both active system configurations (hetzner-sway and m1) successfully complete dry-build without import errors
2. **Given** backup files exist scattered throughout the codebase, **When** all 8 backup files are deleted, **Then** the repository contains only version-controlled source files with no .backup* files remaining
3. **Given** unused flake inputs remain declared (plasma-manager, potentially others), **When** unused inputs are removed from flake.nix, **Then** `nix flake check` passes and flake.lock updates reflect the removal
4. **Given** the deprecated hetzner.nix configuration exists (i3-based variant), **When** it is moved to archived/obsolete-configs/, **Then** it no longer appears in active configurations but remains available for historical reference

---

### User Story 2 - Consolidate Duplicate Modules (Priority: P2)

As a system maintainer, I need to consolidate duplicate functionality across multiple modules (1Password modules, Firefox+PWA modules, hetzner-sway configuration variants) so that configuration changes only need to be made in one place, reducing inconsistencies and maintenance effort.

**Why this priority**: Moderate impact with moderate risk. Consolidation requires refactoring to ensure no functionality is lost, but delivers ongoing benefits by establishing single sources of truth for shared functionality.

**Independent Test**: Can be fully tested by consolidating each module group independently (e.g., just 1Password modules first), rebuilding the affected systems, and verifying all original functionality remains intact. Each consolidation delivers incremental value through reduced duplication.

**Acceptance Scenarios**:

1. **Given** three separate 1Password modules exist with overlapping environment variables and polkit configuration, **When** they are consolidated into a single module with feature flags, **Then** systems using 1Password maintain all original functionality with 150-180 fewer lines of code
2. **Given** Firefox and Firefox-PWA 1Password modules have duplicate configuration, **When** they are merged with an `enablePWA` feature flag, **Then** both Firefox-only and Firefox+PWA systems work correctly with 40-50 fewer lines of code
3. **Given** four hetzner-sway configuration variants exist (production, VM image, minimal, ultra-minimal), **When** they are consolidated into a parameterized configuration or builder pattern, **Then** all four use cases remain supported with reduced code duplication
4. **Given** the consolidated modules are in use, **When** a configuration change is needed, **Then** the change only needs to be made in one location instead of multiple files

---

### User Story 3 - Document and Validate Active System Boundary (Priority: P3)

As a system maintainer, I need clear documentation of what is actively used versus archived so that future contributors can confidently make changes without fear of breaking unused features, and so the codebase boundary between active and archived code is explicit.

**Why this priority**: Lowest immediate technical impact but important for long-term maintainability. Provides clarity and prevents reintroduction of deprecated patterns.

**Independent Test**: Can be fully tested by verifying that documentation accurately reflects the codebase state (only hetzner-sway and m1 listed as active targets, deprecated features clearly marked as archived), and that all active configurations successfully rebuild. Delivers value through improved developer experience.

**Acceptance Scenarios**:

1. **Given** the cleanup is complete, **When** reviewing project documentation (CLAUDE.md, README.md), **Then** only active configurations (hetzner-sway, m1) are listed as current targets with deprecated targets clearly marked as archived
2. **Given** modules supporting deprecated features have been removed or archived, **When** examining the modules/ directory structure, **Then** only modules supporting active Sway/Wayland systems remain in the main codebase
3. **Given** the codebase has been cleaned up, **When** a new contributor examines the repository, **Then** they can quickly identify the two active system targets and their associated configuration without encountering confusing deprecated code
4. **Given** archived features are documented, **When** someone needs to reference legacy implementations, **Then** they can find the archived code with clear explanations of why it was deprecated

---

### Edge Cases

- What happens when a module appears unused but is actually imported indirectly through a chain of imports? *(Validation: Use `nix flake show` and trace all imports before deletion)*
- How does the system handle flake inputs that are declared but appear unused? *(Some inputs may be used by flake outputs like devShells that aren't tested by dry-build)*
- What if consolidated modules need to support different behavior for different targets? *(Use feature flags and target-specific conditionals rather than separate modules)*
- What happens to feature documentation in specs/ directories for deprecated features? *(Keep in specs/ for historical reference but mark as deprecated in top-level index)*
- How do we ensure no system-specific hardware detection logic is lost during consolidation? *(Test both hetzner-sway and m1 targets independently, including hardware-specific features like M1 Asahi firmware, Tailscale, etc.)*

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST successfully build both active configurations (hetzner-sway, m1) after any cleanup changes
- **FR-002**: Cleanup process MUST preserve all functionality currently working in active configurations (hetzner-sway, m1)
- **FR-003**: System MUST remove all modules that exclusively support deprecated features (i3wm, X11/RDP, KDE Plasma, WSL)
- **FR-004**: System MUST delete all backup files from the repository (relying on git for version history)
- **FR-005**: System MUST consolidate duplicate 1Password configuration into a single module with feature flags
- **FR-006**: System MUST consolidate Firefox and Firefox-PWA modules into a unified module with an `enablePWA` flag
- **FR-007**: System MUST reduce or eliminate duplication across hetzner-sway configuration variants (production, image, minimal, ultra-minimal)
- **FR-008**: System MUST remove unused flake inputs from flake.nix while preserving all actively-used inputs
- **FR-009**: System MUST move deprecated but potentially-reference-worthy configurations to an archived/ directory structure
- **FR-010**: Documentation MUST clearly identify only hetzner-sway and m1 as active system targets
- **FR-011**: System MUST validate that consolidated modules support all original use cases with feature flags or conditionals
- **FR-012**: Testing process MUST include dry-build validation for both targets before and after each major change
- **FR-013**: System MUST maintain separation between NixOS system modules (modules/) and home-manager user modules (home-modules/)
- **FR-014**: Cleanup MUST not remove or modify active features (Features 001-088 as documented in CLAUDE.md)
- **FR-015**: System MUST preserve all hardware-specific configuration (M1 Asahi firmware support, WayVNC setup, Tailscale integration)

### Key Entities

- **Active System Configuration**: Represents a buildable NixOS system (hetzner-sway, m1) with specific hardware and software requirements
- **Module**: A reusable Nix configuration file providing specific functionality, categorized as system module (modules/) or home module (home-modules/)
- **Deprecated Feature**: A previously-supported capability (i3wm, X11/RDP, KDE Plasma, WSL) that has been replaced by current implementations (Sway/Wayland)
- **Flake Input**: An external dependency declared in flake.nix, either actively used (nixpkgs, home-manager) or potentially unused (plasma-manager)
- **Configuration Variant**: Different versions of the same system for different purposes (production, VM image, minimal boot, development)
- **Backup File**: A .backup* file representing a snapshot that should be removed (git provides version history)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Both active system configurations (hetzner-sway and m1) successfully complete `nixos-rebuild dry-build` without errors after all cleanup changes
- **SC-002**: Codebase size is reduced by 1,200-1,500 lines of code (approximately 15-20% of system modules)
- **SC-003**: At least 20 files are moved to archived/ directories or deleted entirely
- **SC-004**: Zero backup files (.backup*) remain in the active codebase
- **SC-005**: All duplicate 1Password configuration is consolidated into a single module, reducing related code by 150-180 lines
- **SC-006**: Firefox and Firefox-PWA modules are merged into one module with feature flags, reducing related code by 40-50 lines
- **SC-007**: Configuration changes to consolidated modules require updates in only one location instead of multiple files
- **SC-008**: All modules in modules/ and home-modules/ directories support only active Sway/Wayland-based systems
- **SC-009**: `nix flake check` passes successfully after flake input cleanup
- **SC-010**: Project documentation (CLAUDE.md) accurately reflects only active targets (hetzner-sway, m1) without mentioning deprecated targets as current options
- **SC-011**: Each major cleanup phase (legacy removal, consolidation, documentation) can be tested and validated independently
- **SC-012**: All active features documented in CLAUDE.md (Features 001-088) continue to function correctly after cleanup
