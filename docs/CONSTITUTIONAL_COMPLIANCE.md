# Constitutional Compliance: Declarative Script Generation Pattern

**Document**: Constitutional Compliance Guide
**Date**: 2025-10-19
**Feature**: 014 - i3 Project Management System Consolidation
**Purpose**: Document the declarative script generation pattern for future NixOS modules

---

## Overview

This document describes the constitutional compliance pattern for converting imperative shell scripts to declarative Nix expressions. This pattern ensures **reproducibility**, **purity**, and **declarative configuration** as required by the NixOS Constitution Principle VI.

**Key Insight**: Instead of copying pre-existing shell scripts with `source = ./file.sh`, we generate scripts inline using Nix string interpolation with `text = ''...''` and `${pkgs.package}/bin/binary` paths.

---

## Constitution Principle VI: Declarative Configuration

**Requirement**: "All system configuration, including scripts, MUST be declared in NixOS/home-manager modules. No imperative post-install scripts except temporary migration/capture tools."

**Rationale**: Declarative generation guarantees:
1. **Reproducibility**: Same inputs → same outputs across all systems
2. **Purity**: No external dependencies on PATH or system state
3. **Auditability**: All binary paths explicitly visible in configuration
4. **Traceability**: Nix build system tracks all dependencies

---

## Anti-Pattern: Imperative Script Deployment

### ❌ WRONG (Imperative Copy)

```nix
# home-modules/desktop/i3-project-manager.nix
home.file.".config/i3/scripts/project-switch.sh" = {
  executable = true;
  source = ./scripts/project-switch.sh;  # ❌ IMPERATIVE COPY
};
```

**Problems**:
- Script exists as separate file outside Nix expression
- Binary paths hardcoded in script (depends on PATH)
- No guarantee script uses Nix-provided binaries
- Cannot use Nix interpolation for configuration values
- Harder to audit dependencies

---

## Correct Pattern: Declarative Generation

### ✅ CORRECT (Declarative Generation)

```nix
# home-modules/desktop/i3-project-manager.nix
home.file.".config/i3/scripts/project-switch.sh" = {
  executable = true;
  text = ''
    #!${pkgs.bash}/bin/bash
    # Project switcher script - declaratively generated

    PROJECT_NAME="$1"

    # Query i3 tree using Nix-provided jq binary
    windows=$(${pkgs.i3}/bin/i3-msg -t get_tree | ${pkgs.jq}/bin/jq -r '...')

    # Move windows using Nix-provided coreutils
    ${pkgs.i3}/bin/i3-msg "[con_mark=\"project:$PROJECT_NAME\"] move scratchpad"

    # Update active project file
    ${pkgs.coreutils}/bin/echo '{"name": "'"$PROJECT_NAME"'"}' > ~/.config/i3/active-project

    # Signal i3blocks
    ${pkgs.procps}/bin/pkill -RTMIN+10 i3blocks
  '';
};
```

**Benefits**:
- ✅ Script content inline in Nix expression
- ✅ All binary paths use `${pkgs.package}/bin/binary` format
- ✅ Shebang uses `${pkgs.bash}/bin/bash` (not `/bin/bash`)
- ✅ Can use Nix variables: `${toString cfg.timeout}`
- ✅ Dependencies tracked by Nix build system

---

## Standard Binary Path Mapping

### Core Utilities (`pkgs.coreutils`)

```nix
${pkgs.coreutils}/bin/cat
${pkgs.coreutils}/bin/echo
${pkgs.coreutils}/bin/date
${pkgs.coreutils}/bin/mv
${pkgs.coreutils}/bin/rm
${pkgs.coreutils}/bin/touch
${pkgs.coreutils}/bin/stat
${pkgs.coreutils}/bin/cut
${pkgs.coreutils}/bin/head
${pkgs.coreutils}/bin/tail
${pkgs.coreutils}/bin/sort
${pkgs.coreutils}/bin/uniq
```

### Text Processing

```nix
${pkgs.jq}/bin/jq              # JSON parsing (most common)
${pkgs.gawk}/bin/awk           # AWK text processing
${pkgs.gnugrep}/bin/grep       # Pattern matching
${pkgs.gnused}/bin/sed         # Stream editing
```

### Window Manager Integration

```nix
${pkgs.i3}/bin/i3-msg          # i3 IPC commands
${pkgs.xdotool}/bin/xdotool    # X11 window manipulation
${pkgs.rofi}/bin/rofi          # Application launcher
```

### System Monitoring (`pkgs.procps`, `pkgs.iproute2`)

```nix
${pkgs.procps}/bin/top
${pkgs.procps}/bin/ps
${pkgs.procps}/bin/pkill
${pkgs.iproute2}/bin/ip
```

### Applications

```nix
${pkgs.vscode}/bin/code
${pkgs.ghostty}/bin/ghostty
${pkgs.firefox}/bin/firefox
```

---

## Common Function Library Pattern

Instead of sourcing a common library file, define functions as a Nix variable:

```nix
let
  commonFunctions = ''
    # Logging function
    log() {
      local level="$1"
      shift
      local message="$*"
      local timestamp
      timestamp=$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')
      ${pkgs.coreutils}/bin/echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    }

    # i3 IPC wrapper
    i3_cmd() {
      ${pkgs.i3}/bin/i3-msg "$@"
    }

    # JSON parsing helper
    jq_parse() {
      ${pkgs.jq}/bin/jq "$@"
    }
  '';
in
{
  # Use commonFunctions in multiple scripts
  home.file.".config/i3/scripts/project-switch.sh".text = ''
    #!${pkgs.bash}/bin/bash
    ${commonFunctions}

    log "INFO" "Switching project..."
    i3_cmd -t get_tree
  '';

  home.file.".config/i3/scripts/project-list.sh".text = ''
    #!${pkgs.bash}/bin/bash
    ${commonFunctions}

    log "INFO" "Listing projects..."
  '';
}
```

---

## String Escaping Rules

### Single Quotes (Nix String)

```nix
text = ''
  echo "Hello World"        # ✅ CORRECT: Double quotes inside Nix string
  echo 'Single quotes'      # ✅ CORRECT: Bash single quotes
  echo "$VARIABLE"          # ✅ CORRECT: Bash variable expansion
'';
```

### Nix Interpolation

```nix
text = ''
  # Nix variable (evaluated at build time)
  TIMEOUT=${toString cfg.timeout}

  # Bash variable (evaluated at runtime)
  PROJECT_NAME="$1"

  # Nix path interpolation
  ${pkgs.jq}/bin/jq '.' file.json

  # Escape Nix interpolation if needed
  echo "''${BASH_VAR}"  # ✅ Two single quotes escape to one
'';
```

### Heredoc Pattern (JSON Generation)

```nix
text = ''
  # Generate JSON using heredoc
  cat > "$OUTPUT_FILE" <<'EOF'
  {
    "name": "example",
    "value": 123
  }
  EOF
'';
```

---

## Configuration Value Injection

### Module Options → Script Variables

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.i3ProjectManager;
in
{
  options.programs.i3ProjectManager = {
    timeout = mkOption {
      type = types.int;
      default = 5000;
      description = "Window detection timeout in milliseconds";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug logging";
    };
  };

  config = mkIf cfg.enable {
    home.file.".config/i3/scripts/launcher.sh".text = ''
      #!${pkgs.bash}/bin/bash

      # Nix options injected as script variables
      TIMEOUT=${toString cfg.timeout}
      DEBUG=${if cfg.debug then "1" else "0"}

      if [ "$DEBUG" = "1" ]; then
        ${pkgs.coreutils}/bin/echo "Debug mode enabled (timeout: $TIMEOUT ms)"
      fi
    '';
  };
}
```

---

## Migration Checklist

When converting existing scripts to declarative generation:

### 1. **Audit Phase**

- [ ] Identify all shell scripts deployed via `source = ./file.sh`
- [ ] List all external binaries used (jq, grep, awk, i3-msg, etc.)
- [ ] Identify shared functions used across scripts

### 2. **Conversion Phase**

- [ ] Replace `source = ./file.sh` with `text = ''...''`
- [ ] Change shebang: `#!/bin/bash` → `#!${pkgs.bash}/bin/bash`
- [ ] Replace all binary calls with `${pkgs.package}/bin/binary`
- [ ] Extract common functions into Nix `let` binding
- [ ] Test string escaping (Nix vs Bash variables)

### 3. **Validation Phase**

- [ ] Build configuration: `nixos-rebuild dry-build --flake .#<target>`
- [ ] Check script permissions: `ls -la ~/.config/scripts/`
- [ ] Verify binary paths: `head -1 ~/.config/scripts/*.sh` (shebang)
- [ ] Test runtime execution: `~/.config/scripts/script-name.sh`
- [ ] Check for PATH dependencies: `grep -n 'jq\|grep\|awk' script.sh` (should find none without `${pkgs.`)

### 4. **Cleanup Phase**

- [ ] Delete original `./scripts/*.sh` source files
- [ ] Remove `source =` references from module
- [ ] Update documentation
- [ ] Commit changes: "feat: convert scripts to declarative generation"

---

## Real-World Example: Feature 014 Conversion

### Before (21 scripts, 0% compliant)

```
home-modules/desktop/scripts/
├── i3-project-common.sh           (sourced by others)
├── project-create.sh
├── project-switch.sh
├── project-clear.sh
├── project-list.sh
├── project-current.sh
├── project-delete.sh
├── launch-code.sh
├── launch-ghostty.sh
├── launch-lazygit.sh
├── launch-yazi.sh
└── project-logs.sh

i3blocks/scripts/
├── project.sh
├── cpu.sh
├── memory.sh
├── network.sh
└── datetime.sh
```

**Deployment**:
```nix
home.file.".config/i3/scripts/project-switch.sh".source = ./scripts/project-switch.sh;
# ❌ Imperative copy, hardcoded paths
```

### After (0 files, 100% declarative)

All scripts generated inline in `home-modules/desktop/i3-project-manager.nix`:

```nix
let
  commonFunctions = ''
    # 150 lines of shared functions with ${pkgs.*}/bin/* paths
  '';
in
{
  home.file.".config/i3/scripts/project-switch.sh".text = ''
    #!${pkgs.bash}/bin/bash
    ${commonFunctions}
    # Script logic here
  '';

  home.file.".config/i3/scripts/project-list.sh".text = ''
    #!${pkgs.bash}/bin/bash
    ${commonFunctions}
    # Script logic here
  '';

  # ... 16 more scripts ...
}
```

**Benefits**:
- ✅ 100% reproducible
- ✅ All 120+ binary calls use Nix paths
- ✅ No external script files needed
- ✅ Single source of truth (Nix module)

---

## Shellcheck Integration

Validate generated scripts at build time:

```nix
{ config, lib, pkgs, ... }:

let
  scriptContent = ''
    #!${pkgs.bash}/bin/bash
    echo "Hello World"
  '';

  # Validate with shellcheck during build
  validatedScript = pkgs.runCommand "validated-script.sh" {
    buildInputs = [ pkgs.shellcheck ];
  } ''
    echo '${scriptContent}' > $out
    shellcheck $out
  '';
in
{
  home.file.".config/scripts/script.sh".source = validatedScript;
}
```

---

## Performance Considerations

**Build Time**: Minimal impact. String interpolation happens once during `nixos-rebuild`.

**Runtime**: Identical to imperative scripts. Generated scripts are normal bash files.

**Disk Usage**: Slightly larger (explicit paths), but negligible (KB difference).

---

## Troubleshooting

### Issue: "command not found" at runtime

**Cause**: Binary path missing `${pkgs.package}/bin/` prefix

**Fix**:
```bash
# ❌ WRONG
jq '.' file.json

# ✅ CORRECT
${pkgs.jq}/bin/jq '.' file.json
```

### Issue: Nix interpolation in wrong place

**Cause**: Using `${}` for Bash variable instead of Nix variable

**Fix**:
```nix
text = ''
  # Nix variable (build time)
  TIMEOUT=${toString cfg.timeout}

  # Bash variable (runtime) - escape with ''
  echo "Value: ''${BASH_VAR}"
'';
```

### Issue: Script not executable

**Cause**: Missing `executable = true` attribute

**Fix**:
```nix
home.file.".config/scripts/script.sh" = {
  executable = true;  # ← Required
  text = ''...'';
};
```

---

## Future Work

### Potential Enhancements

1. **Template Functions**: Create reusable Nix functions for common script patterns
   ```nix
   mkProjectScript = name: body: {
     home.file.".config/i3/scripts/${name}.sh" = {
       executable = true;
       text = ''
         #!${pkgs.bash}/bin/bash
         ${commonFunctions}
         ${body}
       '';
     };
   };
   ```

2. **Type-Safe Configuration**: Use Nix types to validate script parameters at build time

3. **Automatic Dependency Detection**: Analyze script content to automatically add packages to buildInputs

---

## References

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/#sec-writing-modules
- **Home Manager Manual**: https://nix-community.github.io/home-manager/
- **Nix Language**: https://nixos.org/manual/nix/stable/language/
- **Feature 014 Implementation**: `/etc/nixos/specs/014-create-a-new/`

---

**Version**: 1.0
**Last Updated**: 2025-10-19
**Maintained By**: NixOS Configuration Team
