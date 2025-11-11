# Research: Unified Workspace Bar Icon System

**Feature**: 057-workspace-bar-icons | **Date**: 2025-11-10

## Research Tasks

This document consolidates findings from technical research needed to resolve "NEEDS CLARIFICATION" markers in the implementation plan.

---

## Task 1: Testing Strategy for Icon Lookup Validation

**Context**: Need to determine the optimal testing approach for validating icon lookup consistency between Walker launcher and workspace bar.

### Decision

**Hybrid testing strategy**: pytest (Python unit/integration tests) + sway-test framework (end-to-end visual validation)

### Rationale

1. **pytest for Python logic validation**:
   - DesktopIconIndex class has complex icon resolution logic (5-step cascade)
   - Unit tests can verify each lookup priority (app registry → PWA registry → desktop files → icon theme → fallback)
   - Integration tests can validate XDG_DATA_DIRS precedence and filesystem icon search
   - Fast feedback loop (<1 second for full Python test suite)
   - Mocking capabilities for registry files and filesystem paths

2. **sway-test for end-to-end validation**:
   - Cannot unit test visual icon rendering in Eww widgets
   - sway-test can launch applications and verify icon paths in Sway tree
   - Partial state comparison mode ideal for checking `iconPath` field in workspace data
   - Validates complete flow: app launch → window creation → icon resolution → bar display
   - Catches integration issues (XDG_DATA_DIRS misconfiguration, icon theme availability)

3. **Manual visual inspection for quality**:
   - Crisp rendering at 20×20 pixels requires subjective assessment
   - Color consistency across icon formats (SVG vs PNG) needs human verification
   - Use sway-test to generate comparison screenshots (if possible) or manual checklist

### Alternatives Considered

**Alternative 1: pytest only**
- **Rejected because**: Cannot validate Eww bar rendering, Sway IPC integration, or visual icon quality

**Alternative 2: sway-test only**
- **Rejected because**: Slower test execution, harder to isolate Python logic bugs, less granular failure messages

**Alternative 3: Manual testing only**
- **Rejected because**: Not repeatable, doesn't prevent regressions, violates Constitution Principle XIV (Test-Driven Development)

### Implementation Plan

**Phase 1: Python unit tests (pytest)**
```python
# tests/057-workspace-bar-icons/unit/test_icon_resolution.py
def test_icon_resolution_app_registry_priority():
    """Verify app registry takes priority over desktop files."""
    index = DesktopIconIndex()
    # Mock registries with conflicting icon names
    icon_info = index.lookup(app_id="firefox", window_class=None, window_instance=None)
    assert icon_info["icon"] == "/path/from/app/registry"

def test_icon_resolution_pwa_registry():
    """Verify PWA registry resolves absolute icon paths."""
    index = DesktopIconIndex()
    icon_info = index.lookup(app_id="ffpwa-01JCYF8Z2M", window_class=None, window_instance=None)
    assert icon_info["icon"] == "/etc/nixos/assets/pwa-icons/claude.png"

def test_icon_resolution_terminal_app():
    """Verify terminal app (Ghostty) resolves to specific app icon."""
    index = DesktopIconIndex()
    # Mock window with Ghostty class but lazygit instance
    icon_info = index.lookup(app_id="ghostty", window_class="ghostty", window_instance="lazygit")
    assert icon_info["icon"].endswith("lazygit.svg")  # Not ghostty icon
```

**Phase 2: sway-test integration tests**
```json
// tests/057-workspace-bar-icons/integration/test_walker_parity.json
{
  "name": "Firefox icon matches between Walker and workspace bar",
  "actions": [
    {"type": "launch_app_sync", "params": {"app_name": "firefox"}},
    {"type": "wait_event", "params": {"event_type": "window::new", "timeout": 2000}}
  ],
  "expectedState": {
    "workspaces": [{
      "num": 3,
      "windows": [{
        "app_id": "firefox",
        "focused": true
      }]
    }]
  }
}
```

**Phase 3: Icon path extraction validation**
- Write Python script to extract icon path from Walker launcher display
- Extract icon path from workspace bar widget (via deflisten output or Eww state)
- Compare paths programmatically (should be identical)

### Best Practices from Existing Features

**From Feature 069 (Sync Test Framework)**:
- Use `launch_app_sync` action with automatic synchronization
- Validate state via Sway IPC GET_TREE (authoritative source)
- Partial state comparison mode for focused assertions

**From Constitution Principle X (Python Development Standards)**:
- pytest with pytest-asyncio for async test cases
- Type hints for test functions and fixtures
- Rich library for test output formatting (if human-readable reports needed)

**From Constitution Principle XIV (Test-Driven Development)**:
- Write tests BEFORE implementing icon lookup enhancements
- Test-first iteration: spec → tests → implement → run → fix → repeat

---

## Task 2: Icon Theme Lookup via PyXDG Best Practices

**Context**: Need to understand XDG Icon Theme Specification and PyXDG `getIconPath()` usage patterns for optimal icon resolution.

### Decision

**Use PyXDG `getIconPath(icon_name, size)` with fallback search through ICON_SEARCH_DIRS** as currently implemented in `workspace_panel.py`.

### Rationale

1. **PyXDG is XDG-compliant**:
   - Follows XDG Icon Theme Specification exactly
   - Searches `XDG_DATA_DIRS` icon directories with proper precedence
   - Supports theme inheritance (e.g., Papirus → hicolor fallback)
   - Handles icon size variants (e.g., 16×16, 20×20, 48×48, scalable)

2. **Existing implementation is sound**:
   - workspace_panel.py:121 uses `getIconPath(icon_name, 48)` (may want 20 for bar)
   - Fallback search through `ICON_SEARCH_DIRS` handles non-themed icons
   - Icon cache prevents redundant filesystem lookups

3. **Walker uses same mechanism**:
   - Walker launcher also uses XDG_DATA_DIRS for icon resolution
   - Relies on standard icon theme directories (`~/.local/share/icons`, `/usr/share/icons`)
   - This ensures parity between Walker and workspace bar

### Alternatives Considered

**Alternative 1: Manual icon theme parsing**
- **Rejected because**: Reinventing XDG Icon Theme Specification, error-prone, harder to maintain

**Alternative 2: Qt/GTK icon theme APIs**
- **Rejected because**: Adds heavy dependencies (Qt/GTK libraries), Python daemon should be lightweight

### Implementation Notes

**Icon size adjustment**:
- Current: `getIconPath(icon_name, 48)` (48×48 pixels)
- Workspace bar: 20×20 pixels (line 96 in eww-workspace-bar.nix)
- **Recommendation**: Keep 48px lookup, let Eww scale down (SVGs scale perfectly, PNGs have better source resolution)

**Icon format priority**:
- Prefer SVG (scalable, crisp at any size)
- Accept PNG (if SVG unavailable)
- Accept XPM (legacy format, rarely needed)

**XDG_DATA_DIRS precedence** (from eww-workspace-bar.nix:248):
```
1. ~/.local/share/i3pm-applications (curated app registry)
2. ~/.local/share (user-installed icons/apps)
3. ~/.nix-profile/share (user profile packages)
4. /run/current-system/sw/share (system packages)
```

This precedence ensures:
- Curated application registry icons take priority
- User customizations override system defaults
- System icon themes provide fallback

---

## Task 3: Terminal Application Icon Detection Pattern

**Context**: Terminal applications (lazygit, yazi, btop) launched via Ghostty need distinct icons instead of generic terminal icon.

### Decision

**Match terminal applications by `window_instance` field in application registry**, then use registry icon name for lookup.

### Rationale

1. **Ghostty sets window_instance to command name**:
   - When launching `ghostty -e lazygit`, Ghostty sets `window_instance = "lazygit"`
   - This is observable via Sway IPC GET_TREE query
   - Provides deterministic identification (unlike window title)

2. **Application registry already indexes by multiple fields**:
   - workspace_panel.py:140-154 shows lookup by `app_id`, `window_class`, `window_instance`
   - Can add terminal app entries to application-registry.json with `expected_instance` field

3. **Icon priority cascade handles this naturally**:
   - App registry lookup tries `app_id`, `window_class`, `window_instance` (line 143)
   - Terminal apps will match on `window_instance`
   - No special-case logic needed if registry entries exist

### Alternatives Considered

**Alternative 1: Parse window title**
- **Rejected because**: Window title is mutable, not reliable (e.g., "lazygit - main branch" changes)

**Alternative 2: Read process command line from /proc**
- **Rejected because**: Adds complexity, /proc access can fail if process exits, window_instance is simpler

**Alternative 3: Separate terminal app registry**
- **Rejected because**: Duplicates existing registry structure, harder to maintain

### Implementation Notes

**Application registry entry example**:
```json
{
  "applications": [
    {
      "name": "lazygit",
      "display_name": "lazygit",
      "command": "ghostty -e lazygit",
      "expected_class": "ghostty",
      "expected_instance": "lazygit",
      "icon": "lazygit",
      "scope": "scoped",
      "preferred_workspace": 7
    }
  ]
}
```

**Icon lookup flow**:
1. Window created with `app_id=None`, `window_class="ghostty"`, `window_instance="lazygit"`
2. DesktopIconIndex.lookup() iterates keys: `["lazygit", "ghostty"]`
3. Matches `"lazygit"` in `_by_app_id` (from registry `name` field)
4. Returns icon: `lazygit` → PyXDG resolves to `/usr/share/icons/Papirus/20x20/apps/lazygit.svg`

**Testing validation**:
- pytest unit test: Mock window with `window_instance="lazygit"`, verify icon path
- sway-test integration: Launch `ghostty -e lazygit`, check workspace bar shows lazygit icon

---

## Task 4: Icon Rendering Quality Validation Pattern

**Context**: Need to verify icons render crisply at 20×20 pixels without pixelation on high DPI displays.

### Decision

**Manual visual inspection checklist + screenshot comparison tooling** (automated pixel-perfect comparison not feasible for subjective "crisp" quality).

### Rationale

1. **Subjective quality assessment**:
   - "Crisp" and "non-pixelated" are subjective human perceptions
   - Automated image comparison (pixel diff) doesn't capture visual appeal
   - Different icon formats (SVG, PNG) render differently - humans judge quality better

2. **Checklist-driven validation**:
   - Test each icon source (app registry, PWA registry, desktop files, icon themes)
   - Test multiple icon formats (SVG, PNG, XPM)
   - Test on different DPI settings (1× standard, 2× Retina)
   - Document pass/fail for each icon tested

3. **Screenshot comparison for regression detection**:
   - Capture workspace bar screenshot before/after changes
   - Visual diff highlights rendering changes
   - Useful for detecting unintended icon quality degradation

### Alternatives Considered

**Alternative 1: Automated pixel-perfect comparison**
- **Rejected because**: Too brittle (minor rendering changes fail tests), doesn't capture "crisp" perception

**Alternative 2: Perceptual image hashing (pHash, SSIM)**
- **Rejected because**: Complexity not justified for icon validation, false positives on valid rendering improvements

### Implementation Notes

**Manual validation checklist** (to be created in quickstart.md):
```markdown
## Icon Quality Validation Checklist

Test each icon source on both Hetzner (HEADLESS-1) and M1 (eDP-1):

- [ ] Regular app icon (Firefox): SVG rendering crisp at 20×20?
- [ ] Regular app icon (VS Code): Transparent background integrates well?
- [ ] PWA icon (Claude): PNG rendering crisp at 20×20?
- [ ] PWA icon background: Transparent or no white/solid background? (Firefox, VS Code = good; ChatGPT, Claude with white = needs replacement)
- [ ] Terminal app icon (lazygit): Icon shows (not Ghostty icon)?
- [ ] Fallback icon (unknown app): First letter rendered clearly?
- [ ] High DPI (M1 Retina): Icons sharp without pixelation?
- [ ] Low DPI (Hetzner VNC): Icons readable at 1× scale?
- [ ] Icon colors: Consistent with Catppuccin Mocha palette?
- [ ] Icon backgrounds: No visible white/solid rectangular backgrounds?
- [ ] Icon spacing: Consistent gaps between workspace buttons?
```

**Screenshot comparison workflow**:
1. Capture baseline: `grim -o HEADLESS-1 ~/workspace-bar-before.png`
2. Apply changes, rebuild NixOS
3. Capture updated: `grim -o HEADLESS-1 ~/workspace-bar-after.png`
4. Visual diff: `compare workspace-bar-before.png workspace-bar-after.png diff.png`

---

## Summary of Research Findings

| Task | Decision | Impact on Implementation |
|------|----------|--------------------------|
| **Testing Strategy** | Hybrid: pytest (Python) + sway-test (E2E) | Write unit tests for DesktopIconIndex, integration tests for Walker parity |
| **Icon Theme Lookup** | Use PyXDG `getIconPath()` (already implemented) | No changes needed to icon theme resolution logic |
| **Terminal App Detection** | Match by `window_instance` in app registry | Add terminal app entries to application-registry.json with expected_instance field |
| **Icon Quality Validation** | Manual checklist + screenshot comparison | Create validation checklist in quickstart.md, capture screenshots for regression detection |

**All "NEEDS CLARIFICATION" markers resolved.** Ready to proceed to Phase 1 (data model and contracts generation).
