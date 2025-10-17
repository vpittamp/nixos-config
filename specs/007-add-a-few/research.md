# Research Findings: Multi-Session Remote Desktop & Web Application Launcher

**Feature Branch**: `007-add-a-few`
**Date**: 2025-10-16
**Status**: Phase 0 Complete

## Overview

This document consolidates research findings for all technical clarifications identified in the Technical Context section of plan.md. Each section presents a decision, rationale, and alternatives considered for the key technology choices.

---

## 1. Multi-Session xrdp with i3wm

### Decision
Use **i3wm with xrdp using UBC Session Policy and X11 Display Server**

**Configuration Approach:**
- **Window Manager:** i3wm (tiling window manager)
- **Display Server:** X11 (not Wayland)
- **RDP Server:** xrdp with xorgxrdp backend
- **Session Policy:** `Policy=UBC` (User, BitPerPixel, Connection) in sesman.ini
- **Session Isolation:** Each connection creates a new independent session

### Rationale
**i3wm Provides Superior Multi-Session Characteristics:**
- Lightweight resource footprint (~3MB RAM vs KDE Plasma's significantly higher usage)
- Allows 3-5 concurrent sessions without resource exhaustion
- Native session isolation - each RDP session gets its own i3 instance
- No shared state between window manager instances (unlike KDE Plasma D-Bus conflicts)
- Minimal dependencies reduce potential conflict points

**X11 + xrdp Mature Ecosystem:**
- X11 display server has mature, well-tested xrdp integration
- xorgxrdp backend provides native Xorg support for each session
- 1Password desktop application has solid X11 support
- X11 naturally supports multiple display servers (`:10`, `:11`, `:12`, etc.)
- Each xrdp session gets its own X11 display, ensuring complete isolation

**UBC Session Policy Configuration:**
- **U**ser, **B**itPerPixel, **C**onnection = new session per connection
- Each device connection creates a separate, independent session
- Sessions remain active when user disconnects (based on KillDisconnected setting)
- User can reconnect to existing sessions or create new ones

**Existing Configuration Foundation:**
- Codebase already has `/etc/nixos/modules/desktop/i3wm.nix` and `/etc/nixos/modules/desktop/xrdp.nix`
- `/etc/nixos/configurations/hetzner-i3.nix` provides working integration example
- Existing `xrdp.nix` uses `Policy=Separate` which works, but `Policy=UBC` is more standard

### Alternatives Considered

**Alternative 1: KDE Plasma + xrdp (Current Hetzner Base)**
- **Rejected Because:**
  - D-Bus conflicts: KDE Plasma components share D-Bus session state
  - Resource intensive: Each Plasma session consumes significantly more RAM/CPU
  - Complex session management: Requires workarounds (custom startwm script, D-Bus wrappers)
  - Current configuration has `KillDisconnected=yes` which terminates sessions on disconnect

**Alternative 2: Xvnc Backend (Instead of Xorg)**
- **Rejected Because:**
  - Different session isolation characteristics
  - xorgxrdp provides better performance and native X11 integration
  - Better 1Password desktop application compatibility with native Xorg

**Alternative 3: Wayland + RDP**
- **Rejected Because:**
  - Wayland RDP support is less mature
  - More complex configuration and debugging
  - User requirement specifically mentions X11 for mature RDP/xrdp compatibility
  - i3wm is primarily an X11 window manager (Sway for Wayland is different)

### NixOS Configuration Notes

**Critical sesman.ini Configuration:**
```ini
[Sessions]
X11DisplayOffset=10          # Start X11 displays from :10
MaxSessions=50               # Support multiple concurrent sessions
KillDisconnected=no          # Keep sessions alive when disconnected
DisconnectedTimeLimit=0      # No timeout - keep indefinitely (or 86400 for 24h)
IdleTimeLimit=0              # No idle timeout
Policy=UBC                   # New session per connection
```

**Critical Changes from Current Config:**
```nix
# WRONG (current remote-access.nix):
KillDisconnected=yes        # Terminates on disconnect
DisconnectedTimeLimit=60    # Only 60 seconds

# CORRECT (multi-session):
KillDisconnected=no         # Keep sessions alive
DisconnectedTimeLimit=0     # Or 86400 for 24-hour cleanup
```

**Audio Configuration - Use PulseAudio (Not PipeWire):**
```nix
services.pipewire.enable = lib.mkForce false;
hardware.pulseaudio = {
  enable = true;
  package = pkgs.pulseaudioFull;
};
```
PulseAudio has better xrdp audio redirection support via `pulseaudio-module-xrdp`.

### Potential Issues
1. **Session Limit Exhaustion:** Mitigate with `DisconnectedTimeLimit=86400` (24h cleanup)
2. **1Password Desktop Conflicts:** Should work per-user; validate `~/.1password/agent.sock` across sessions
3. **D-Bus Session Bus:** Ensure D-Bus launched per session (add `export $(dbus-launch)` if needed)
4. **Display Number Conflicts:** Already handled by `X11DisplayOffset=10`
5. **Clipboard Between Sessions:** Implement per-session clipboard first (simpler, more secure)

---

## 2. Clipboard Manager Selection

### Decision
Use **Clipcat** as the primary clipboard manager

**Configuration:**
- Home-manager service: `services.clipcat`
- Rofi integration for keyboard-driven access
- Pattern-based filtering for sensitive content
- Support for both X11 PRIMARY and CLIPBOARD selections
- 100 entry history with persistent storage

### Rationale

**Excellent NixOS Support:**
- Home-manager provides dedicated `services.clipcat` module
- Comprehensive declarative configuration via `daemonSettings`, `menuSettings`, `ctlSettings`
- No manual configuration files needed

**X11 PRIMARY & CLIPBOARD Support:**
- Native support for monitoring both selections independently
- Configurable `primary_threshold_ms` to control primary selection update frequency

**Configurable History:**
- Set `max_history = 50-100` (or higher)
- Persistent storage via `history_file_path`

**Pattern-Based Filtering:**
- `denied_text_regex_patterns` for regex-based sensitive content filtering
- `filter_text_min_length` and `filter_text_max_length` for size-based filtering
- `sensitive_mime_types` for blocking specific content types

**Rofi Integration:**
- Built-in support for rofi/dmenu launchers
- Configure via `menuSettings.finder = "rofi"`

**Modern Implementation:**
- Written in Rust (performant, actively maintained)
- Cross-application support via X11 clipboard integration

### Alternatives Considered

**Alternative 1: CopyQ**
- **Pros:** Most feature-rich, GUI configuration, advanced scripting, window-based filtering
- **Cons:** Qt-based GUI feels heavy for i3wm, less declarative NixOS configuration
- **Best for:** Users preferring GUI configuration and visual clipboard browsing

**Alternative 2: Clipmenu**
- **Pros:** Extremely minimal and lightweight, well-established in i3wm community
- **Cons:** Limited NixOS declarative configuration, no built-in sensitive content filtering
- **Best for:** Users prioritizing absolute minimalism over features

**Alternative 3: Greenclip**
- **Pros:** Designed for rofi integration, simple TOML configuration
- **Cons:** Basic NixOS module (only enable/package options), limited declarative config
- **Best for:** Users needing only basic rofi integration

**Alternative 4: Clipse**
- **Pros:** Modern TUI interface with vim-like navigation, good home-manager module
- **Cons:** No explicit PRIMARY selection support, TUI-based requires terminal launch
- **Best for:** Users preferring TUI interfaces

### NixOS Configuration Pattern

```nix
# home-modules/tools/clipcat.nix
{ config, lib, pkgs, ... }:
{
  services.clipcat = {
    enable = true;
    package = pkgs.clipcat;

    daemonSettings = {
      daemonize = true;
      max_history = 100;
      history_file_path = "${config.xdg.cacheHome}/clipcat/clipcatd-history";

      watcher = {
        enable_clipboard = true;
        enable_primary = true;
        primary_threshold_ms = 5000;

        # Sensitive content filtering
        denied_text_regex_patterns = [
          # Passwords (16+ chars with mixed case/numbers)
          "^[A-Za-z0-9!@#$%^&*()_+\\-=\\[\\]{}|;:,.<>?]{16,128}$"
          # Credit card numbers
          "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b"
          # SSH private keys
          "-----BEGIN.*PRIVATE KEY-----"
          # API tokens/keys
          "(?i)(api[_-]?key|token|secret)[\\s:=]+[A-Za-z0-9_\\-]+"
        ];

        filter_text_min_length = 1;
        filter_text_max_length = 20000000;
        filter_image_max_size = 5242880;  # 5MB
      };

      capture_image = true;
    };

    menuSettings = {
      finder = "rofi";
      rofi_config_path = "${config.xdg.configHome}/rofi/config.rasi";
    };
  };
}
```

### Integration Notes

**Firefox, VS Code, Alacritty:** Work seamlessly via X11 CLIPBOARD selection (Ctrl+C/V)

**tmux Integration:**
```nix
programs.tmux.extraConfig = ''
  set -g set-clipboard on
  bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -i -selection clipboard"
'';
```

**i3 Keybindings:**
```nix
# In i3 config
bindsym $mod+v exec clipcat-menu         # Open clipboard menu
bindsym $mod+Shift+v exec clipctl clear  # Clear clipboard history
```

---

## 3. Web Application Launcher System

### Decision
Use **Chromium with `--app` mode + Custom Desktop Entries**

**Implementation Approach:**
- Ungoogled Chromium for privacy-focused browser
- Launch web apps with `--app=URL --class=webapp-name` flags
- Separate authentication contexts via `--user-data-dir` profiles
- Custom `.desktop` files via home-manager `xdg.desktopEntries`
- Wrapper scripts using `pkgs.writeScriptBin` pattern
- i3wm window rules for workspace assignment

### Rationale

**Superior i3wm Integration:**
- Custom WM_CLASS via `--class` flag enables unique window manager entries
- Separate taskbar icons and Alt+Tab entries for each web app
- i3wm `for_window` directives can target specific web apps by class

**Full Browser Extension Support:**
- 1Password browser extension works perfectly in Chromium app mode
- Native messaging between desktop app and browser extensions maintained

**Separate Authentication Contexts:**
- `--user-data-dir=/path/to/webapp/profile` creates isolated browser contexts
- Different cookies, localStorage, and authentication state per web app
- Allows multiple instances of same domain with different accounts

**Declarative Pattern Alignment:**
- Follows existing `activity-aware-apps-native.nix` pattern
- Uses `pkgs.writeScriptBin` for wrapper scripts
- Desktop entries via `xdg.desktopEntries` in home-manager
- Activation scripts for profile directory creation

**Native Rofi Integration:**
- Desktop entries automatically indexed by rofi's `-show drun` mode
- Keywords field enables enhanced search
- Custom icons display with `-show-icons` flag

### Alternatives Considered

**Alternative 1: FirefoxPWA**
- **Rejected Because:**
  - Unreliable WM_CLASS control on i3wm
  - Overly complex architecture designed for KDE Plasma
  - Additional extension and native messaging host dependencies
  - More moving parts = more failure points

**Alternative 2: Firefox Profiles with `--class`**
- **Rejected Because:**
  - Window grouping issues - Firefox groups windows by profile
  - Inconsistent `--class` flag behavior in app mode
  - Less reliable window manager integration than Chromium

**Alternative 3: Firefox Multi-Account Containers**
- **Rejected Because:**
  - Doesn't meet requirement for separate windows/taskbar icons
  - All containers run in same browser window (tabs, not separate windows)
  - No WM_CLASS differentiation

**Alternative 4: Standard Chromium**
- **Considered But:**
  - Less privacy-focused than Ungoogled Chromium
  - Includes Google tracking and telemetry
  - Ungoogled Chromium provides same functionality without privacy concerns

### NixOS Configuration Pattern

**Architecture:**
```
home-modules/tools/
├── web-apps-declarative.nix    # Main module (like firefox-pwas-declarative.nix)
└── web-apps-sites.nix          # Site definitions (like pwa-sites.nix)
```

**Implementation Pattern:**
```nix
# 1. Site definitions
sites = [
  {
    name = "Gmail";
    url = "https://mail.google.com";
    class = "webapp-gmail";
    icon = ./assets/webapp-icons/gmail.png;
    workspace = "2";
  }
  # ... more sites
];

# 2. Wrapper scripts (pkgs.writeScriptBin)
launcherScript = pkgs.writeScriptBin "webapp-${site.name}" ''
  #!/bin/sh
  PROFILE_DIR="$HOME/.local/share/webapps/${site.class}"
  mkdir -p "$PROFILE_DIR"
  exec ${pkgs.ungoogled-chromium}/bin/chromium \
    --user-data-dir="$PROFILE_DIR" \
    --class="${site.class}" \
    --app="${site.url}"
'';

# 3. Desktop entries (xdg.desktopEntries)
xdg.desktopEntries."webapp-${site.name}" = {
  name = site.name;
  exec = "webapp-${site.name}";
  icon = site.icon;
  categories = [ "Network" "WebBrowser" ];
  keywords = [ "web" "app" site.name ];
};

# 4. i3wm window rules
for_window [class="^${site.class}$"] move to workspace ${site.workspace}
```

**Icon Management:**
- Store custom icons in `/etc/nixos/assets/webapp-icons/`
- Follow existing PWA icon pattern
- Support standard icon formats (PNG, SVG)

### Desktop Integration

**Rofi Integration:**
- Desktop entries automatically appear in `rofi -show drun`
- Search by name or keywords
- Launch with Enter key

**i3wm Window Rules:**
```nix
for_window [class="^webapp-gmail$"] move to workspace 2
assign [class="^webapp-gmail$"] workspace 2
```

**Lifecycle Management:**
- User-configurable: some apps persist, others fresh launch
- Controlled via i3wm window rules and startup configuration
- Profile directories persist authentication state

---

## 4. Alacritty Terminal Emulator

### Decision
**Alacritty is FULLY COMPATIBLE and RECOMMENDED** as default terminal emulator

**Configuration:**
- Set as default terminal in i3wm via `$mod+Return` keybinding
- Configure via home-manager `programs.alacritty` module
- No changes needed to existing terminal customizations

### Rationale

**Industry Standard for i3wm + tmux Workflows:**
- Most popular terminal choice for modern i3wm configurations
- Alacritty + tmux + sesh is proven, widely-used combination
- Multiple well-documented configurations exist

**Excellent tmux Compatibility:**
- Existing tmux configuration already handles terminal compatibility correctly
- `terminal = "tmux-256color"` with proper terminal overrides
- No configuration changes needed

**Bash and Starship Prompt Support:**
- Works seamlessly with bash shells and Starship prompt
- Starship explicitly supports Alacritty
- Existing bash configuration works without modification
- Nerd Font support (FiraCode Nerd Font) works perfectly

**Session Manager (sesh) Compatibility:**
- sesh is tmux-focused, not terminal-dependent
- Alacritty + tmux + sesh is documented workflow pattern
- No configuration changes needed

**NixOS/home-manager First-Class Support:**
- Home-manager has dedicated `programs.alacritty` module
- Configuration is fully declarative
- No manual configuration files needed

**Performance Benefits:**
- GPU-accelerated rendering (smooth scrolling, fast startup)
- Better performance than Konsole, especially over RDP/XRDP
- Lower latency for terminal operations

### Alternatives Considered

**Alternative 1: Kitty**
- **Pros:** Similar performance, GPU-accelerated, more built-in features (tabs, splits)
- **Cons:** Slightly heavier than Alacritty, more features than needed
- **Best for:** Users wanting built-in multiplexing (but we have tmux)

**Alternative 2: Konsole (Current)**
- **Pros:** Already working, feature-rich GUI, established configuration
- **Cons:** Heavier than Alacritty, slower for i3wm workflows
- **Best for:** Users preferring GUI configuration

**Alternative 3: WezTerm**
- **Pros:** Modern Rust-based, built-in multiplexing, GPU-accelerated
- **Cons:** Could replace tmux (not recommended - existing workflow established)
- **Best for:** Users wanting all-in-one terminal solution

### NixOS Configuration

**Alacritty Module:**
```nix
# home-modules/terminal/alacritty.nix
{ config, pkgs, lib, ... }:
{
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      font = {
        normal = {
          family = "FiraCode Nerd Font";
          style = "Regular";
        };
        size = 9.0;
      };

      window = {
        padding = { x = 2; y = 2; };
        decorations = "full";
      };

      selection.save_to_clipboard = true;
      scrolling.history = 10000;

      # Match Catppuccin Mocha theme
      colors = {
        primary = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
        };
        # ... additional Catppuccin colors
      };
    };
  };
}
```

**i3wm Default Terminal:**
```nix
# In i3 config
bindsym $mod+Return exec ${pkgs.alacritty}/bin/alacritty
```

**Environment Variable:**
```nix
# In bash.nix sessionVariables
TERMINAL = "alacritty";  # For i3-sensible-terminal
```

### Compatibility Notes

**No Changes Needed:**
- **bash.nix**: Already handles terminal detection correctly
- **tmux.nix**: Already properly configured with terminal overrides
- **sesh.nix**: Works through tmux, no changes needed
- **starship.nix**: Auto-detects terminal, no changes needed

**Clipboard Integration:**
- Existing tmux clipboard configuration works with Alacritty
- Set `selection.save_to_clipboard = true` in Alacritty for seamless integration

**TERM Variable:**
- Alacritty sets `TERM = "xterm-256color"`
- tmux handles with `default-terminal "tmux-256color"`
- This is the recommended configuration

### Potential Issues

**Issue 1: TERM Variable Conflicts**
- **Solution:** Already handled - tmux and Alacritty use standard configuration

**Issue 2: Clipboard Sync**
- **Solution:** Set `selection.save_to_clipboard = true` + existing tmux clipboard piping

**Issue 3: i3-sensible-terminal Preference**
- **Solution:** Set `TERMINAL = "alacritty"` in bash sessionVariables

**Issue 4: Font Rendering in RDP**
- **Solution:** Existing FiraCode Nerd Font works well with XRDP

---

## Storage Location Clarifications

### Clipboard History Storage
- **Location:** `$HOME/.cache/clipcat/clipcatd-history` (Clipcat)
- **Persistence:** Across application restarts, cleared on system reboot (optional)
- **Format:** Text-based storage (binary/images if supported by manager)

### xrdp Session State
- **Location:** `/var/lib/xrdp` or similar (managed by xrdp service)
- **Session Data:** X11 display numbers, session PIDs, connection states
- **Cleanup:** Automatic based on `DisconnectedTimeLimit` setting

### Web Application Profiles
- **Location:** `$HOME/.local/share/webapps/webapp-{name}/` (Chromium profiles)
- **Content:** Cookies, localStorage, browser cache, authentication state
- **Management:** Per-app isolation, cleaned up when app definition removed

---

## Technology Stack Summary

| Component | Choice | Primary Reason |
|-----------|--------|----------------|
| **Window Manager** | i3wm | Lightweight, session isolation, mature xrdp support |
| **Display Server** | X11 | Mature RDP/xrdp compatibility, 1Password support |
| **RDP Server** | xrdp (xorgxrdp) | Multi-session support, UBC policy |
| **Clipboard Manager** | Clipcat | Best declarative NixOS config, pattern filtering |
| **Browser (Web Apps)** | Ungoogled Chromium | Privacy-focused, excellent `--app` mode, WM_CLASS control |
| **Terminal Emulator** | Alacritty | GPU-accelerated, excellent tmux compat, i3wm standard |

---

## Next Steps for Phase 1

1. **Generate data-model.md** - Define entities for sessions, web apps, clipboard entries
2. **Generate API contracts** - Define configuration schemas for modules
3. **Generate quickstart.md** - Document module usage and configuration patterns
4. **Update agent context** - Add new technologies (Clipcat, Ungoogled Chromium, UBC policy)
5. **Re-evaluate Constitution Check** - Ensure design still complies with all principles

---

**Research Phase Complete** ✅
All NEEDS CLARIFICATION items have been resolved with justified technology choices.
