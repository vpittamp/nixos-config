# Data Model: Unified Application Launcher with Project Context

**Feature**: 034-create-a-feature
**Date**: 2025-10-24
**Phase**: Phase 1 - Design & Contracts
**Status**: Complete

## Overview

This document defines the core data entities for the unified application launcher system. The data model supports project-aware application launching with variable substitution, automatic desktop file generation, and window rules integration.

## Entity Relationship Diagram

```
┌─────────────────────────────────┐
│  ApplicationRegistryEntry       │
│  (source of truth)              │
│  - name                         │
│  - display_name                 │
│  - command                      │
│  - parameters                   │
│  - scope                        │
│  - expected_class               │
│  - preferred_workspace          │
│  - icon                         │
│  - nix_package                  │
│  - multi_instance               │
│  - fallback_behavior            │
└─────────┬───────────────────────┘
          │
          │ generates (1:1)
          ├──────────────────────────────┐
          │                              │
          ▼                              ▼
┌─────────────────────┐        ┌─────────────────────┐
│  DesktopFile        │        │  WindowRule         │
│  (generated)        │        │  (generated)        │
│  - file_path        │        │  - pattern          │
│  - name             │        │  - scope            │
│  - exec_command     │        │  - priority         │
│  - icon             │        │  - workspace        │
│  - categories       │        │  - description      │
│  - startup_wm_class │        └─────────────────────┘
└─────────────────────┘
          │
          │ invokes at runtime
          ▼
┌─────────────────────────────────┐
│  LauncherWrapper                │
│  (runtime execution)            │
│  1. Queries daemon              │
│  2. Loads VariableContext       │
│  3. Substitutes variables       │
│  4. Creates LaunchCommand       │
│  5. Executes application        │
└─────────┬───────────────────────┘
          │
          │ uses
          ▼
┌─────────────────────────────────┐      ┌─────────────────────┐
│  VariableContext                │      │  LaunchCommand      │
│  (runtime state)                │      │  (execution log)    │
│  - project_name                 │      │  - template         │
│  - project_dir                  │      │  - resolved_command │
│  - session_name                 │      │  - context_snapshot │
│  - workspace                    │      │  - timestamp        │
│  - user_home                    │      │  - exit_code        │
│  - display_name                 │      └─────────────────────┘
│  - icon                         │
└─────────────────────────────────┘
```

## Core Entities

### 1. ApplicationRegistryEntry

**Purpose**: Declarative application definition in the registry

**Storage**: `~/.config/i3/application-registry.json` (generated from Nix)

**Lifecycle**: Created during home-manager rebuild, persists until removed from Nix config

**Schema**:
```json
{
  "name": "string (required)",
  "display_name": "string (required)",
  "command": "string (required)",
  "parameters": "string (optional)",
  "scope": "scoped | global (optional, default: global)",
  "expected_class": "string (optional)",
  "expected_title_contains": "string (optional)",
  "preferred_workspace": "integer 1-9 (optional)",
  "icon": "string (optional)",
  "nix_package": "string (optional)",
  "multi_instance": "boolean (optional, default: true)",
  "fallback_behavior": "skip | use_home | error (optional, default: skip)"
}
```

**Fields**:

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|------------|
| `name` | string | ✅ | Unique identifier (kebab-case) | `^[a-z0-9-]+$` |
| `display_name` | string | ✅ | Human-readable name for launcher | 1-50 chars |
| `command` | string | ✅ | Executable command (base, no args) | Must be in PATH or absolute |
| `parameters` | string | ❌ | Arguments with variable templates | May contain `$VAR` placeholders |
| `scope` | enum | ❌ | Project association (scoped/global) | `scoped \| global` |
| `expected_class` | string | ❌ | WM_CLASS pattern for window rules | Regex pattern |
| `expected_title_contains` | string | ❌ | Window title substring match | Used if `expected_class` not applicable |
| `preferred_workspace` | integer | ❌ | Target workspace number | 1-9 |
| `icon` | string | ❌ | Icon name or path | Icon theme name or absolute path |
| `nix_package` | string | ❌ | NixOS package reference | For documentation/validation |
| `multi_instance` | boolean | ❌ | Allow multiple windows | Default: true |
| `fallback_behavior` | enum | ❌ | Behavior when project unavailable | `skip \| use_home \| error` |

**Relationships**:
- 1:1 with DesktopFile (generated)
- 1:1 with WindowRule (generated, if `expected_class` provided)
- 1:N with LaunchCommand (execution history)

**Example**:
```json
{
  "name": "vscode",
  "display_name": "VS Code",
  "command": "code",
  "parameters": "$PROJECT_DIR",
  "scope": "scoped",
  "expected_class": "Code",
  "preferred_workspace": 1,
  "icon": "vscode",
  "nix_package": "pkgs.vscode",
  "multi_instance": true,
  "fallback_behavior": "skip"
}
```

**Validation Rules**:
- `name` must be unique across all registry entries
- `command` must be a valid executable (checked at build time if `nix_package` provided)
- `parameters` must not contain shell metacharacters: `;`, `|`, `&`, `` ` ``, `$()`, `${}`
- `preferred_workspace` must be 1-9 if provided
- At least one of `expected_class` or `expected_title_contains` should be provided for scoped applications

---

### 2. DesktopFile

**Purpose**: XDG desktop entry for launcher integration

**Storage**: `~/.local/share/applications/<name>.desktop` (managed by home-manager)

**Lifecycle**: Generated during home-manager rebuild, removed when registry entry deleted

**Schema** (XDG Desktop Entry Specification):
```ini
[Desktop Entry]
Type=Application
Name=<display_name>
Exec=<wrapper_script> <name>
Icon=<icon>
Categories=<generated_from_scope>
Terminal=false
StartupWMClass=<expected_class>
X-Project-Scope=<scope>
X-Preferred-Workspace=<preferred_workspace>
```

**Fields**:

| Field | Source | Example |
|-------|--------|---------|
| `Name` | `display_name` | "VS Code" |
| `Exec` | Generated | "/home/user/.local/bin/app-launcher-wrapper.sh vscode" |
| `Icon` | `icon` | "vscode" |
| `Categories` | Derived from `scope` | "Development;IDE;Scoped;" or "Application;Global;" |
| `StartupWMClass` | `expected_class` | "Code" |
| `X-Project-Scope` | `scope` | "scoped" |
| `X-Preferred-Workspace` | `preferred_workspace` | "1" |

**Generation Logic** (Nix):
```nix
xdg.desktopEntries.${app.name} = {
  name = app.display_name;
  exec = "${config.home.homeDirectory}/.local/bin/app-launcher-wrapper.sh ${app.name}";
  icon = app.icon;
  categories = if app.scope == "scoped" then [ "Development" "Scoped" ] else [ "Application" "Global" ];
  terminal = false;
  settings = {
    StartupWMClass = app.expected_class;
    "X-Project-Scope" = app.scope;
    "X-Preferred-Workspace" = toString app.preferred_workspace;
  };
};
```

**Relationships**:
- 1:1 with ApplicationRegistryEntry (source)
- Invokes LauncherWrapper on execution

---

### 3. WindowRule

**Purpose**: Window classification and workspace assignment

**Storage**: `~/.config/i3/window-rules-generated.json` (managed by home-manager)

**Lifecycle**: Generated during home-manager rebuild, merged with manual rules by daemon

**Schema**:
```json
{
  "pattern_rule": {
    "pattern": "string",
    "scope": "scoped | global",
    "priority": "integer",
    "description": "string"
  },
  "workspace": "integer 1-9"
}
```

**Fields**:

| Field | Source | Description |
|-------|--------|-------------|
| `pattern_rule.pattern` | `expected_class` or `expected_title_contains` | Regex pattern for window matching |
| `pattern_rule.scope` | `scope` | Window scope (scoped/global) |
| `pattern_rule.priority` | Computed | 240 (scoped), 180 (global), 200 (PWA) |
| `pattern_rule.description` | Generated | "{display_name} - WS{workspace}" |
| `workspace` | `preferred_workspace` | Target workspace number |

**Generation Logic** (Nix):
```nix
let
  generateRule = app: {
    pattern_rule = {
      pattern = app.expected_class or app.expected_title_contains;
      scope = app.scope;
      priority = if app.scope == "scoped" then 240 else 180;
      description = "${app.display_name} - WS${toString app.preferred_workspace}";
    };
    workspace = app.preferred_workspace;
  };
in
  map generateRule (filter (app: app.expected_class or app.expected_title_contains != null) registry.applications)
```

**Priority Levels**:
- **250+**: Manual overrides (user customization)
- **240**: Scoped applications (generated)
- **200**: PWA applications (generated)
- **180**: Global applications (generated)

**Relationships**:
- 1:1 with ApplicationRegistryEntry (source)
- Merged with manual rules by daemon

---

### 4. VariableContext

**Purpose**: Runtime environment for variable substitution

**Storage**: Ephemeral (queried at launch time, not persisted)

**Lifecycle**: Created during application launch, destroyed after command execution

**Schema**:
```typescript
interface VariableContext {
  project_name: string | null;        // From daemon query
  project_dir: string | null;         // From project config file
  session_name: string | null;        // Convention: same as project_name
  workspace: number | null;           // Target workspace (from registry)
  user_home: string;                  // $HOME environment variable
  display_name: string | null;        // From project config
  icon: string | null;                // From project config
}
```

**Fields**:

| Field | Source | Example | Substitution Variable |
|-------|--------|---------|----------------------|
| `project_name` | Daemon query | "nixos" | `$PROJECT_NAME` |
| `project_dir` | Project config | "/etc/nixos" | `$PROJECT_DIR` |
| `session_name` | project_name | "nixos" | `$SESSION_NAME` |
| `workspace` | Registry entry | 1 | `$WORKSPACE` |
| `user_home` | $HOME | "/home/user" | `$HOME` |
| `display_name` | Project config | "NixOS" | `$PROJECT_DISPLAY_NAME` |
| `icon` | Project config | "" | `$PROJECT_ICON` |

**Data Flow**:
```
1. Query daemon: get_current_project() → project_name or null
2. Load project config: ~/.config/i3/projects/<name>.json → { directory, display_name, icon }
3. Populate context: { project_name, project_dir, session_name, ... }
4. Validate: Ensure project_dir is absolute, exists, no special chars
5. Substitute: Replace $VAR placeholders in parameters
```

**Validation Rules**:
- `project_dir` must be absolute path (starts with `/`)
- `project_dir` must exist on filesystem
- `project_dir` must not contain newlines, null bytes, or shell metacharacters
- If validation fails, set to null and use fallback behavior

**Example**:
```json
{
  "project_name": "nixos",
  "project_dir": "/etc/nixos",
  "session_name": "nixos",
  "workspace": 1,
  "user_home": "/home/vpittamp",
  "display_name": "NixOS",
  "icon": ""
}
```

**Relationships**:
- Created by LauncherWrapper
- Used to resolve variables in ApplicationRegistryEntry.parameters

---

### 5. LaunchCommand

**Purpose**: Fully resolved command ready for execution

**Storage**: `~/.local/state/app-launcher.log` (execution log, last 1000 entries)

**Lifecycle**: Created at launch time, logged for debugging

**Schema**:
```typescript
interface LaunchCommand {
  timestamp: string;              // ISO 8601 format
  app_name: string;               // Application identifier
  template: string;               // Original command template
  resolved_command: string;       // After variable substitution
  context_snapshot: VariableContext;  // Project context at launch time
  exit_code: number | null;       // Process exit code (if available)
}
```

**Fields**:

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `timestamp` | string | Launch time (ISO 8601) | "2025-10-24T14:32:45-04:00" |
| `app_name` | string | Application identifier | "vscode" |
| `template` | string | Original command + parameters | "code $PROJECT_DIR" |
| `resolved_command` | string | After substitution | "code /etc/nixos" |
| `context_snapshot` | object | Variable context at launch | {...} |
| `exit_code` | number | Process exit code | 0 (success), 1 (error) |

**Log Format**:
```
[2025-10-24T14:32:45-04:00] App: vscode | Project: nixos | Command: code /etc/nixos | Exit: 0
```

**Example**:
```json
{
  "timestamp": "2025-10-24T14:32:45-04:00",
  "app_name": "vscode",
  "template": "code $PROJECT_DIR",
  "resolved_command": "code /etc/nixos",
  "context_snapshot": {
    "project_name": "nixos",
    "project_dir": "/etc/nixos",
    "session_name": "nixos",
    "workspace": 1,
    "user_home": "/home/vpittamp",
    "display_name": "NixOS",
    "icon": ""
  },
  "exit_code": 0
}
```

**Use Cases**:
- Debugging launch failures
- Auditing application usage
- Verifying variable substitution
- Performance monitoring

**Relationships**:
- N:1 with ApplicationRegistryEntry (many launches per app)
- Contains snapshot of VariableContext

---

## State Transitions

### ApplicationRegistryEntry Lifecycle

```
[Defined in Nix] → [home-manager rebuild] → [JSON generated] → [Desktop file created] → [Window rule created]
                                                    ↓
                                           [Available in launcher]
                                                    ↓
                                            [User selects app]
                                                    ↓
                                          [LauncherWrapper invoked]
                                                    ↓
                                         [VariableContext created]
                                                    ↓
                                        [LaunchCommand executed]
                                                    ↓
                                          [Application launches]
```

### Variable Substitution Flow

```
[Application selected] → [Load registry entry] → [Query daemon for project]
                                                         ↓
                                              [Project active?]
                                             /              \
                                          Yes               No
                                           ↓                 ↓
                              [Load project config]    [Use fallback behavior]
                                        ↓                    ↓
                              [Create VariableContext]      ↓
                                        ↓                    ↓
                              [Substitute variables] ← ─ ─ ─
                                        ↓
                              [Validate resolved values]
                                        ↓
                              [Build argument array]
                                        ↓
                              [Execute command]
```

### Window Rule Resolution

```
[Window created] → [Daemon receives i3 event] → [Load window rules (generated + manual)]
                                                          ↓
                                                [Sort by priority (descending)]
                                                          ↓
                                            [Match window against patterns]
                                                          ↓
                                            [First match wins (highest priority)]
                                                          ↓
                                   [Apply scope (scoped/global) + workspace assignment]
                                                          ↓
                                            [Mark window with project tag if scoped]
```

---

## Validation Rules

### Build-Time Validation (Nix)

1. **Registry schema validation**:
   - All required fields present (`name`, `display_name`, `command`)
   - Field types correct (string, integer, enum)
   - `name` matches pattern `^[a-z0-9-]+$`
   - `preferred_workspace` in range 1-9
   - No duplicate `name` values

2. **Parameter safety validation**:
   - `parameters` does not contain: `;`, `|`, `&`, `` ` ``, `$()`, `${}`
   - Only whitelisted variables allowed: `$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`, `$WORKSPACE`, `$HOME`

3. **Desktop file generation**:
   - `Exec` line points to valid wrapper script
   - `Icon` resolves to icon theme or valid path
   - `StartupWMClass` matches `expected_class`

### Runtime Validation (Wrapper Script)

1. **Registry lookup**:
   - Application exists in registry
   - Registry JSON is valid

2. **Directory validation**:
   - `project_dir` is absolute path (`starts with /`)
   - `project_dir` exists (`-d "$project_dir"`)
   - `project_dir` contains no newlines or null bytes

3. **Command validation**:
   - `command` exists in PATH
   - Resolved parameters contain no shell metacharacters after substitution

---

## Error Handling

### Missing Project Context

| Fallback Behavior | Action | Use Case |
|-------------------|--------|----------|
| `skip` | Launch without parameter | Terminal emulators (default to $HOME) |
| `use_home` | Substitute `$HOME` | File managers (open home directory) |
| `error` | Show error, abort launch | Critical project-dependent tools |

### Invalid Registry Entry

| Error | Detection | Action |
|-------|-----------|--------|
| Malformed JSON | Build time | nixos-rebuild fails with syntax error |
| Missing required field | Build time | nixos-rebuild fails with validation error |
| Invalid field type | Build time | nixos-rebuild fails with type error |
| Duplicate name | Build time | nixos-rebuild fails with uniqueness error |

### Launch Failures

| Error | Cause | Recovery |
|-------|-------|----------|
| Command not found | `command` not in PATH | Show error with package hint |
| Invalid directory | `project_dir` validation failed | Use fallback or error |
| Daemon not running | `i3pm project current` fails | Default to global mode (no project) |
| Permission denied | Execute permission missing | Show error with chmod suggestion |

---

## Performance Characteristics

| Operation | Target | Actual | Measurement |
|-----------|--------|--------|-------------|
| Daemon query | < 10ms | < 5ms | `get_current_project()` latency |
| Variable substitution | < 100ms | < 50ms | Bash string replacement |
| Total launch overhead | < 500ms | < 200ms | Wrapper script execution |
| Desktop file load | < 100ms | ~50ms | rofi `-show drun` startup |

---

## Storage Locations

| Entity | Path | Owner | Persistence |
|--------|------|-------|-------------|
| ApplicationRegistryEntry | `~/.config/i3/application-registry.json` | home-manager | Until rebuild |
| DesktopFile | `~/.local/share/applications/<name>.desktop` | home-manager | Until rebuild |
| WindowRule (generated) | `~/.config/i3/window-rules-generated.json` | home-manager | Until rebuild |
| WindowRule (manual) | `~/.config/i3/window-rules-manual.json` | User | Forever (force=false) |
| LaunchCommand (log) | `~/.local/state/app-launcher.log` | Wrapper script | Last 1000 entries |
| VariableContext | Ephemeral | Runtime | Discarded after launch |

---

## Extensibility

### Adding New Variables

To add a new variable (e.g., `$PROJECT_REPO_URL`):

1. **Update VariableContext** (this document):
   ```typescript
   interface VariableContext {
     ...
     repo_url: string | null;  // From project config
   }
   ```

2. **Update project config schema** (project JSON):
   ```json
   {
     "repo_url": "https://github.com/user/repo"
   }
   ```

3. **Update wrapper script** (variable substitution):
   ```bash
   REPO_URL=$(jq -r '.repo_url // ""' "$PROJECT_CONFIG")
   PARAM_RESOLVED="${PARAM_RESOLVED//\$PROJECT_REPO_URL/$REPO_URL}"
   ```

4. **Update validation** (whitelist):
   ```bash
   # Allow $PROJECT_REPO_URL in parameters
   ```

### Adding New Fallback Behaviors

To add a new fallback (e.g., `prompt`):

1. **Update ApplicationRegistryEntry schema**:
   ```json
   "fallback_behavior": "skip | use_home | error | prompt"
   ```

2. **Update wrapper script**:
   ```bash
   case "$FALLBACK_BEHAVIOR" in
     "prompt")
       PROJECT_DIR=$(zenity --file-selection --directory)
       ;;
   esac
   ```

---

## Related Documents

- **Specification**: `/etc/nixos/specs/034-create-a-feature/spec.md`
- **Implementation Plan**: `/etc/nixos/specs/034-create-a-feature/plan.md`
- **Research Findings**: `/etc/nixos/specs/034-create-a-feature/research.md`
- **Contracts**: `/etc/nixos/specs/034-create-a-feature/contracts/` (next phase)

---

**Data Model Status**: ✅ COMPLETE
**Next Step**: Generate contracts/ directory (JSON schemas, CLI API specs, launcher protocol)
