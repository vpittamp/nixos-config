# Window Rules Generation from Application Registry - Research Document

**Feature**: 034-create-a-feature
**Date**: 2025-10-24
**Research Scope**: Automatic window rules generation from application registry

## Executive Summary

This document analyzes the current window rules system and presents a recommended strategy for automatically generating window rules from the application registry. The analysis reveals that:

1. **Current Schema**: window-rules.json uses a daemon-specific format (PatternRule) different from Feature 031's schema
2. **Daemon Architecture**: Event-driven Python daemon with file watcher and hot-reload capability
3. **Generation Strategy**: Build-time generation via home-manager with user override support
4. **Reload Mechanism**: Automatic via file watcher (100ms debounce)

---

## 1. Current window-rules.json Schema

### Location and Format

**File**: `~/.config/i3/window-rules.json`
**Owner**: i3-project-event-daemon (Python)
**Schema**: Daemon-internal format (NOT Feature 031's schema)

### Current Schema Structure

```json
[
  {
    "pattern_rule": {
      "pattern": "Code",              // WM_CLASS to match
      "scope": "scoped",              // scoped or global
      "priority": 250,                // Higher = evaluated first
      "description": "VS Code editor"
    },
    "workspace": 1,                   // Target workspace (1-9)
    "command": "floating disable",    // Optional i3 command (legacy)
    "actions": [                      // Optional structured actions (Feature 024)
      {"type": "workspace", "target": 2},
      {"type": "layout", "mode": "tabbed"}
    ],
    "modifier": "GLOBAL",             // Optional: GLOBAL, DEFAULT, ON_CLOSE, TITLE
    "blacklist": []                   // For GLOBAL modifier only
  }
]
```

**Schema Documentation**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/window_rules.py` (lines 16-181)

### Example Entries

```json
[
  {
    "pattern_rule": {
      "pattern": "Code",
      "scope": "scoped",
      "priority": 240,
      "description": "VS Code - Workspace 1"
    },
    "workspace": 1
  },
  {
    "pattern_rule": {
      "pattern": "FFPWA-01K772ZBM45JD68HXYNM193CVW",
      "scope": "global",
      "priority": 200,
      "description": "ChatGPT Codex - Workspace 2"
    },
    "workspace": 2
  },
  {
    "pattern_rule": {
      "pattern": "Pavucontrol",
      "scope": "global",
      "priority": 180,
      "description": "Volume Control - Workspace 8"
    },
    "workspace": 8
  }
]
```

**Current File Size**: 12,594 bytes (~65 rules)

### Key Schema Insights

1. **Array of Rules**: Top-level JSON array (no version wrapper)
2. **Pattern Matching**: Simple string patterns (exact WM_CLASS match)
3. **Priority System**: Explicit numeric priorities (higher = first)
4. **Scope Classification**: "scoped" (project-specific) or "global" (always visible)
5. **Legacy + New Format**: Supports both `workspace`/`command` (old) and `actions` (new)
6. **No Registry References**: Current rules are standalone, no link to registry

---

## 2. Daemon Rule Processing

### Rule Loading and Evaluation

**Source**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/window_rules.py`

#### Loading Process

```python
def load_window_rules(config_path: str) -> List[WindowRule]:
    """Load window rules from JSON file.

    Returns:
        List of WindowRule objects sorted by priority (highest first).
        Returns empty list if file doesn't exist.
    """
    path = Path(config_path).expanduser()

    if not path.exists():
        return []

    with open(path, "r") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError("window-rules.json must be a JSON array")

    rules = [WindowRule.from_json(item) for item in data]

    # Sort by priority (highest first) for efficient matching
    rules.sort(key=lambda r: r.priority, reverse=True)

    return rules
```

**Key Points**:
- Empty file or missing file returns empty list (graceful degradation)
- Rules sorted by priority (highest first) for efficient first-match evaluation
- Validation errors raise ValueError with context

#### Window Matching Logic

```python
class WindowRule:
    def matches(self, window_class: str, window_title: str = "") -> bool:
        """Check if this rule matches the window."""
        # Check pattern match (both class and title)
        if not self.pattern_rule.matches(window_class, window_title):
            return False

        # Check blacklist (for GLOBAL rules)
        if self.modifier == "GLOBAL" and window_class in self.blacklist:
            return False

        return True
```

**Evaluation Strategy**: First-match wins (highest priority rule that matches)

#### Priority Resolution

**Default Priorities** (observed from current config):
- **PWA applications**: 200
- **Scoped applications**: 240-250
- **Global applications**: 180-200

**No Conflicts**: Current system uses simple first-match, no multi-criteria scoring needed

---

## 3. Home-Manager JSON Merging Capabilities

### Current JSON Generation Pattern

**Example**: `/etc/nixos/home-modules/desktop/i3-project-daemon.nix` (lines 89-126)

```nix
xdg.configFile."i3/workspace-monitor-mapping.json" = {
  enable = true;
  force = false;  # Don't overwrite existing config - PRESERVES USER EDITS
  text = builtins.toJSON {
    version = "1.0";
    distribution = {
      "1_monitor" = {
        primary = [ 1 2 3 4 5 6 7 8 9 10 ... ];
        secondary = [];
      };
      "2_monitors" = {
        primary = [ 1 2 ];
        secondary = [ 3 4 5 6 7 8 9 10 ... ];
      };
      # ...
    };
  };
};
```

**Key Features**:
1. `force = false`: Preserves manual user edits (doesn't overwrite if file exists)
2. `builtins.toJSON`: Generates JSON from Nix data structures
3. `text`: Direct string generation (alternative to `source`)

### Merge Strategies Available

#### Strategy 1: Force Overwrite (force = true)
```nix
xdg.configFile."i3/window-rules.json" = {
  force = true;  # Always overwrite
  text = builtins.toJSON generatedRules;
};
```

**Pros**:
- Simple, guaranteed consistency with registry
- No stale rules from old configs

**Cons**:
- Destroys manual user edits
- Cannot customize individual rules without registry modification

#### Strategy 2: No Overwrite (force = false)
```nix
xdg.configFile."i3/window-rules.json" = {
  force = false;  # Preserve if exists
  text = builtins.toJSON generatedRules;
};
```

**Pros**:
- Preserves manual user edits
- Users can experiment with rules without registry changes

**Cons**:
- Initial generation only, no updates on registry changes
- Rules can drift from registry definitions

#### Strategy 3: Separate Generated + Manual Files
```nix
# Generated rules (always up-to-date)
xdg.configFile."i3/window-rules-generated.json" = {
  force = true;
  text = builtins.toJSON registryRules;
};

# Manual rules (user-editable, never overwritten)
xdg.configFile."i3/window-rules-manual.json" = {
  force = false;
  text = builtins.toJSON [];  # Empty initial
};
```

**Daemon loads both**:
```python
generated_rules = load_window_rules("~/.config/i3/window-rules-generated.json")
manual_rules = load_window_rules("~/.config/i3/window-rules-manual.json")
all_rules = generated_rules + manual_rules
all_rules.sort(key=lambda r: r.priority, reverse=True)
```

**Pros**:
- Clear separation: generated (automated) vs manual (custom)
- Registry updates automatically propagate
- Users can add manual overrides with higher priorities
- Both files can be JSON arrays (no complex merging needed)

**Cons**:
- Two files to understand
- Priority conflicts between files require careful management

### Recommended Strategy: Separate Generated + Manual Files

**Rationale**:
1. **Automatic Updates**: Generated file always reflects registry changes
2. **User Freedom**: Manual file allows customization without registry edits
3. **Clear Ownership**: Generated = home-manager, Manual = user
4. **Priority Control**: Manual rules can override generated via priority
5. **Debugging**: Can easily diff generated vs manual rules

---

## 4. Generation Implementation Strategy

### Build-Time vs Runtime Generation

#### Option A: Build-Time Generation (Recommended)

**Approach**: Generate window-rules-generated.json during home-manager rebuild

**Implementation**:
```nix
let
  # Read application registry
  registryData = builtins.fromJSON (builtins.readFile ./application-registry.json);

  # Transform registry entries to window rules
  generateWindowRule = app: {
    pattern_rule = {
      pattern = app.expected_class or app.expected_title_contains;
      scope = app.scope;  # "scoped" or "global"
      priority = if app.scope == "scoped" then 240 else 180;
      description = "${app.display_name} - Workspace ${toString app.preferred_workspace}";
    };
    workspace = app.preferred_workspace;
  };

  generatedRules = map generateWindowRule registryData.applications;
in
{
  xdg.configFile."i3/window-rules-generated.json" = {
    force = true;  # Always regenerate from registry
    text = builtins.toJSON generatedRules;
  };

  xdg.configFile."i3/window-rules-manual.json" = {
    force = false;  # Never overwrite user edits
    text = builtins.toJSON [];  # Empty initial array
  };
}
```

**Pros**:
- Fast (no runtime overhead)
- Deterministic (same registry = same rules)
- Validated at build time (errors prevent rebuild)
- No daemon dependency for generation

**Cons**:
- Requires home-manager rebuild to update
- Cannot react to runtime registry changes

#### Option B: Runtime Generation (Not Recommended)

**Approach**: Daemon generates rules on startup from registry

**Pros**:
- Updates without rebuild
- Can react to runtime changes

**Cons**:
- Complex daemon logic
- Error handling more difficult
- Slower startup
- Two sources of truth (registry + generated rules)

**Verdict**: Build-time generation is simpler, more reliable, and follows NixOS declarative philosophy.

---

## 5. Reload/Notification Mechanism

### File Watcher System

**Source**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/config.py` (lines 256-378)

#### Automatic Reload via Watchdog

```python
class WindowRulesWatcher:
    """File system watcher for window-rules.json with auto-reload."""

    def __init__(self, config_file: Path, reload_callback: Callable, debounce_ms: int = 100):
        """Initialize with debounced reload."""
        self.config_file = config_file
        self.reload_callback = reload_callback
        self.observer = Observer()  # watchdog.observers.Observer
        self.handler = DebouncedReloadHandler(reload_callback, debounce_ms)

    def start(self):
        """Start watching for modifications.

        Watches parent directory (not file itself) to handle atomic saves
        (temp file + rename) used by editors like vim/neovim.
        """
        watch_dir = self.config_file.parent
        self.observer.schedule(self.handler, str(watch_dir), recursive=False)
        self.observer.start()
```

**Debouncing**:
```python
class DebouncedReloadHandler(FileSystemEventHandler):
    def on_modified(self, event):
        """Debounces rapid file changes (editor save sequences)."""
        if self._debounce_task:
            self._debounce_task.cancel()

        self._debounce_task = self._loop.create_task(self._debounced_callback())

    async def _debounced_callback(self):
        await asyncio.sleep(self.debounce_seconds)  # 100ms default
        self.callback()  # Reload rules
```

**Reload Implementation**:
```python
def reload_window_rules(config_file: Path, previous_rules: List[WindowRule]) -> List[WindowRule]:
    """Reload with error handling and rollback."""
    try:
        rules = load_window_rules(str(config_file))
        logger.info(f"Reloaded {len(rules)} window rule(s)")
        return rules
    except ValueError as e:
        logger.error(f"Failed to reload: {e}")

        # Desktop notification on error
        subprocess.run([
            "notify-send", "-u", "critical",
            "i3pm Window Rules Error",
            f"Failed to reload window-rules.json:\n{str(e)[:100]}"
        ])

        # Rollback to previous config
        logger.warning(f"Retaining previous {len(previous_rules)} rules")
        return previous_rules
```

**Key Features**:
1. **Automatic Detection**: No manual reload command needed
2. **Debouncing**: Prevents excessive reloads during rapid edits (100ms default)
3. **Error Resilience**: Keeps old rules if new config is invalid
4. **User Notification**: Desktop notification on reload errors
5. **Graceful Degradation**: Daemon continues running with old rules

### Manual Reload Command

**Current Behavior**: No explicit reload command exists because file watcher handles it automatically.

**Future Enhancement** (optional):
```bash
# Force reload via IPC
i3pm rules reload

# Or via systemd restart
systemctl --user restart i3-project-event-listener
```

---

## 6. Generation from Application Registry

### Registry Schema Review

**File**: `/etc/nixos/specs/031-create-a-new/contracts/application-registry.schema.json`

**Registry Entry Structure**:
```json
{
  "name": "vscode",
  "display_name": "VS Code",
  "command": "code",
  "parameters": "$PROJECT_DIR",
  "expected_pattern_type": "class",
  "expected_class": "Code",
  "scope": "scoped",
  "preferred_workspace": 1,
  "nix_package": "pkgs.vscode"
}
```

### Transformation Logic

#### Pattern Type Mapping

| Registry `expected_pattern_type` | Window Rule `pattern` |
|----------------------------------|-----------------------|
| `"class"` | Use `expected_class` |
| `"title"` | Use `expected_title_contains` |
| `"title_regex"` | Use `expected_title_contains` with regex flag |
| `"pwa"` | Use `expected_class` (FFPWA-* pattern) |

#### Priority Assignment

**Scope-Based Priorities**:
```nix
priority = if app.scope == "scoped" then 240 else 180;
```

**Pattern Type Adjustments**:
```nix
priority =
  if app.expected_pattern_type == "pwa" then 200
  else if app.scope == "scoped" then 240
  else 180;
```

#### Workspace Assignment

**Direct Mapping**:
```nix
workspace = app.preferred_workspace;  # 1-9
```

**Validation**:
```nix
assert (app.preferred_workspace >= 1 && app.preferred_workspace <= 9);
```

### Example Transformation

**Registry Entry**:
```json
{
  "name": "lazygit",
  "display_name": "Lazygit",
  "command": "ghostty -e lazygit",
  "parameters": "--work-tree=$PROJECT_DIR",
  "expected_pattern_type": "title",
  "expected_title_contains": "lazygit",
  "scope": "scoped",
  "preferred_workspace": 2
}
```

**Generated Window Rule**:
```json
{
  "pattern_rule": {
    "pattern": "lazygit",
    "scope": "scoped",
    "priority": 240,
    "description": "Lazygit - Workspace 2"
  },
  "workspace": 2
}
```

### Nix Implementation Example

```nix
{ config, lib, pkgs, ... }:

let
  # Read application registry
  registryPath = "${config.xdg.configHome}/i3/application-registry.json";
  registryData = builtins.fromJSON (builtins.readFile registryPath);

  # Transform registry entry to window rule
  generateRule = app:
    let
      # Determine pattern from expected type
      pattern =
        if app.expected_pattern_type == "class" || app.expected_pattern_type == "pwa"
        then app.expected_class
        else app.expected_title_contains;

      # Assign priority based on pattern type and scope
      priority =
        if app.expected_pattern_type == "pwa" then 200
        else if app.scope == "scoped" then 240
        else 180;

      # Build description
      description = "${app.display_name} - Workspace ${toString app.preferred_workspace}";
    in
    {
      pattern_rule = {
        inherit pattern;
        scope = app.scope;
        priority = priority;
        description = description;
      };
      workspace = app.preferred_workspace;
    };

  # Generate rules from all registry applications
  generatedRules = map generateRule registryData.applications;

in
{
  # Generated rules (always up-to-date with registry)
  xdg.configFile."i3/window-rules-generated.json" = {
    enable = true;
    force = true;  # Always regenerate
    text = builtins.toJSON generatedRules;
  };

  # Manual rules (user overrides, never overwritten)
  xdg.configFile."i3/window-rules-manual.json" = {
    enable = true;
    force = false;  # Preserve user edits
    text = builtins.toJSON [];
  };
}
```

---

## 7. Daemon Integration Changes

### Loading Multiple Rule Files

**Current Implementation** (single file):
```python
# In daemon.py
rules = reload_window_rules(
    Path.home() / ".config/i3/window-rules.json"
)
```

**Enhanced Implementation** (multiple files):
```python
def load_all_window_rules() -> List[WindowRule]:
    """Load rules from both generated and manual sources."""
    config_dir = Path.home() / ".config/i3"

    # Load generated rules (from registry)
    generated_rules = reload_window_rules(
        config_dir / "window-rules-generated.json",
        previous_rules=[]
    )

    # Load manual rules (user customizations)
    manual_rules = reload_window_rules(
        config_dir / "window-rules-manual.json",
        previous_rules=[]
    )

    # Combine and sort by priority (highest first)
    all_rules = generated_rules + manual_rules
    all_rules.sort(key=lambda r: r.priority, reverse=True)

    logger.info(
        f"Loaded {len(generated_rules)} generated + "
        f"{len(manual_rules)} manual = {len(all_rules)} total rules"
    )

    return all_rules
```

### File Watcher Enhancement

**Watch Both Files**:
```python
# Watch generated rules
generated_watcher = WindowRulesWatcher(
    config_file=Path.home() / ".config/i3/window-rules-generated.json",
    reload_callback=lambda: reload_all_rules()
)

# Watch manual rules
manual_watcher = WindowRulesWatcher(
    config_file=Path.home() / ".config/i3/window-rules-manual.json",
    reload_callback=lambda: reload_all_rules()
)

generated_watcher.start()
manual_watcher.start()
```

---

## 8. Recommended Implementation Approach

### Summary of Recommendations

| Aspect | Recommendation | Rationale |
|--------|---------------|-----------|
| **Generation Timing** | Build-time (home-manager) | Deterministic, validated, fast |
| **File Strategy** | Separate generated + manual files | Clear ownership, automatic updates |
| **Merge Logic** | Concatenate + sort by priority | Simple, predictable, first-match evaluation |
| **Reload Mechanism** | Automatic via file watcher | Already implemented, <100ms response |
| **Priority System** | Scope-based (scoped=240, global=180, pwa=200) | Consistent with current config |
| **User Overrides** | Manual rules with higher priorities | Flexible without breaking automation |

### Implementation Phases

#### Phase 1: Home-Manager Module (Priority: P1)

**File**: `/etc/nixos/home-modules/tools/app-launcher/window-rules-generator.nix`

**Tasks**:
1. Read application-registry.json
2. Transform to window rules format
3. Generate window-rules-generated.json
4. Create empty window-rules-manual.json (if not exists)

**Example Usage**:
```nix
{ config, lib, pkgs, ... }:

{
  imports = [ ./app-launcher/window-rules-generator.nix ];

  services.appLauncher = {
    enable = true;
    registryPath = "${config.xdg.configHome}/i3/application-registry.json";
    generateWindowRules = true;
  };
}
```

#### Phase 2: Daemon Enhancement (Priority: P2)

**File**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/config.py`

**Tasks**:
1. Add `load_all_window_rules()` function
2. Update daemon startup to load both files
3. Add watchers for both generated and manual files
4. Update logging to show rule source counts

#### Phase 3: CLI Integration (Priority: P3)

**File**: `/etc/nixos/home-modules/tools/i3pm-deno/src/commands/rules.ts`

**Tasks**:
1. `i3pm rules list` - Show all rules with source indicator
2. `i3pm rules validate` - Check for conflicts and coverage
3. `i3pm rules edit manual` - Open manual rules in $EDITOR
4. `i3pm rules sync` - Force regeneration from registry

### Migration Path for Existing Users

**Step 1**: Backup existing window-rules.json
```bash
cp ~/.config/i3/window-rules.json ~/.config/i3/window-rules.backup
```

**Step 2**: Split into generated (from registry) and manual (custom)
```bash
# Auto-detect rules that match registry applications
i3pm rules split --input window-rules.json \
  --generated window-rules-generated.json \
  --manual window-rules-manual.json
```

**Step 3**: Verify split results
```bash
i3pm rules validate
```

**Step 4**: Rebuild with new home-manager module
```bash
nixos-rebuild switch --flake .#hetzner
```

---

## 9. Code Examples

### Complete Nix Module

```nix
# /etc/nixos/home-modules/tools/app-launcher/window-rules-generator.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.appLauncher;

  # Read and parse application registry
  registryPath = "${config.xdg.configHome}/i3/application-registry.json";
  registryData =
    if builtins.pathExists registryPath
    then builtins.fromJSON (builtins.readFile registryPath)
    else { version = "1.0.0"; applications = []; };

  # Transform registry entry to window rule
  generateRule = app:
    let
      # Determine pattern from expected type
      pattern =
        if app.expected_pattern_type == "class" || app.expected_pattern_type == "pwa"
        then app.expected_class
        else app.expected_title_contains or (throw "Application ${app.name} missing pattern field");

      # Assign priority based on pattern type and scope
      priority =
        if app.expected_pattern_type == "pwa" then 200
        else if app.scope == "scoped" then 240
        else 180;

      # Build description
      description = "${app.display_name} - Workspace ${toString app.preferred_workspace}";
    in
    {
      pattern_rule = {
        inherit pattern;
        scope = app.scope;
        priority = priority;
        description = description;
      };
      workspace = app.preferred_workspace;
    };

  # Generate rules from all applications
  generatedRules = map generateRule registryData.applications;

in
{
  options.services.appLauncher = {
    generateWindowRules = mkEnableOption "automatic window rules generation from registry";
  };

  config = mkIf cfg.generateWindowRules {
    # Generated rules (always up-to-date)
    xdg.configFile."i3/window-rules-generated.json" = {
      enable = true;
      force = true;  # Always overwrite with latest registry
      text = builtins.toJSON generatedRules;
    };

    # Manual rules (user overrides)
    xdg.configFile."i3/window-rules-manual.json" = {
      enable = true;
      force = false;  # Never overwrite user edits
      text = builtins.toJSON [];
    };
  };
}
```

### Daemon Rule Loading

```python
# Enhanced config.py

def load_all_window_rules() -> List[WindowRule]:
    """Load rules from both generated and manual sources.

    Returns:
        List of WindowRule objects sorted by priority (highest first).
        Combines generated rules (from registry) with manual rules (user overrides).
    """
    config_dir = Path.home() / ".config/i3"

    # Load generated rules
    generated_path = config_dir / "window-rules-generated.json"
    generated_rules = reload_window_rules(generated_path, previous_rules=[])

    # Load manual rules
    manual_path = config_dir / "window-rules-manual.json"
    manual_rules = reload_window_rules(manual_path, previous_rules=[])

    # Combine and sort by priority
    all_rules = generated_rules + manual_rules
    all_rules.sort(key=lambda r: r.priority, reverse=True)

    logger.info(
        f"Loaded window rules: {len(generated_rules)} generated + "
        f"{len(manual_rules)} manual = {len(all_rules)} total"
    )

    return all_rules


def watch_all_rule_files(reload_callback: Callable) -> List[WindowRulesWatcher]:
    """Setup watchers for both rule files.

    Args:
        reload_callback: Function to call when either file changes

    Returns:
        List of active watcher instances
    """
    config_dir = Path.home() / ".config/i3"

    generated_watcher = WindowRulesWatcher(
        config_file=config_dir / "window-rules-generated.json",
        reload_callback=reload_callback,
        debounce_ms=100
    )

    manual_watcher = WindowRulesWatcher(
        config_file=config_dir / "window-rules-manual.json",
        reload_callback=reload_callback,
        debounce_ms=100
    )

    generated_watcher.start()
    manual_watcher.start()

    logger.info("Started watching generated and manual window rules files")

    return [generated_watcher, manual_watcher]
```

---

## 10. Testing Strategy

### Unit Tests

```typescript
// i3pm-deno/src/commands/rules.test.ts

Deno.test("rules list shows generated + manual breakdown", async () => {
  const output = await runCommand("i3pm rules list");

  assert(output.includes("Generated rules: 15"));
  assert(output.includes("Manual rules: 3"));
  assert(output.includes("Total rules: 18"));
});

Deno.test("rules validate detects priority conflicts", async () => {
  // Setup: Create manual rule with same pattern as generated
  const result = await runCommand("i3pm rules validate");

  assert(result.exitCode === 1);
  assert(result.stderr.includes("Priority conflict"));
});
```

### Integration Tests

```bash
# Test automatic reload
echo "Adding new application to registry..."
jq '.applications += [{"name": "test", ...}]' ~/.config/i3/application-registry.json > tmp.json
mv tmp.json ~/.config/i3/application-registry.json

# Rebuild
nixos-rebuild switch --flake .#hetzner

# Verify rule appears
i3pm rules list | grep "test"

# Verify daemon reloaded
i3pm daemon events --type=config | grep "Reloaded.*window rules"
```

---

## 11. Future Enhancements

### 1. Conflict Detection CLI

```bash
i3pm rules conflicts

# Output:
# ⚠ Conflict detected:
#   Pattern: Code (class)
#   Generated: workspace=1, priority=240 (from registry: vscode)
#   Manual: workspace=3, priority=250 (from manual rules)
#   Winner: Manual (higher priority)
#
# Suggestion: Remove manual override or update registry
```

### 2. Coverage Analysis

```bash
i3pm rules coverage

# Output:
# Registry coverage: 15/20 applications (75%)
#
# Missing rules:
#   - slack (no window pattern defined)
#   - discord (expected_class not set)
#
# Orphaned rules (not in registry):
#   - OldApp (workspace=5)
```

### 3. Rule Visualization

```bash
i3pm rules tree

# Output:
# Window Rules (Priority Order):
# ├─ 250 [Manual] Code → WS3 (scoped)
# ├─ 240 [Generated] Ghostty → WS1 (scoped)
# ├─ 240 [Generated] Code → WS1 (scoped) [SHADOWED]
# ├─ 200 [Generated] FFPWA-* → WS2 (global)
# └─ 180 [Generated] Firefox → WS3 (global)
```

---

## Appendix: File Locations Reference

| File | Location | Owner | Purpose |
|------|----------|-------|---------|
| application-registry.json | `~/.config/i3/` | User/Home-Manager | Source of truth for applications |
| window-rules-generated.json | `~/.config/i3/` | Home-Manager | Auto-generated from registry |
| window-rules-manual.json | `~/.config/i3/` | User | Manual rule overrides |
| app-classes.json | `~/.config/i3/` | User/Home-Manager | Scoped/global classification |
| window-rules.json (legacy) | `~/.config/i3/` | Deprecated | Migrated to split files |

---

## References

1. **Daemon Window Rules**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/window_rules.py`
2. **Registry Schema**: `/etc/nixos/specs/031-create-a-new/contracts/application-registry.schema.json`
3. **Config Management**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/config.py`
4. **Home-Manager JSON Pattern**: `/etc/nixos/home-modules/desktop/i3-project-daemon.nix`
5. **Feature 031 Spec**: `/etc/nixos/specs/031-create-a-new/spec.md`
6. **Feature 034 Spec**: `/etc/nixos/specs/034-create-a-feature/spec.md`
