# Data Model: Registry-Centric Project & Workspace Management

**Feature**: 035-now-that-we | **Date**: 2025-10-25
**Status**: Design Phase | **Input**: research-proc-filtering.md (environment-based approach)

## Overview

This document defines the data schemas for the registry-centric project and workspace management system. The schemas are implemented across multiple layers:

- **Build-time (Nix)**: `app-registry.nix` schema compiled to JSON
- **Runtime (Deno)**: TypeScript interfaces for CLI operations
- **Storage (JSON)**: Project and layout configurations in `~/.config/i3/`
- **Process Environment**: I3PM_* environment variables injected at application launch

All schemas follow the principle of **registry as single source of truth** - application metadata lives only in the registry, projects reference directory and metadata, and layouts reference apps by instance ID for exact window matching.

**Key Innovation**: Environment variables injected at launch (`I3PM_PROJECT_NAME`, `I3PM_APP_ID`) enable deterministic window-to-project association without tag configuration.

---

## Entity: Application Registry Entry

**Purpose**: Defines a launchable application with metadata for workspace assignment, window matching, scope, and launch parameters.

**Location**:
- Source: `home-modules/desktop/app-registry.nix` (Nix configuration)
- Compiled: `~/.config/i3/application-registry.json` (runtime access)

**Schema (Nix AttrSet)** (extends Feature 034, removes tags):

```nix
{
  name = "unique-app-id";           # String - unique identifier, kebab-case
  display_name = "Display Name";    # String - human-readable name for UI
  icon = "icon-name";                # String - icon identifier for launcher

  # Launch configuration
  command = "${pkgs.package}/bin/command";  # String - absolute path to executable
  parameters = [                     # List<String> - command-line arguments
    "--flag"
    "$PROJECT_DIR"                  # Variable substitution marker
  ];
  terminal = false;                  # Boolean - launch in terminal emulator

  # Window management
  expected_class = "WindowClass";    # String - WM_CLASS for window matching
  expected_title_contains = "...";   # String (optional) - fallback window title match
  preferred_workspace = 2;           # Integer (1-9) - target workspace number

  # Scope and behavior
  scope = "scoped";                  # Enum: "scoped" | "global"
  fallback_behavior = "use_home";    # Enum: "skip" | "use_home" | "error"
  multi_instance = false;            # Boolean - allow multiple windows

  # REMOVED: tags field (replaced by environment-based filtering)
}
```

**Field Validation Rules**:

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `name` | String | Yes | Unique, kebab-case, no spaces, 3-64 chars |
| `display_name` | String | Yes | Human-readable, 1-128 chars |
| `icon` | String | Yes | Icon identifier from theme or absolute path |
| `command` | String | Yes | Absolute path from Nix package, executable |
| `parameters` | List<String> | No | Variable substitution validated at build time |
| `terminal` | Boolean | No | Default: false |
| `expected_class` | String | Yes | WM_CLASS value, 1-128 chars, may include regex |
| `expected_title_contains` | String | No | Window title substring for fallback matching |
| `preferred_workspace` | Integer | No | Range: 1-9, null for multi-instance or dynamic |
| `scope` | Enum | Yes | "scoped" or "global" |
| `fallback_behavior` | Enum | No | "skip", "use_home", or "error", default: "use_home" |
| `multi_instance` | Boolean | No | Default: false |

**Build-time Validation** (Nix assertions):
- No duplicate `name` values across registry
- All `command` paths exist in Nix store
- `preferred_workspace` in range 1-9 if specified
- `parameters` with `$PROJECT_DIR` only allowed for scoped apps
- No shell metacharacters in `parameters` (security)

**Runtime Validation** (Deno CLI):
- Registry JSON file exists and is valid JSON
- All fields present and types match expected schema

**Example - Scoped Application (VS Code)**:

```nix
{
  name = "vscode";
  display_name = "Visual Studio Code";
  icon = "vscode";
  command = "${pkgs.vscode}/bin/code";
  parameters = [ "$PROJECT_DIR" ];
  terminal = false;
  expected_class = "Code";
  preferred_workspace = 1;
  scope = "scoped";
  fallback_behavior = "skip";  # Don't launch without project
  multi_instance = false;
  # No tags field - environment variables determine project association
}
```

**Example - Global Application (Firefox)**:

```nix
{
  name = "firefox";
  display_name = "Firefox";
  icon = "firefox";
  command = "${pkgs.firefox}/bin/firefox";
  parameters = [];
  terminal = false;
  expected_class = "firefox";
  preferred_workspace = 2;
  scope = "global";
  fallback_behavior = "use_home";  # Not applicable, but safe default
  multi_instance = false;
  # No tags field - global apps always visible
}
```

**Example - Multi-Instance Application (Terminal)**:

```nix
{
  name = "ghostty";
  display_name = "Ghostty Terminal";
  icon = "utilities-terminal";
  command = "${pkgs.ghostty}/bin/ghostty";
  parameters = [ "--project" "$PROJECT_NAME" ];
  terminal = false;  # Is a terminal itself
  expected_class = "ghostty";
  preferred_workspace = null;  # Dynamic based on context
  scope = "scoped";
  fallback_behavior = "use_home";
  multi_instance = true;  # Allow multiple terminals per project
  # Each instance gets unique I3PM_APP_ID for identification
}
```

**Example - PWA Application**:

```nix
{
  name = "youtube-pwa";
  display_name = "YouTube";
  icon = "youtube";
  command = "${pkgs.firefox}/bin/firefox";
  parameters = [ "--profile" "$HOME/.mozilla/firefox/pwa-youtube" "--class=FFPWA-01K666N2V6BQMDSBMX3AY74TY7" ];
  terminal = false;
  expected_class = "FFPWA-01K666N2V6BQMDSBMX3AY74TY7";  # PWA-specific class
  preferred_workspace = 7;
  scope = "global";
  fallback_behavior = "use_home";
  multi_instance = false;
}
```

---

## Entity: Process Environment (NEW)

**Purpose**: Environment variables injected at application launch for project context and window identification.

**Location**: Process environment of launched application, readable via `/proc/<pid>/environ`

**Schema (Environment Variables)**:

```typescript
interface ProcessEnvironment {
  // Application instance identification
  I3PM_APP_ID: string;              // Unique instance ID: "${app}-${project}-${pid}-${timestamp}"
  I3PM_APP_NAME: string;            // Registry application name (e.g., "vscode")

  // Project context
  I3PM_PROJECT_NAME: string;        // Project name (e.g., "nixos") or empty for global
  I3PM_PROJECT_DIR: string;         // Absolute path to project directory or empty
  I3PM_PROJECT_DISPLAY_NAME: string; // Human-readable project name or empty
  I3PM_PROJECT_ICON?: string;       // Optional project icon

  // Scope and state
  I3PM_SCOPE: "scoped" | "global";  // Application scope from registry
  I3PM_ACTIVE: "true" | "false";    // Whether a project is active

  // Launch metadata
  I3PM_LAUNCH_TIME: string;         // Unix timestamp (seconds since epoch)
  I3PM_LAUNCHER_PID: string;        // PID of app-launcher-wrapper.sh
}
```

**Field Details**:

| Variable | Type | Always Set | Purpose |
|----------|------|------------|---------|
| `I3PM_APP_ID` | String | Yes | Unique instance identifier for exact window matching |
| `I3PM_APP_NAME` | String | Yes | Registry app name for lookup and logging |
| `I3PM_PROJECT_NAME` | String | If project active | Project identifier for window filtering |
| `I3PM_PROJECT_DIR` | String | If project active | Project root directory for app initialization |
| `I3PM_PROJECT_DISPLAY_NAME` | String | If project active | Human-readable project name |
| `I3PM_PROJECT_ICON` | String | If set | Optional project icon |
| `I3PM_SCOPE` | Enum | Yes | "scoped" or "global" from registry |
| `I3PM_ACTIVE` | String | Yes | "true" if project active, "false" otherwise |
| `I3PM_LAUNCH_TIME` | String | Yes | Unix timestamp for debugging |
| `I3PM_LAUNCHER_PID` | String | Yes | Launcher process PID for debugging |

**ID Generation Pattern**:

```bash
# Format: ${app_name}-${project_name}-${pid}-${timestamp}
I3PM_APP_ID="vscode-nixos-12345-1730000000"
I3PM_APP_ID="ghostty-stacks-12346-1730000001"
I3PM_APP_ID="firefox-global-12347-1730000002"  # Global apps use "global" as project
```

**Example - Scoped Application with Project**:

```bash
# Environment for VS Code launched in "nixos" project
I3PM_APP_ID="vscode-nixos-12345-1730000000"
I3PM_APP_NAME="vscode"
I3PM_PROJECT_NAME="nixos"
I3PM_PROJECT_DIR="/etc/nixos"
I3PM_PROJECT_DISPLAY_NAME="NixOS Configuration"
I3PM_PROJECT_ICON="nix-snowflake"
I3PM_SCOPE="scoped"
I3PM_ACTIVE="true"
I3PM_LAUNCH_TIME="1730000000"
I3PM_LAUNCHER_PID="12340"
```

**Example - Scoped Application without Project**:

```bash
# Environment for VS Code launched with no active project
I3PM_APP_ID="vscode-global-12345-1730000000"
I3PM_APP_NAME="vscode"
I3PM_PROJECT_NAME=""  # Empty when no project
I3PM_PROJECT_DIR=""   # Empty when no project
I3PM_PROJECT_DISPLAY_NAME=""
I3PM_SCOPE="scoped"
I3PM_ACTIVE="false"   # No project active
I3PM_LAUNCH_TIME="1730000000"
I3PM_LAUNCHER_PID="12340"
```

**Example - Global Application**:

```bash
# Environment for Firefox (global app)
I3PM_APP_ID="firefox-global-12347-1730000002"
I3PM_APP_NAME="firefox"
I3PM_PROJECT_NAME=""  # Global apps have no project
I3PM_PROJECT_DIR=""
I3PM_SCOPE="global"
I3PM_ACTIVE="false"   # Not project-specific
I3PM_LAUNCH_TIME="1730000002"
I3PM_LAUNCHER_PID="12340"
```

**Reading Process Environment**:

Python daemon reads via `/proc/<pid>/environ`:

```python
def read_process_environ(pid: int) -> dict[str, str]:
    """Read environment variables from /proc/<pid>/environ"""
    with open(f'/proc/{pid}/environ', 'rb') as f:
        environ_data = f.read()
        env_pairs = environ_data.split(b'\0')
        env_dict = {}
        for pair in env_pairs:
            if b'=' in pair:
                key, value = pair.split(b'=', 1)
                env_dict[key.decode('utf-8')] = value.decode('utf-8')
        return env_dict

# Usage
env = read_process_environ(window_pid)
project_name = env.get('I3PM_PROJECT_NAME')  # Filter windows by project
app_id = env.get('I3PM_APP_ID')              # Exact window matching
```

---

## Entity: Project Configuration

**Purpose**: Defines a named workspace context with root directory, display name, icon, and optional saved layout.

**Location**: `~/.config/i3/projects/<project-name>.json` (one file per project)

**Schema (JSON)**:

```typescript
interface Project {
  name: string;                    // Unique project identifier (kebab-case)
  display_name: string;            // Human-readable name
  directory: string;               // Absolute path to project root
  icon?: string;                   // Optional icon identifier

  // Layout state
  saved_layout?: string;           // Optional: path to layout file (relative to layouts dir)

  // Metadata
  created_at: string;              // ISO 8601 timestamp
  updated_at: string;              // ISO 8601 timestamp

  // REMOVED: application_tags field (replaced by environment-based filtering)
}
```

**Field Validation Rules**:

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `name` | String | Yes | Unique across projects, kebab-case, 3-64 chars |
| `display_name` | String | Yes | Human-readable, 1-128 chars |
| `directory` | String | Yes | Absolute path, must exist, readable |
| `icon` | String | No | Icon identifier or absolute path to icon file |
| `saved_layout` | String | No | Layout filename (no path), validated on load |
| `created_at` | String | Yes | ISO 8601 timestamp with timezone |
| `updated_at` | String | Yes | ISO 8601 timestamp with timezone |

**Validation Rules**:
- `name` must be unique (checked at creation time)
- `directory` must be absolute path (starts with `/` or `~`)
- `directory` must exist and be readable
- `saved_layout` references a file in `~/.config/i3/layouts/`
- Timestamps must be valid ISO 8601 format

**Example - NixOS Project**:

```json
{
  "name": "nixos",
  "display_name": "NixOS Configuration",
  "directory": "/etc/nixos",
  "icon": "nix-snowflake",
  "saved_layout": "nixos-coding.json",
  "created_at": "2025-09-01T12:00:00-04:00",
  "updated_at": "2025-10-20T15:30:00-04:00"
}
```

**Example - Stacks Development Project**:

```json
{
  "name": "stacks",
  "display_name": "Stacks Blockchain Development",
  "directory": "/home/user/code/stacks",
  "icon": "code-blocks",
  "saved_layout": "stacks-fullstack.json",
  "created_at": "2025-08-15T09:00:00-04:00",
  "updated_at": "2025-10-18T14:20:00-04:00"
}
```

**Example - Personal Project (No Layout)**:

```json
{
  "name": "personal",
  "display_name": "Personal Tasks",
  "directory": "/home/user/documents",
  "icon": "folder-documents",
  "saved_layout": null,
  "created_at": "2025-09-15T10:00:00-04:00",
  "updated_at": "2025-10-01T08:30:00-04:00"
}
```

---

## Entity: Active Project State

**Purpose**: Tracks currently active project for CLI and daemon.

**Location**: `~/.config/i3/active-project.json`

**Schema (JSON)**:

```typescript
interface ActiveProject {
  project_name: string | null;     // Current project name or null if no project
  activated_at: string | null;     // ISO 8601 timestamp of activation or null
}
```

**Example - Active Project**:

```json
{
  "project_name": "nixos",
  "activated_at": "2025-10-25T08:00:00-04:00"
}
```

**Example - No Active Project**:

```json
{
  "project_name": null,
  "activated_at": null
}
```

---

## Entity: Layout Configuration

**Purpose**: Snapshot of window positions, sizes, and workspace assignments for a project, with application instance IDs for exact window matching.

**Location**: `~/.config/i3/layouts/<layout-name>.json` (referenced by project's `saved_layout` field)

**Schema (JSON)**:

```typescript
interface Layout {
  project_name: string;           // Project this layout belongs to
  layout_name: string;            // Unique layout identifier

  // Window snapshots
  windows: WindowSnapshot[];      // Array of window states

  // Metadata
  captured_at: string;            // ISO 8601 timestamp of layout save
  i3_version: string;             // i3 version at capture time (for compatibility)
}

interface WindowSnapshot {
  // Application reference (registry-based)
  registry_app_id: string;        // Must match registry entry name
  app_instance_id: string;        // Unique instance ID for exact matching (NEW)

  // Window geometry (absolute coordinates)
  workspace: number;              // Workspace number (1-9)
  x: number;                      // X coordinate in pixels
  y: number;                      // Y coordinate in pixels
  width: number;                  // Width in pixels
  height: number;                 // Height in pixels

  // Window state
  floating: boolean;              // Is window floating or tiled
  focused: boolean;               // Was this window focused when captured

  // Optional metadata for debugging
  captured_class?: string;        // Actual WM_CLASS at capture time
  captured_title?: string;        // Actual window title at capture time
  captured_pid?: number;          // Process PID at capture time
}
```

**Field Validation Rules**:

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `project_name` | String | Yes | Must match owning project's `name` |
| `layout_name` | String | Yes | Unique within project, kebab-case |
| `windows` | List<WindowSnapshot> | Yes | Min 1 window, max 50 windows |
| `captured_at` | String | Yes | ISO 8601 timestamp |
| `i3_version` | String | Yes | Semantic version string |
| **WindowSnapshot** | | | |
| `registry_app_id` | String | Yes | Must exist in registry, validated at restore |
| `app_instance_id` | String | Yes | Expected I3PM_APP_ID for exact window matching |
| `workspace` | Integer | Yes | Range: 1-9 |
| `x`, `y`, `width`, `height` | Integer | Yes | Positive values, screen bounds not validated |
| `floating` | Boolean | Yes | true or false |
| `focused` | Boolean | Yes | Only one window per layout should be focused |
| `captured_class` | String | No | For debugging, not used during restore |
| `captured_title` | String | No | For debugging, not used during restore |
| `captured_pid` | Integer | No | For debugging, not used during restore |

**Restore Behavior (with Instance ID Matching)**:
1. **Pre-restore**: Close all existing project-scoped windows (FR-012)
2. **Validation**: Ensure all `registry_app_id` values exist in current registry
3. **Launch with Expected ID**: For each window:
   - Set `I3PM_APP_ID` to match `app_instance_id` from layout
   - Launch via registry protocol with project context
   - Daemon watches for window::new event
4. **Window Matching**: When window appears:
   - Read `/proc/<pid>/environ` to get actual `I3PM_APP_ID`
   - Match against expected `app_instance_id`
   - If match → this is the exact window we're waiting for
5. **Positioning**: After exact match confirmed, apply geometry (workspace, x, y, width, height)
6. **Graceful Degradation**: Skip windows with missing registry apps, log warning (FR-013)
7. **Focus**: After all windows restored, focus the window marked `focused: true`

**Example - NixOS Coding Layout**:

```json
{
  "project_name": "nixos",
  "layout_name": "nixos-coding",
  "windows": [
    {
      "registry_app_id": "vscode",
      "app_instance_id": "vscode-nixos-12345-1730000000",
      "workspace": 1,
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080,
      "floating": false,
      "focused": true,
      "captured_class": "Code",
      "captured_title": "configuration.nix - Visual Studio Code",
      "captured_pid": 12345
    },
    {
      "registry_app_id": "ghostty",
      "app_instance_id": "ghostty-nixos-12346-1730000001",
      "workspace": 3,
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 540,
      "floating": false,
      "focused": false,
      "captured_class": "ghostty",
      "captured_title": "user@nixos:~/nixos",
      "captured_pid": 12346
    },
    {
      "registry_app_id": "ghostty",
      "app_instance_id": "ghostty-nixos-12347-1730000002",
      "workspace": 3,
      "x": 0,
      "y": 540,
      "width": 1920,
      "height": 540,
      "floating": false,
      "focused": false,
      "captured_class": "ghostty",
      "captured_title": "user@nixos:~/nixos",
      "captured_pid": 12347
    },
    {
      "registry_app_id": "firefox",
      "app_instance_id": "firefox-global-12348-1730000003",
      "workspace": 2,
      "x": 0,
      "y": 0,
      "width": 1920,
      "height": 1080,
      "floating": false,
      "focused": false,
      "captured_class": "firefox",
      "captured_title": "Mozilla Firefox",
      "captured_pid": 12348
    }
  ],
  "captured_at": "2025-10-20T14:00:00-04:00",
  "i3_version": "4.23"
}
```

**Key Benefit**: The `app_instance_id` field enables exact window identification. When restoring:
- Launch VS Code with `I3PM_APP_ID="vscode-nixos-12345-1730000000"`
- Window appears → daemon reads `/proc/<pid>/environ`
- Daemon finds `I3PM_APP_ID="vscode-nixos-12345-1730000000"`
- Exact match! → Apply geometry to this specific window
- No ambiguity even with multiple VS Code instances

---

## TypeScript Interfaces (Deno CLI)

**Location**: `home-modules/tools/i3pm/src/models/`

**Registry Model** (`models/registry.ts`):

```typescript
export interface ApplicationRegistry {
  version: string;
  applications: RegistryApplication[];
}

export interface RegistryApplication {
  name: string;
  display_name: string;
  icon: string;
  command: string;
  parameters: string[];
  terminal: boolean;
  expected_class: string;
  expected_title_contains?: string;
  preferred_workspace?: number;
  scope: "scoped" | "global";
  fallback_behavior: "skip" | "use_home" | "error";
  multi_instance: boolean;
  // No tags field - environment-based filtering
}
```

**Environment Model** (`models/environment.ts` - NEW):

```typescript
export interface ProcessEnvironment {
  I3PM_APP_ID: string;
  I3PM_APP_NAME: string;
  I3PM_PROJECT_NAME: string;
  I3PM_PROJECT_DIR: string;
  I3PM_PROJECT_DISPLAY_NAME: string;
  I3PM_PROJECT_ICON?: string;
  I3PM_SCOPE: "scoped" | "global";
  I3PM_ACTIVE: "true" | "false";
  I3PM_LAUNCH_TIME: string;
  I3PM_LAUNCHER_PID: string;
}

export function generateAppInstanceId(
  appName: string,
  projectName: string | null,
  pid: number
): string {
  const project = projectName || "global";
  const timestamp = Math.floor(Date.now() / 1000);
  return `${appName}-${project}-${pid}-${timestamp}`;
}
```

**Project Model** (`models/project.ts`):

```typescript
export interface Project {
  name: string;
  display_name: string;
  directory: string;
  icon?: string;
  saved_layout?: string;
  created_at: string;
  updated_at: string;
  // No application_tags field - environment-based filtering
}

export interface ActiveProject {
  project_name: string | null;
  activated_at: string | null;
}
```

**Layout Model** (`models/layout.ts`):

```typescript
export interface Layout {
  project_name: string;
  layout_name: string;
  windows: WindowSnapshot[];
  captured_at: string;
  i3_version: string;
}

export interface WindowSnapshot {
  registry_app_id: string;
  app_instance_id: string;  // NEW: for exact window matching
  workspace: number;
  x: number;
  y: number;
  width: number;
  height: number;
  floating: boolean;
  focused: boolean;
  captured_class?: string;
  captured_title?: string;
  captured_pid?: number;
}
```

---

## Data Flow Examples

### Example 1: Launching Application with Environment Injection

```
User Action: Launch VS Code for "nixos" project
  ↓
Walker → app-launcher-wrapper.sh vscode
  ↓
Wrapper:
  1. Load registry → get vscode metadata
  2. Query daemon → active project = "nixos"
  3. Generate instance ID: "vscode-nixos-12345-1730000000"
  4. Inject environment:
     export I3PM_APP_ID="vscode-nixos-12345-1730000000"
     export I3PM_APP_NAME="vscode"
     export I3PM_PROJECT_NAME="nixos"
     export I3PM_PROJECT_DIR="/etc/nixos"
     export I3PM_SCOPE="scoped"
  5. Substitute: $PROJECT_DIR → "/etc/nixos"
  6. exec /nix/store/.../bin/code "/etc/nixos"
  ↓
VS Code Process (PID 12345)
  - /proc/12345/environ contains all I3PM_* variables
  - VS Code can read $I3PM_PROJECT_DIR if needed
```

### Example 2: Window Filtering on Project Switch

```
User Action: i3pm project switch stacks
  ↓
CLI:
  1. Update active-project.json: project_name = "stacks"
  2. Send i3 tick event: "project:switch:stacks"
  ↓
Daemon receives tick event:
  1. Query i3 for all windows
  2. For each window:
     - Get window ID
     - Get PID via xprop
     - Read /proc/<PID>/environ
     - Extract I3PM_PROJECT_NAME
     - Compare to "stacks"
  3. Results:
     - Window 1: I3PM_PROJECT_NAME="nixos" → hide (move to scratchpad)
     - Window 2: I3PM_PROJECT_NAME="stacks" → show (keep visible)
     - Window 3: no I3PM_PROJECT_NAME → global → show (keep visible)
  ↓
User sees only "stacks" project windows + global apps
```

### Example 3: Layout Restore with Instance ID Matching

```
User Action: i3pm layout restore nixos
  ↓
CLI:
  1. Load layout: nixos-coding.json
  2. Close existing project windows
  3. For each window in layout:
     - registry_app_id = "vscode"
     - app_instance_id = "vscode-nixos-12345-1730000000"

     Launch with expected ID:
       export I3PM_APP_ID="vscode-nixos-12345-1730000000"
       app-launcher-wrapper.sh vscode
  ↓
Window opens → daemon receives window::new event:
  1. Get window PID via xprop
  2. Read /proc/<PID>/environ
  3. Extract I3PM_APP_ID
  4. Match against expected: "vscode-nixos-12345-1730000000"
  5. MATCH! → This is the exact window
  6. Apply geometry from layout
  ↓
All windows restored in exact positions with exact apps
```

---

## Migration Notes

**From Tag-Based to Environment-Based**:

1. **Registry Changes**:
   - Remove `tags` field from all applications
   - No other schema changes needed

2. **Project Changes**:
   - Remove `application_tags` field from projects
   - Projects now only store metadata (name, directory, icon)

3. **Layout Changes**:
   - Add `app_instance_id` field to window snapshots
   - Layouts captured after migration will have instance IDs
   - Legacy layouts without instance IDs can fall back to window class matching

4. **Backward Compatibility**:
   - **Intentionally broken** per Principle XII (Forward-Only Development)
   - Tag-based filtering completely removed, not maintained alongside new approach
   - Existing projects must be recreated (simple: just name and directory now)
   - Existing layouts remain compatible (window class matching as fallback)

---

## Summary of Changes from Tag-Based Approach

**Removed**:
- ❌ `tags` field from registry applications
- ❌ `application_tags` field from projects
- ❌ Tag validation logic
- ❌ XDG isolation for application filtering

**Added**:
- ✅ Process environment entity with I3PM_* variables
- ✅ `app_instance_id` field in layout snapshots
- ✅ Environment reading via /proc/<pid>/environ
- ✅ Deterministic window matching by instance ID

**Benefits**:
- Simpler: No tag configuration needed
- Powerful: Applications can access project context
- Deterministic: Exact window identification via instance IDs
- Flexible: Any environment variable can be added for future features

**Trade-offs**:
- Slightly slower project switching (~440ms vs instant tag filtering)
- Requires /proc filesystem access (Linux-specific, already available)
- Requires xprop for PID lookup (~20ms per window)
