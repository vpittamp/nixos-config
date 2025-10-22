# Layout Save/Restore Analysis: i3pm vs i3-resurrect

**Created**: 2025-10-22
**Purpose**: Compare current i3pm layout capabilities with i3-resurrect to identify gaps and integration opportunities

---

## Executive Summary

**Current State**:
- ✅ i3pm has functional layout save/restore with app relaunching
- ✅ More sophisticated than i3-resurrect (app discovery, launch commands, environment capture)
- ⚠️ Missing some i3-resurrect features (swallow criteria flexibility, xdotool window manipulation)
- ⚠️ Not integrated with window state visualization (opportunity!)

**Recommendation**:
1. **Keep i3pm's architecture** - It's more advanced
2. **Adopt specific i3-resurrect patterns** - Swallow criteria, window unmapping during restore
3. **Integrate with window state visualization** - Make layouts visual and interactive
4. **Add i3-resurrect compatibility mode** - Import/export i3-resurrect layouts

---

## Feature Comparison Matrix

| Feature | i3-resurrect | i3pm | Winner | Notes |
|---------|--------------|------|--------|-------|
| **Core Functionality** |
| Save workspace layout | ✅ | ✅ | Tie | Both use i3's native append_layout |
| Restore workspace layout | ✅ | ✅ | Tie | Both restore with placeholders |
| Launch programs | ✅ Basic | ✅ Advanced | i3pm | i3pm has app discovery + env capture |
| Multiple profiles | ✅ | ✅ | Tie | Both support named profiles |
| **Window Matching** |
| Swallow criteria (class) | ✅ | ✅ | Tie | Both support class matching |
| Swallow criteria (instance) | ✅ | ✅ | Tie | Both support instance matching |
| Swallow criteria (title) | ✅ | ❌ | i3-resurrect | i3pm lacks title-based swallow |
| Swallow criteria (window_role) | ✅ | ❌ | i3-resurrect | i3pm lacks role-based swallow |
| Configurable criteria | ✅ Flexible | ⚠️ Fixed | i3-resurrect | i3pm uses fixed class+instance |
| **Launch Detection** |
| Command mapping | ✅ Manual | ✅ Auto | i3pm | i3pm discovers launch commands |
| Environment capture | ❌ | ✅ | i3pm | i3pm captures CWD, env vars |
| Terminal detection | ✅ Config list | ✅ Auto | i3pm | i3pm auto-detects terminals |
| PWA detection | ❌ | ✅ | i3pm | i3pm handles Firefox PWAs |
| Process tree analysis | ❌ | ✅ | i3pm | i3pm uses psutil for accuracy |
| **Restoration** |
| Placeholder window creation | ✅ | ✅ | Tie | Both use append_layout |
| Window unmapping during restore | ✅ | ❌ | i3-resurrect | Prevents window flicker |
| Placeholder cleanup | ✅ | ⚠️ Implicit | i3-resurrect | Explicit xdotool kill |
| Output/monitor assignment | ✅ | ✅ | Tie | Both restore to original monitor |
| Workspace layout mode | ✅ | ⚠️ Not explicit | i3-resurrect | Sets layout mode separately |
| **Project Integration** |
| Project-scoped layouts | ❌ | ✅ | i3pm | Core i3pm feature |
| Auto-launch lists | ❌ | ✅ | i3pm | i3pm's Restore All feature |
| Classification integration | ❌ | ✅ | i3pm | Uses scoped/global classes |
| **User Interface** |
| CLI commands | ✅ | ✅ | Tie | Both have CLI |
| TUI | ❌ | ✅ | i3pm | i3pm has layout manager TUI |
| Layout list view | ❌ | ✅ | i3pm | i3pm shows metadata table |
| Visual preview | ❌ | ❌ | Neither | Opportunity! |
| **Portability** |
| i3-compatible JSON | ✅ Pure | ⚠️ Extended | i3-resurrect | i3pm adds metadata |
| Import/export | ✅ | ⚠️ Partial | i3-resurrect | Could add compatibility |
| **Reliability** |
| Error handling | ⚠️ Basic | ✅ Comprehensive | i3pm | i3pm has detailed error tracking |
| Window loss prevention | ✅ try/finally | ✅ Error recovery | Tie | Both safe |
| Dry-run mode | ❌ | ✅ | i3pm | i3pm can preview actions |

---

## Key Insights

### What i3pm Does Better

1. **App Discovery & Launch Intelligence**
   - i3-resurrect: Requires manual command mapping config
   - i3pm: Automatically discovers launch commands from running processes
   - i3pm: Captures working directory and environment variables
   - i3pm: Handles complex cases (PWAs, terminals, nested processes)

2. **Project Integration**
   - i3pm layouts are project-scoped
   - "Restore All" feature for complete project setup
   - Integration with classification system
   - Metadata tracking (saved_at, window counts, etc.)

3. **User Experience**
   - Rich TUI with table view of saved layouts
   - Detailed error messages and recovery
   - Dry-run mode to preview changes
   - Better async/await patterns (vs i3-resurrect's sync i3ipc)

### What i3-resurrect Does Better

1. **Flexible Swallow Criteria**
   ```python
   # i3-resurrect allows configurable criteria:
   --swallow "class,instance,title,window_role"

   # i3pm is fixed to class+instance
   ```
   - Some apps need title matching (e.g., terminal tabs with different titles)
   - Some apps need window_role (e.g., browser toolbars vs content)

2. **Window Unmapping During Restore**
   ```python
   # i3-resurrect hides existing windows during restore:
   for window_id in window_ids:
       xdo_unmap_window(window_id)  # Hide

   # ... restore layout ...

   for window_id in window_ids:
       xdo_map_window(window_id)  # Show
   ```
   - Prevents visual flicker as windows reorganize
   - Cleaner user experience
   - i3pm doesn't do this (windows jump around during restore)

3. **Explicit Workspace Layout Mode**
   ```python
   # i3-resurrect explicitly sets workspace layout:
   workspace_node.command(f"layout {ws_layout_mode}")
   ```
   - i3pm doesn't preserve the workspace-level layout (splith/splitv/tabbed/stacked)
   - Can cause layout mode mismatch after restore

4. **Pure i3 JSON Compatibility**
   - i3-resurrect layouts are pure i3 JSON
   - Can be imported/exported with standard i3 tools
   - i3pm adds custom metadata (not compatible with vanilla i3)

---

## Recommended Enhancements to i3pm

### Priority 1: Adopt i3-resurrect Window Handling

**Add window unmapping during restore**:

```python
# In LayoutManager.restore_layout():

async def restore_layout(self, request: LayoutRestoreRequest) -> LayoutRestoreResponse:
    """Restore a saved layout with window unmapping."""
    existing_windows = await self._get_workspace_windows(workspace)

    # NEW: Unmap existing windows (prevents flicker)
    unmapped_window_ids = []
    for window in existing_windows:
        if not self._is_placeholder(window):
            await self._unmap_window(window.window_id)
            unmapped_window_ids.append(window.window_id)

    try:
        # ... existing restore logic ...
        # Create placeholders via append_layout
        # Launch missing applications
        # Wait for windows to appear
    finally:
        # NEW: Always remap windows (even on error)
        for window_id in unmapped_window_ids:
            await self._map_window(window_id)

async def _unmap_window(self, window_id: int) -> None:
    """Hide window using xdotool."""
    await asyncio.create_subprocess_exec(
        "xdotool", "windowunmap", str(window_id),
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL
    )

async def _map_window(self, window_id: int) -> None:
    """Show window using xdotool."""
    await asyncio.create_subprocess_exec(
        "xdotool", "windowmap", str(window_id),
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL
    )
```

**Benefits**:
- ✅ No visual flicker during restore
- ✅ Cleaner user experience
- ✅ Safer (finally ensures windows always remapped)

---

### Priority 2: Flexible Swallow Criteria

**Add configurable swallow criteria to LayoutWindow**:

```python
@dataclass
class LayoutWindow:
    # Existing fields...
    window_class: str
    window_instance: str
    window_title: str

    # NEW: Configurable swallow criteria
    swallow_criteria: List[str] = field(default_factory=lambda: ["class", "instance"])
    # Options: "class", "instance", "title", "window_role"

    def to_swallow_dict(self) -> Dict[str, str]:
        """Generate swallow dict based on configured criteria."""
        swallow = {}

        if "class" in self.swallow_criteria and self.window_class:
            swallow["class"] = f"^{re.escape(self.window_class)}$"

        if "instance" in self.swallow_criteria and self.window_instance:
            swallow["instance"] = f"^{re.escape(self.window_instance)}$"

        if "title" in self.swallow_criteria and self.window_title:
            swallow["title"] = f"^{re.escape(self.window_title)}$"

        if "window_role" in self.swallow_criteria and self.window_role:
            swallow["window_role"] = f"^{re.escape(self.window_role)}$"

        return swallow
```

**Configuration**:
```json
{
  "default_swallow_criteria": ["class", "instance"],
  "swallow_overrides": {
    "Ghostty": ["class", "instance", "title"],  // Match terminal tabs by title
    "firefox": ["class", "window_role"]         // Match browser windows by role
  }
}
```

**Benefits**:
- ✅ Handles edge cases (terminal tabs, browser windows)
- ✅ User can customize per-application
- ✅ Falls back to safe default (class+instance)

---

### Priority 3: Workspace Layout Mode Preservation

**Save and restore workspace-level layout**:

```python
@dataclass
class WorkspaceLayout:
    workspace_name: str
    workspace_num: int
    output: str
    windows: List[LayoutWindow]

    # NEW: Preserve workspace layout mode
    workspace_layout: str = "default"  # "default", "splith", "splitv", "tabbed", "stacked"

async def save_layout(self, request: LayoutSaveRequest) -> LayoutSaveResponse:
    """Save layout including workspace mode."""
    workspace_node = await self._get_workspace_node(workspace_name)

    layout = WorkspaceLayout(
        workspace_name=workspace_node.name,
        workspace_num=workspace_node.num,
        output=workspace_node.ipc_data.get("output"),
        workspace_layout=workspace_node.layout,  # NEW: Capture layout mode
        windows=[...]
    )

async def restore_layout(self, request: LayoutRestoreRequest) -> LayoutRestoreResponse:
    """Restore layout including workspace mode."""
    workspace_node = await self._get_workspace_node(layout.workspace_name)

    # NEW: Set workspace layout mode BEFORE appending layout
    await self.i3.command(f'[con_id={workspace_node.id}] layout {layout.workspace_layout}')

    # Then append_layout as usual...
```

**Benefits**:
- ✅ Preserves tabbed/stacked workspace layouts
- ✅ More accurate restore
- ✅ Minimal code change

---

### Priority 4: i3-resurrect Compatibility Mode

**Add import/export for i3-resurrect layouts**:

```python
class LayoutManager:
    async def import_i3_resurrect_layout(
        self,
        profile_path: Path,
        project_name: str
    ) -> LayoutSaveResponse:
        """Import i3-resurrect layout file into i3pm format.

        Args:
            profile_path: Path to i3-resurrect layout JSON
            project_name: Target project for import

        Returns:
            LayoutSaveResponse with conversion details
        """
        # Read i3-resurrect layout
        resurrect_layout = json.loads(profile_path.read_text())

        # Convert to i3pm format
        i3pm_layout = WorkspaceLayout(
            workspace_name=resurrect_layout.get("name", "1"),
            workspace_num=resurrect_layout.get("num", 1),
            output=resurrect_layout.get("output", "primary"),
            workspace_layout=resurrect_layout.get("layout", "default"),
            windows=self._extract_windows_from_tree(resurrect_layout)
        )

        # Save as i3pm layout
        return await self.save_layout_object(project_name, "imported", i3pm_layout)

    async def export_to_i3_resurrect(
        self,
        project_name: str,
        layout_name: str,
        output_path: Path
    ) -> LayoutExportResponse:
        """Export i3pm layout to i3-resurrect format.

        Strips i3pm-specific metadata to create vanilla i3 JSON.
        """
        layout = await self.load_layout(project_name, layout_name)

        # Convert to pure i3 JSON (strip i3pm extensions)
        resurrect_layout = self._to_i3_resurrect_format(layout)

        # Write to file
        output_path.write_text(json.dumps(resurrect_layout, indent=2))

        return LayoutExportResponse(
            success=True,
            export_path=output_path,
            file_size=output_path.stat().st_size
        )
```

**Benefits**:
- ✅ Users can migrate from i3-resurrect
- ✅ Interoperability with vanilla i3 tools
- ✅ Backup/portability

---

## Integration with Window State Visualization

### Opportunity: Visual Layout Editor

**Current**: Layouts are JSON files, no visual representation

**Proposed**: Integrate layout management with window state tree view

```
i3pm windows --tree

📺 Output: rdp0 (1920x1080) [Project: nixos]
├─ 📋 Workspace 1: Terminal
│  ├─ 🪟 Ghostty [scoped]
│  └─ 🪟 Ghostty [scoped]
├─ 📋 Workspace 2: Code ⭐ current
│  └─ 🪟 Code [scoped] ← focused
└─ 📋 Workspace 3: Browser
   └─ 🪟 Firefox [global]

Actions:
[s] Save current state as layout
[r] Restore layout
[v] Visual diff with saved layout "default"
[e] Edit layout (launch commands, swallow criteria)
```

**Features**:

1. **Visual Diff Mode**
   ```
   Current State          Saved Layout "default"
   ────────────────       ────────────────────
   WS1: 2 windows    ───  WS1: 3 windows ⚠️ MISSING 1
   WS2: 1 window     ───  WS2: 2 windows ⚠️ MISSING 1
   WS3: 1 window     ───  WS3: 1 window  ✓ MATCH

   Missing windows:
   - Ghostty (WS1, title: "~/repos/stacks")
   - Lazygit (WS2, title: "nixos")

   [Restore Missing] [Save Current As New] [Cancel]
   ```

2. **Interactive Layout Editor**
   - Click window in tree → Edit launch command
   - Click window → Change swallow criteria
   - Drag window in tree → Change workspace assignment
   - Right-click → Remove from layout

3. **Layout Snapshot Comparison**
   ```
   i3pm layouts diff default current

   Diff: default (2025-10-15 14:30) → current (2025-10-22 11:45)

   ✓ Kept: 5 windows
   + Added: 2 windows (Ghostty x2)
   - Removed: 1 window (YouTube)
   ≈ Moved: 1 window (Code WS2 → WS1)

   [Save as New Layout] [Update "default"] [Discard Changes]
   ```

---

## Implementation Roadmap

### Phase 1: i3-resurrect Pattern Adoption (2 hours)
- [ ] Add `_unmap_window()` and `_map_window()` using xdotool
- [ ] Wrap restore logic with unmap/remap try/finally
- [ ] Add workspace layout mode preservation
- [ ] Test restore visual quality

### Phase 2: Flexible Swallow Criteria (3 hours)
- [ ] Add `swallow_criteria` field to LayoutWindow
- [ ] Add `swallow_overrides` to config
- [ ] Update `to_swallow_dict()` to use criteria
- [ ] Add CLI flag: `--swallow="class,instance,title"`
- [ ] Test with terminal tabs and browser windows

### Phase 3: i3-resurrect Compatibility (4 hours)
- [ ] Implement `import_i3_resurrect_layout()`
- [ ] Implement `export_to_i3_resurrect()`
- [ ] Add CLI commands: `i3pm layout import`, `i3pm layout export`
- [ ] Test import/export roundtrip
- [ ] Document migration guide

### Phase 4: Visual Layout Integration (6 hours)
- [ ] Integrate layout save/restore into WindowStateScreen TUI
- [ ] Add visual diff view (current vs saved)
- [ ] Add "missing windows" detection and highlight
- [ ] Add keyboard shortcuts: `s` save, `r` restore, `d` diff
- [ ] Implement interactive layout editor (stretch goal)

### Phase 5: Testing & Documentation (2 hours)
- [ ] Test all new features end-to-end
- [ ] Update quickstart documentation
- [ ] Add migration guide from i3-resurrect
- [ ] Performance test with 50+ window layouts

**Total Estimated Time**: 17 hours (~2 working days)

---

## Conclusion

**i3pm's layout system is already more sophisticated than i3-resurrect**, but we can adopt specific proven patterns:

1. ✅ **Window unmapping** - Prevents visual flicker
2. ✅ **Flexible swallow criteria** - Handles edge cases
3. ✅ **Workspace layout preservation** - More accurate restore
4. ✅ **Compatibility mode** - Migration path from i3-resurrect

**The big opportunity**: **Visual layout management integrated with window state tree view**

This would give users:
- Visual understanding of their layouts
- Diff view to see changes
- Interactive editing
- One unified TUI for all window/layout management

**Next Step**: Should we proceed with Phase 1 (i3-resurrect pattern adoption) or jump straight to Phase 4 (visual integration with window state tree)?
