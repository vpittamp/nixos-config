# Window Rules Auto-Generation - Quickstart

**Feature**: 034-create-a-feature | **Updated**: 2025-10-24

## 5-Minute Overview

### What This Does

Automatically generates window placement rules from your application registry, eliminating manual window-rules.json editing.

### How It Works

```
application-registry.json
    ↓ (build-time transformation)
window-rules-generated.json ──┐
                              ├─→ Daemon loads both → Sorts by priority → First match wins
window-rules-manual.json ─────┘
```

**Key Insight**: Split rules into generated (automatic) and manual (your overrides)

---

## Current vs New System

### Current System (Single File)

```
~/.config/i3/window-rules.json (65 rules)
  ├─ Registry-based rules (auto-generated?)
  └─ Custom rules (manual edits)

Problem: Updates overwrite manual edits
```

### New System (Split Files)

```
~/.config/i3/
  ├─ window-rules-generated.json  (from registry, always fresh)
  ├─ window-rules-manual.json     (your overrides, preserved)
  └─ application-registry.json    (source of truth)
```

**Benefit**: Registry updates propagate automatically, your customizations preserved

---

## Quick Reference

### Add Application → Auto-Generate Rule

**1. Edit registry**:
```bash
vi ~/.config/i3/application-registry.json
```

**2. Add entry**:
```json
{
  "name": "slack",
  "display_name": "Slack",
  "command": "slack",
  "expected_pattern_type": "class",
  "expected_class": "Slack",
  "scope": "global",
  "preferred_workspace": 6
}
```

**3. Rebuild**:
```bash
nixos-rebuild switch --flake .#hetzner
```

**4. Verify**:
```bash
cat ~/.config/i3/window-rules-generated.json | jq '.[] | select(.pattern_rule.pattern == "Slack")'
```

**Output** (auto-generated):
```json
{
  "pattern_rule": {
    "pattern": "Slack",
    "scope": "global",
    "priority": 180,
    "description": "Slack - Workspace 6"
  },
  "workspace": 6
}
```

**No daemon restart needed** - file watcher auto-reloads in <100ms

---

## Override Generated Rule

**Scenario**: Want VS Code on workspace 3 instead of registry-defined workspace 1

**1. Edit manual rules**:
```bash
vi ~/.config/i3/window-rules-manual.json
```

**2. Add override with higher priority**:
```json
[
  {
    "pattern_rule": {
      "pattern": "Code",
      "scope": "scoped",
      "priority": 250,
      "description": "VS Code override - WS3 instead of WS1"
    },
    "workspace": 3
  }
]
```

**3. Save** - daemon auto-reloads (no rebuild)

**Result**:
- Generated rule (priority 240): Code → WS1 [SHADOWED]
- Manual rule (priority 250): Code → WS3 [ACTIVE]

---

## Priority Cheat Sheet

| Priority | Source | Example |
|----------|--------|---------|
| **250+** | Manual overrides | Your custom rules |
| **240** | Scoped apps | VS Code, terminals |
| **200** | PWA apps | YouTube, ChatGPT |
| **180** | Global apps | Firefox, Slack |

**Rule**: Higher priority wins (first-match evaluation)

---

## Common Patterns

### Pattern Type Mapping

| Registry `expected_pattern_type` | Uses Field | Example |
|----------------------------------|------------|---------|
| `"class"` | `expected_class` | `"Code"` |
| `"title"` | `expected_title_contains` | `"lazygit"` |
| `"pwa"` | `expected_class` | `"FFPWA-01K..."` |

### Workspace Assignment

**Direct mapping**:
```json
"preferred_workspace": 5  →  "workspace": 5
```

**Validation**: Must be 1-9 (enforced at build time)

---

## File Structure

```
~/.config/i3/
├── application-registry.json         (source of truth)
├── window-rules-generated.json       (build-time generated, force=true)
├── window-rules-manual.json          (user edits, force=false)
├── window-rules.json.backup          (migration backup)
└── app-classes.json                  (separate concern)
```

---

## CLI Commands (Future)

### List Rules
```bash
i3pm rules list

# Output:
# Window Rules (18 total):
# - 15 generated (from registry)
# - 3 manual (user overrides)
#
# [250] Manual     Code → WS3 (scoped)
# [240] Generated  Ghostty → WS1 (scoped)
# [240] Generated  Code → WS1 (scoped) [SHADOWED]
# [200] Generated  FFPWA-* → WS2 (global)
# [180] Generated  Firefox → WS3 (global)
```

### Validate Rules
```bash
i3pm rules validate

# Checks:
# ✓ No syntax errors
# ✓ All priorities valid
# ⚠ Warning: Manual rule "Code" shadows generated rule
# ✓ Coverage: 15/20 registry apps have rules
```

### Edit Manual Rules
```bash
i3pm rules edit manual
# Opens ~/.config/i3/window-rules-manual.json in $EDITOR
```

### Sync from Registry
```bash
i3pm rules sync
# Force regeneration from registry (triggers rebuild)
```

---

## Troubleshooting

### Rule Not Applied

**Check 1**: Verify rule exists
```bash
cat ~/.config/i3/window-rules-generated.json | jq '.[] | select(.pattern_rule.pattern == "YourApp")'
```

**Check 2**: Check daemon loaded it
```bash
i3pm daemon status
# Shows rule count: "Loaded 15 generated + 3 manual = 18 total rules"
```

**Check 3**: Check priority order
```bash
i3pm rules list | grep YourApp
# See if shadowed by higher priority rule
```

### File Watcher Not Working

**Check daemon logs**:
```bash
journalctl --user -u i3-project-event-listener -f | grep "Reloaded"
```

**Expected**: Within 100ms of file save, see "Reloaded N window rule(s)"

**If not working**:
```bash
systemctl --user restart i3-project-event-listener
```

### Invalid JSON Error

**Symptom**: Desktop notification "Failed to reload window-rules.json"

**Check**:
```bash
python3 -m json.tool ~/.config/i3/window-rules-manual.json
# Shows syntax error location
```

**Daemon behavior**: Retains previous valid rules (graceful degradation)

---

## Migration Example

### Before (Single File)

```json
// ~/.config/i3/window-rules.json
[
  { "pattern_rule": { "pattern": "Code", ... }, "workspace": 1 },  // From registry
  { "pattern_rule": { "pattern": "Code", ... }, "workspace": 3 },  // My override
  { "pattern_rule": { "pattern": "Slack", ... }, "workspace": 6 }  // From registry
]
```

**Problem**: Rebuild overwrites my Code override

### After (Split Files)

**Generated** (auto-updated):
```json
// ~/.config/i3/window-rules-generated.json
[
  { "pattern_rule": { "pattern": "Code", ... }, "workspace": 1 },  // From registry
  { "pattern_rule": { "pattern": "Slack", ... }, "workspace": 6 }  // From registry
]
```

**Manual** (preserved):
```json
// ~/.config/i3/window-rules-manual.json
[
  { "pattern_rule": { "pattern": "Code", "priority": 250 }, "workspace": 3 }  // My override
]
```

**Result**: Manual rule (priority 250) wins over generated (priority 240)

---

## Implementation Status

### Phase 1: Home-Manager Module
- [ ] Create window-rules-generator.nix
- [ ] Transform registry to rules
- [ ] Generate window-rules-generated.json
- [ ] Create empty window-rules-manual.json

### Phase 2: Daemon Enhancement
- [ ] Add load_all_window_rules()
- [ ] Watch both files
- [ ] Log rule source counts

### Phase 3: CLI Integration
- [ ] i3pm rules list
- [ ] i3pm rules validate
- [ ] i3pm rules edit manual
- [ ] i3pm rules sync

### Phase 4: Migration Tool
- [ ] i3pm rules split
- [ ] Detect registry vs manual rules
- [ ] Backup original config

---

## Key Benefits Recap

✅ **Automatic Updates**: Registry changes → Rules update on rebuild
✅ **Preserved Customizations**: Manual overrides never overwritten
✅ **Clear Ownership**: Generated (system) vs Manual (user)
✅ **Fast Reload**: <100ms via file watcher
✅ **Error Resilience**: Invalid JSON → Keeps old rules + notification
✅ **Priority Control**: Manual rules always win (higher priority)

---

## Next Steps

1. Review [window-rules-generation-research.md](./window-rules-generation-research.md) for full analysis
2. Implement home-manager module (Phase 1)
3. Test with 5 applications
4. Roll out to full registry (70+ apps)

---

**Questions?** See full research doc or check `/etc/nixos/CLAUDE.md` section on window rules.
