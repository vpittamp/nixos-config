# Data Model: Unified Workspace Bar Icon System

**Feature**: 057-workspace-bar-icons | **Date**: 2025-11-10

This document defines the data entities, relationships, validation rules, and state transitions for the workspace bar icon system.

---

## Entity Definitions

### 1. IconIndex

**Description**: In-memory mapping from application identifiers (app_id, window_class, window_instance) to resolved icon paths and display names.

**Fields**:
```python
class IconIndex:
    _by_desktop_id: Dict[str, IconPayload]      # Desktop file stem → icon info
    _by_startup_wm: Dict[str, IconPayload]      # StartupWMClass → icon info
    _by_app_id: Dict[str, IconPayload]          # App name/PWA ULID → icon info
    _icon_cache: Dict[str, str]                 # Icon name → resolved absolute path
```

**IconPayload** (nested structure):
```python
@dataclass
class IconPayload:
    icon: str          # Absolute path to icon file or empty string
    name: str          # Display name for tooltip/fallback
```

**Lifecycle**:
- **Creation**: On daemon startup via `DesktopIconIndex.__init__()`
- **Population**: Loads app registry, PWA registry, desktop files sequentially
- **Usage**: Queried for every workspace update (window focus, window creation, workspace switch)
- **Invalidation**: Daemon restart required for registry changes (no hot-reload)

**Validation Rules**:
1. Icon paths MUST be absolute or empty string (relative paths not allowed)
2. Icon files MUST exist on filesystem at time of resolution (cache entry = "" if not found)
3. Display names MUST be non-empty (fallback to app_id if missing)
4. All dictionary keys MUST be lowercase for case-insensitive matching
5. Icon backgrounds SHOULD integrate well with Catppuccin Mocha theme - either transparent OR intentional colored backgrounds that complement the palette (non-blocking validation - only unintentional white/default backgrounds are problematic)

**Related Entities**: IconResolutionCascade (uses IconIndex for lookup)

---

### 2. IconResolutionCascade

**Description**: Ordered lookup chain starting from application registry, progressing through PWA registry and desktop files, then falling back to icon theme lookup and single-letter symbols.

**Priority Levels** (highest to lowest):
1. **Application Registry** (`_by_app_id` from `application-registry.json`)
   - Maps app names to icon names (e.g., `"firefox" → "firefox"`)
   - Includes terminal apps with `expected_instance` field (e.g., `"lazygit" → "lazygit"`)
2. **PWA Registry** (`_by_app_id` from `pwa-registry.json`)
   - Maps PWA ULIDs to absolute icon paths (e.g., `"ffpwa-01JCYF8Z2M" → "/etc/nixos/assets/pwa-icons/claude.png"`)
3. **Desktop File by ID** (`_by_desktop_id` from `.desktop` files)
   - Maps desktop file stem to icon name from `Icon=` field
4. **Desktop File by StartupWMClass** (`_by_startup_wm` from `.desktop` files)
   - Maps `StartupWMClass` property to icon name
5. **Icon Theme Lookup** (via `PyXDG.getIconPath()`)
   - Searches `XDG_DATA_DIRS` icon directories following XDG Icon Theme Specification
   - Supports theme inheritance (Papirus → hicolor)
6. **Fallback Symbol** (first uppercase letter of app name)
   - Returns styled single character when no icon found

**State Transitions**:
```
START → Try app registry lookup
  ↓ (not found)
Try PWA registry lookup
  ↓ (not found)
Try desktop file by ID
  ↓ (not found)
Try desktop file by StartupWMClass
  ↓ (not found)
Try icon theme lookup (getIconPath)
  ↓ (not found)
Return fallback symbol → END
```

**Validation Rules**:
1. Each lookup level MUST return `IconPayload` or empty dict
2. Cascade MUST try all levels before returning fallback
3. First successful lookup MUST terminate cascade (no further levels checked)
4. Icon theme lookup MUST respect `XDG_DATA_DIRS` precedence order
5. Fallback symbol MUST always succeed (cannot return empty)

**Performance Constraints**:
- **Cached lookup**: <50ms (cache hit on icon path)
- **Initial lookup**: <200ms (full cascade + filesystem access)
- **Cache size**: <10MB for ~100 applications

---

### 3. WorkspaceButton

**Description**: Single workspace UI element in the bar, containing workspace number, icon path, icon fallback symbol, focused/visible/urgent state, and application name for tooltip.

**Fields** (from Eww yuck widget definition):
```lisp
(defwidget workspace-button [
  number_label      ; String: Workspace number or name (e.g., "1", "23", "firefox")
  workspace_name    ; String: Full workspace name from Sway
  app_name          ; String: Application display name for tooltip
  icon_path         ; String: Absolute path to icon file or ""
  icon_fallback     ; String: Single uppercase character (e.g., "F" for Firefox)
  workspace_id      ; Integer: Sway workspace container ID
  focused           ; Boolean: Is this workspace currently focused?
  visible           ; Boolean: Is this workspace visible on any output?
  urgent            ; Boolean: Does this workspace have urgent hint?
  empty             ; Boolean: Does this workspace have zero windows?
])
```

**Visual States** (CSS classes):
1. **focused**: Purple background (`$mauve`), solid border
2. **visible** (not focused): Blue border (`$blue`), surface0 background
3. **urgent**: Red background (`$red`), solid border
4. **empty**: 40% opacity, dimmed appearance
5. **has-icon**: Icon image visible, fallback text hidden
6. **no-icon**: Icon image hidden (opacity 0), fallback text visible

**State Transitions**:
```
INITIAL (empty=true) → Window created → empty=false
UNFOCUSED → User focuses workspace → focused=true
FOCUSED → User switches away → focused=false, visible=false
VISIBLE (other output) → Monitor disconnected → visible=false
NO_ICON (icon_path="") → Icon resolved → has-icon (icon_path="/path/to/icon.svg")
```

**Validation Rules**:
1. `number_label` MUST be non-empty string
2. `workspace_id` MUST match valid Sway workspace container ID
3. `focused`, `visible`, `urgent`, `empty` MUST be mutually consistent:
   - `focused=true` implies `visible=true`
   - `empty=true` implies `app_name=""` and `icon_path=""`
4. `icon_path` MUST be absolute path or empty string (relative paths invalid)
5. `icon_fallback` MUST be single uppercase character (length=1)
6. At most ONE workspace button can have `focused=true` per output

**Related Entities**: IconIndex (provides icon_path), ApplicationRegistry (provides app_name)

---

### 4. ApplicationRegistry

**Description**: Centralized JSON mapping of application names to metadata including icon names, expected window classes, display names, and workspace preferences.

**File Path**: `~/.config/i3/application-registry.json`

**Schema**:
```json
{
  "version": "1.0",
  "applications": [
    {
      "name": "firefox",
      "display_name": "Firefox",
      "command": "firefox",
      "expected_class": "firefox",
      "expected_instance": null,
      "icon": "firefox",
      "scope": "global",
      "preferred_workspace": 3,
      "preferred_monitor_role": "secondary"
    },
    {
      "name": "lazygit",
      "display_name": "lazygit",
      "command": "ghostty -e lazygit",
      "expected_class": "ghostty",
      "expected_instance": "lazygit",
      "icon": "lazygit",
      "scope": "scoped",
      "preferred_workspace": 7,
      "preferred_monitor_role": null
    }
  ]
}
```

**Field Definitions**:
- `name` (string, required): Unique application identifier (lowercase, no spaces)
- `display_name` (string, required): Human-readable name for UI display
- `command` (string, required): Shell command to launch application
- `expected_class` (string, nullable): Expected `window_class` from Sway
- `expected_instance` (string, nullable): Expected `window_instance` (for terminal apps)
- `icon` (string, required): Icon name or absolute path
- `scope` (enum: "global" | "scoped", required): Project visibility scope
- `preferred_workspace` (integer, nullable): Workspace number preference
- `preferred_monitor_role` (enum: "primary" | "secondary" | "tertiary", nullable): Monitor assignment

**Validation Rules**:
1. `name` MUST be unique across all applications
2. `icon` MUST be non-empty (either icon name or absolute path)
3. `expected_class` OR `expected_instance` MUST be non-null (at least one identifier)
4. `preferred_workspace` MUST be in range [1, 70] if not null
5. Terminal apps (launched via `ghostty`) SHOULD have `expected_instance` matching command argument

**Indexing Strategy**:
- Primary index: `name` → `IconPayload`
- No indexing by `expected_class` (multiple apps can share same class, e.g., firefox/firefox-pwa)
- No indexing by `expected_instance` (only used for matching, not lookup key)

**Related Entities**: IconIndex (loads this registry), PWARegistry (separate registry)

---

### 5. PWARegistry

**Description**: JSON mapping of PWA ULIDs to metadata including custom icon paths (typically PNG files in `/etc/nixos/assets/pwa-icons/`).

**File Path**: `~/.config/i3/pwa-registry.json`

**Schema**:
```json
{
  "version": "1.0",
  "pwas": [
    {
      "name": "Claude",
      "url": "https://claude.ai",
      "ulid": "01JCYF8Z2VQRSTUVWXYZ123456",
      "icon": "/etc/nixos/assets/pwa-icons/claude.png",
      "preferred_workspace": 52,
      "preferred_monitor_role": "tertiary"
    }
  ]
}
```

**Field Definitions**:
- `name` (string, required): Human-readable PWA name
- `url` (string, required): PWA origin URL
- `ulid` (string, required): Unique ULID identifier (26 characters, base32)
- `icon` (string, required): Absolute path to PNG icon file
- `preferred_workspace` (integer, nullable): Workspace number preference
- `preferred_monitor_role` (enum: "primary" | "secondary" | "tertiary", nullable): Monitor assignment

**Validation Rules**:
1. `ulid` MUST be unique across all PWAs
2. `ulid` MUST be valid ULID format (26 characters, base32: `[0-9A-HJKMNP-TV-Z]{26}`)
3. `icon` MUST be absolute path to existing PNG file
4. `preferred_workspace` MUST be in range [1, 70] if not null
5. PWA app_id in Sway MUST follow pattern: `ffpwa-{ulid}` (lowercase)
6. PWA icons SHOULD integrate well with workspace bar theme - either transparent backgrounds OR intentional colored backgrounds that complement Catppuccin Mocha palette. Icons with unintentional white/default backgrounds (like some ChatGPT/Claude PWA icons) should be replaced with transparent versions or designs with theme-coordinated colors (see adi1090x/widgets examples: GitHub #24292E, Reddit #E46231)

**Indexing Strategy**:
- Primary index: `"ffpwa-{ulid}".lower()` → `IconPayload`
- Example: `"ffpwa-01jcyf8z2vqrstuvwxyz123456"` → `{icon: "/etc/nixos/assets/pwa-icons/claude.png", name: "Claude"}`

**Related Entities**: IconIndex (loads this registry), ApplicationRegistry (separate registry)

---

## Relationships

### Entity Relationship Diagram

```
┌─────────────────────┐
│ ApplicationRegistry │ (JSON file)
│ ~/.config/i3/       │
│ application-        │
│ registry.json       │
└──────────┬──────────┘
           │ loads
           ↓
       ┌───────────┐      resolves icons for      ┌──────────────────┐
       │ IconIndex │ ←─────────────────────────── │ WorkspaceButton  │
       │ (in-memory│                               │ (Eww widget)     │
       │  cache)   │                               └──────────────────┘
       └─────┬─────┘
             ↑ loads
             │
┌────────────┴──────┐
│ PWARegistry       │ (JSON file)
│ ~/.config/i3/     │
│ pwa-registry.json │
└───────────────────┘
             ↑
             │ uses
             │
  ┌──────────┴──────────────┐
  │ IconResolutionCascade   │ (algorithm)
  │ (5-step priority chain) │
  └─────────────────────────┘
```

**Key Relationships**:
1. **IconIndex** loads **ApplicationRegistry** and **PWARegistry** on daemon startup
2. **IconResolutionCascade** queries **IconIndex** for each workspace button update
3. **WorkspaceButton** displays icon resolved by **IconResolutionCascade**
4. **ApplicationRegistry** and **PWARegistry** are independent sources (no cross-references)

---

## Data Flow

### Icon Resolution Flow

```
┌─────────────────┐
│ Window Created  │ (Sway IPC event: window::new)
└────────┬────────┘
         ↓
┌────────────────────────────┐
│ Extract Window Identifiers │
│ - app_id                   │
│ - window_class             │
│ - window_instance          │
└────────┬───────────────────┘
         ↓
┌────────────────────────────┐
│ Query IconIndex.lookup()   │
│ - Try app registry         │
│ - Try PWA registry         │
│ - Try desktop files        │
│ - Try icon theme lookup    │
│ - Fallback to symbol       │
└────────┬───────────────────┘
         ↓
┌────────────────────────────┐
│ Return IconPayload         │
│ {icon: "/path/icon.svg",   │
│  name: "Firefox"}          │
└────────┬───────────────────┘
         ↓
┌────────────────────────────┐
│ Generate Workspace Data    │
│ (build_workspace_payload)  │
└────────┬───────────────────┘
         ↓
┌────────────────────────────┐
│ Emit Eww Yuck Markup       │
│ (workspace-button widget)  │
└────────┬───────────────────┘
         ↓
┌────────────────────────────┐
│ Eww Renders Icon           │
│ (image widget 20×20px)     │
└────────────────────────────┘
```

**Performance Characteristics**:
1. **Cache hit**: Icon path already in `_icon_cache` → <5ms
2. **Registry hit**: Icon name in app/PWA registry → 5-20ms (dict lookup + cache)
3. **Desktop file hit**: Icon in `.desktop` file → 20-50ms (filesystem read + cache)
4. **Icon theme hit**: PyXDG `getIconPath()` → 50-150ms (theme inheritance + filesystem search)
5. **Fallback**: First letter extraction → <1ms (always succeeds)

---

## Validation Rules Summary

### Cross-Entity Constraints

1. **Icon Path Consistency**:
   - All icon paths in IconIndex MUST resolve to existing files OR be empty string
   - PWARegistry icon paths MUST be absolute (no icon name lookup)
   - ApplicationRegistry icon values CAN be icon names or absolute paths

2. **Window Identifier Uniqueness**:
   - `app_id` alone NOT guaranteed unique (e.g., multiple firefox windows)
   - `expected_instance` distinguishes terminal apps sharing same `window_class`
   - IconIndex uses ALL identifiers (app_id, class, instance) for matching

3. **Workspace Button Icon Display**:
   - `icon_path != ""` → Display image, hide fallback
   - `icon_path == ""` → Hide image, display fallback symbol
   - Fallback symbol MUST always be single character (never empty)

4. **Registry Version Compatibility**:
   - ApplicationRegistry version: `"1.0"`
   - PWARegistry version: `"1.0"`
   - Daemon MUST validate version field before loading

---

## Testing Validation Matrix

| Entity | Unit Tests | Integration Tests | E2E Tests (sway-test) |
|--------|------------|-------------------|-----------------------|
| **IconIndex** | ✅ Dict operations, cache logic | ✅ Registry loading | ❌ (internal only) |
| **IconResolutionCascade** | ✅ Priority ordering, fallback | ✅ Icon theme lookup | ✅ Walker parity |
| **WorkspaceButton** | ❌ (Eww widget) | ❌ (visual component) | ✅ Icon display |
| **ApplicationRegistry** | ✅ Schema validation | ✅ File loading | ✅ Terminal app icons |
| **PWARegistry** | ✅ ULID format validation | ✅ Absolute path verification | ✅ PWA icon display |

**Test Coverage Goals**:
- **Unit tests**: >80% coverage for Python code (IconIndex, validation logic)
- **Integration tests**: All registry loading paths, icon resolution cascade
- **E2E tests**: Visual icon display for 5+ representative apps (regular, PWA, terminal, fallback)

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-10 | Initial data model definition for feature 057 |

