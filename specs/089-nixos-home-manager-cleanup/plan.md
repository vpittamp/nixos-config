# Implementation Plan: NixOS Configuration Cleanup and Consolidation

**Branch**: `089-nixos-home-manager-cleanup` | **Date**: 2025-11-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/089-nixos-home-manager-cleanup/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

This feature performs a comprehensive cleanup and consolidation of the NixOS configuration codebase, removing approximately 1,200-1,500 lines of deprecated code (15-20% of system modules) while establishing single sources of truth for shared functionality. The cleanup is organized in three prioritized phases: (P1) removing deprecated legacy modules supporting obsolete features (i3wm, X11/RDP, KDE Plasma, WSL), (P2) consolidating duplicate modules (1Password, Firefox+PWA, hetzner-sway variants), and (P3) documenting the active system boundary. Each phase can be independently tested via dry-build validation to ensure no functionality is lost for the two active configurations (hetzner-sway, m1).

## Technical Context

**Language/Version**: Nix 2.18+, Bash 5.0+ (for validation scripts)
**Primary Dependencies**: nixpkgs (unstable), home-manager (unstable), flake-parts, nixos-apple-silicon (for M1)
**Storage**: Git version control (all configuration declarative, no runtime state)
**Testing**: `nixos-rebuild dry-build` for build validation, `nix flake check` for flake validation, manual feature testing for regression detection
**Target Platform**: NixOS 23.11+ (hetzner-sway: x86_64-linux, m1: aarch64-linux)
**Project Type**: Infrastructure-as-code (declarative system configuration)
**Performance Goals**: Dry-build validation completes in <5 minutes per target, cleanup reduces codebase by 1,200-1,500 LOC
**Constraints**: Zero functional regression (all 88 active features must continue working), preserve hardware-specific config (M1 Asahi firmware, WayVNC, Tailscale)
**Scale/Scope**: 176 active Nix files, 32 system modules (2,560 LOC), 97 home-modules, 2 active system targets (hetzner-sway, m1)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Core Principles Compliance

✅ **Principle I - Modular Composition**
- **Status**: ENHANCES - Consolidation will improve module composition by reducing duplication
- **Action**: Ensure consolidated modules maintain single responsibility and proper option patterns

✅ **Principle II - Reference Implementation Flexibility**
- **Status**: ALIGNED - hetzner-sway remains reference, cleanup preserves its full functionality
- **Action**: Test all cleanup changes on hetzner-sway first before applying to m1

✅ **Principle III - Test-Before-Apply (NON-NEGOTIABLE)**
- **Status**: CORE REQUIREMENT - Spec mandates dry-build validation before and after each major change
- **Action**: FR-012 explicitly requires dry-build testing for both targets at each phase

✅ **Principle IV - Override Priority Discipline**
- **Status**: ALIGNED - Consolidation will maintain proper mkDefault/mkForce usage
- **Action**: Document priority levels in consolidated modules (especially 1Password, Firefox+PWA)

✅ **Principle V - Platform Flexibility Through Conditional Features**
- **Status**: ENHANCES - Consolidation will improve conditional logic patterns
- **Action**: Ensure consolidated modules use lib.mkIf and lib.optionals for target-specific behavior

✅ **Principle VI - Declarative Configuration Over Imperative**
- **Status**: ALIGNED - Cleanup removes only declarative Nix files, no runtime state
- **Action**: N/A - all changes are to declarative configuration files

✅ **Principle VII - Documentation as Code**
- **Status**: CORE REQUIREMENT - P3 user story dedicated to documentation updates
- **Action**: FR-010 requires updating CLAUDE.md and README.md to reflect active targets only

⚠️ **Principle XII - Forward-Only Development & Legacy Elimination**
- **Status**: PERFECTLY ALIGNED - This feature IS the embodiment of this principle
- **Action**: Complete removal of legacy code without backwards compatibility (user explicitly stated "we don't care about backwards compatibility")
- **Rationale**: This cleanup eliminates technical debt from deprecated features (i3wm, X11/RDP, KDE Plasma, WSL) without preservation, exactly as Principle XII mandates

✅ **All other principles**: Not directly applicable to this infrastructure cleanup task (no Python daemons, Deno CLIs, Sway tests, or i3 IPC work involved)

### Constitution Compliance Summary

**Overall Status**: ✅ **APPROVED - FULLY ALIGNED**

This feature exemplifies constitutional compliance:
- Embodies Principle XII (Forward-Only Development) by completely eliminating legacy code
- Strengthens Principle I (Modular Composition) through consolidation
- Mandates Principle III (Test-Before-Apply) through comprehensive dry-build validation
- Improves documentation (Principle VII) by clearly defining active system boundary

**No violations or complexity justifications required.**

## Project Structure

### Documentation (this feature)

```text
specs/089-nixos-home-manager-cleanup/
├── spec.md              # Feature specification (created by /speckit.specify)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (dependency analysis, consolidation strategies)
├── data-model.md        # Phase 1 output (module structure, configuration entities)
├── quickstart.md        # Phase 1 output (cleanup execution guide)
├── contracts/           # Phase 1 output (validation scripts, dry-build workflows)
│   └── validation.sh    # Automated dry-build validation for both targets
├── checklists/          # Quality checklists
│   └── requirements.md  # Spec quality checklist (created by /speckit.specify)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

This is an infrastructure cleanup task, not a new feature implementation. The changes will modify existing repository structure:

```text
# Affected directories (existing structure)
/
├── configurations/           # System target definitions
│   ├── hetzner-sway.nix     # PRIMARY - Production (consolidation source)
│   ├── hetzner-sway-image.nix   # CONSOLIDATE - VM image variant
│   ├── hetzner-sway-minimal.nix # CONSOLIDATE - Development variant
│   ├── hetzner-sway-ultra-minimal.nix # CONSOLIDATE - Minimal boot variant
│   ├── hetzner.nix          # ARCHIVE - Deprecated i3 variant
│   └── m1.nix               # PRESERVE - M1 Apple Silicon target
│
├── modules/                 # System modules (NixOS configuration)
│   ├── desktop/             # Desktop environment modules
│   │   ├── i3-project-workspace.nix  # DELETE - i3-only (537 LOC)
│   │   ├── xrdp.nix                  # DELETE - X11/RDP deprecated (126 LOC)
│   │   ├── remote-access.nix         # DELETE - X11/RDP deprecated (166 LOC)
│   │   ├── rdp-display.nix           # DELETE - X11/RDP deprecated (163 LOC)
│   │   ├── wireless-display.nix      # DELETE - X11 deprecated
│   │   └── firefox-virtual-optimization.nix # DELETE - KDE-specific
│   ├── services/            # System services modules
│   │   ├── onepassword.nix           # CONSOLIDATE - Merge 3 modules
│   │   ├── onepassword-automation.nix # CONSOLIDATE - Into onepassword.nix
│   │   ├── onepassword-password-management.nix # CONSOLIDATE - Into onepassword.nix
│   │   ├── audio-network.nix         # DELETE - X11-specific
│   │   ├── kde-optimization.nix      # DELETE - KDE deprecated
│   │   └── wsl-docker.nix            # DELETE - WSL deprecated
│   ├── assertions/          # Build-time assertions
│   │   └── wsl-check.nix    # DELETE - WSL deprecated
│   └── wsl/                 # WSL-specific modules
│       └── wsl-config.nix   # DELETE - WSL deprecated
│
├── home-modules/            # Home-manager user modules
│   ├── desktop/             # User desktop configuration
│   │   ├── firefox-1password.nix     # CONSOLIDATE - Merge with PWA variant
│   │   └── firefox-pwa-1password.nix # CONSOLIDATE - Into firefox-1password.nix
│   └── tools/               # User tool configuration
│
├── flake.nix                # MODIFY - Remove unused inputs (plasma-manager, etc.)
├── flake.lock               # UPDATE - Auto-update on input removal
│
├── archived/                # CREATE - Archive deprecated configurations
│   └── obsolete-configs/    # CREATE - For deprecated but reference-worthy configs
│       ├── hetzner.nix      # MOVE - Deprecated i3 configuration
│       └── README.md        # CREATE - Explain why these configs were deprecated
│
├── docs/                    # Documentation
│   ├── CLAUDE.md            # UPDATE - Remove WSL, hetzner (i3), KDE references
│   └── README.md            # UPDATE - Reflect only active targets
│
└── **/*.backup*             # DELETE - All backup files (8 files total)
```

**Structure Decision**: This cleanup task modifies the existing NixOS configuration structure by:
1. **Removing** deprecated modules and configurations (11 modules, 1 config, 8 backup files)
2. **Consolidating** duplicate modules into unified implementations (1Password: 3→1, Firefox+PWA: 2→1, hetzner-sway: 4→1 parameterized)
3. **Archiving** potentially-reference-worthy deprecated configurations to `archived/obsolete-configs/`
4. **Preserving** the existing directory structure for active modules and configurations

The cleanup focuses on eliminating dead code and duplication while maintaining the modular architecture established by Constitution Principle I.

## Complexity Tracking

> **No constitutional violations identified - this section is empty.**

This feature fully complies with all applicable constitution principles and requires no complexity justification.

---

## Phase 0: Research & Analysis

**Objective**: Resolve all technical unknowns and establish cleanup strategies before implementation.

### Research Tasks

1. **Module Dependency Analysis**
   - **Question**: How do we verify a module is truly unused and not imported indirectly?
   - **Research**: Investigate Nix trace capabilities, flake show output, and import chain analysis
   - **Deliverable**: Document validation process in research.md (Section: "Unused Module Detection")

2. **Flake Input Usage Verification**
   - **Question**: How do we confirm flake inputs are unused when they might be used by flake outputs like devShells?
   - **Research**: Analyze flake.nix structure, check all flake outputs (nixosConfigurations, homeConfigurations, devShells, packages, checks)
   - **Deliverable**: Document flake input verification process in research.md (Section: "Flake Input Validation")

3. **Module Consolidation Strategies**
   - **Question**: What's the best approach to consolidate 3 1Password modules with overlapping configuration?
   - **Research**: Study existing feature flag patterns in codebase, evaluate mkIf/mkMerge strategies, analyze option inheritance
   - **Deliverable**: Document consolidation strategy with code examples in research.md (Section: "1Password Module Consolidation")

4. **Configuration Variant Parameterization**
   - **Question**: How should we consolidate 4 hetzner-sway variants (production, image, minimal, ultra-minimal)?
   - **Research**: Evaluate NixOS module options pattern vs builder pattern, study existing variant implementations, consider maintenance tradeoffs
   - **Deliverable**: Document parameterization strategy in research.md (Section: "Hetzner-Sway Variant Consolidation")

5. **Hardware-Specific Configuration Preservation**
   - **Question**: How do we ensure M1 Asahi firmware support, WayVNC setup, and Tailscale integration aren't broken during cleanup?
   - **Research**: Identify all hardware-specific modules and their dependencies, create validation checklist
   - **Deliverable**: Document hardware-specific modules and validation approach in research.md (Section: "Hardware-Specific Validation")

6. **Backup File Safety**
   - **Question**: Are there any backup files that contain unique configuration not in git history?
   - **Research**: Review each .backup* file, compare with git history, verify all unique config is preserved in current files
   - **Deliverable**: Document backup file analysis in research.md (Section: "Backup File Review")

7. **Feature Documentation Preservation**
   - **Question**: What do we do with specs/ directories for deprecated features (Features 001, 009, 045)?
   - **Research**: Review existing archived features, establish deprecation documentation pattern
   - **Deliverable**: Document specs archival strategy in research.md (Section: "Feature Specs Archival")

### Research Deliverable: research.md

This file will contain:
- **Section 1: Unused Module Detection**: Process for validating modules are truly unused (nix flake show, import tracing, build validation)
- **Section 2: Flake Input Validation**: Method to verify flake inputs aren't used by any flake outputs
- **Section 3: 1Password Module Consolidation**: Detailed consolidation strategy with feature flags and option merging
- **Section 4: Hetzner-Sway Variant Consolidation**: Parameterization approach (likely: extract common base, use mkIf for variant-specific config)
- **Section 5: Hardware-Specific Validation**: Checklist of hardware modules to preserve and test (M1 Asahi, WayVNC, Tailscale, etc.)
- **Section 6: Backup File Review**: Analysis of each backup file and justification for deletion
- **Section 7: Feature Specs Archival**: Strategy for handling deprecated feature documentation (keep in specs/ but mark as deprecated)

---

## Phase 1: Design & Contracts

**Prerequisites**: research.md complete with all unknowns resolved

### Design Artifacts

#### 1. Data Model (data-model.md)

**Entities to Document**:

- **Active System Configuration**
  - Fields: name (hetzner-sway, m1), architecture (x86_64-linux, aarch64-linux), modules (list of imported modules), hardware-config (path to hardware-configuration.nix)
  - Relationships: imports → Modules, references → Hardware Config
  - Validation: Must build successfully with `nixos-rebuild dry-build`

- **Module**
  - Fields: path (relative to repo root), type (system/home), category (desktop/services/tools), enabled-by (list of configurations using it), dependencies (other modules it imports)
  - Relationships: imported-by → Active System Configuration, depends-on → Other Modules
  - Validation: Must be imported by at least one active configuration OR marked for deletion

- **Deprecated Feature**
  - Fields: feature-name (i3wm, X11/RDP, KDE Plasma, WSL), replacement (Sway/Wayland), modules (list of modules supporting this feature), deprecated-date
  - Relationships: supported-by → Modules
  - State: DEPRECATED → ARCHIVED (moved to archived/) OR DELETED (no historical value)

- **Flake Input**
  - Fields: name (nixpkgs, home-manager, plasma-manager), url, used-by (list of flake outputs or modules), status (active/unused)
  - Relationships: imported-by → Modules OR Flake Outputs
  - Validation: If status=unused AND used-by=[], safe to remove

- **Configuration Variant**
  - Fields: base (hetzner-sway), variant-name (image, minimal, ultra-minimal), purpose (VM image, development, minimal boot), specific-config (variant-specific configuration)
  - Relationships: extends → Base Configuration
  - Consolidation Strategy: Extract common config to base, use feature flags for variant-specific config

- **Backup File**
  - Fields: path, original-file (what it's a backup of), last-modified, unique-config (whether it contains config not in git)
  - State: REVIEW → DELETE (if no unique config) OR PRESERVE (if unique config needs migration)
  - Validation: Compare with git history to identify unique configuration

#### 2. API Contracts (contracts/)

**Contract 1: Dry-Build Validation Script** (`contracts/validation.sh`)
```bash
#!/usr/bin/env bash
# Validates both active configurations build successfully

set -euo pipefail

echo "=== Validating hetzner-sway configuration ==="
sudo nixos-rebuild dry-build --flake .#hetzner-sway

echo "=== Validating m1 configuration ==="
sudo nixos-rebuild dry-build --flake .#m1 --impure

echo "=== Validating flake structure ==="
nix flake check

echo "✅ All validations passed"
```

**Contract 2: Module Usage Analysis Script** (`contracts/module-usage.sh`)
```bash
#!/usr/bin/env bash
# Analyzes which modules are imported by active configurations

echo "=== Modules imported by hetzner-sway ==="
nix eval --json .#nixosConfigurations.hetzner-sway.config.imports | jq -r '.[]'

echo "=== Modules imported by m1 ==="
nix eval --json .#nixosConfigurations.m1.config.imports | jq -r '.[]'

echo "=== Flake inputs ==="
nix flake metadata --json | jq -r '.locks.nodes | keys[]'
```

**Contract 3: Hardware-Specific Feature Test** (`contracts/hardware-validation.sh`)
```bash
#!/usr/bin/env bash
# Validates hardware-specific features are preserved

# M1 Asahi firmware check
if grep -r "hardware.asahi" configurations/m1.nix; then
  echo "✅ M1 Asahi firmware configuration present"
else
  echo "❌ M1 Asahi firmware configuration missing"
  exit 1
fi

# WayVNC check (both targets)
if grep -r "wayvnc" configurations/; then
  echo "✅ WayVNC configuration present"
else
  echo "❌ WayVNC configuration missing"
  exit 1
fi

# Tailscale check (both targets)
if grep -r "tailscale" modules/ configurations/; then
  echo "✅ Tailscale configuration present"
else
  echo "❌ Tailscale configuration missing"
  exit 1
fi

echo "✅ All hardware-specific features validated"
```

#### 3. Quickstart Guide (quickstart.md)

**Purpose**: Step-by-step guide for executing the cleanup safely

**Sections**:
1. **Prerequisites**: Git clean working directory, backup git branches, validation scripts executable
2. **Phase 1 - Remove Legacy Modules**: Detailed steps to delete 11 deprecated modules, remove backup files, update flake.nix
3. **Phase 2 - Consolidate Duplicates**: Step-by-step module consolidation (1Password, Firefox+PWA, hetzner-sway variants)
4. **Phase 3 - Update Documentation**: Documentation update checklist (CLAUDE.md, README.md, specs archival)
5. **Validation**: How to run validation scripts at each phase
6. **Rollback**: How to revert if validation fails (git reset --hard, git checkout previous branch)
7. **Troubleshooting**: Common issues and solutions (import errors, missing dependencies, build failures)

#### 4. Agent Context Update

Run `.specify/scripts/bash/update-agent-context.sh claude` to add this cleanup work to the agent context (CLAUDE.md). This should document:
- New archival pattern for deprecated configurations
- Module consolidation best practices
- Validation workflow for infrastructure changes

---

## Phase 2: Task Generation

**Note**: This phase is handled by `/speckit.tasks` command, NOT by `/speckit.plan`.

The tasks will be generated based on:
- User stories from spec.md (P1, P2, P3)
- Research findings from research.md
- Design artifacts from data-model.md and contracts/
- Quickstart guide workflow from quickstart.md

Expected task structure:
1. **Preparation Tasks**: Create validation scripts, backup current configuration, create archived/ directory
2. **P1 Tasks**: Delete deprecated modules (11 modules), remove backup files (8 files), remove unused flake inputs, archive hetzner.nix
3. **P2 Tasks**: Consolidate 1Password modules, consolidate Firefox+PWA modules, consolidate hetzner-sway variants
4. **P3 Tasks**: Update CLAUDE.md, update README.md, document archived features
5. **Validation Tasks**: Run dry-build for both targets, run hardware-specific validation, run feature regression tests

---

## Re-Evaluation of Constitution Check (Post-Design)

After completing research and design phases, re-evaluate constitution compliance:

✅ **Principle I - Modular Composition**: Consolidation enhances modular composition by reducing duplication and establishing clearer module boundaries

✅ **Principle III - Test-Before-Apply**: Validation contracts ensure dry-build testing before and after each phase

✅ **Principle VII - Documentation as Code**: Quickstart guide and updated CLAUDE.md maintain documentation alignment with code

✅ **Principle XII - Forward-Only Development**: Complete removal of legacy code without backwards compatibility preservation

**Final Status**: ✅ **APPROVED - DESIGN MAINTAINS FULL CONSTITUTIONAL COMPLIANCE**

No design decisions introduce new complexity or violate constitution principles. The cleanup strengthens the codebase's alignment with constitutional standards.
