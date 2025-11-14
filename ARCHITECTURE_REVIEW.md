# NixOS Flakes Architecture Review

**Date:** 2025-11-14
**Reviewed Configuration:** `/home/user/nixos-config`

## Executive Summary

Your NixOS configuration demonstrates a **well-structured, modular flake-based architecture** with good separation of concerns. The hybrid approach combining NixOS modules for system configuration and Home Manager for user-level configuration aligns with modern best practices. However, there are opportunities to reduce duplication and improve maintainability using established patterns from the NixOS community.

---

## Current Architecture Analysis

### Overview

- **550 lines** in `flake.nix` (primary entry point)
- **91 home-manager modules** in `home-modules/`
- **32 system modules** in `modules/`
- **3 NixOS configurations:** `hetzner-sway`, `m1`, container builds
- **3 Home configurations:** `vpittamp`, `code`, `darwin`

### Architecture Pattern: Hybrid NixOS Module + Standalone Home Manager

Your configuration uses a **dual-output pattern**:

1. **nixosConfigurations** - System-level builds with Home Manager integrated as a NixOS module
2. **homeConfigurations** - Standalone Home Manager configurations for non-NixOS systems

```nix
# Current pattern in flake.nix
nixosConfigurations = {
  hetzner-sway = nixpkgs.lib.nixosSystem {
    modules = [
      home-manager.nixosModules.home-manager  # ← Integrated
      { home-manager.users.vpittamp = { imports = [...]; }; }
    ];
  };
};

homeConfigurations = {
  vpittamp = home-manager.lib.homeManagerConfiguration {  # ← Standalone
    pkgs = ...;
    modules = [ ./home-vpittamp.nix ];
  };
};
```

### Home Manager Integration Method

You're using the **NixOS module integration** approach with these settings:

```nix
home-manager = {
  useGlobalPkgs = true;        # ✓ Correct - shares pkgs instance
  useUserPackages = true;      # ✓ Correct - installs to /etc/profiles
  backupFileExtension = "backup";  # ✓ Good for conflict management
  extraSpecialArgs = {         # ✓ Passes flake inputs to HM modules
    inherit inputs self;
    pkgs-unstable = ...;       # ✓ Provides bleeding-edge packages
    osConfig = config;         # ✓ Allows HM to read NixOS config
  };
};
```

### Directory Structure

```
nixos-config/
├── flake.nix                    # 550 lines - central entry point
├── configurations/              # System-level configs (hetzner, m1, etc.)
├── modules/                     # NixOS modules (system-wide)
│   ├── desktop/                 # Desktop environment (Sway, i3, etc.)
│   ├── services/                # System services
│   └── assertions/              # Environment validation
├── home-modules/                # Home Manager modules (91 modules)
│   ├── profiles/                # Base profiles
│   ├── desktop/                 # Window managers, bars
│   ├── tools/                   # CLI tools, applications
│   ├── editors/                 # Neovim, VS Code
│   ├── shell/                   # Bash, Starship
│   └── terminal/                # Ghostty, tmux
├── hardware/                    # Hardware-specific (M1, etc.)
└── home-vpittamp.nix           # User entry point
```

**Assessment:** ✓ Excellent separation of concerns, clear naming conventions

---

## What You're Doing Well

### ✓ 1. Input Follows Pattern

```nix
home-manager = {
  url = "github:nix-community/home-manager/master";
  inputs.nixpkgs.follows = "nixpkgs";  # ✓ Prevents version conflicts
};
```

This prevents the common issue of Home Manager using a different nixpkgs version.

### ✓ 2. Modular Structure

- **91 home modules** organized by function (tools, desktop, editors, etc.)
- **32 system modules** focused on specific services
- Clear separation between system (`modules/`) and user (`home-modules/`)

### ✓ 3. Multi-Architecture Support

You correctly handle multiple architectures (x86_64-linux, aarch64-linux, aarch64-darwin) without helper libraries:

```nix
packages = {
  x86_64-linux = mkPackagesFor "x86_64-linux";
  aarch64-linux = mkPackagesFor "aarch64-linux";
};
```

### ✓ 4. DRY Helper Functions

Your `mkSystem` helper reduces duplication:

```nix
mkSystem = { hostname, system, modules }: ...
```

**However:** You don't use it consistently - `hetzner-sway` and `m1` are manually defined instead.

### ✓ 5. Build Metadata Tracking

```nix
environment.etc."nixos-metadata".text = ''
  GIT_COMMIT=${self.rev or self.dirtyRev or "unknown"}
  NIXPKGS_REV=${inputs.nixpkgs.rev or "unknown"}
  # ... reproducibility info
'';
```

Excellent for debugging and reproducibility!

### ✓ 6. Dual Package Sets

```nix
extraSpecialArgs = {
  pkgs-unstable = import nixpkgs-bleeding { ... };
};
```

Allows stable base with bleeding-edge packages where needed.

---

## Issues & Improvement Opportunities

### ⚠️ 1. Inconsistent Use of mkSystem Helper

**Issue:** Lines 173-220 manually define `hetzner-sway` instead of using your `mkSystem` helper.

**Impact:** Code duplication, harder to maintain

**Fix:** Either use `mkSystem` consistently OR remove it if manual control is needed.

### ⚠️ 2. Large Monolithic flake.nix (550 lines)

**Issue:** All configuration logic in a single file makes it harder to navigate.

**Community Pattern:** Most mature configs extract outputs to separate files:

```nix
# Better pattern (from search results)
outputs = { self, nixpkgs, home-manager, ... }: {
  nixosConfigurations = import ./hosts { inherit inputs; };
  homeConfigurations = import ./home { inherit inputs; };
  packages = import ./packages { inherit inputs; };
};
```

### ⚠️ 3. Duplicate Home Manager Integration Code

**Issue:** Lines 126-150, 196-218, 255-274 repeat similar Home Manager setup logic.

**Fix:** Extract common HM config to a function or separate module.

### ⚠️ 4. homeConfigurations Partially Redundant

**Issue:** Your standalone `homeConfigurations` duplicates user config already in `nixosConfigurations`.

**Question:** Are you actually using `homeConfigurations.vpittamp` or is it only for the Darwin system?

**Assessment:**
- `homeConfigurations.darwin` → ✓ Necessary (macOS doesn't use nixosConfigurations)
- `homeConfigurations.vpittamp/code` → ⚠️ Potentially redundant if only used on NixOS

### ⚠️ 5. Manual osConfig Simulation in homeConfigurations

Lines 294-296:
```nix
osConfigFor = system:
  if system == "aarch64-linux" then self.nixosConfigurations.m1.config
  else self.nixosConfigurations.hetzner-sway.config;
```

**Issue:** Creates circular dependency risk and assumes system architecture = specific host.

### ⚠️ 6. No Use of flake-parts or Similar

**Observation:** You manually handle per-system outputs.

**Trade-off:** More explicit control vs. community-standard patterns and less boilerplate.

---

## Alternative Architectures

### Option A: Current Hybrid (Your Approach)

**Pattern:** Home Manager as NixOS module + standalone homeConfigurations

**Pros:**
- ✓ Single rebuild command (`nixos-rebuild switch`)
- ✓ Guarantees system/user config consistency
- ✓ Access to `osConfig` in Home Manager modules
- ✓ Supports non-NixOS systems via standalone configs

**Cons:**
- ✗ Some code duplication between nixosConfigurations and homeConfigurations
- ✗ Manual management of per-system outputs
- ✗ Larger flake.nix file

**Best For:** Users who want atomic system+user rebuilds and support multiple platforms (NixOS + macOS/Linux)

---

### Option B: Standalone Home Manager Only

**Pattern:** Use `homeConfigurations` exclusively, keep system config minimal

```nix
nixosConfigurations.hetzner-sway = {
  # Only system-critical stuff (boot, networking, users)
};

homeConfigurations.vpittamp = {
  # ALL user software and config
};
```

**Pros:**
- ✓ Maximum portability (same config on any Linux/macOS)
- ✓ Faster user-space iterations (no root/reboot needed)
- ✓ Better security (less software with root privileges)
- ✓ Simpler flake outputs

**Cons:**
- ✗ Two separate rebuild commands
- ✗ No access to `osConfig` (can't read system settings)
- ✗ Harder to coordinate system and user services
- ✗ Not suitable if desktop environment needs system integration (e.g., Sway needs system-level config)

**Best For:** Users prioritizing portability or using minimal window managers that don't need system integration

---

### Option C: Integrated Home Manager (No Standalone)

**Pattern:** Only use `nixosConfigurations` with Home Manager as module, remove `homeConfigurations`

```nix
nixosConfigurations.hetzner-sway = {
  modules = [
    home-manager.nixosModules.home-manager
    { home-manager.users.vpittamp.imports = [ ./home.nix ]; }
  ];
};

# No homeConfigurations output
```

**Pros:**
- ✓ Single source of truth
- ✓ No duplication
- ✓ Simpler mental model
- ✓ One rebuild command

**Cons:**
- ✗ Can't use same config on non-NixOS systems
- ✗ Requires root access to update user config

**Best For:** Users who only use NixOS and want maximum simplicity

---

### Option D: flake-parts Modularization

**Pattern:** Use `flake-parts` to organize outputs into modules

```nix
# flake.nix
{
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      imports = [
        ./hosts        # nixosConfigurations
        ./home         # homeConfigurations
        ./packages     # packages output
        ./checks       # checks output
      ];
    };
}

# hosts/default.nix
{ inputs, ... }: {
  flake.nixosConfigurations = {
    hetzner-sway = ...;
    m1 = ...;
  };
}
```

**Pros:**
- ✓ Drastically reduces boilerplate
- ✓ Automatic per-system handling
- ✓ Community-standard pattern (increasing adoption in 2025)
- ✓ Composable modules
- ✓ Cleaner flake.nix (<50 lines typical)

**Cons:**
- ✗ Additional dependency
- ✗ Learning curve
- ✗ Slightly more abstraction

**Best For:** Complex configurations with multiple systems, architectures, and output types

---

### Option E: Directory-per-Host Pattern

**Pattern:** Move each host config to its own directory with dedicated flake

```
nixos-config/
├── flake.nix                    # Root flake with common inputs
├── hosts/
│   ├── hetzner-sway/
│   │   ├── configuration.nix
│   │   └── home.nix
│   └── m1/
│       ├── configuration.nix
│       └── home.nix
└── common/                      # Shared modules
```

```nix
# Root flake.nix
nixosConfigurations = {
  hetzner-sway = import ./hosts/hetzner-sway { inherit inputs; };
  m1 = import ./hosts/m1 { inherit inputs; };
};
```

**Pros:**
- ✓ Clear host isolation
- ✓ Easy to understand what affects which host
- ✓ Git history cleaner per host

**Cons:**
- ✗ More files/directories
- ✗ Can lead to duplication without discipline

**Best For:** Teams managing many hosts with distinct configs

---

## Comparison Matrix

| Aspect | Current (A) | Standalone HM (B) | Integrated Only (C) | flake-parts (D) | Per-Host Dirs (E) |
|--------|-------------|-------------------|---------------------|-----------------|-------------------|
| **Simplicity** | Medium | High | High | Medium | Medium |
| **Portability** | High | Very High | Low | High | High |
| **Maintenance** | Medium | High | Very High | Very High | Medium |
| **Boilerplate** | High | Medium | Low | Very Low | Medium |
| **Rebuild Speed** | Slow (system) | Fast (user) | Slow (system) | Same as current | Same as current |
| **Security** | Good | Excellent | Good | Good | Good |
| **Multi-Platform** | Yes | Yes | No | Yes | Yes |
| **Learning Curve** | Low | Low | Low | Medium | Low |

---

## Recommendations

### Immediate Improvements (No Architecture Change)

1. **Extract outputs to separate files** - Reduce flake.nix to <200 lines
   ```nix
   nixosConfigurations = import ./nixos { inherit inputs self nixpkgs home-manager; };
   homeConfigurations = import ./home { inherit inputs self nixpkgs home-manager; };
   ```

2. **Fix mkSystem inconsistency** - Either use it for all hosts or remove it

3. **Create common Home Manager config function**
   ```nix
   mkHomeConfig = user: extraModules: {
     home-manager = {
       useGlobalPkgs = true;
       useUserPackages = true;
       extraSpecialArgs = { inherit inputs self pkgs-unstable; };
       users.${user}.imports = extraModules;
     };
   };
   ```

4. **Clarify homeConfigurations purpose**
   - Keep `darwin` (needed for macOS)
   - Remove `vpittamp`/`code` if only used on NixOS systems (use nixosConfigurations instead)
   - OR document when/why standalone configs are used

### Medium-Term (Consider After Current Work)

5. **Evaluate flake-parts adoption** if you add more hosts/systems
   - Would reduce your 550-line flake.nix to ~100 lines
   - See: https://flake.parts/

6. **Split large home modules** - Some modules in `home-modules/` could be broken down further

### Long-Term (Strategic)

7. **Consider per-host directories** if config diverges significantly between hetzner and m1

8. **Evaluate standalone Home Manager** if you prioritize:
   - Faster iteration cycles
   - Better security posture
   - Cross-distro portability

---

## Specific Code Issues

### Circular Dependency Risk (Lines 294-296)

```nix
# CURRENT - Can cause infinite recursion
osConfigFor = system:
  if system == "aarch64-linux" then self.nixosConfigurations.m1.config
  else self.nixosConfigurations.hetzner-sway.config;
```

**Fix:** Remove `osConfig` from standalone homeConfigurations or use a safer pattern:

```nix
# OPTION 1: Don't provide osConfig for standalone
homeConfigurations.vpittamp = home-manager.lib.homeManagerConfiguration {
  extraSpecialArgs = { inherit inputs pkgs-unstable; };  # No osConfig
};

# OPTION 2: Only provide for Darwin where nixosConfigurations doesn't exist
homeConfigurations.darwin = home-manager.lib.homeManagerConfiguration {
  extraSpecialArgs = { inherit inputs pkgs-unstable; };  # No osConfig on Darwin
};
```

### Unused mkSystem Helper

Lines 82-152 define `mkSystem` but it's only used by the (commented out) `hetzner` config. Either:

**Option A:** Use it consistently
```nix
hetzner-sway = mkSystem {
  hostname = "nixos-hetzner-sway";
  system = "x86_64-linux";
  modules = [ ./configurations/hetzner-sway.nix ];
};
```

**Option B:** Remove it and embrace manual definitions for flexibility

---

## Best Practices Validation

### ✓ You're Following These

- [x] `inputs.nixpkgs.follows = "nixpkgs"` for home-manager
- [x] `useGlobalPkgs = true` and `useUserPackages = true`
- [x] Modular structure with clear separation
- [x] Multi-architecture support
- [x] Build metadata tracking
- [x] Git-tracked flake.lock for reproducibility

### ⚠️ Consider Adding

- [ ] Extract outputs to separate files (reduce flake.nix size)
- [ ] Use `flake-parts` or similar for per-system boilerplate
- [ ] Document when to use nixosConfigurations vs homeConfigurations
- [ ] Add CI checks for flake evaluation (nix flake check)
- [ ] Consider using `nixosModules` output for reusable modules

---

## Conclusion

Your configuration is **well-architected** and follows most NixOS best practices. The hybrid approach (NixOS module + standalone Home Manager) makes sense for your multi-platform use case (NixOS + macOS).

**Top 3 Priorities:**

1. **Extract flake outputs to separate files** - Improves maintainability
2. **Fix or remove mkSystem helper** - Eliminate dead code
3. **Clarify homeConfigurations strategy** - Remove redundant standalone configs or document their purpose

**Strategic Decision:**

Consider **Option D (flake-parts)** if you:
- Plan to add more systems/architectures
- Want to reduce boilerplate
- Value community-standard patterns

Stick with **current approach** if you:
- Prefer explicit control over magic abstractions
- Are happy with current maintainability
- Don't plan significant expansion

---

## Resources

- **Home Manager Manual:** https://nix-community.github.io/home-manager/
- **flake-parts Documentation:** https://flake.parts/
- **NixOS & Flakes Book:** https://nixos-and-flakes.thiscute.world/
- **Misterio77's Starter Configs:** https://github.com/Misterio77/nix-starter-configs
- **NixOS Wiki - Flakes:** https://wiki.nixos.org/wiki/Flakes

---

**Review Date:** 2025-11-14
**Configuration Version:** `flake.lock` lastModified varies by input
**Reviewer:** Claude (Anthropic AI Assistant)
