# i3-resurrect Window Matching Analysis

**Date**: 2025-10-22
**Purpose**: Understanding i3-resurrect's window matching approach for Feature 024

## Summary

i3-resurrect uses **swallow criteria** to match windows for layout restoration. This is fundamentally different from Feature 024's rule-based routing system, but we can learn from their pattern matching approach.

## How i3-resurrect Window Matching Works

### 1. Swallow Criteria System

**Purpose**: Create placeholder windows that "swallow" (match) real windows when they appear.

**Command Line Interface**:
```bash
# Save with different matching criteria
i3-resurrect save -w 1 --swallow=class,instance,title
```

**Available Criteria** (from CLI `--swallow` parameter):
- `class` - Window class (WM_CLASS)
- `instance` - Window instance
- `title` - Window title
- `window_role` - Window role (WM_WINDOW_ROLE)

**Default**: `class,instance` (most reliable, least specific)

### 2. Window Properties Extraction

**From `treeutils.py:process_node()` and `programs.py:windows_in_workspace()`**:

```python
# Properties available from i3 tree
window_properties = {
    "class": str,      # WM_CLASS class
    "instance": str,   # WM_CLASS instance
    "title": str,      # Window title (_NET_WM_NAME)
    "transient_for": int,  # Parent window ID (for dialogs)
}

# Also available but not used for swallow criteria:
# - window_role (WM_WINDOW_ROLE)
# - window_type (not explicitly shown but implied)
```

### 3. Per-Window Configuration Override

**From config.json** (`window_swallow_criteria`):

```json
{
  "window_swallow_criteria": {
    "Ario": ["class", "instance"]
  }
}
```

**Logic in `treeutils.py:process_node()` (lines 2507-2523)**:
```python
# Set swallow criteria if the node is a window.
if "window_properties" in original:
    processed["swallows"] = [{}]
    # Local variable for swallow criteria.
    swallow_criteria = swallow  # From command line
    # Get swallow criteria from config.
    window_swallow_mappings = config.get("window_swallow_criteria", {})
    window_class = original["window_properties"].get("class", "")
    # Swallow criteria from config override the command line parameters
    # if present.
    if window_class in window_swallow_mappings:
        swallow_criteria = window_swallow_mappings[window_class]
    for criterion in swallow_criteria:
        if criterion in original["window_properties"]:
            # Escape special characters in swallow criteria.
            escaped = re.escape(original["window_properties"][criterion])
            processed["swallows"][0][criterion] = escaped
```

**Key Insight**: Config file overrides command line for specific window classes.

### 4. Pattern Escaping for Regex

**From `treeutils.py` line 2522**:
```python
# Escape special characters in swallow criteria.
escaped = re.escape(original["window_properties"][criterion])
```

**Why this matters**:
- i3's swallow criteria uses regex matching
- Special regex characters in window titles (like `[`, `]`, `(`, `)`, `.`, `*`) must be escaped
- `re.escape()` converts: `"Vim [main.py]"` → `"Vim \[main\.py\]"`

### 5. Window Command Mapping (Different Feature)

**From `programs.py:calc_rule_match_score()` (lines 2425-2450)**:

This is a SEPARATE feature for determining what command to run to restore a program (not for matching windows to placeholders).

```python
def calc_rule_match_score(rule, window_properties):
    """
    Score window command mapping match based on which criteria match.

    Scoring is done based on which criteria are considered "more specific".
    """
    # Window properties and value to add to score when match is found.
    criteria = {
        "window_role": 1,
        "class": 2,
        "instance": 3,
        "title": 10,  # Most specific = highest score
    }

    score = 0
    for criterion in criteria:
        if criterion in rule:
            # Score is zero if there are any non-matching criteria.
            if (
                criterion not in window_properties
                or rule[criterion] != window_properties[criterion]
            ):
                return 0  # ANY mismatch = no match
            score += criteria[criterion]
    return score
```

**Scoring System**:
- All specified criteria must match (AND logic)
- More specific matches get higher scores
- Title (10 points) > Instance (3) > Class (2) > Window Role (1)
- Best match wins (highest score)

**Config Example** (`window_command_mappings`):
```json
{
  "window_command_mappings": [
    {
      "class": "Gnome-terminal",
      "command": "gnome-terminal"
    },
    {
      "class": "Some-program"
      // No command = don't launch anything
    },
    {
      "class": "Some-program",
      "title": "Main window's title",
      "command": ["some-program", "arg1", "arg2"]
    }
  ]
}
```

## Relevant Lessons for Feature 024

### 1. ✅ Config Override Pattern (ADOPT)

**i3-resurrect approach**:
```json
{
  "window_swallow_criteria": {
    "Ario": ["class", "instance"]  // Override for specific class
  }
}
```

**Feature 024 equivalent** (already planned):
```json
{
  "rules": [
    {
      "name": "ario-override",
      "match_criteria": {
        "class": {"pattern": "Ario", "match_type": "exact"}
      },
      "priority": "project"  // Higher priority = override
    }
  ]
}
```

**Decision**: ✅ Feature 024's priority system is more flexible (project > global > default)

### 2. ✅ Regex Escaping Pattern (ALREADY CONSIDERED)

**i3-resurrect approach**:
```python
escaped = re.escape(original["window_properties"][criterion])
```

**Feature 024 approach** (from existing `pattern.py`):
```python
if pattern_type == "regex":
    try:
        re.compile(raw_pattern)  # Validate regex at rule creation
    except re.error as e:
        raise ValueError(f"Invalid regex pattern '{raw_pattern}': {e}")
```

**Decision**: ✅ Feature 024 validates regex at rule creation (better UX)

### 3. ✅ Scoring System for Best Match (CONSIDER)

**i3-resurrect approach**:
- Score rules based on specificity
- Higher score = more specific = better match
- All criteria must match (AND logic)

**Feature 024 approach** (from existing `pattern_resolver.py`):
- Priority-based evaluation (1000 → 200 → 100 → 50)
- First-match semantics (stop at first match)
- No scoring within same priority

**Decision**: ✅ Keep Feature 024's first-match approach (simpler, more predictable)

### 4. ⚠️ Window Properties Coverage

**i3-resurrect extracts**:
- ✅ class
- ✅ instance
- ✅ title
- ✅ transient_for
- ❓ window_role (mentioned but not shown in extraction)

**Feature 024 planned**:
- ✅ class
- ✅ instance
- ✅ title
- ✅ window_role
- ✅ window_type (NEW - not in i3-resurrect)
- ✅ transient_for

**Decision**: ✅ Feature 024 has better coverage (includes window_type)

### 5. ⚠️ Pattern Types Comparison

**i3-resurrect**:
- Only supports regex (via i3's swallow criteria)
- Uses `re.escape()` for literal matching
- No explicit wildcard/glob support

**Feature 024** (from existing `pattern.py`):
- ✅ `exact` - Literal string match
- ✅ `glob` - Shell-style wildcards (`*`, `?`)
- ✅ `regex` - Full regex support
- ✅ `pwa` - Special PWA detection (FFPWA-* + title)
- ✅ `title` - Title-only patterns

**Decision**: ✅ Feature 024 has richer pattern types (keep all)

### 6. ❌ Argument Interpolation (NOT RELEVANT)

**i3-resurrect feature**:
```python
command = [arg.format(*cmdline) for arg in best_match["command"]]
```

Example: `"code -n {1}"` + `['code', '/path/to/file']` → `"code -n /path/to/file"`

**Feature 024 scope**: Window routing, not program launching

**Decision**: ❌ Not applicable (different problem domain)

## Conclusion for Feature 024

### What to Keep from i3-resurrect

1. ✅ **Regex escaping pattern** - Already validated in Feature 024
2. ✅ **Window properties extraction** - Cover all properties (class, instance, title, role, type, transient_for)
3. ✅ **Config override hierarchy** - Priority system covers this better

### What NOT to Adopt

1. ❌ **Scoring system** - First-match is simpler and more predictable
2. ❌ **Command line swallow parameter** - Rules are configured in JSON, not CLI
3. ❌ **Argument interpolation** - Out of scope (program launching, not routing)

### Confirmed Design Decisions

**Feature 024's approach is superior in these areas**:
1. ✅ First-match semantics (vs scoring) - more predictable
2. ✅ Priority levels (project/global/default) - more flexible than per-class overrides
3. ✅ Multiple pattern types (exact/glob/regex/pwa/title) - richer matching
4. ✅ Window type support - not in i3-resurrect
5. ✅ Structured actions - i3-resurrect only does layout restoration

### No Changes Needed

The reconciliation analysis already identified that Feature 024's existing pattern matching (`pattern.py`) and window property extraction (`handlers.py`) are comprehensive. This i3-resurrect review confirms:

✅ **Existing pattern.py is BETTER** than i3-resurrect's approach
✅ **Existing WindowInfo model covers needed properties**
✅ **No new features needed from i3-resurrect**

## Implementation Impact

**No changes to reconciled tasks** - Analysis confirms existing approach is correct.

The reconciled plan already includes:
- ✅ R010: validate_target_workspace() - Better than i3-resurrect (no validation)
- ✅ R004-R005: Structured actions - i3-resurrect doesn't have this
- ✅ R014-R017: CLI validation tools - i3-resurrect has basic validation only

**Feature 024 is a more comprehensive solution** than i3-resurrect for window routing.

---

**Analysis Complete**: No changes needed to reconciliation plan based on i3-resurrect review.
