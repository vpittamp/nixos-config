# Eww Architecture Research: Conditional Class Patterns

**Date**: 2025-11-20
**Context**: Feature 085 - Addressing ternary operator challenges in window widget implementation

## Problem Statement

During implementation of User Story 3 (T027-T032), we encountered syntax errors when using ternary operators with empty strings in Eww widget classes:

```yuck
:class "window ${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ${window.floating ? 'window-floating' : ''} ${window.hidden ? 'window-hidden' : ''}"
```

**Error**: `syntax error, unexpected '}', expecting ';'`

**Root Cause**: The empty string `''` in Nix multi-line strings (starting with `''`) has special escaping rules that conflict with Eww's ternary operator syntax.

## Research Findings

### 1. Official Eww Expression Language

**Source**: [Eww Expression Language Documentation](https://elkowar.github.io/eww/expression_language.html)

Eww supports ternary operators with the standard syntax:
```yuck
{condition ? 'true_value' : 'false_value'}
```

**Key Features**:
- String interpolation: `"text ${expression} text"`
- Elvis operator (`?:`): Returns right side if left is `""` or `null`
- Safe access (`?.`): Returns `null` if left side is empty
- Chained ternaries: `{cond1 ? val1 : cond2 ? val2 : default}`

**Important Finding**: Empty strings (`""`) are **valid** in Eww ternary operators. The issue we encountered was **Nix escaping**, not Eww limitations.

### 2. Best Practice Patterns from Community

#### Pattern 1: String Concatenation with Multiple Conditionals (RECOMMENDED)

**Source**: GitHub community configs, Arch Linux forums

```yuck
:class "base-class ${condition1 ? 'class1' : ''} ${condition2 ? 'class2' : ''} ${condition3 ? 'class3' : ''}"
```

**Example from real-world configs**:
```yuck
:class "workspace-entry ${workspace.id == current_workspace ? 'current' : ''} ${workspace.windows > 0 ? 'occupied' : 'empty'}"
```

**Advantages**:
- Clean, readable syntax
- All conditionals in one place
- Easy to add/remove conditional classes
- No nested widget structures needed

**Disadvantages**:
- Empty strings can cause Nix escaping issues (our problem)

#### Pattern 2: Chained Ternary for Complex Conditions

**Source**: Community examples, GitHub issue #430

```yuck
:class {condition1 ? 'class1' : condition2 ? 'class2' : condition3 ? 'class3' : 'default'}
```

**Example**:
```yuck
:class {bat.status == 'Discharging' && bat.capacity <= 5 ? 'warning' : (bat.status == 'Charging' && bat.capacity > 95) || bat.status == 'Full' ? 'good' : 'normal'}
```

**Advantages**:
- Single expression, no string interpolation issues
- Works well for mutually exclusive states

**Disadvantages**:
- Hard to read with many conditions
- Doesn't support multiple simultaneous classes

#### Pattern 3: Separate :visible Widgets (OFFICIAL RECOMMENDATION)

**Source**: GitHub Discussion #435, Official docs

For conditionally showing different widgets:
```yuck
(box
  (box :visible {condition1} (widget1))
  (box :visible {condition2} (widget2))
  (box :visible {condition3} (widget3)))
```

**Advantages**:
- No ternary operators needed
- Each state can have completely different structure
- Recommended by Eww maintainers

**Disadvantages**:
- Creates multiple DOM elements (hidden ones still exist)
- Not suitable for just adding CSS classes

#### Pattern 4: Nested Box Structure (OUR CURRENT SOLUTION)

Our implemented solution:
```yuck
(box
  :class "window ${window.scope == 'scoped' ? 'scoped-window' : 'global-window'}"
  (box
    :class "${window.floating ? 'window-floating' : 'window-normal'} ${window.hidden ? 'window-hidden' : 'window-visible'}"
    ; ... labels here
    ))
```

**Advantages**:
- Avoids Nix escaping issues with empty strings
- Separates scope from state classes
- Works reliably

**Disadvantages**:
- Extra DOM element (performance impact minimal)
- More complex structure than needed

## Recommended Solutions

### Solution 1: Fix Nix Escaping (BEST PRACTICE)

**Problem**: Nix multi-line strings (`''`) treat `''` specially (escape sequence for single quote).

**Solution**: Use regular double-quoted strings in Nix for Yuck content:

```nix
# WRONG (causes escaping issues):
xdg.configFile."eww/eww.yuck".text = ''
  (defwidget foo []
    (box :class "bar ${x ? 'y' : ''}"))
'';

# CORRECT (no escaping issues):
xdg.configFile."eww/eww.yuck".text = ''
  (defwidget foo []
    (box :class "bar ${"$"}{x ? 'y' : \"\"}"))
'';
```

**Key**: Escape the `${` in Nix to prevent variable interpolation, and use `\"` for empty strings.

**Even Better**: Use dedicated variables for complex class strings:

```yuck
(defvar empty "")

(defwidget window-widget [window]
  (box
    :class "window ${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ${window.floating ? 'window-floating' : empty} ${window.hidden ? 'window-hidden' : empty}"
    ; ... content
    ))
```

### Solution 2: Use String Builder Pattern

Create a helper function or use string concatenation:

```yuck
(defwidget window-widget [window]
  (let ((classes (concat
                   "window "
                   (if (== window.scope "scoped") "scoped-window" "global-window")
                   (if window.floating " window-floating" "")
                   (if window.hidden " window-hidden" "")
                   (if window.focused " window-focused" ""))))
    (box :class classes
      ; ... content
      )))
```

**Note**: Eww doesn't have `concat` or `if` functions built-in. This would require custom defpoll or external script support.

### Solution 3: Simplify State Model (ARCHITECTURAL IMPROVEMENT)

Instead of multiple boolean flags, use a single state enum:

```yuck
; Backend returns: window.state = "floating-hidden-focused"
(defwidget window-widget [window]
  (box
    :class "window ${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ${window.state}"
    ; ... content
    ))
```

**Backend transformation** (`monitoring_data.py`):
```python
def get_window_state(window: Dict[str, Any]) -> str:
    """Generate composite state class string."""
    states = []
    if window.get("floating"):
        states.append("window-floating")
    if window.get("hidden"):
        states.append("window-hidden")
    if window.get("focused"):
        states.append("window-focused")
    return " ".join(states) if states else "window-normal"

return {
    # ... other fields
    "state": get_window_state(window)
}
```

**Advantages**:
- Single ternary operator in Yuck
- All complexity moved to Python (where it's easier to test)
- No Nix escaping issues
- More maintainable

**Disadvantages**:
- Backend now responsible for presentation logic
- Loses some flexibility in Yuck layer

## Recommended Architecture for Feature 085

### Phase 1: Immediate Fix (Current Implementation)

**Keep the nested box structure** - it works and is stable:
```yuck
(box
  :class "window ${window.scope == 'scoped' ? 'scoped-window' : 'global-window'}"
  (box
    :class "${window.floating ? 'window-floating' : 'window-normal'} ${window.hidden ? 'window-hidden' : 'window-visible'}"
    ; ... content
    ))
```

### Phase 2: Refactor to State Model (Future Enhancement)

**Implement Solution 3** - move state composition to backend:

1. **Backend change** (`monitoring_data.py`):
   ```python
   def get_window_state_classes(window: Dict[str, Any]) -> str:
       """Generate space-separated CSS class string for window states."""
       classes = []
       if window.get("floating"):
           classes.append("window-floating")
       if window.get("hidden"):
           classes.append("window-hidden")
       if window.get("focused"):
           classes.append("window-focused")
       return " ".join(classes)

   return {
       # ... existing fields
       "state_classes": get_window_state_classes(window)
   }
   ```

2. **Yuck simplification**:
   ```yuck
   (defwidget window-widget [window]
     (box
       :class "window ${window.scope == 'scoped' ? 'scoped-window' : 'global-window'} ${window.state_classes}"
       ; ... content (no nested box needed)
       ))
   ```

**Benefits**:
- Cleaner Yuck code
- Single DOM element (better performance)
- Easier to test (Python unit tests)
- No Nix escaping issues
- Follows separation of concerns (data transformation in backend, display in frontend)

## Comparison with Our Current Solution

| Approach | DOM Elements | Nix Escaping Issues | Readability | Testability | Performance |
|----------|--------------|---------------------|-------------|-------------|-------------|
| Current (Nested Boxes) | 2 per window | ✅ None | ⚠️ Medium | ⚠️ Medium | ⚠️ Good |
| String Concatenation | 1 per window | ❌ Yes (requires careful escaping) | ✅ High | ⚠️ Medium | ✅ Excellent |
| State Model (Recommended) | 1 per window | ✅ None | ✅ High | ✅ Excellent | ✅ Excellent |
| :visible Pattern | 3+ per window | ✅ None | ⚠️ Low | ⚠️ Low | ❌ Poor (hidden elements) |

## Action Items

1. **Document current solution** in tasks.md as working solution ✅ (already done)
2. **Create tech debt task** for refactoring to state model pattern (Phase 7: Polish)
3. **Add unit tests** for state class generation in backend (Phase 6: Testing)
4. **Update quickstart.md** with troubleshooting for Nix escaping issues

## References

- [Eww Expression Language Docs](https://elkowar.github.io/eww/expression_language.html)
- [GitHub Discussion #435: Clarification on EWW expressions](https://github.com/elkowar/eww/discussions/435)
- [GitHub Issue #1209: Empty string handling bug](https://github.com/elkowar/eww/issues/1209)
- [Arch Linux Forums: Workspace widget configuration](https://bbs.archlinux.org/viewtopic.php?id=293267)
