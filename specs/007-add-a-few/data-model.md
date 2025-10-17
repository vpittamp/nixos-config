# Data Model: Multi-Session Remote Desktop & Web Application Launcher

**Feature Branch**: `007-add-a-few`
**Date**: 2025-10-16
**Status**: Phase 1

## Overview

This document defines the key entities and their relationships for the multi-session remote desktop and web application launcher system. These entities represent the logical data structures that the NixOS modules will manage.

---

## Entity Definitions

### 1. RemoteDesktopSession

Represents an active RDP connection from a specific device to the remote workstation.

**Fields:**
- `sessionId` (string): Unique identifier for the session (e.g., `:10`, `:11`)
- `userId` (string): System user owning the session
- `displayNumber` (integer): X11 display number (10-50)
- `connectionTime` (timestamp): When the session was established
- `lastActivityTime` (timestamp): Last user interaction timestamp
- `disconnectedTime` (timestamp | null): When user disconnected (null if connected)
- `sourceDevice` (string): Identifying information about connecting device (for logging)
- `sessionState` (enum): `connected` | `disconnected` | `cleaning_up`
- `processId` (integer): PID of the X11 server process
- `windowManagerPid` (integer): PID of the i3wm instance for this session

**Relationships:**
- One user can have multiple RemoteDesktopSessions (1:N)
- Each session has one independent i3wm instance
- Each session has its own set of ClipboardEntries (isolated per session)

**Validation Rules:**
- `displayNumber` must be between X11DisplayOffset and X11DisplayOffset+MaxSessions
- `disconnectedTime` triggers cleanup after 24 hours (86400 seconds)
- Maximum 3-5 concurrent sessions per user (configurable)

**State Transitions:**
```
[New Connection] → connected
connected → disconnected (user closes RDP client)
disconnected → cleaning_up (after 24h idle or manual cleanup)
cleaning_up → [Session Destroyed]
```

---

### 2. WebApplicationDefinition

Represents a configured web application available for launch.

**Fields:**
- `id` (string): Unique identifier (e.g., "gmail", "notion")
- `name` (string): Display name shown in rofi and taskbar
- `url` (string): Web application URL (must be valid HTTPS URL)
- `wmClass` (string): Window manager class for i3wm targeting (e.g., "webapp-gmail")
- `iconPath` (string | null): Absolute path to custom icon file
- `profileDir` (string): Browser profile directory path
- `workspace` (string | null): Preferred i3wm workspace (e.g., "2", "web")
- `lifecycle` (enum): `persistent` | `fresh` - whether to keep running or launch clean
- `keywords` (list<string>): Search keywords for rofi
- `enabled` (boolean): Whether the application is active

**Relationships:**
- Each WebApplicationDefinition generates one `.desktop` file
- Each definition has one BrowserContext (profile directory)
- Multiple WebApplicationDefinitions can exist for the same domain (different profiles)

**Validation Rules:**
- `id` must be unique across all web application definitions
- `url` must be valid and start with `https://` (or `http://` for localhost)
- `wmClass` must start with `webapp-` and be unique
- `iconPath` must exist if specified
- `profileDir` is derived from id: `$HOME/.local/share/webapps/webapp-{id}/`

**Derived Values:**
- `launcherScriptName`: `webapp-{id}`
- `desktopEntryId`: `webapp-{id}.desktop`
- `browserCommand`: `chromium --user-data-dir={profileDir} --class={wmClass} --app={url}`

---

### 3. BrowserContext

Represents an isolated browser profile for a web application.

**Fields:**
- `profileDir` (string): Absolute path to profile directory
- `applicationId` (string): Foreign key to WebApplicationDefinition.id
- `cookies` (opaque): Browser cookie storage (managed by Chromium)
- `localStorage` (opaque): Browser localStorage (managed by Chromium)
- `extensions` (list<string>): Installed browser extensions (e.g., ["1password"])
- `authenticationState` (opaque): Login sessions and tokens (managed by browser)
- `cacheSize` (integer): Approximate cache size in bytes
- `lastUsed` (timestamp): Last time this profile was accessed

**Relationships:**
- One BrowserContext per WebApplicationDefinition (1:1)
- BrowserContext persists across system rebuilds (stored in user home directory)

**Validation Rules:**
- `profileDir` must be within `$HOME/.local/share/webapps/`
- Directory is automatically created by wrapper script on first launch

**Lifecycle:**
- Created on first web application launch
- Persists until web application definition is removed
- Automatically cleaned up when definition removed from configuration

---

### 4. ClipboardEntry

Represents a single item in clipboard history.

**Fields:**
- `id` (integer): Sequential entry ID (auto-increment)
- `content` (string | bytes): Clipboard content (text or image data)
- `contentType` (enum): `text` | `image` | `html` | `other`
- `mimeType` (string): MIME type of content (e.g., "text/plain", "image/png")
- `selectionType` (enum): `primary` | `clipboard` - X11 selection type
- `timestamp` (timestamp): When content was copied
- `sourceApplication` (string | null): Application that created the copy (if detectable)
- `contentLength` (integer): Size of content in bytes
- `isSensitive` (boolean): Whether content matched sensitive patterns

**Relationships:**
- Multiple ClipboardEntries per user (1:N)
- ClipboardEntries are session-isolated (each RemoteDesktopSession has separate history)

**Validation Rules:**
- `contentLength` must be between `filter_text_min_length` and `filter_text_max_length`
- `content` must not match `denied_text_regex_patterns` if `contentType` is text
- Maximum 100 entries per session (configurable via `max_history`)
- Images must be smaller than `filter_image_max_size` (default 5MB)

**Automatic Filtering:**
```
IF contentType == text AND matches(denied_text_regex_patterns)
  THEN reject (do not create ClipboardEntry)

IF contentLength > filter_text_max_length
  THEN reject

IF contentType == image AND contentLength > filter_image_max_size
  THEN reject
```

**Storage:**
- Persisted to `$HOME/.cache/clipcat/clipcatd-history`
- Survives application restarts
- Cleared on system reboot (optional configuration)

**FIFO Queue Management:**
```
IF count(ClipboardEntry) >= max_history
  THEN delete oldest entry (min(timestamp))
```

---

### 5. TerminalConfiguration

Represents the declarative terminal environment setup.

**Fields:**
- `emulator` (string): Terminal emulator binary ("alacritty")
- `font.family` (string): Font family name ("FiraCode Nerd Font")
- `font.size` (float): Font size in points (9.0)
- `colorScheme` (string): Theme name ("catppuccin-mocha")
- `termEnvVar` (string): TERM environment variable value ("xterm-256color")
- `clipboardIntegration` (boolean): Save selections to clipboard
- `scrollbackLines` (integer): Number of lines in scrollback buffer
- `padding.x` (integer): Horizontal padding in pixels
- `padding.y` (integer): Vertical padding in pixels

**Relationships:**
- One TerminalConfiguration per user (singleton)
- Integrates with existing tmux, sesh, bash, and Starship configurations
- Does NOT replace existing terminal tools (tmux, sesh remain active)

**Validation Rules:**
- `emulator` must be "alacritty" (as per requirement FR-024)
- `font.family` must be available in system fonts
- Configuration must be compatible with existing tmux terminal settings

**Integration Points:**
- i3wm keybinding: `$mod+Return` → `alacritty`
- Environment variable: `$TERMINAL = "alacritty"`
- tmux configuration: Unchanged (uses `terminal = "tmux-256color"`)
- Starship prompt: Auto-detects Alacritty, no changes needed

---

## Entity Relationships Diagram

```
User (1)
  ├── (N) RemoteDesktopSession
  │     ├── sessionId: string
  │     ├── displayNumber: int
  │     ├── sessionState: enum
  │     └── (N) ClipboardEntry [session-isolated]
  │           ├── content: string|bytes
  │           ├── selectionType: enum
  │           └── timestamp: datetime
  │
  ├── (N) WebApplicationDefinition
  │     ├── id: string
  │     ├── name: string
  │     ├── url: string
  │     ├── wmClass: string
  │     └── (1) BrowserContext
  │           ├── profileDir: string
  │           ├── authenticationState: opaque
  │           └── lastUsed: datetime
  │
  └── (1) TerminalConfiguration
        ├── emulator: "alacritty"
        ├── font: { family, size }
        └── colorScheme: string
```

---

## Configuration Schema Representations

These entities are declared in NixOS configuration files and managed by their respective modules.

### RemoteDesktopSession (xrdp-multisession module)
```nix
services.xrdp = {
  enable = true;
  sesman.policy = "UBC";                    # Creates new session per connection
  sesman.maxSessions = 5;                   # Max concurrent sessions
  sesman.killDisconnected = false;          # Keep sessions alive
  sesman.disconnectedTimeLimit = 86400;     # 24-hour cleanup
};
```

### WebApplicationDefinition (web-apps-declarative module)
```nix
webApps = {
  gmail = {
    name = "Gmail";
    url = "https://mail.google.com";
    wmClass = "webapp-gmail";
    icon = ./assets/webapp-icons/gmail.png;
    workspace = "2";
    lifecycle = "persistent";
    keywords = [ "email" "mail" "google" ];
  };
};
```

### BrowserContext (auto-managed)
```bash
# Automatically created by launcher script
PROFILE_DIR="$HOME/.local/share/webapps/webapp-gmail/"
chromium --user-data-dir="$PROFILE_DIR" --class="webapp-gmail" --app="https://mail.google.com"
```

### ClipboardEntry (clipcat daemon configuration)
```nix
services.clipcat = {
  enable = true;
  daemonSettings = {
    max_history = 100;
    watcher = {
      enable_clipboard = true;
      enable_primary = true;
      denied_text_regex_patterns = [ /* sensitive patterns */ ];
    };
  };
};
```

### TerminalConfiguration (alacritty module)
```nix
programs.alacritty = {
  enable = true;
  settings = {
    env.TERM = "xterm-256color";
    font = {
      normal.family = "FiraCode Nerd Font";
      size = 9.0;
    };
    selection.save_to_clipboard = true;
  };
};
```

---

## Data Persistence

| Entity | Storage Location | Persistence | Cleanup Strategy |
|--------|------------------|-------------|------------------|
| RemoteDesktopSession | `/var/lib/xrdp/` (system) | Until cleanup | Auto after 24h idle |
| WebApplicationDefinition | `/etc/nixos/*.nix` (config) | Version-controlled | Manual (remove from config) |
| BrowserContext | `~/.local/share/webapps/` (user) | Indefinite | Auto on config removal |
| ClipboardEntry | `~/.cache/clipcat/` (user) | Until reboot | FIFO when max reached |
| TerminalConfiguration | `/etc/nixos/*.nix` (config) | Version-controlled | Manual (config change) |

---

## Validation and Constraints

### Multi-Session Constraints
- Maximum 5 concurrent RemoteDesktopSessions per user
- Each session must have unique X11 display number (`:10` - `:50`)
- Disconnected sessions auto-cleanup after 24 hours

### Web Application Constraints
- `wmClass` must be unique across all WebApplicationDefinitions
- `url` must be valid HTTPS URL (or HTTP for localhost)
- Profile directories must not exceed reasonable disk usage (~100MB per app)

### Clipboard Constraints
- Maximum 100 ClipboardEntries per session
- Individual entries limited to 20MB (`filter_text_max_length`)
- Images limited to 5MB (`filter_image_max_size`)
- Pattern-based sensitive content rejection

### Terminal Constraints
- Must maintain compatibility with existing tmux configuration
- Font family must be available in system fonts
- Alacritty must be set as default terminal in i3wm

---

## Success Criteria Mapping

| Success Criteria | Entity | Validation |
|------------------|--------|------------|
| SC-001: 3+ concurrent sessions | RemoteDesktopSession | `count(active) >= 3` |
| SC-002: Session persistence | RemoteDesktopSession | `disconnectedTime < now() - 24h → cleanup` |
| SC-003: rofi search <5s | WebApplicationDefinition | Desktop entry indexed |
| SC-006: 1Password works in 95% | BrowserContext | Extension state persisted |
| SC-014: Clipboard access <2s | ClipboardEntry | `rofi` integration enabled |
| SC-015: 95% copy capture | ClipboardEntry | Both PRIMARY and CLIPBOARD monitored |
| SC-017: 50+ entries | ClipboardEntry | `max_history >= 50` |

---

**Data Model Complete** ✅
All entities defined with fields, relationships, validation rules, and configuration schemas.
