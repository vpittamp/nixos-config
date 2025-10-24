# Window Rules Generation - Quick Summary

**Feature**: 034-create-a-feature | **Date**: 2025-10-24

## TL;DR

**Recommended Strategy**: Separate generated + manual files with build-time generation via home-manager

**Files**:
- `window-rules-generated.json` - Auto-generated from registry (force=true)
- `window-rules-manual.json` - User overrides (force=false)

**Daemon**: Loads both files, concatenates, sorts by priority (highest first), first-match wins

**Reload**: Automatic via file watcher (100ms debounce)

---

## Current Schema (Daemon Format)

```json
[
  {
    "pattern_rule": {
      "pattern": "Code",              // WM_CLASS to match
      "scope": "scoped",              // scoped or global
      "priority": 240,                // Higher = evaluated first
      "description": "VS Code editor"
    },
    "workspace": 1                    // Target workspace (1-9)
  }
]
```

**Location**: `~/.config/i3/window-rules.json` (currently), will split into 2 files

**Owner**: i3-project-event-daemon (Python)

**Current Size**: 12,594 bytes (~65 rules)

---

## Registry to Window Rules Transformation

### Pattern Mapping

| Registry Field | Window Rule Field |
|---------------|-------------------|
| `expected_class` (for class/pwa) | `pattern_rule.pattern` |
| `expected_title_contains` (for title) | `pattern_rule.pattern` |
| `scope` | `pattern_rule.scope` |
| `preferred_workspace` | `workspace` |

### Priority Assignment

```nix
priority =
  if app.expected_pattern_type == "pwa" then 200
  else if app.scope == "scoped" then 240
  else 180;
```

### Example

**Registry**:
```json
{
  "name": "vscode",
  "display_name": "VS Code",
  "expected_pattern_type": "class",
  "expected_class": "Code",
  "scope": "scoped",
  "preferred_workspace": 1
}
```

**Generated Rule**:
```json
{
  "pattern_rule": {
    "pattern": "Code",
    "scope": "scoped",
    "priority": 240,
    "description": "VS Code - Workspace 1"
  },
  "workspace": 1
}
```

---

## Implementation Approach

### 1. Home-Manager Module (Build-Time Generation)

**File**: `/etc/nixos/home-modules/tools/app-launcher/window-rules-generator.nix`

```nix
let
  registryData = builtins.fromJSON (builtins.readFile registryPath);

  generateRule = app: {
    pattern_rule = {
      pattern = app.expected_class or app.expected_title_contains;
      scope = app.scope;
      priority = if app.scope == "scoped" then 240 else 180;
      description = "${app.display_name} - Workspace ${toString app.preferred_workspace}";
    };
    workspace = app.preferred_workspace;
  };

  generatedRules = map generateRule registryData.applications;
in
{
  # Generated rules (always regenerated)
  xdg.configFile."i3/window-rules-generated.json" = {
    force = true;
    text = builtins.toJSON generatedRules;
  };

  # Manual rules (never overwritten)
  xdg.configFile."i3/window-rules-manual.json" = {
    force = false;
    text = builtins.toJSON [];
  };
}
```

### 2. Daemon Enhancement (Load Both Files)

**File**: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/config.py`

```python
def load_all_window_rules() -> List[WindowRule]:
    """Load rules from both generated and manual sources."""
    config_dir = Path.home() / ".config/i3"

    generated_rules = reload_window_rules(config_dir / "window-rules-generated.json")
    manual_rules = reload_window_rules(config_dir / "window-rules-manual.json")

    all_rules = generated_rules + manual_rules
    all_rules.sort(key=lambda r: r.priority, reverse=True)

    logger.info(f"Loaded {len(generated_rules)} generated + {len(manual_rules)} manual rules")
    return all_rules
```

### 3. File Watchers (Both Files)

```python
generated_watcher = WindowRulesWatcher(config_dir / "window-rules-generated.json", reload_callback)
manual_watcher = WindowRulesWatcher(config_dir / "window-rules-manual.json", reload_callback)

generated_watcher.start()
manual_watcher.start()
```

---

## Reload Mechanism

### Automatic (File Watcher)

**Implementation**: watchdog.observers.Observer with 100ms debounce

**Behavior**:
1. Detects file modification in `~/.config/i3/` directory
2. Waits 100ms (debounce rapid editor saves)
3. Calls reload_callback
4. On error: Shows desktop notification, retains previous rules

**Response Time**: <100ms from file save to daemon reload

### Manual (Optional)

```bash
# Force reload (not needed with file watcher)
i3pm rules reload

# Or restart daemon
systemctl --user restart i3-project-event-listener
```

---

## Priority System

### Default Priorities

| Application Type | Priority | Evaluation Order |
|-----------------|----------|------------------|
| Manual overrides | 250+ | First (highest) |
| Scoped apps | 240 | Second |
| PWA apps | 200 | Third |
| Global apps | 180 | Last (lowest) |

### Conflict Resolution

**Rule**: First-match wins (highest priority rule that matches the window)

**Example**:
```
Priority 250: Manual rule Code → WS3 (wins)
Priority 240: Generated rule Code → WS1 (shadowed)
```

**User Override Strategy**: Add manual rule with higher priority (250+) to override generated rule (240)

---

## User Workflows

### 1. Add Application to Registry

```bash
# Edit registry
vi ~/.config/i3/application-registry.json

# Add entry
{
  "name": "slack",
  "display_name": "Slack",
  "command": "slack",
  "expected_pattern_type": "class",
  "expected_class": "Slack",
  "scope": "global",
  "preferred_workspace": 6
}

# Rebuild
nixos-rebuild switch --flake .#hetzner

# Rule automatically generated in window-rules-generated.json
# Daemon auto-reloads via file watcher
```

### 2. Override Generated Rule

```bash
# Edit manual rules
vi ~/.config/i3/window-rules-manual.json

# Add override with higher priority
[
  {
    "pattern_rule": {
      "pattern": "Code",
      "scope": "scoped",
      "priority": 250,
      "description": "VS Code override - WS3"
    },
    "workspace": 3
  }
]

# Daemon auto-reloads (no rebuild needed)
```

### 3. Verify Rules

```bash
# List all rules
i3pm rules list

# Output:
# Window Rules (18 total):
# - 15 generated (from registry)
# - 3 manual (user overrides)
#
# Priority order:
# 250 [Manual] Code → WS3 (scoped)
# 240 [Generated] Ghostty → WS1 (scoped)
# 240 [Generated] Code → WS1 (scoped) [SHADOWED]
# ...
```

---

## Benefits

### 1. Automatic Updates
- Registry changes propagate to rules on rebuild
- No manual window-rules.json editing needed

### 2. User Freedom
- Manual overrides preserved across rebuilds
- Higher priority wins (manual > generated)

### 3. Clear Ownership
- Generated file: Managed by home-manager
- Manual file: User-editable

### 4. Debugging
- Easy to diff generated vs manual
- Source tracking in rule listings

### 5. Consistency
- Single source of truth (registry)
- No duplicate rule definitions

---

## Migration from Existing Config

### Current State
- Single `window-rules.json` with 65 rules
- Mix of registry-based and custom rules

### Migration Steps

1. **Backup**:
   ```bash
   cp ~/.config/i3/window-rules.json ~/.config/i3/window-rules.backup
   ```

2. **Split** (automated tool):
   ```bash
   i3pm rules split \
     --input window-rules.json \
     --generated window-rules-generated.json \
     --manual window-rules-manual.json
   ```

3. **Validate**:
   ```bash
   i3pm rules validate
   ```

4. **Rebuild**:
   ```bash
   nixos-rebuild switch --flake .#hetzner
   ```

---

## Testing Checklist

- [ ] Registry entry generates correct window rule
- [ ] Generated file updates on rebuild
- [ ] Manual file preserved across rebuilds
- [ ] Daemon loads both files
- [ ] File watcher detects changes to both files
- [ ] Priority system works (manual > generated)
- [ ] Invalid JSON shows error + retains old rules
- [ ] Desktop notification on reload error
- [ ] Rule matching works (first-match, highest priority)
- [ ] CLI shows rule source (generated vs manual)

---

## Files Modified/Created

### New Files
- `/etc/nixos/home-modules/tools/app-launcher/window-rules-generator.nix` - Generation module
- `~/.config/i3/window-rules-generated.json` - Auto-generated rules
- `~/.config/i3/window-rules-manual.json` - User overrides

### Modified Files
- `/etc/nixos/home-modules/desktop/i3-project-event-daemon/config.py` - Load both files
- `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py` - Watch both files
- `/etc/nixos/home-modules/tools/i3pm-deno/src/commands/rules.ts` - CLI enhancements

### Deprecated Files
- `~/.config/i3/window-rules.json` - Split into generated + manual

---

## Next Steps

1. Implement home-manager module (Phase 1) - **Priority: P1**
2. Enhance daemon to load both files (Phase 2) - **Priority: P2**
3. Add CLI commands for rule management (Phase 3) - **Priority: P3**
4. Create migration tool for existing configs (Phase 4) - **Priority: P3**

---

## Full Research Document

See [window-rules-generation-research.md](./window-rules-generation-research.md) for detailed analysis, code examples, and architectural decisions.
