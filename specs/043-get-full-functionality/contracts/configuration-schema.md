# Configuration Schema: Walker/Elephant Launcher

**Feature**: 043-get-full-functionality
**Date**: 2025-10-27

## Overview

This document defines the configuration contracts for Walker and Elephant launcher system. These are declarative NixOS/home-manager configurations that generate TOML config files and systemd service definitions.

---

## Walker Configuration (`~/.config/walker/config.toml`)

### Schema

```toml
# Window behavior (X11 mode)
as_window = boolean              # true = X11 window, false = Wayland layer shell
force_keyboard_focus = boolean   # Force keyboard focus on window open
close_when_open = boolean        # Close window when opening item

# Provider modules
[modules]
applications = boolean           # Desktop application launcher
calc = boolean                   # Calculator
clipboard = boolean              # Clipboard history
files = boolean                  # File search and browser
menus = boolean                  # Context menus
runner = boolean                 # Shell command execution
symbols = boolean                # Symbol/emoji picker
websearch = boolean              # Web search integration

# Provider prefixes (array of tables)
[[providers.prefixes]]
prefix = string                  # Keyboard shortcut (":", "/", "@", "=", ".", ">")
provider = string                # Provider name (matches module name)

# Provider actions (nested tables by provider)
[[providers.actions.<provider>]]
action = string                  # Action identifier ("open", "run", "runterminal")
bind = string                    # Keybinding ("Return", "shift Return", "ctrl Return")
default = boolean                # Is this the default action?
after = string                   # Behavior after action ("Close", "Nothing")
label = string                   # Action label for UI

# Custom plugins (array of tables)
[[plugins]]
name = string                    # Plugin identifier
prefix = string                  # Activation prefix (";s ", ";p ")
src_once = string                # Command to populate items (run once)
cmd = string                     # Command to execute on selection (%RESULT% placeholder)
keep_sort = boolean              # Preserve original sort order?
recalculate_score = boolean      # Recalculate fuzzy match score?
show_icon_when_single = boolean  # Show icon if single result?
switcher_only = boolean          # Plugin is for switching only (no search)?
```

### Validation Rules

- `as_window` MUST be `true` for X11 environments
- At least one module MUST be enabled
- Each provider prefix MUST be unique
- Each provider prefix MUST reference an enabled module
- Provider actions MUST reference valid providers
- Exactly one action per provider MUST be marked `default = true`
- Plugin `cmd` MUST include `%RESULT%` placeholder if it uses selection
- Plugin `src_once` output MUST be newline-separated list

### Example

```toml
as_window = true
close_when_open = true

[modules]
applications = true
clipboard = true
files = true

[[providers.prefixes]]
prefix = ":"
provider = "clipboard"

[[providers.prefixes]]
prefix = "/"
provider = "files"

[[providers.actions.files]]
action = "run /path/to/walker-open-in-nvim %RESULT%"
bind = "Return"
default = true
after = "Close"
label = "open in nvim"
```

---

## Elephant Websearch Configuration (`~/.config/elephant/websearch.toml`)

### Schema

```toml
# Search engines (array of tables)
[[engines]]
name = string                    # Display name ("Google", "DuckDuckGo")
url = string                     # URL template with %s placeholder

# Default engine (top-level key)
default = string                 # Engine name (must match an engines.name)
```

### Validation Rules

- Each engine MUST have unique `name`
- Each engine `url` MUST contain exactly one `%s` placeholder
- Each engine `url` MUST be valid HTTPS URL
- `default` MUST reference an existing engine name
- At least one engine MUST be defined

### URL Template Substitution

When user searches for "nixos tutorial":
```
Input: "nixos tutorial"
Template: "https://www.google.com/search?q=%s"
Output: "https://www.google.com/search?q=nixos+tutorial"

Encoding rules:
- Space → "+"
- Special chars → URL percent encoding
```

### Example

```toml
[[engines]]
name = "Google"
url = "https://www.google.com/search?q=%s"

[[engines]]
name = "DuckDuckGo"
url = "https://duckduckgo.com/?q=%s"

[[engines]]
name = "GitHub"
url = "https://github.com/search?q=%s"

default = "Google"
```

---

## Systemd Service Configuration (Elephant)

### Service Unit Schema

```ini
[Unit]
Description = string             # Service description
PartOf = [string]                # Parent targets (service stops when parent stops)
After = [string]                 # Start after these units

[Service]
ExecStart = string               # Command to execute
Restart = string                 # Restart policy ("on-failure", "always", "no")
RestartSec = integer             # Delay before restart (seconds)
Environment = [string]           # Static environment variables
PassEnvironment = [string]       # Dynamic environment variables to pass through

[Install]
WantedBy = [string]              # Targets that depend on this service
```

### Validation Rules

- `ExecStart` MUST be absolute path to executable
- `Restart` MUST be one of: "no", "on-failure", "on-abnormal", "always"
- `RestartSec` MUST be positive integer (seconds)
- `PassEnvironment` variables MUST be available in systemd user environment
- `WantedBy` MUST reference valid systemd targets

### Environment Variables (Elephant Service)

```bash
# Static environment (set via Environment=)
PATH=/home/user/.local/bin:/nix/profile/bin:/run/current-system/sw/bin
XDG_DATA_DIRS=/home/user/.local/share/i3pm-applications
XDG_RUNTIME_DIR=%t  # systemd specifier → /run/user/1000

# Dynamic environment (inherited via PassEnvironment=)
DISPLAY=:10  # Set by X11/xrdp, varies per session
```

### Example

```ini
[Unit]
Description=Elephant launcher backend (X11)
PartOf=default.target
After=default.target

[Service]
ExecStart=/nix/store/xxx-elephant/bin/elephant
Restart=on-failure
RestartSec=1
Environment="PATH=/home/user/.local/bin:/nix/profile/bin"
Environment="XDG_DATA_DIRS=/home/user/.local/share/i3pm-applications"
Environment="XDG_RUNTIME_DIR=%t"
PassEnvironment=DISPLAY

[Install]
WantedBy=default.target
```

---

## i3 Configuration (Walker Integration)

### Keybinding Schema

```
bindsym <modifier>+<key> exec <command>
```

**Parameters**:
- `modifier`: Mod1 (Alt), Mod4 (Super/Win), Shift, Control
- `key`: Letter, number, or special key name
- `command`: Full command with arguments

### Environment Variable Injection

Walker launch command includes environment overrides:
```bash
env GDK_BACKEND=x11 XDG_DATA_DIRS="/path/to/i3pm-applications:$XDG_DATA_DIRS" /path/to/walker
```

**Required Environment Overrides**:
- `GDK_BACKEND=x11`: Force GTK4 to use X11 backend (not Wayland)
- `XDG_DATA_DIRS`: Include i3pm-applications directory for registry filtering

### Window Rules Schema

```
for_window [<criteria>] <command>
```

**Walker Window Rule**:
```
for_window [class="walker"] floating enable, border pixel 0, move position center, mark _global_ui
```

**Explanation**:
- `[class="walker"]`: Match windows with WM_CLASS=walker
- `floating enable`: Make window floating (not tiled)
- `border pixel 0`: No window border
- `move position center`: Center window on screen
- `mark _global_ui`: Mark window to prevent project-scoped filtering

### DISPLAY Import

```
exec_always --no-startup-id systemctl --user import-environment DISPLAY
exec_always --no-startup-id systemctl --user restart elephant.service
```

**Sequence**:
1. Import DISPLAY into systemd user environment (makes it available to user services)
2. Restart Elephant service to pick up DISPLAY variable

**Timing**: `exec_always` ensures this runs on i3 startup and reload

---

## NixOS Module Configuration (home-manager)

### Walker Module Schema

```nix
programs.walker = {
  enable = boolean;
  runAsService = boolean;
  config = {
    # TOML configuration as Nix attrset
    # (or use lib.mkForce {} to disable and use xdg.configFile instead)
  };
};

xdg.configFile."walker/config.toml" = {
  text = string;  # TOML content as string
};

xdg.configFile."elephant/websearch.toml" = {
  text = string;  # TOML content as string
};
```

### Systemd Service Module Schema

```nix
systemd.user.services.elephant = {
  Unit = {
    Description = string;
    PartOf = [ string ];
    After = [ string ];
  };
  Service = {
    ExecStart = string;
    Restart = string;
    RestartSec = integer;
    Environment = [ string ];
    PassEnvironment = [ string ];
  };
  Install = {
    WantedBy = [ string ];
  };
};
```

### Validation Rules (NixOS)

- `ExecStart` MUST use `${pkgs.package}/bin/executable` format for reproducibility
- String interpolation MUST use Nix variables, not shell variables (use `${var}` not `$var`)
- TOML text MUST be valid TOML syntax (Nix will validate on build)
- Service definition MUST include all required systemd unit keys

### Example (Nix)

```nix
{ config, pkgs, ... }:

{
  programs.walker = {
    enable = true;
    runAsService = false;  # Use direct invocation
    config = lib.mkForce {};  # Disable upstream config generation
  };

  xdg.configFile."walker/config.toml".text = ''
    as_window = true

    [modules]
    clipboard = true
    files = true

    [[providers.prefixes]]
    prefix = ":"
    provider = "clipboard"
  '';

  xdg.configFile."elephant/websearch.toml".text = ''
    [[engines]]
    name = "Google"
    url = "https://www.google.com/search?q=%s"

    default = "Google"
  '';

  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant launcher backend";
      After = [ "default.target" ];
    };
    Service = {
      ExecStart = "${pkgs.elephant}/bin/elephant";
      Restart = "on-failure";
      PassEnvironment = [ "DISPLAY" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
```

---

## Contract Validation

### Build-Time Validation (NixOS)

```bash
# Validate TOML syntax
nix eval --raw '.#nixosConfigurations.hetzner.config.home-manager.users.user.xdg.configFile."walker/config.toml".text' | tomlq .

# Validate systemd service
systemctl --user cat elephant.service

# Dry-build entire configuration
nixos-rebuild dry-build --flake .#hetzner
```

### Runtime Validation

```bash
# Check Elephant service environment
systemctl --user show-environment | grep -E "DISPLAY|PATH|XDG_"

# Check Elephant service status
systemctl --user status elephant

# Check Walker config loaded
cat ~/.config/walker/config.toml

# Check websearch config loaded
cat ~/.config/elephant/websearch.toml

# Test Walker launch
env GDK_BACKEND=x11 walker
```

### Functional Validation

| Provider | Test Command | Expected Result |
|----------|--------------|-----------------|
| Applications | Meta+D → type "code" | VS Code appears in list |
| Clipboard | Meta+D → type ":" | Clipboard history appears |
| Files | Meta+D → type "/nixos" | Files matching "nixos" appear |
| Websearch | Meta+D → type "@test" | Search engines appear |
| Calculator | Meta+D → type "=2+2" | Result "4" appears |
| Symbols | Meta+D → type ".lambda" | λ symbol appears |
| Runner | Meta+D → type ">echo hello" | Command ready to execute |

---

## Error Handling

### Invalid TOML Syntax

**Symptom**: NixOS rebuild fails with TOML parse error

**Example Error**:
```
error: invalid TOML syntax at line 12, column 5
```

**Resolution**: Fix TOML syntax in `xdg.configFile."walker/config.toml".text` or `websearch.toml`

---

### Missing Environment Variable

**Symptom**: Elephant service fails to start or applications don't display

**Diagnosis**:
```bash
systemctl --user status elephant
# Check logs for "DISPLAY not set" or similar

systemctl --user show-environment | grep DISPLAY
# Should output: DISPLAY=:10 (or similar)
```

**Resolution**: Ensure i3 config imports DISPLAY before restarting Elephant

---

### Invalid Search Engine URL

**Symptom**: Web search fails to open browser or opens malformed URL

**Example**: URL missing `%s` placeholder
```toml
[[engines]]
name = "Google"
url = "https://www.google.com/search?q=test"  # ❌ Missing %s
```

**Validation**:
```bash
# Check websearch.toml for %s placeholder
grep '%s' ~/.config/elephant/websearch.toml
```

**Resolution**: Fix URL template to include `%s` placeholder

---

## Version Compatibility

| Component | Minimum Version | Reason |
|-----------|----------------|--------|
| Walker | 1.5.0 | X11 file provider fix |
| Elephant | (matches Walker) | Package from same flake input |
| NixOS | 24.05 | systemd user session support |
| i3wm | 4.20+ | Window marking and rules |

---

## Configuration Change Impact Matrix

| Change | Requires Restart | Validation Method |
|--------|------------------|-------------------|
| Walker config.toml | No (Walker reads on launch) | Launch Walker, verify behavior |
| Elephant websearch.toml | Yes (Elephant service) | `systemctl --user restart elephant` |
| Elephant service env | Yes (NixOS rebuild) | `nixos-rebuild switch` |
| i3 keybindings | Yes (i3 reload) | `i3-msg reload` |
| i3 window rules | Yes (i3 reload) | `i3-msg reload` |

---

## Summary

This configuration schema defines the contracts between:
1. **NixOS/home-manager** → TOML config files (Walker, Elephant websearch)
2. **NixOS/home-manager** → systemd service definitions (Elephant)
3. **NixOS/home-manager** → i3 configuration (keybindings, window rules, DISPLAY import)

All configurations are declarative and reproducible via NixOS rebuild workflow. Changes are validated at build time (TOML syntax, Nix evaluation) and verified at runtime (service status, functional tests).
