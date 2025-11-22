# Quickstart Guide: NixOS Configuration Cleanup

**Feature**: 089-nixos-home-manager-cleanup
**Branch**: `089-nixos-home-manager-cleanup`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Overview

This guide provides step-by-step instructions for safely executing the NixOS configuration cleanup. The cleanup is organized in three phases that can be executed independently with validation at each step.

## Prerequisites

Before starting, ensure you have:

- [ ] Clean git working directory (`git status` shows no uncommitted changes)
- [ ] Current branch is `089-nixos-home-manager-cleanup`
- [ ] Validation scripts are executable (`chmod +x specs/089-nixos-home-manager-cleanup/contracts/*.sh`)
- [ ] You have sudo access for `nixos-rebuild` commands
- [ ] Backup/snapshot of system (optional but recommended for production systems)

## Validation Workflow

At each phase, run these validation commands:

```bash
# Basic validation (dry-build both targets)
specs/089-nixos-home-manager-cleanup/contracts/validation.sh

# Hardware-specific validation
specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh

# Both should exit with status 0 (success)
```

---

## Phase 1: Remove Legacy Modules

**Goal**: Remove deprecated modules supporting obsolete features (i3wm, X11/RDP, KDE Plasma, WSL)

**Expected Impact**: ~1,000 LOC removed, 11 modules deleted, 8 backup files removed, unused flake inputs removed

### Step 1.1: Delete Deprecated Desktop Modules

```bash
# Delete i3-only modules (537 LOC)
git rm modules/desktop/i3-project-workspace.nix

# Delete X11/RDP modules (455 LOC total)
git rm modules/desktop/xrdp.nix
git rm modules/desktop/remote-access.nix
git rm modules/desktop/rdp-display.nix
git rm modules/desktop/wireless-display.nix

# Delete KDE-specific module
git rm modules/desktop/firefox-virtual-optimization.nix
```

### Step 1.2: Delete Deprecated Service Modules

```bash
# Delete X11-specific service
git rm modules/services/audio-network.nix

# Delete KDE optimization
git rm modules/services/kde-optimization.nix

# Delete WSL Docker integration
git rm modules/services/wsl-docker.nix
```

### Step 1.3: Delete WSL Modules

```bash
# Delete WSL assertion
git rm modules/assertions/wsl-check.nix

# Delete WSL configuration
git rm modules/wsl/wsl-config.nix

# Remove wsl directory if empty
rmdir modules/wsl 2>/dev/null || true
```

### Step 1.4: Remove Backup Files

```bash
# Find all backup files
find . -name "*.backup*" -type f | grep -v archived | grep -v specs

# Delete them
find . -name "*.backup*" -type f | grep -v archived | grep -v specs | xargs git rm
```

### Step 1.5: Archive Deprecated Configuration

```bash
# Create archived directory structure
mkdir -p archived/obsolete-configs

# Move deprecated hetzner.nix (i3-based variant)
git mv configurations/hetzner.nix archived/obsolete-configs/

# Create README explaining archival
cat > archived/obsolete-configs/README.md << 'ARCHIVE_README'
# Archived NixOS Configurations

Configurations moved here are no longer actively used but preserved for historical reference.

## hetzner.nix
- **Archived**: 2025-11-22
- **Reason**: Replaced by Sway/Wayland (Feature 045)
- **Active Replacement**: configurations/hetzner-sway.nix
- **Description**: Original i3wm + X11 + xrdp configuration for Hetzner Cloud
- **Last Active**: Prior to Feature 045 (X11 → Wayland migration)

This configuration used i3 tiling window manager with xrdp for remote desktop access. It was replaced by hetzner-sway.nix which uses Sway (Wayland compositor) with WayVNC for remote access, providing better performance and modern display protocol support.
ARCHIVE_README

git add archived/obsolete-configs/README.md
```

### Step 1.6: Remove Unused Flake Inputs

Edit `flake.nix` to remove unused inputs:

```bash
# Open flake.nix in your editor
${EDITOR:-vim} flake.nix

# Remove these inputs from the `inputs` attribute set:
# - plasma-manager (only used in archived kubevirt-full)
# - flake-utils (declared but never directly used)
# - Any others identified in research.md

# Save and close editor
```

Update flake.lock:

```bash
# Update flake lock to reflect removed inputs
nix flake update
```

### Step 1.7: Validate Phase 1

```bash
# Run validation scripts
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh

# Both should pass (exit 0)
```

### Step 1.8: Commit Phase 1

```bash
git add -A
git commit -m "feat(089): Phase 1 - Remove deprecated legacy modules

- Delete 11 deprecated modules supporting obsolete features (i3wm, X11/RDP, KDE, WSL)
- Remove 8 backup files (git history provides versioning)
- Archive hetzner.nix (i3-based) to archived/obsolete-configs/
- Remove unused flake inputs (plasma-manager, flake-utils)

Impact: ~1,000 LOC removed, codebase clarity improved

Validation:
- hetzner-sway: dry-build passed ✅
- m1: dry-build passed ✅
- Hardware features: validated ✅

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 2: Consolidate Duplicate Modules

**Goal**: Consolidate duplicate functionality into single sources of truth

**Expected Impact**: ~200 LOC reduction, 1Password (3→1), Firefox+PWA (2→1), hetzner-sway variants consolidated

### Step 2.1: Consolidate 1Password Modules

Follow the consolidation strategy documented in `research.md` Section 3:

1. Create new consolidated module `modules/services/onepassword.nix` with feature flags
2. Update all configurations to use new options
3. Test each configuration
4. Remove old modules (`onepassword-automation.nix`, `onepassword-password-management.nix`)

**Detailed steps**: See `research.md` Section "1Password Module Consolidation"

### Step 2.2: Consolidate Firefox+PWA Modules

1. Merge `home-modules/desktop/firefox-pwa-1password.nix` into `firefox-1password.nix`
2. Add `enablePWA` feature flag
3. Update configurations to use consolidated module
4. Test Firefox-only and Firefox+PWA scenarios
5. Remove old `firefox-pwa-1password.nix`

### Step 2.3: Consolidate Hetzner-Sway Variants

Follow the Profile Imports pattern documented in `research.md` Section 4:

1. Extract common configuration to `modules/hetzner-sway-common.nix`
2. Create profile modules in `modules/profiles/hetzner-sway-*.nix`
3. Update configuration files to thin wrappers importing profile + common
4. Test each variant (production, image, minimal, ultra-minimal)
5. Remove duplicate code from original variants

**Expected**: 700 LOC → 400 LOC (43% reduction)

### Step 2.4: Validate Phase 2

```bash
# Run full validation suite
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
specs/089-nixos-home-manager-cleanup/contracts/hardware-validation.sh

# Test specific features (manual)
# - 1Password GUI, automation, SSH agent
# - Firefox with and without PWAs
# - All four hetzner-sway variants build correctly
```

### Step 2.5: Commit Phase 2

```bash
git add -A
git commit -m "feat(089): Phase 2 - Consolidate duplicate modules

- Consolidate 3 1Password modules → 1 with feature flags (150-180 LOC saved)
- Merge Firefox + Firefox-PWA modules with enablePWA flag (40-50 LOC saved)
- Consolidate 4 hetzner-sway variants using profile imports (300 LOC saved)

Impact: ~200 LOC reduction, single sources of truth established

Validation:
- All configurations: dry-build passed ✅
- 1Password features: tested ✅
- Firefox/PWA: tested ✅
- All hetzner-sway variants: tested ✅

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 3: Update Documentation

**Goal**: Ensure documentation accurately reflects active system boundary

**Expected Impact**: CLAUDE.md and README.md updated, deprecated features clearly marked

### Step 3.1: Update CLAUDE.md

Edit `docs/CLAUDE.md`:

```bash
${EDITOR:-vim} docs/CLAUDE.md

# Changes to make:
# 1. Remove all references to WSL as a current target
# 2. Remove references to hetzner (i3) configuration
# 3. Remove KDE Plasma references
# 4. Update "Configuration Targets" section to list only hetzner-sway and m1
# 5. Update quick start commands to remove WSL examples
# 6. Add note about archived configurations in archived/obsolete-configs/
```

### Step 3.2: Update README.md

Edit `README.md`:

```bash
${EDITOR:-vim} README.md

# Changes to make:
# 1. Update configuration targets section
# 2. Remove WSL setup instructions (or move to archived/ docs)
# 3. Ensure only hetzner-sway and m1 are listed as active
# 4. Add note about historical configurations in archived/
```

### Step 3.3: Document Archived Features

Create `archived/DEPRECATED_FEATURES.md`:

```bash
cat > archived/DEPRECATED_FEATURES.md << 'FEATURES_DOC'
# Deprecated Features Documentation

This document tracks features that have been deprecated and replaced in this project.

## Feature 001: WSL2 Configuration
- **Deprecated**: 2025-11-22 (Feature 089)
- **Reason**: Project no longer targets WSL2 environments
- **Replacement**: Native NixOS on dedicated hardware (hetzner-sway, m1)
- **Modules Archived**: 
  - modules/assertions/wsl-check.nix
  - modules/wsl/wsl-config.nix
  - modules/services/wsl-docker.nix
- **Specs**: specs/001-* (marked as deprecated)

## Feature 009: KDE Plasma Desktop
- **Deprecated**: 2025-11-22 (Feature 089)
- **Reason**: Migrated to Sway/Wayland for better tiling WM and Wayland support
- **Replacement**: Sway compositor (Feature 045)
- **Modules Archived**:
  - modules/services/kde-optimization.nix
  - modules/desktop/firefox-virtual-optimization.nix
- **Flake Inputs Removed**: plasma-manager

## Feature 045: X11/RDP Remote Desktop
- **Deprecated**: 2025-11-22 (Feature 089)
- **Reason**: Replaced by Wayland + WayVNC for modern remote access
- **Replacement**: WayVNC over Tailscale (Feature 048)
- **Modules Archived**:
  - modules/desktop/xrdp.nix
  - modules/desktop/remote-access.nix
  - modules/desktop/rdp-display.nix
  - modules/desktop/wireless-display.nix
  - modules/services/audio-network.nix
- **Configuration Archived**: configurations/hetzner.nix (i3 + X11 + xrdp)

## Feature 037: i3 Project Workspace Management
- **Deprecated**: 2025-11-22 (Feature 089)
- **Reason**: Replaced by Sway-based project management
- **Replacement**: Sway + i3pm daemon (Features 042-088)
- **Modules Archived**:
  - modules/desktop/i3-project-workspace.nix (537 LOC)
FEATURES_DOC

git add archived/DEPRECATED_FEATURES.md
```

### Step 3.4: Validate Phase 3

```bash
# Ensure documentation is consistent
grep -r "WSL" docs/CLAUDE.md docs/README.md && echo "⚠️  WSL references still present" || echo "✅ WSL references removed"
grep -r "hetzner.nix" docs/ && echo "⚠️  hetzner.nix references still present" || echo "✅ hetzner.nix references removed"

# Run build validation
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
```

### Step 3.5: Commit Phase 3

```bash
git add -A
git commit -m "feat(089): Phase 3 - Update documentation for active system boundary

- Update CLAUDE.md to reflect only active targets (hetzner-sway, m1)
- Update README.md to remove WSL and deprecated configuration references
- Create archived/DEPRECATED_FEATURES.md documenting deprecated features
- Remove all mentions of obsolete configurations from user-facing docs

Impact: Documentation accurately reflects current system state

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Rollback Procedures

If validation fails at any phase:

### Quick Rollback (Uncommitted Changes)

```bash
# Discard all uncommitted changes
git reset --hard HEAD

# Validation should now pass again
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
```

### Rollback After Commit

```bash
# Rollback to previous commit
git reset --hard HEAD~1

# Or rollback to specific commit
git log --oneline  # Find the commit before cleanup
git reset --hard <commit-hash>

# Validation should now pass
specs/089-nixos-home-manager-cleanup/contracts/validation.sh
```

### Emergency Access (System Won't Boot)

If you've already applied changes with `nixos-rebuild switch` and the system won't boot:

1. **Boot into previous generation**:
   - At bootloader (systemd-boot), select previous NixOS generation
   - System should boot with old configuration

2. **Rollback permanently**:
   ```bash
   # List generations
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   
   # Rollback to previous
   sudo nix-env --rollback --profile /nix/var/nix/profiles/system
   
   # Reboot
   sudo reboot
   ```

3. **Fix configuration**:
   - Git reset to working commit
   - Fix issues
   - Re-run dry-build before applying

---

## Troubleshooting

### Import Errors

**Error**: `Path 'modules/desktop/xrdp.nix' does not exist`

**Cause**: Module was deleted but still referenced in a configuration

**Fix**:
```bash
# Find all references
rg "xrdp.nix" configurations/ modules/

# Remove the import line from the referencing file
```

### Missing Dependencies

**Error**: `The option 'services.xrdp-i3.enable' does not exist`

**Cause**: Configuration uses options from a deleted module

**Fix**:
```bash
# Find all option references
rg "services.xrdp-i3" configurations/

# Remove or comment out the option usage
```

### Build Failures

**Error**: Build fails with trace showing missing package

**Cause**: Deleted module provided a package

**Fix**:
```bash
# Check what packages were provided by deleted module
git show HEAD~1:modules/desktop/xrdp.nix | grep -A20 "systemPackages"

# Add necessary packages to configuration manually
```

### Flake Check Failures

**Error**: `nix flake check` fails after removing flake input

**Cause**: Input still referenced in flake.nix or modules

**Fix**:
```bash
# Search for input references
rg "plasma-manager" flake.nix configurations/ modules/

# Remove all references
```

---

## Success Criteria

After completing all three phases, verify:

- [ ] Both configurations build successfully (`validation.sh` passes)
- [ ] Hardware features are preserved (`hardware-validation.sh` passes)
- [ ] Codebase reduced by 1,200-1,500 LOC (check with `wc -l modules/**/*.nix`)
- [ ] At least 20 files moved to archived/ or deleted (`git log --stat`)
- [ ] Zero backup files remain (`find . -name "*.backup*" | wc -l` returns 0)
- [ ] Documentation reflects only active targets (hetzner-sway, m1)
- [ ] All 88 active features continue working (manual smoke tests)

---

## Next Steps

After completing the cleanup:

1. **Test on actual systems**: Deploy to hetzner-sway and m1 with `nixos-rebuild switch`
2. **Monitor for issues**: Watch for any functionality regressions
3. **Update feature documentation**: Ensure specs/ accurately reflects current state
4. **Create release notes**: Document the cleanup in project changelog

