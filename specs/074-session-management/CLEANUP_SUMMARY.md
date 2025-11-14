# Cleanup Summary: Remove All Backward Compatibility

**Status**: Ready for Implementation
**Philosophy**: Forward-Only Development (Constitution Principle XII)
**Breaking Change**: YES - Old layouts incompatible

---

## Executive Summary

**Current State**: Implementation has backward compatibility code (Optional fields, None defaults, fallbacks)

**Target State**: Pure forward-only implementation (required fields, strict validation, no fallbacks)

**Impact**: Old layouts from before Feature 074 will **NOT load** and must be re-saved

---

## Key Changes

### 1. **Make All Model Fields Required**

| Field | Current | New | Rationale |
|-------|---------|-----|-----------|
| `cwd` | `Optional[Path] = None` | `Path` (required) | Use `Path()` for non-terminals, never None |
| `focused` | `bool = False` | `bool` (required) | Always captured, exactly one per workspace |
| `app_registry_name` | `Optional[str] = None` | `str` (required) | From I3PM_APP_NAME, never None ("unknown" fallback) |
| `focused_workspace` | `Optional[int] = None` | `int` (required) | Always captured from Sway tree |

### 2. **Remove Backward Compatibility Code**

**Delete**:
- ❌ `if field is not None:` checks
- ❌ Fallback to `launch_command` when `app_registry_name` missing
- ❌ Default `focused_workspace = None` handling
- ❌ Pydantic Optional field handling
- ❌ T108 validation task

**Keep**:
- ✅ Mark-based correlation (Sway-compatible)
- ✅ AppLauncher service (wrapper-based launching)
- ✅ Strict field validation

### 3. **Add Migration Path**

**User Action Required**:
1. Delete old layouts: `rm ~/.local/share/i3pm/layouts/*/*.json`
2. Re-save layouts: `i3pm layout save <name>` for each project
3. Verify: `cat layout.json | jq 'recurse | select(. == null)'` returns empty

**Error Messages**:
```
Layout 'old-layout' is incompatible (missing fields: focused_workspace, cwd).
This layout was created before Feature 074.
Please re-save your layouts: i3pm layout save <name>
```

---

## Implementation Checklist

### **Phase 1: Specifications** ✅

- [ ] Update `spec.md`: Remove T108, add breaking change notice
- [ ] Update `data-model.md`: Make all fields required, remove Optional
- [ ] Update `tasks.md`: Remove T108 (backward compatibility task)
- [ ] Update `plan.md`: Update constitution check (no backward compat)
- [ ] Update `quickstart.md`: Add migration guide

### **Phase 2: Models** ✅

File: `layout/models.py`

- [ ] **WindowPlaceholder**: Remove `Optional[...]`, add required fields
  - [ ] `cwd: Path` (not Optional)
  - [ ] `focused: bool` (not Optional)
  - [ ] `app_registry_name: str` (not Optional)
  - [ ] `restoration_mark: str` (not Optional)
- [ ] **LayoutSnapshot**: Remove `Optional[int]`
  - [ ] `focused_workspace: int` (not Optional)
- [ ] Add validators:
  - [ ] `cwd` must be absolute or empty `Path()`
  - [ ] `app_registry_name` must not be empty string
- [ ] Remove `is None` checks in methods

### **Phase 3: Capture** ✅

File: `layout/capture.py`

- [ ] Always populate `cwd`:
  - [ ] Terminals: Read from `/proc/{pid}/cwd`
  - [ ] Non-terminals: Set to `Path()` (empty)
- [ ] Always populate `focused`:
  - [ ] Find focused window per workspace
  - [ ] Set exactly one `focused=True` per workspace
- [ ] Always populate `app_registry_name`:
  - [ ] Read from `I3PM_APP_NAME` env var
  - [ ] Fallback to `"unknown"` (never None)
- [ ] Always populate `focused_workspace`:
  - [ ] Read from Sway `get_tree()` focused workspace
  - [ ] Fallback to `1` (never None)

### **Phase 4: Restore** ✅

File: `layout/restore.py`

- [ ] Remove fallback logic:
  - [ ] Delete: `if app_registry_name: ... else: direct_launch`
  - [ ] Always use AppLauncher (no direct launch fallback)
- [ ] Remove None checks:
  - [ ] Delete: `if placeholder.cwd:`
  - [ ] Use: `if placeholder.cwd != Path():`
- [ ] Remove swallow mechanism:
  - [ ] Delete `_swallow_window()` method entirely
  - [ ] Remove conditional: `if is_sway: ... else: swallow`

### **Phase 5: Persistence** ✅

File: `layout/persistence.py`

- [ ] Add strict validation on load:
  - [ ] Check required top-level fields: `focused_workspace`
  - [ ] Check required window fields: `cwd`, `focused`, `app_registry_name`
  - [ ] Raise helpful error for missing fields
- [ ] Remove backward compatibility handling:
  - [ ] No "graceful degradation"
  - [ ] No default None values

### **Phase 6: Documentation** ✅

- [ ] `quickstart.md`: Add migration section
- [ ] `CLAUDE.md`: Update session management section
- [ ] `README.md`: Add breaking change notice (if exists)
- [ ] Add `MIGRATION.md` guide

### **Phase 7: Testing** ✅

- [ ] Test: Old layout rejection
  - [ ] Create fake old layout (missing fields)
  - [ ] Verify error message is helpful
- [ ] Test: New layout success
  - [ ] Save new layout
  - [ ] Verify all required fields present
  - [ ] Verify no None/null values
- [ ] Test: Terminal cwd
  - [ ] Verify terminals get real Path
  - [ ] Verify non-terminals get `Path()` (empty)
- [ ] Test: App registry name
  - [ ] Verify never None/empty
  - [ ] Verify "unknown" for manual launches

---

## Benefits of Cleanup

### **Simplified Code**

**Before** (with backward compatibility):
```python
if placeholder.app_registry_name:
    await self.app_launcher.launch_app(placeholder.app_registry_name)
else:
    # Fallback to direct launch (legacy)
    subprocess.Popen(placeholder.launch_command)
```

**After** (clean):
```python
await self.app_launcher.launch_app(placeholder.app_registry_name)
```

### **Clearer Error Messages**

**Before**:
```
Error: 'NoneType' object has no attribute 'is_absolute'
(user has no idea what's wrong)
```

**After**:
```
Layout 'old-layout' is incompatible (missing field: cwd).
This layout was created before Feature 074.
Please re-save your layouts: i3pm layout save <name>
```

### **Better Type Safety**

**Before**:
```python
cwd: Optional[Path] = None  # Could be None, Path, or missing
# Need None checks everywhere
```

**After**:
```python
cwd: Path  # Always Path (could be empty Path() but never None)
# No None checks needed
```

---

## Migration Instructions for Users

### **Automatic Migration Script** (Future Enhancement)

```bash
#!/usr/bin/env bash
# migrate-layouts.sh - Migrate old layouts to new format

set -e

echo "🔄 Migrating layouts to Feature 074 format..."

# Backup old layouts
backup_dir="$HOME/.local/share/i3pm/layouts.backup.$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
cp -r "$HOME/.local/share/i3pm/layouts" "$backup_dir/"
echo "✅ Backed up old layouts to: $backup_dir"

# For each project
for project_dir in "$HOME/.local/share/i3pm/layouts"/*; do
    project=$(basename "$project_dir")
    echo "📦 Processing project: $project"

    # Switch to project
    i3pm project switch "$project"

    # List non-auto layouts
    for layout_file in "$project_dir"/*.json; do
        layout_name=$(basename "$layout_file" .json)

        # Skip auto-saves (will be regenerated)
        [[ "$layout_name" == auto-* ]] && continue

        echo "  💾 Re-saving: $layout_name"

        # Load old layout (best effort - may fail)
        if i3pm layout restore "$layout_name" 2>/dev/null; then
            # Save with new format
            i3pm layout save "${layout_name}-migrated"
            echo "  ✅ Migrated to: ${layout_name}-migrated"
        else
            echo "  ⚠️  Could not restore $layout_name (incompatible)"
        fi
    done
done

echo "🎉 Migration complete!"
echo "Old layouts backed up to: $backup_dir"
echo "New layouts saved with '-migrated' suffix"
```

### **Manual Migration**

```bash
# 1. List your projects
i3pm project list

# 2. For each project, re-save layouts
i3pm project switch nixos
# Arrange windows as desired
i3pm layout save main

# 3. Repeat for all projects
i3pm project switch dotfiles
i3pm layout save main

# 4. Clean up old layouts
rm ~/.local/share/i3pm/layouts/*/old-*.json
```

---

## Rollback Plan

If cleanup causes issues:

1. **Revert commits**:
   ```bash
   git log --oneline | grep "cleanup\|backward"
   git revert <commit-hash>
   ```

2. **Restore old layouts**:
   ```bash
   cp -r ~/.local/share/i3pm/layouts.backup.*/* ~/.local/share/i3pm/layouts/
   ```

3. **Rebuild daemon**:
   ```bash
   sudo nixos-rebuild switch --flake .#m1 --impure
   systemctl --user restart i3-project-event-listener
   ```

---

## Timeline

**Estimated Effort**: 2-3 hours

1. **Specifications** (30 min) - Update all docs
2. **Models** (15 min) - Remove Optional fields
3. **Capture** (30 min) - Always populate fields
4. **Restore** (20 min) - Remove fallbacks
5. **Persistence** (20 min) - Add strict validation
6. **Documentation** (30 min) - Migration guide
7. **Testing** (30 min) - Verify old rejected, new works

---

## Success Metrics

After cleanup:

✅ **Zero Optional fields** in models
✅ **Zero None defaults** in models
✅ **Zero "if field is not None" checks** in code
✅ **Zero mentions of "backward compatible"** in docs
✅ **100% field population** in new layouts
✅ **Clear error messages** for old layouts
✅ **Migration guide** in documentation

---

## Questions & Answers

**Q**: Why not support old layouts?
**A**: Constitution Principle XII: "Forward-Only Development & Legacy Elimination". Maintaining dual code paths increases complexity and bugs. Clean break is better.

**Q**: Will users lose their layouts?
**A**: Yes, but migration is simple: re-save each layout. Old layouts are backed up. Clear error messages guide users.

**Q**: What if a field genuinely can't be populated?
**A**: Use sentinel values:
- `cwd`: Use `Path()` (empty) for non-terminals
- `app_registry_name`: Use `"unknown"` for manual launches
- `focused_workspace`: Use `1` as fallback
- Never use `None` or `Optional`

**Q**: What about performance (empty Path() overhead)?
**A**: Negligible. Empty `Path()` is ~50 bytes. For 100 windows, that's 5KB total.

---

## Approval Required

This is a **BREAKING CHANGE** that requires:

1. ✅ User acknowledgment of data migration
2. ✅ Clear migration path documented
3. ✅ Rollback plan available
4. ✅ Testing plan defined

**Recommended**: Proceed with cleanup after user approval.
