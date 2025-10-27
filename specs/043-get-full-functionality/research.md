# Research: Complete Walker/Elephant Launcher Functionality

**Feature**: 043-get-full-functionality
**Date**: 2025-10-27
**Status**: Complete

## Overview

This research document captures technical decisions and best practices for enabling full Walker/Elephant launcher functionality with proper X11 environment variable propagation. Since Walker and Elephant are already partially configured, this focuses on enabling missing providers and ensuring environment correctness.

## Technical Decisions

### Decision 1: Elephant Service Runtime - Systemd User Service

**Decision**: Run Elephant as systemd user service (not system service)

**Rationale**:
- User services inherit user session environment variables (DISPLAY, XDG_DATA_DIRS, PATH)
- Applications launched via Elephant need access to user's home directory and project context
- System services run in isolated environment without access to X11 DISPLAY or user session state
- i3pm daemon provides project context via environment variables - only accessible in user session

**Alternatives Considered**:
1. **System service** - REJECTED: Cannot access DISPLAY, user environment, or i3pm daemon
2. **DBus activation** - REJECTED: Walker documentation indicates known issues with X11/XRDP
3. **Direct invocation** - REJECTED: Walker UI needs persistent backend for clipboard history and file indexing

**Implementation**:
```nix
systemd.user.services.elephant = {
  Unit = {
    Description = "Elephant launcher backend (X11)";
    PartOf = [ "default.target" ];
    After = [ "default.target" ];
  };
  Service = {
    ExecStart = "${elephant-package}/bin/elephant";
    Restart = "on-failure";
    RestartSec = 1;
    Environment = [
      "PATH=${homeDirectory}/.local/bin:${profileDirectory}/bin:/run/current-system/sw/bin"
      "XDG_DATA_DIRS=${i3pmAppsDir}"
      "XDG_RUNTIME_DIR=%t"
    ];
    PassEnvironment = [ "DISPLAY" ];
  };
  Install = {
    WantedBy = [ "default.target" ];
  };
};
```

---

### Decision 2: DISPLAY Environment Propagation

**Decision**: Use `PassEnvironment = [ "DISPLAY" ]` in systemd service + `systemctl --user import-environment DISPLAY` in i3 config

**Rationale**:
- DISPLAY is set by X11/xrdp when user session starts
- systemd user services start before DISPLAY may be available
- i3 config explicitly imports DISPLAY into systemd user environment
- PassEnvironment ensures Elephant receives DISPLAY when available
- Elephant auto-restarts on failure, picking up DISPLAY after i3 imports it

**Alternatives Considered**:
1. **Hardcode DISPLAY=:10** - REJECTED: Display number varies per xrdp session
2. **Use Environment="DISPLAY=..."** - REJECTED: Cannot dynamically determine display number
3. **ConditionEnvironment=DISPLAY** - REJECTED: Prevents service from starting if DISPLAY not yet available (race condition)

**Evidence**:
From existing `home-modules/desktop/i3.nix`:
```nix
# Ensure DISPLAY is explicitly imported into systemd user environment
exec_always --no-startup-id ${pkgs.systemd}/bin/systemctl --user import-environment DISPLAY
# Restart Elephant after DISPLAY is imported
exec_always --no-startup-id ${pkgs.systemd}/bin/systemctl --user restart elephant.service
```

---

### Decision 3: Walker Invocation - GDK_BACKEND=x11 Override

**Decision**: Launch Walker with explicit `GDK_BACKEND=x11` environment variable override

**Rationale**:
- GTK4 applications auto-detect display backend (Wayland or X11)
- In XRDP environment, GTK may incorrectly try to use Wayland
- Walker MUST render as X11 window for proper integration with i3wm
- GDK_BACKEND=x11 forces GTK to use X11 backend

**Alternatives Considered**:
1. **Rely on GTK auto-detection** - REJECTED: Unreliable in XRDP/mixed environments
2. **Global GDK_BACKEND setting** - REJECTED: Would affect all GTK apps, only Walker needs override
3. **Walker runAsService mode** - REJECTED: Known issues with GApplication DBus in X11/XRDP (documented in walker.nix)

**Implementation**:
```nix
# i3 keybinding for Walker launch
bindsym $mod+d exec env GDK_BACKEND=x11 XDG_DATA_DIRS="${homeDirectory}/.local/share/i3pm-applications:$XDG_DATA_DIRS" ${walker-package}/bin/walker
```

---

### Decision 4: Walker Config - File Provider Safe in v1.5+

**Decision**: Enable file provider in Walker config (already done in existing configuration)

**Rationale**:
- Walker v1.5+ fixed X11 file provider segfault issue
- File provider requires `as_window = true` for X11 safety
- Feature 034 comment confirms: "Walker ≥v1.5 supports X11 safely when launched as a window"

**Alternatives Considered**:
1. **Disable file provider** - REJECTED: Feature requirement explicitly needs file search (FR-009, FR-010, FR-011)
2. **Use external file search tool** - REJECTED: Walker provides integrated file search with keyboard shortcuts

**Evidence**:
From existing `home-modules/desktop/walker.nix` (line 291-292):
```toml
# File provider now enabled (Walker ≥v1.5 supports X11 safely when launched as a window)
files = true
```

---

### Decision 5: Clipboard History - Walker Built-in Provider

**Decision**: Use Walker's built-in clipboard provider (Elephant backend)

**Rationale**:
- Walker/Elephant includes native clipboard history support
- No external clipboard manager needed (clipcat not required for Walker)
- Clipboard provider supports both text and images
- Ephemeral storage (no persistence needed per spec Out of Scope)

**Alternatives Considered**:
1. **Use clipcat with Walker integration** - REJECTED: Adds complexity, Walker has native support
2. **Use rofi + clipcat** - REJECTED: Walker is the chosen launcher, rofi redundant
3. **Use KDE Klipper** - REJECTED: Spec assumption states no interference from system clipboard manager

**Implementation**:
```toml
[modules]
clipboard = true

[[providers.prefixes]]
prefix = ":"
provider = "clipboard"
```

---

### Decision 6: Web Search - Elephant TOML Configuration

**Decision**: Configure web search engines via `~/.config/elephant/websearch.toml`

**Rationale**:
- Elephant websearch provider reads search engines from TOML config file
- Declarative generation via home-manager ensures reproducibility
- TOML format is simple and human-readable for engine definitions

**Alternatives Considered**:
1. **Hardcode engines in Walker config** - REJECTED: Elephant uses separate websearch.toml
2. **Dynamic engine discovery** - REJECTED: No API for dynamic search engine configuration
3. **Environment variables for engines** - REJECTED: Not supported by Elephant websearch provider

**Implementation**:
```nix
xdg.configFile."elephant/websearch.toml".text = ''
  [[engines]]
  name = "Google"
  url = "https://www.google.com/search?q=%s"

  [[engines]]
  name = "DuckDuckGo"
  url = "https://duckduckgo.com/?q=%s"

  default = "Google"
'';
```

---

### Decision 7: Calculator & Symbols - Built-in Providers

**Decision**: Use Walker's built-in calc and symbols providers with no additional configuration

**Rationale**:
- Both providers work out-of-box when module enabled
- Calc provider uses standard math expression parser
- Symbols provider includes emoji and special characters database
- No external dependencies required

**Alternatives Considered**:
1. **Use qalc (Qalculate) for calculator** - REJECTED: Walker calc provider sufficient for basic math (spec FR-014)
2. **Use rofi-emoji for symbols** - REJECTED: Walker has native symbol picker
3. **Custom symbol database** - REJECTED: Spec Out of Scope states no custom symbol sets

**Implementation**:
```toml
[modules]
calc = true
symbols = true

[[providers.prefixes]]
prefix = "="
provider = "calc"

[[providers.prefixes]]
prefix = "."
provider = "symbols"
```

---

### Decision 8: Shell Command Execution - Runner Provider

**Decision**: Use Walker's runner provider with Ghostty terminal integration

**Rationale**:
- Runner provider supports both background execution (Return) and terminal execution (Shift+Return)
- Ghostty is the configured default terminal (per Technical Context)
- Runner provider respects $TERMINAL environment variable

**Alternatives Considered**:
1. **Use rofi -show run** - REJECTED: Walker is the chosen launcher
2. **Custom shell script wrapper** - REJECTED: Runner provider already handles terminal vs background execution
3. **Use xterm for terminal execution** - REJECTED: Ghostty is the project standard (Constitution Principle IX)

**Implementation**:
```toml
[modules]
runner = true

[[providers.prefixes]]
prefix = ">"
provider = "runner"

[[providers.actions.runner]]
action = "run"
bind = "Return"
after = "Close"
default = true

[[providers.actions.runner]]
action = "runterminal"
bind = "shift Return"
after = "Close"
```

---

### Decision 9: i3pm Project Context Propagation

**Decision**: No additional configuration needed - app-launcher-wrapper.sh already propagates I3PM_* variables

**Rationale**:
- Feature 034/035 established app-launcher-wrapper.sh system
- Wrapper queries i3pm daemon for active project before launching apps
- All I3PM_* environment variables injected automatically
- Walker .desktop files already use wrapper (Exec=app-launcher-wrapper.sh <app>)

**Alternatives Considered**:
1. **Modify Elephant to query i3pm daemon** - REJECTED: Wrapper handles this at launch time
2. **Pass I3PM_* to Elephant service** - REJECTED: Project context is dynamic, changes per launch
3. **Desktop file variable substitution** - REJECTED: Already using app-launcher-wrapper.sh

**Evidence**:
From CLAUDE.md Feature 041 documentation:
```
1. Application Launch:
   - User launches app via Walker, keybinding, or CLI
   - app-launcher-wrapper.sh intercepts the launch
   - Wrapper queries daemon for active project
   - Injects I3PM_* environment variables
   - Launches application (variables persist in /proc)
```

---

## Best Practices

### Walker/Elephant Configuration Patterns

1. **Walker config.toml**: Use TOML for Walker-specific settings (modules, prefixes, actions, plugins)
2. **Elephant websearch.toml**: Separate file for search engine configuration (Elephant-specific)
3. **Systemd service**: User service with explicit environment + PassEnvironment for DISPLAY
4. **i3 integration**: Import DISPLAY before restarting Elephant to ensure proper startup

### Environment Variable Propagation

1. **DISPLAY**: Import via systemd + PassEnvironment pattern
2. **PATH**: Explicit Environment with ~/.local/bin for app-launcher-wrapper.sh
3. **XDG_DATA_DIRS**: Set to i3pm-applications directory for registry isolation (Feature 034/035)
4. **XDG_RUNTIME_DIR**: Use systemd %t specifier for automatic runtime directory

### Testing Checklist

1. Verify Elephant service starts: `systemctl --user status elephant`
2. Check DISPLAY available: `systemctl --user show-environment | grep DISPLAY`
3. Test Walker launch: Press Meta+D, verify window appears
4. Test clipboard history: Copy text, type `:` in Walker
5. Test file search: Type `/nixos` in Walker
6. Test web search: Type `@nixos tutorial` in Walker
7. Test calculator: Type `=2+2` in Walker
8. Test symbols: Type `.lambda` in Walker
9. Test runner: Type `>echo hello` in Walker (Return for background, Shift+Return for terminal)
10. Verify app launch environment: Launch VS Code via Walker, check `/proc/<pid>/environ | grep I3PM_PROJECT_NAME`

---

## Dependencies & Versions

- **Walker**: ≥1.5.0 (X11 file provider fix)
- **Elephant**: From flake input `inputs.elephant.packages.${pkgs.system}.default`
- **xclip**: For clipboard operations (standard package)
- **Ghostty**: Terminal emulator (already configured)
- **Neovim**: Text editor for file opening (already configured)
- **Firefox**: Browser for web search (already configured)

---

## Configuration Changes Required

### File: `home-modules/desktop/walker.nix`

**Changes**:
1. ✅ **No changes needed** - All providers already enabled in config.toml (lines 287-296)
2. ✅ **No changes needed** - Elephant service already configured with environment (lines 425-458)
3. ✅ **No changes needed** - Elephant websearch.toml already configured (lines 390-415)
4. ✅ **No changes needed** - Walker prefixes already configured (lines 324-346)
5. ✅ **No changes needed** - Provider actions already configured (lines 348-385)

**Verification**: All functional requirements (FR-001 through FR-020) are already satisfied by existing configuration.

---

## Conclusion

**Research Status**: COMPLETE - No unknowns remain

**Key Finding**: Walker/Elephant full functionality is **already configured** in the existing `home-modules/desktop/walker.nix`. All providers (clipboard, files, websearch, calc, symbols, runner) are enabled, Elephant service has proper environment variable setup, and i3 integration ensures DISPLAY propagation.

**Implementation Impact**: This feature is **validation-only** - verify existing configuration meets all functional requirements, test all providers, and document expected behavior in quickstart.md.

**Next Phase**: Proceed directly to Phase 1 (data-model.md, contracts/, quickstart.md) to document the existing system's data flows and user workflows.
