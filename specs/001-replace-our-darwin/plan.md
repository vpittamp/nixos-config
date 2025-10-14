# Implementation Plan: Migrate Darwin Home-Manager to Nix-Darwin

**Branch**: `001-replace-our-darwin` | **Date**: 2025-10-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-replace-our-darwin/spec.md`

## Summary

Replace the current standalone home-manager Darwin configuration with a comprehensive nix-darwin system configuration. This enables system-level package management and declarative macOS preferences while maintaining all existing user-level functionality through home-manager integration. The implementation follows the established NixOS modular architecture pattern, providing consistency across the multi-platform nixos-config repository.

**Key Changes**:
- Add `darwinConfigurations.darwin` output to flake.nix
- Create `configurations/darwin.nix` for system configuration
- Integrate home-manager as nix-darwin module (not standalone)
- Configure system packages matching base.nix (where applicable on macOS)
- Set up macOS system preferences declaratively
- Maintain backward compatibility with existing home-darwin.nix

## Technical Context

**Language/Version**: Nix Expression Language (nix-lang) with Nix 2.18+

**Primary Dependencies**:
- nix-darwin (latest from flake input): System configuration framework for macOS
- home-manager (master branch): User-level dotfile and package management
- nixpkgs (nixos-unstable): Package repository with Darwin support
- nix-darwin.lib.darwinSystem: System builder function
- home-manager.darwinModules.home-manager: Home-manager integration module

**Storage**:
- Configuration: Declarative .nix files in git repository
- System profile: `/nix/var/nix/profiles/system` symlinks
- User profile: `~/.nix-profile` symlinks
- Nix store: `/nix/store` (content-addressed storage)
- macOS preferences: `~/Library/Preferences/*.plist` (managed by nix-darwin)

**Testing**:
- Syntax validation: `darwin-rebuild check --flake .#darwin`
- Dry-run: `darwin-rebuild --dry-run switch --flake .#darwin`
- Build without activation: `darwin-rebuild build --flake .#darwin`
- Integration testing: Manual verification of all user stories
- Rollback testing: `darwin-rebuild rollback`

**Target Platform**:
- macOS 12.0 (Monterey) or newer
- Apple Silicon (aarch64-darwin) and Intel (x86_64-darwin)
- Multi-architecture support using `builtins.currentSystem`

**Project Type**: Configuration management (not software development)

**Performance Goals**:
- Initial build: < 5 minutes (with binary cache)
- Incremental rebuild: < 60 seconds
- Activation: < 10 seconds
- Rebuild time within 20% of current home-manager builds (SC-007)

**Constraints**:
- Must not break existing home-darwin.nix (FR-013, SC-008)
- Must maintain cross-platform compatibility (Constitution IV)
- Must be reproducible from flake.lock (Constitution VII)
- Must support both Apple Silicon and Intel Macs (FR-005, SC-009)
- Activation must not require reboot (except for certain macOS defaults)

**Scale/Scope**:
- Single-user configuration (vinodpittampalli)
- ~50 system packages (from base.nix equivalent)
- ~100 user packages (from darwin-home.nix)
- 15 functional requirements
- 5 user stories (prioritized P1-P3)
- 10 success criteria

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### ✅ I. Declarative Configuration

**Status**: PASS

**Evidence**:
- All configuration in .nix files (configurations/darwin.nix, modules/darwin/*)
- System state derived from nix-darwin declarations
- macOS preferences managed via `system.defaults` (not imperative defaults write)
- No manual system modifications - all changes via darwin-rebuild
- Home-manager integration maintains user-level declarative config

**Compliance**:
- ✅ All packages declared in configuration files
- ✅ All services configured through nix-darwin options
- ✅ User environment managed via home-manager
- ✅ No manual system modifications outside Nix

### ✅ II. Test-First Deployment (NON-NEGOTIABLE)

**Status**: PASS

**Evidence**:
- Testing workflow defined in quickstart.md
- darwin-rebuild provides check, dry-run, and build commands
- Rollback mechanism available (darwin-rebuild rollback)
- Documentation emphasizes testing before switch

**Testing Process**:
1. Syntax check: `darwin-rebuild check --flake .#darwin`
2. Dry-run: `darwin-rebuild --dry-run switch --flake .#darwin`
3. Build: `darwin-rebuild build --flake .#darwin` (test without activating)
4. Apply: `darwin-rebuild switch --flake .#darwin`

**Compliance**:
- ✅ Equivalent to `nixos-rebuild dry-build` via darwin-rebuild commands
- ✅ Local testing possible before deployment
- ✅ No --impure flag needed (unlike M1 NixOS with firmware)
- ✅ --show-trace available for debugging

**Note**: darwin-rebuild doesn't have explicit "dry-build", but `--dry-run switch` and `build` commands provide equivalent functionality.

### ✅ III. Modular Composition

**Status**: PASS

**Evidence**:
- Follows NixOS pattern: base configuration + platform-specific modules
- configurations/darwin.nix as base Darwin configuration
- Optional modules/darwin/ directory for Darwin-specific modules
- home-manager imported as module (not standalone)
- Reuses existing home-modules without duplication

**Module Hierarchy**:
```
flake.nix (darwinConfigurations.darwin)
  └── configurations/darwin.nix (base Darwin config)
      ├── modules/darwin/defaults.nix (if created - macOS preferences)
      ├── modules/darwin/packages.nix (if created - system packages)
      └── home-manager.darwinModules.home-manager
          └── imports home-darwin.nix
              └── imports home-modules/profiles/darwin-home.nix
```

**Compliance**:
- ✅ Modular architecture matches NixOS pattern
- ✅ Each module serves single purpose
- ✅ Modules independently toggleable (via conditional imports)
- ✅ Uses `lib.mkDefault` for overrideable defaults (per FR-012)
- ✅ No duplication - reuses home-modules from NixOS config

### ✅ IV. Platform Compatibility

**Status**: PASS

**Evidence**:
- Adds Darwin as supported platform (Constitution explicitly lists "Darwin (macOS via home-manager only)")
- Maintains compatibility with existing platforms (WSL2, Hetzner, M1, Containers)
- Uses `pkgs.stdenv.isDarwin` for platform-specific logic
- Shares home-modules across platforms
- Documents macOS-specific paths and configurations

**Platform Support**:
- ✅ WSL2: Unchanged, no conflicts
- ✅ Hetzner: Unchanged, no conflicts
- ✅ M1 NixOS: Unchanged, no conflicts
- ✅ Containers: Unchanged, no conflicts
- ✅ Darwin (NEW): Full support via nix-darwin

**Compliance**:
- ✅ Darwin-specific code isolated to configurations/darwin.nix and modules/darwin/
- ✅ Uses conditional logic for platform features (see colors.nix fix)
- ✅ Platform requirements documented in spec and quickstart
- ✅ Common logic remains in shared modules

### ✅ V. Documentation Completeness

**Status**: PASS

**Evidence**:
- spec.md: Complete feature specification
- plan.md: This implementation plan
- research.md: Technical decisions and rationale
- data-model.md: Configuration structure
- contracts/: Interface definitions
- quickstart.md: User-facing guide
- CLAUDE.md: Will be updated with Darwin-specific commands

**Documentation Requirements**:
- ⚠️ CLAUDE.md: Must be updated after implementation (add Darwin rebuild commands, troubleshooting)
- ✅ README.md: May need minor update mentioning nix-darwin (optional)
- ✅ Module comments: Will be added to configurations/darwin.nix
- ✅ Platform guide: quickstart.md serves this purpose

**Compliance**:
- ✅ Comprehensive documentation created
- ⏳ CLAUDE.md update pending (will be done in implementation phase)
- ✅ All significant changes documented
- ✅ Migration path documented

### ✅ VI. Single Source of Truth

**Status**: PASS

**Evidence**:
- Reuses shared/package-lists.nix with platform filtering
- Reuses all home-modules/* without duplication
- System packages defined once in configurations/darwin.nix
- macOS defaults defined once in system.defaults
- No copy-paste from NixOS configurations

**Shared Components**:
- ✅ home-modules/shell/* (bash, starship, colors)
- ✅ home-modules/terminal/* (tmux, sesh)
- ✅ home-modules/editors/* (neovim)
- ✅ home-modules/tools/* (git, ssh, onepassword, etc.)
- ✅ shared/package-lists.nix (with `pkgs.stdenv.isDarwin` filtering)

**Compliance**:
- ✅ No duplication of configuration
- ✅ Extraction of common patterns (uses existing shared modules)
- ✅ Platform-specific overrides only in darwin.nix
- ✅ No copy-paste between configurations

### ✅ VII. Reproducible Builds

**Status**: PASS

**Evidence**:
- Uses flake.lock to pin all inputs
- system.configurationRevision tracks git commit
- Build metadata can be added (similar to NixOS /etc/nixos-metadata)
- Generations tracked in /nix/var/nix/profiles/system-*-link
- Rollback restores exact previous state

**Reproducibility Mechanisms**:
- ✅ flake.lock pins nixpkgs, nix-darwin, home-manager versions
- ✅ system.configurationRevision = self.rev or self.dirtyRev
- ✅ Can add build metadata to system profile (optional, similar to NixOS)
- ✅ Generations enable exact rollback

**Compliance**:
- ✅ Flake inputs pinned with lock file
- ✅ Git commit metadata tracked
- ✅ Build metadata available (can query system profile)
- ✅ Can reproduce any deployed configuration from git commit + flake.lock

### Summary

**GATE STATUS**: ✅ **PASS** - All 7 principles satisfied

**No Violations**: This implementation fully complies with the constitution.

**No Complexity Justification Required**: Standard modular architecture, no special cases.

## Project Structure

### Documentation (this feature)

```
specs/001-replace-our-darwin/
├── plan.md                      # This file
├── spec.md                      # Feature specification
├── research.md                  # Phase 0: Technical research and decisions
├── data-model.md                # Phase 1: Configuration structure
├── quickstart.md                # Phase 1: User quick-start guide
├── contracts/                   # Phase 1: Interface contracts
│   └── darwin-configuration-interface.md
└── checklists/                  # Quality validation
    └── requirements.md          # Spec quality checklist (complete)

# Note: tasks.md will be created by /speckit.tasks command (not by /speckit.plan)
```

### Source Code (repository root)

```
nixos-config/
├── flake.nix                              # MODIFY: Add darwinConfigurations output
│
├── configurations/
│   ├── base.nix                           # Unchanged (NixOS base)
│   ├── hetzner.nix                        # Unchanged
│   ├── m1.nix                             # Unchanged
│   ├── wsl.nix                            # Unchanged
│   ├── container.nix                      # Unchanged
│   └── darwin.nix                         # NEW: nix-darwin system configuration
│
├── modules/
│   ├── services/                          # Unchanged (NixOS services)
│   ├── desktop/                           # Unchanged (NixOS desktop)
│   └── darwin/                            # NEW (optional): Darwin-specific modules
│       ├── defaults.nix                   # macOS system preferences (optional)
│       ├── packages.nix                   # System packages (optional)
│       └── services.nix                   # Darwin services (optional)
│
├── hardware/                              # Unchanged (NixOS hardware)
├── shared/
│   └── package-lists.nix                  # MODIFY: Add Darwin platform filtering (if needed)
│
├── home-modules/                          # Unchanged (shared across all platforms)
│   ├── profiles/
│   │   ├── base-home.nix                  # Unchanged
│   │   └── darwin-home.nix                # Unchanged (already has platform checks)
│   ├── shell/
│   │   ├── bash.nix                       # Unchanged (already cross-platform)
│   │   ├── colors.nix                     # FIXED: Already updated (isDarwin check)
│   │   └── starship.nix                   # Unchanged
│   ├── terminal/
│   │   ├── tmux.nix                       # Unchanged
│   │   └── sesh.nix                       # Unchanged
│   ├── editors/
│   │   └── neovim.nix                     # Unchanged
│   └── tools/
│       ├── git.nix                        # Unchanged
│       ├── ssh.nix                        # Unchanged
│       ├── onepassword.nix                # Unchanged
│       ├── onepassword-env.nix            # Unchanged (has Darwin paths)
│       └── ...                            # All other tools unchanged
│
├── home-darwin.nix                        # Unchanged (imported by nix-darwin)
├── home-vpittamp.nix                      # Unchanged (NixOS)
├── home-code.nix                          # Unchanged (NixOS containers)
│
├── README.md                              # OPTIONAL UPDATE: Mention nix-darwin
└── CLAUDE.md                              # UPDATE: Add Darwin rebuild commands
```

**Structure Decision**:

This implementation uses the **Single Configuration** pattern (not "Option 1/2/3" from template - this is config management, not software development).

The structure follows the established nixos-config repository pattern:
- **Root level**: Entry point (flake.nix) and top-level configurations
- **configurations/**: Platform-specific system configurations
- **modules/**: Reusable system modules (organized by service type or platform)
- **home-modules/**: Reusable user-level modules (shared across all platforms)
- **shared/**: Cross-platform utilities

**Key Principle**: Darwin configuration reuses maximum existing code:
- ✅ 100% of home-modules unchanged (already cross-platform)
- ✅ All existing platforms unchanged
- ✅ Only adds configurations/darwin.nix + optional modules/darwin/
- ✅ Minimal changes to flake.nix (add darwinConfigurations output)

## Implementation Phases

### Phase 0: Research & Decisions ✅ COMPLETE

**Completed Artifacts**:
- ✅ research.md: All technical decisions documented
- ✅ Technology choices: nix-darwin, home-manager integration pattern
- ✅ Package distribution: System vs user level
- ✅ 1Password integration: macOS-specific paths
- ✅ macOS defaults: Recommended settings
- ✅ Build workflow: darwin-rebuild commands
- ✅ Risk mitigation strategies

**Key Decisions Made**:
1. Use `nix-darwin.lib.darwinSystem` (analogous to NixOS)
2. Import `home-manager.darwinModules.home-manager` as module
3. System packages: Core dev tools, compilers, cloud CLIs
4. User packages: Language tools, editor plugins, shell enhancements
5. 1Password: Use macOS-specific socket path in SSH config
6. macOS defaults: Configure dock, finder, trackpad, keyboard
7. Testing: check → dry-run → build → switch workflow

### Phase 1: Design & Contracts ✅ COMPLETE

**Completed Artifacts**:
- ✅ data-model.md: Configuration entities and relationships
- ✅ contracts/darwin-configuration-interface.md: Interface specifications
- ✅ quickstart.md: User-facing quick start guide

**Design Highlights**:
1. **Configuration Entities**: Darwin System, macOS Defaults, Home Manager, Services, Packages
2. **Configuration Flow**: Evaluation → Activation → Profile switch → Defaults write → Service start
3. **Rollback Flow**: Generation selection → Profile switch → Activation
4. **File System Impact**: /run/current-system, ~/.nix-profile, ~/Library/Preferences
5. **Validation**: Pre-build checks, post-build verification
6. **Error Handling**: Syntax errors, missing attributes, permission issues, conflicts

**Interface Contracts**:
1. **Flake Output**: darwinConfigurations.darwin structure
2. **System Module**: Required and optional attributes
3. **Home-Manager Integration**: Module structure and imports
4. **System Defaults**: macOS preference types and values
5. **SSH Configuration**: 1Password integration format
6. **Build Commands**: darwin-rebuild interface and exit codes
7. **Environment**: Pre/post-conditions, PATH management
8. **Validation**: Pre-build checks, post-build verification
9. **Error Handling**: Error types and recovery procedures
10. **Rollback**: Trigger conditions, process, guarantees, limitations

### Phase 2: Task Generation (Next)

**Pending**: This phase will be completed by `/speckit.tasks` command

**Expected Output**: `tasks.md` with implementation tasks organized by user story

**Task Structure** (will be generated):
- Phase 1: Setup (project structure)
- Phase 2: Foundational (flake.nix, configurations/darwin.nix)
- Phase 3: User Story 1 - System-Level Package Management (P1)
- Phase 4: User Story 2 - Home-Manager Integration (P1)
- Phase 5: User Story 3 - 1Password Integration (P2)
- Phase 6: User Story 4 - Development Services (P2)
- Phase 7: User Story 5 - macOS System Preferences (P3)
- Phase N: Polish & Cross-Cutting Concerns

**Note**: Tasks will be derived from:
- User stories in spec.md
- Functional requirements (FR-001 through FR-015)
- Technical decisions in research.md
- Configuration entities in data-model.md
- Interface contracts in contracts/

## Complexity Tracking

*Fill ONLY if Constitution Check has violations that must be justified*

**Status**: No violations - table not needed

All constitutional principles satisfied without exceptions. No complexity justification required.

## Integration Points

### With Existing NixOS Configuration

**Shared Inputs** (unchanged):
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  nix-darwin.url = "github:LnL7/nix-darwin";  # Already present
  home-manager.url = "github:nix-community/home-manager/master";
  # ... other inputs unchanged
};
```

**New Output**:
```nix
darwinConfigurations.darwin = nix-darwin.lib.darwinSystem {
  system = builtins.currentSystem or "aarch64-darwin";
  modules = [
    ./configurations/darwin.nix
    home-manager.darwinModules.home-manager
  ];
  specialArgs = { inherit inputs; };
};
```

**Shared Modules** (reused without changes):
- All home-modules/* (100% reuse)
- shared/package-lists.nix (with platform filtering)

### With Current Darwin Home-Manager

**Migration Path**:
1. Keep home-darwin.nix unchanged (FR-013)
2. Import it within nix-darwin's home-manager module
3. Transition from `home-manager switch` to `darwin-rebuild switch`
4. Both commands manage the same home-manager configuration

**Backwards Compatibility**:
- ✅ All home-manager modules work unchanged
- ✅ User profile path unchanged (~/.nix-profile)
- ✅ Config files in same locations (~/.config, etc.)
- ✅ No breaking changes to user experience

### With External Services

**1Password**:
- System: SSH config in programs.ssh.extraConfig
- System: Environment variable SSH_AUTH_SOCK
- User: Git signing in home-modules/tools/git.nix (unchanged)
- User: Shell integration in home-modules/tools/onepassword-plugins.nix (unchanged)

**Docker Desktop**:
- Assumed: Docker Desktop installed separately
- System: docker-compose package available
- User: Shell aliases in home-modules/shell/bash.nix (unchanged)
- Integration: /var/run/docker.sock (managed by Docker Desktop)

## Post-Implementation Validation

### Automated Checks

```bash
# Syntax validation
darwin-rebuild check --flake .#darwin

# Dry-run
darwin-rebuild --dry-run switch --flake .#darwin

# Build test
darwin-rebuild build --flake .#darwin
```

### Manual Verification (from Success Criteria)

**SC-001**: ✓ User can rebuild with `darwin-rebuild switch --flake .#darwin`
```bash
darwin-rebuild switch --flake .#darwin
# Exit code: 0
```

**SC-002**: ✓ Core tools available system-wide
```bash
which git vim curl wget htop tmux tree ripgrep fd ncdu rsync openssl jq
# All should be in /run/current-system/sw/bin
```

**SC-003**: ✓ User configs work identically
```bash
# Test bash config
echo $PS1  # Should show starship prompt
bash --version  # Should show 5.3+ if shell changed

# Test tmux config
tmux new-session -d -s test && tmux kill-session -t test

# Test neovim config
nvim --version && nvim -c "quit"
```

**SC-004**: ✓ 1Password SSH agent works
```bash
ssh-add -l  # Should list keys from 1Password
ssh -T git@github.com  # Should authenticate
git commit --allow-empty -m "test" --gpg-sign  # Should sign
```

**SC-005**: ✓ Docker works
```bash
docker ps  # Should not error
docker-compose --version  # Should show version
```

**SC-006**: ✓ System functional across macOS updates
```
# Manual test: Update macOS minor version
# Verify: darwin-rebuild switch still works
# Document: Any macOS-version-specific issues
```

**SC-007**: ✓ Rebuild time comparable (within 20%)
```bash
# Measure current home-manager rebuild
time home-manager switch --flake .#darwin

# Measure nix-darwin rebuild
time darwin-rebuild switch --flake .#darwin

# Compare: nix-darwin time should be < 1.2 * home-manager time
```

**SC-008**: ✓ All current packages functional
```bash
# List packages from current profile
nix-store -q --requisites ~/.nix-profile | grep -E "bin/|share/" | head -20

# After migration, verify same packages available
# Compare: Should have same or more packages
```

**SC-009**: ✓ Cross-architecture support
```nix
# Configuration uses:
system = builtins.currentSystem or "aarch64-darwin";

# Verify on Apple Silicon:
nix eval --raw .#darwinConfigurations.darwin.system  # → aarch64-darwin

# Could verify on Intel:
# nix eval --raw .#darwinConfigurations.darwin.system  # → x86_64-darwin
```

**SC-010**: ✓ System preferences persist
```bash
# Set preferences in darwin.nix
system.defaults.dock.autohide = true;

# Rebuild
darwin-rebuild switch --flake .#darwin

# Verify
defaults read com.apple.dock autohide  # → 1

# Reboot and verify still set
```

### User Story Acceptance Tests

**US1 - System-Level Package Management**:
- [ ] AS1.1: Core tools available system-wide after rebuild
- [ ] AS1.2: New packages installed on next rebuild
- [ ] AS1.3: Package list matches NixOS where applicable

**US2 - Home-Manager Integration**:
- [ ] AS2.1: Shell configs applied after rebuild
- [ ] AS2.2: Tmux and bash active in new terminal
- [ ] AS2.3: Neovim plugins present

**US3 - 1Password Integration**:
- [ ] AS3.1: Can access 1Password vaults with `op item list`
- [ ] AS3.2: SSH authentication prompts 1Password
- [ ] AS3.3: Git commits signed with 1Password key

**US4 - Development Services**:
- [ ] AS4.1: Docker accessible without sudo
- [ ] AS4.2: kubectl available and configured
- [ ] AS4.3: Node, Python, Go, Rust available

**US5 - macOS System Preferences**:
- [ ] AS5.1: Dock settings match configuration
- [ ] AS5.2: Keyboard repeat works as configured
- [ ] AS5.3: Trackpad tap-to-click works

## Documentation Updates Required

### CLAUDE.md (Critical)

Add new section or update existing Darwin section:

```markdown
## 🍎 nix-darwin Configuration

For using this configuration on macOS with system-level management:

### Essential Commands

```bash
# Test configuration changes (ALWAYS RUN BEFORE APPLYING)
darwin-rebuild check --flake .#darwin

# Dry-run (see what would change)
darwin-rebuild --dry-run switch --flake .#darwin

# Apply configuration changes
darwin-rebuild switch --flake .#darwin

# Build without activating
darwin-rebuild build --flake .#darwin
```

### Rollback

```bash
# List generations
darwin-rebuild --list-generations

# Rollback to previous generation
darwin-rebuild rollback
```

### Quick Debugging

```bash
# Check configuration syntax
darwin-rebuild check --flake .#darwin

# View current system profile
ls -l /run/current-system

# Check what would change
darwin-rebuild --dry-run switch --flake .#darwin
```
```

### README.md (Optional)

Minor update to mention nix-darwin:

```markdown
## 🚀 Quick Start

...

#### For macOS (nix-darwin)
```bash
# Test the configuration
darwin-rebuild check --flake .#darwin

# Apply the configuration
darwin-rebuild switch --flake .#darwin
```
```

## Next Steps

After this planning phase:

1. **Run `/speckit.tasks`**: Generate detailed implementation tasks
2. **Implement tasks**: Follow task order (setup → foundational → user stories by priority)
3. **Test incrementally**: Verify each user story independently
4. **Update documentation**: Modify CLAUDE.md and README.md
5. **Create PR**: Document migration benefits and testing evidence

**Do NOT proceed with implementation until tasks are generated by `/speckit.tasks`.**

## References

- **Specification**: [spec.md](./spec.md)
- **Research**: [research.md](./research.md)
- **Data Model**: [data-model.md](./data-model.md)
- **Contracts**: [contracts/darwin-configuration-interface.md](./contracts/darwin-configuration-interface.md)
- **Quick Start**: [quickstart.md](./quickstart.md)
- **Constitution**: [../.specify/memory/constitution.md](../../.specify/memory/constitution.md)
- **nix-darwin Manual**: https://daiderd.com/nix-darwin/manual/
- **home-manager Darwin**: https://nix-community.github.io/home-manager/index.xhtml#sec-install-nix-darwin-module
