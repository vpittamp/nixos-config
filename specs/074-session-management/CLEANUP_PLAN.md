# Cleanup Plan: Remove Backward Compatibility & Legacy Code

**Created**: 2025-01-14
**Purpose**: Remove all backward compatibility code and enforce optimal-only approach for Feature 074

## Philosophy: Forward-Only Development (Constitution Principle XII)

> "Mark-based correlation REPLACES broken swallow mechanism (no dual support)"
> "No backward compatibility for old layout format - Pydantic handles graceful defaults"

**Decision**: Remove ALL legacy code paths. Old layouts are incompatible and will not load.

---

## Changes to Specifications

### 1. **spec.md** - Remove Backward Compatibility References

**Remove**:
- ❌ User Story test T108: "Validate backward compatibility"
- ❌ Any mention of "existing layouts" loading
- ❌ References to "optional fields" being backward compatible

**Add**:
- ✅ Breaking change notice: "Layouts from before Feature 074 are incompatible"
- ✅ Migration guide: "Re-save all layouts after upgrade"

### 2. **data-model.md** - Make All Fields Required

**Current Problems**:
```python
# REMOVE: Optional fields with None defaults
cwd: Optional[Path] = None
focused: bool = False
app_registry_name: Optional[str] = None
focused_workspace: Optional[int] = None
```

**New Approach**:
```python
# ENFORCE: All fields required (no Optional, no None defaults)
cwd: Path  # Required for terminals, empty Path() for non-terminals
focused: bool  # Required, always set during capture
app_registry_name: str  # Required, from I3PM_APP_NAME env var
focused_workspace: int  # Required, always captured from Sway tree
```

### 3. **tasks.md** - Remove Backward Compatibility Task

**Remove**:
- ❌ T108: Validate backward compatibility

**Update Phase 2 Description**:
- Change "optional fields with None default" to "required fields"
- Remove "Pydantic handles missing fields gracefully"

### 4. **plan.md** - Update Constitution Check

**Remove**:
- ❌ "No backward compatibility for old layout format - Pydantic handles graceful defaults"

**Add**:
- ✅ "No backward compatibility - old layouts incompatible (breaking change)"
- ✅ "Migration required: re-save all layouts"

---

## Code Changes Required

### Phase 1: Models - Make Fields Required

#### **File**: `layout/models.py` (WindowPlaceholder)

**Remove Optional Fields**:
```python
# BEFORE (backward compatible):
cwd: Optional[Path] = None
focused: bool = False
restoration_mark: Optional[str] = None
app_registry_name: Optional[str] = None

# AFTER (required fields):
cwd: Path  # Always set: actual path OR Path() for non-terminals
focused: bool  # Always set during capture (one per workspace)
restoration_mark: str  # Always generated during restoration
app_registry_name: str  # Always from I3PM_APP_NAME (or "unknown")
```

**Validator Changes**:
```python
@field_validator('cwd')
@classmethod
def validate_cwd_absolute(cls, v: Path) -> Path:
    """Ensure cwd is absolute path."""
    if not v.is_absolute() and v != Path():
        raise ValueError(f"Working directory must be absolute: {v}")
    return v

@field_validator('app_registry_name')
@classmethod
def validate_app_name_not_empty(cls, v: str) -> str:
    """Ensure app name is not empty."""
    if not v or not v.strip():
        raise ValueError("app_registry_name cannot be empty")
    return v
```

#### **File**: `layout/models.py` (LayoutSnapshot)

**Remove Optional Field**:
```python
# BEFORE:
focused_workspace: Optional[int] = Field(default=None, ge=1, le=70)

# AFTER:
focused_workspace: int = Field(..., ge=1, le=70)
```

**Remove Validator**:
```python
# REMOVE: validator allowing None
@model_validator(mode='after')
def validate_focused_workspace_exists(self) -> 'LayoutSnapshot':
    if self.focused_workspace is not None:  # ❌ REMOVE this check
        # ... validation
```

---

### Phase 2: Capture - Always Populate Required Fields

#### **File**: `layout/capture.py`

**Changes**:

1. **Always set cwd** (even for non-terminals):
```python
# BEFORE:
if is_terminal:
    cwd = await terminal_cwd_tracker.get_terminal_cwd(pid)
    placeholder.cwd = cwd if cwd else None  # ❌ WRONG

# AFTER:
if is_terminal:
    cwd = await terminal_cwd_tracker.get_terminal_cwd(pid)
    placeholder.cwd = cwd if cwd else Path()  # ✅ Empty Path for non-terminals
else:
    placeholder.cwd = Path()  # ✅ Always set
```

2. **Always set focused** (no default False):
```python
# BEFORE:
focused = window_id == focused_window_id if focused_window_id else False

# AFTER:
focused = (window_id == focused_window_id)  # Always boolean, never None
```

3. **Always set app_registry_name**:
```python
# BEFORE:
app_name = env_vars.get("I3PM_APP_NAME")
placeholder.app_registry_name = app_name if app_name else None  # ❌ WRONG

# AFTER:
app_name = env_vars.get("I3PM_APP_NAME", "unknown")
placeholder.app_registry_name = app_name or "unknown"  # ✅ Never None
```

4. **Always set focused_workspace**:
```python
# BEFORE:
focused_workspace = self._get_focused_workspace(tree)
snapshot.focused_workspace = focused_workspace  # Could be None

# AFTER:
focused_workspace = self._get_focused_workspace(tree) or 1  # Default to 1
snapshot.focused_workspace = focused_workspace  # Always int
```

---

### Phase 3: Restore - Remove Fallback Logic

#### **File**: `layout/restore.py`

**Remove None Checks**:
```python
# BEFORE:
if placeholder.app_registry_name:
    # Use AppLauncher
else:
    # Fallback to direct launch  # ❌ REMOVE fallback

# AFTER:
# Always use AppLauncher (no fallback)
await self.app_launcher.launch_app(
    app_name=placeholder.app_registry_name,
    cwd=placeholder.cwd if placeholder.cwd != Path() else None,
    # ...
)
```

**Remove Optional Handling**:
```python
# BEFORE:
cwd = placeholder.cwd if placeholder.cwd else None  # ❌ REMOVE

# AFTER:
cwd = placeholder.cwd if placeholder.cwd != Path() else None  # ✅ Check empty
```

---

### Phase 4: Persistence - Reject Old Layouts

#### **File**: `layout/persistence.py`

**Add Validation on Load**:
```python
def load_layout(self, name: str, project: str = "global") -> LayoutSnapshot:
    """Load layout snapshot (strict validation - no backward compat)"""

    # Load JSON
    with open(filepath, 'r') as f:
        data = json.load(f)

    # ENFORCE: Check for required fields
    required_fields = ['focused_workspace']
    missing = [f for f in required_fields if f not in data]
    if missing:
        raise ValueError(
            f"Layout {name} is incompatible (missing fields: {missing}). "
            "This layout was created before Feature 074. "
            "Please re-save your layouts."
        )

    # ENFORCE: Check WindowPlaceholder fields
    for ws in data.get('workspace_layouts', []):
        for window in ws.get('windows', []):
            required_window_fields = ['cwd', 'focused', 'app_registry_name']
            missing = [f for f in required_window_fields if f not in window]
            if missing:
                raise ValueError(
                    f"Layout {name} has incompatible windows (missing: {missing}). "
                    "Please re-save this layout."
                )

    # Deserialize with Pydantic (will enforce types)
    try:
        snapshot = LayoutSnapshot.model_validate(data)
    except ValidationError as e:
        raise ValueError(f"Layout {name} validation failed: {e}")

    return snapshot
```

---

### Phase 5: Remove Swallow Mechanism

#### **File**: `layout/restore.py`

**Remove swallow_window Method**:
```python
# REMOVE ENTIRELY:
def _swallow_window(self, ...):
    """Swallow mechanism for i3 (DEPRECATED - Sway incompatible)"""
    # ❌ DELETE THIS ENTIRE METHOD
```

**Remove Conditional Logic**:
```python
# REMOVE:
if is_sway:
    # Use mark-based correlation
else:
    # Use swallow  # ❌ DELETE

# ALWAYS use mark-based correlation (Sway and i3)
```

---

### Phase 6: Update Documentation

#### **File**: `quickstart.md`

**Add Breaking Change Notice**:
```markdown
## ⚠️ Breaking Change Notice

Feature 074 introduces a new layout format. **Old layouts are incompatible**.

### Migration Required

1. List your old layouts:
   ```bash
   ls ~/.local/share/i3pm/layouts/*/
   ```

2. For each project, re-save layouts:
   ```bash
   i3pm project switch my-project
   # Arrange windows as desired
   i3pm layout save my-layout-name
   ```

3. Delete old layouts:
   ```bash
   rm ~/.local/share/i3pm/layouts/*/old-layout-name.json
   ```

### What Changed

New required fields:
- `focused_workspace`: Which workspace was focused (always captured)
- `cwd`: Working directory for ALL windows (empty for non-terminals)
- `focused`: Which window was focused per workspace
- `app_registry_name`: App name from wrapper system (never "unknown")

Old layouts lacking these fields will fail to load with a clear error message.
```

#### **File**: `CLAUDE.md` (Project root)

**Update Session Management Section**:
```markdown
## 🔄 Session Management (Feature 074)

**Breaking Change**: Old layouts incompatible. Re-save all layouts after upgrade.

### Quick Commands
```bash
i3pm layout save my-layout        # Save current layout
i3pm layout restore my-layout     # Restore saved layout
i3pm layout list                  # List layouts (auto-saves hidden by default)
i3pm layout delete old-layout     # Delete incompatible old layout
```

### Migration
```bash
# 1. Switch to each project and re-save layouts
pswitch nixos && i3pm layout save main
pswitch dotfiles && i3pm layout save main

# 2. Clean up old incompatible layouts
find ~/.local/share/i3pm/layouts -name "*.json" -mtime +7 -delete
```
```

---

## Validation After Cleanup

### Test Cases

1. **Old Layout Rejection**:
   ```bash
   # Create fake old layout (missing fields)
   echo '{"name":"old","project":"test","workspace_layouts":[]}' > \
     ~/.local/share/i3pm/layouts/test/old.json

   # Try to restore - should fail with clear error
   i3pm layout restore old
   # Expected: "Layout old is incompatible (missing fields: focused_workspace)"
   ```

2. **New Layout Success**:
   ```bash
   # Save new layout
   i3pm layout save new-layout

   # Verify all required fields present
   cat ~/.local/share/i3pm/layouts/*/new-layout.json | jq .
   # Should have: focused_workspace, cwd for all windows, focused, app_registry_name
   ```

3. **No None Values**:
   ```bash
   # Check no None/null values in saved layouts
   cat ~/.local/share/i3pm/layouts/*/new-layout.json | jq 'recurse | select(. == null)'
   # Should return EMPTY (no nulls)
   ```

---

## Implementation Order

1. ✅ **Update Specifications** (spec.md, data-model.md, tasks.md, plan.md)
2. ✅ **Update Models** (make fields required, remove Optional)
3. ✅ **Update Capture** (always populate all fields, no None)
4. ✅ **Update Restore** (remove fallbacks, enforce required fields)
5. ✅ **Update Persistence** (reject old layouts on load)
6. ✅ **Remove Swallow** (delete _swallow_window method entirely)
7. ✅ **Update Documentation** (breaking change notices, migration guide)
8. ✅ **Test** (verify old layouts rejected, new layouts work)

---

## Risk Assessment

**Risk**: Users lose access to old layouts
**Mitigation**: Clear error messages with migration instructions

**Risk**: Terminal cwd empty for non-terminals wastes space
**Mitigation**: Use `Path()` (empty) instead of None - minimal overhead

**Risk**: app_registry_name="unknown" pollutes data
**Mitigation**: Wrapper system ensures this rarely happens (only manual launches)

---

## Success Criteria

✅ No `Optional[...]` fields in models
✅ No `None` default values
✅ No `if field is not None:` checks in code
✅ No backward compatibility mentions in docs
✅ Old layouts rejected with helpful error message
✅ All new layouts have 100% required fields populated
✅ T108 removed from tasks.md
✅ Swallow mechanism completely deleted

---

## Next Steps

Run: `/speckit.specify` with this cleanup plan to update spec.md
Run: `/speckit.plan` to regenerate plan.md
Run: `/speckit.tasks` to regenerate tasks.md with cleanup tasks
