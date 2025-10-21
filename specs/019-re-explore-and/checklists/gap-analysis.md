# Requirements Gap Analysis: App Discovery Enhancements

**Analysis Date**: 2025-10-21
**Analyzed Against**: `/etc/nixos/specs/019-re-explore-and/spec.md`
**Checklist**: `/etc/nixos/specs/019-re-explore-and/checklists/app-discovery-enhancements.md`

---

## Executive Summary

This analysis evaluates the current specification against the comprehensive requirements quality checklist for the four app discovery enhancements. The current spec (v1) focuses on the core i3 project management system but **does not yet contain specifications for the four app discovery enhancements**. This gap analysis identifies all missing requirements that must be specified before implementation.

### Gap Statistics

| Enhancement | Total Requirements | Specified | Missing | % Complete |
|-------------|-------------------|-----------|---------|------------|
| 1. Xvfb Detection | 92 | 0 | 92 | 0% |
| 2. TUI Wizard | 126 | 8* | 118 | 6% |
| 3. Pattern Rules | 85 | 2* | 83 | 2% |
| 4. Window Inspection | 89 | 3* | 86 | 3% |
| Cross-Enhancement | 23 | 4* | 19 | 17% |
| Testing & Docs | 32 | 10* | 22 | 31% |
| **TOTAL** | **447** | **27** | **420** | **6%** |

*Partial coverage from existing FR-058 through FR-072 (unified TUI/CLI interface requirements)

---

## Enhancement 1: Xvfb Detection Activation

### Current State
**Missing: 100%** - No requirements specified in current spec for isolated window class detection.

### Critical Gaps

#### 1.1 Dependency Management (0/4 requirements)
- [ ] **DEP-001**: xvfb-run installation requirements not specified
  - **Impact**: Users won't know how to install dependencies
  - **Recommendation**: Add FR specifying NixOS package requirements (`pkgs.xvfb`, `pkgs.xdotool`, `pkgs.xorg.xprop`)

- [ ] **DEP-002**: xdotool dependency requirements not specified
  - **Impact**: Detection will fail without clear error message
  - **Recommendation**: Add FR for pre-execution dependency validation

- [ ] **DEP-003**: xprop dependency requirements not specified
  - **Impact**: WM_CLASS extraction will fail silently
  - **Recommendation**: Add FR for property extraction tool requirements

- [ ] **DEP-004**: Dependency availability checks not specified
  - **Impact**: Poor user experience when dependencies missing
  - **Recommendation**: Add FR for graceful degradation and clear error messages

#### 1.2 Isolation Execution (0/4 requirements)
- [ ] **ISO-001**: Xvfb display number allocation not specified
  - **Impact**: Race conditions, display conflicts
  - **Recommendation**: Add FR specifying `xvfb-run -a` auto-allocation requirement

- [ ] **ISO-002**: Framebuffer size not specified
  - **Impact**: Apps may not render correctly, leading to detection failure
  - **Recommendation**: Add FR specifying default 1920x1080x24 framebuffer

- [ ] **ISO-003**: Timeout requirements not measurable
  - **Impact**: Slow apps may timeout incorrectly
  - **Recommendation**: Add FR specifying default 10s timeout with customization option

- [ ] **ISO-004**: Window appearance detection not specified
  - **Impact**: No algorithm for detecting when app window appears
  - **Recommendation**: Add FR specifying polling interval (100ms) and max retries

#### 1.3 Window Class Extraction (0/3 requirements)
- [ ] **EXT-001**: WM_CLASS extraction algorithm not specified
  - **Impact**: Inconsistent extraction across different apps
  - **Recommendation**: Add FR specifying xprop command syntax and parsing

- [ ] **EXT-002**: Window ID mapping not specified
  - **Impact**: May extract class from wrong window
  - **Recommendation**: Add FR for xdotool window search by PID

- [ ] **EXT-003**: Extraction failure handling not specified
  - **Impact**: Single failure causes entire detection to fail
  - **Recommendation**: Add FR for retry logic and fallback methods

#### 1.4 Cleanup & Safety (0/3 requirements)
- [ ] **CLN-001**: Process termination not specified
  - **Impact**: Zombie processes, resource leaks
  - **Recommendation**: Add FR for graceful SIGTERM + SIGKILL sequence

- [ ] **CLN-002**: Temporary resource cleanup not specified
  - **Impact**: Lock files and sockets left behind
  - **Recommendation**: Add FR for cleanup on success, timeout, and error

- [ ] **CLN-003**: Error state cleanup not specified
  - **Impact**: Partial state after interruption
  - **Recommendation**: Add FR for cleanup in all exit paths

#### 1.5 Fallback Strategy (0/3 requirements)
- [ ] **FALL-001**: Xvfb unavailable fallback not specified
  - **Impact**: Feature completely fails if Xvfb not installed
  - **Recommendation**: Add FR for fallback to `guess_wm_class` (already implemented)

- [ ] **FALL-002**: Detection failure fallback not specified
  - **Impact**: No recovery path when detection times out
  - **Recommendation**: Add FR for user notification and manual input option

- [ ] **FALL-003**: Success criteria not defined
  - **Impact**: Ambiguous what constitutes "successful detection"
  - **Recommendation**: Add FR defining success as "WM_CLASS property extracted and non-empty"

#### 1.6 Integration (0/3 requirements)
- [ ] **INT-001**: CLI integration not specified
  - **Impact**: No user-facing command to trigger isolated detection
  - **Recommendation**: Add FR for `i3pm app-classes detect --isolated <app-name>`

- [ ] **INT-002**: Bulk detection not specified
  - **Impact**: Must detect apps one-by-one
  - **Recommendation**: Add FR for batch processing of apps without WM_CLASS

- [ ] **INT-003**: Caching not specified
  - **Impact**: Re-detection every time (slow)
  - **Recommendation**: Add FR for caching detection results with cache invalidation

#### 1.7 UX & Observability (0/3 requirements)
- [ ] **UX-001**: Progress indication not specified
  - **Impact**: User sees no feedback during 10s detection
  - **Recommendation**: Add FR for progress messages ("Launching app...", "Waiting for window...", "Extracting class...")

- [ ] **UX-002**: Verbose logging not specified
  - **Impact**: Hard to debug detection failures
  - **Recommendation**: Add FR for --verbose mode showing Xvfb output

- [ ] **UX-003**: Error messages not specified
  - **Impact**: Generic errors without actionable guidance
  - **Recommendation**: Add FR for error message format with remediation suggestions

### Recommended Priority Additions

**CRITICAL (must have before implementation)**:
1. Add FR for Xvfb dependency requirements (DEP-001 through DEP-004)
2. Add FR for isolation execution algorithm (ISO-001 through ISO-004)
3. Add FR for cleanup safety (CLN-001 through CLN-003)
4. Add FR for CLI integration (`i3pm app-classes detect --isolated`)

**HIGH (needed for production quality)**:
1. Add FR for extraction algorithms (EXT-001 through EXT-003)
2. Add FR for fallback strategies (FALL-001 through FALL-003)
3. Add FR for progress indication and error messages (UX-001, UX-003)

**MEDIUM (enhances usability)**:
1. Add FR for bulk detection (INT-002)
2. Add FR for caching (INT-003)
3. Add FR for verbose logging (UX-002)

---

## Enhancement 2: Interactive Classification Wizard (TUI)

### Current State
**Partial: 6%** - FR-058 through FR-072 specify unified TUI/CLI interface but lack wizard-specific requirements.

### Existing Coverage

**From FR-058 through FR-072**:
- ✅ FR-058: Unified command supporting TUI + CLI modes
- ✅ FR-059: Interactive TUI when no args, CLI mode with args
- ✅ FR-060: TUI project browser (analogous but not specific to app classification)
- ✅ FR-062: Project creation wizard (pattern to follow for app classification wizard)
- ✅ FR-063: Monitoring dashboard integration (provides precedent for mode switching)
- ✅ FR-066: Keyboard-only navigation requirement
- ✅ FR-070: Direct screen launching (e.g., `i3pm wizard apps` to launch directly to wizard)
- ✅ FR-072: Shell completion scripts

### Critical Gaps

#### 2.1 Discovery & Data Loading (0/3 requirements)
- [ ] **LOAD-001**: App discovery trigger not specified for wizard
  - **Gap**: No requirement for `i3pm app-classes wizard` command
  - **Recommendation**: Add FR for wizard command integration with app discovery

- [ ] **LOAD-002**: App filtering not specified
  - **Gap**: No requirement for "apps without WM_CLASS" filter
  - **Recommendation**: Add FR for filter types (unclassified, without-class, by-category)

- [ ] **LOAD-003**: App sorting not specified
  - **Gap**: No default sort order defined
  - **Recommendation**: Add FR for sort columns (name, category, confidence) with toggleable direction

#### 2.2 Presentation & Visual Hierarchy (0/4 requirements)
- [ ] **PRES-001**: App list display format not specified
  - **Gap**: No table column layout requirement
  - **Recommendation**: Add FR defining columns: Name (30%), Exec (25%), WM Class (15%), Suggestion (15%), Status (15%)

- [ ] **PRES-002**: Color scheme not specified
  - **Gap**: No semantic colors defined
  - **Recommendation**: Add FR for color scheme (scoped=green, global=blue, unknown=yellow, error=red)

- [ ] **PRES-003**: Icon/glyph requirements not specified
  - **Gap**: No status indicators defined
  - **Recommendation**: Add FR for glyphs (✓=classified, ?=unknown, ⚠=conflict, 🔒=scoped, 🌍=global)

- [ ] **PRES-004**: Confidence score visualization not specified
  - **Gap**: No display format for heuristic confidence
  - **Recommendation**: Add FR for confidence display (percentage with color-coded thresholds)

#### 2.3 Keyboard Navigation (0/4 requirements)
- [ ] **NAV-001**: List navigation keys not specified
  - **Gap**: Arrow keys, Page Up/Down, Home/End not defined
  - **Existing**: FR-066 requires keyboard-only navigation (general)
  - **Recommendation**: Add FR specifying navigation keybindings for wizard mode

- [ ] **NAV-002**: Selection keys not specified
  - **Gap**: Space, Enter, multi-select behaviors undefined
  - **Recommendation**: Add FR for selection keybindings (Space=toggle, Enter=approve+next, Shift+arrows=multi-select)

- [ ] **NAV-003**: Action keys not specified
  - **Gap**: Classification action shortcuts not defined
  - **Recommendation**: Add FR for action keys (s=scoped, g=global, u=unknown, A=accept-all, R=reject-all)

- [ ] **NAV-004**: Focus management not specified
  - **Gap**: Tab order and focus restoration undefined
  - **Recommendation**: Add FR for focus management (list → filter → actions → buttons)

#### 2.4 App Details & Inspection (0/3 requirements)
- [ ] **DETAIL-001**: Detail panel not specified
  - **Gap**: No requirement for app detail view
  - **Recommendation**: Add FR for detail panel showing desktop file fields, suggestion reasoning

- [ ] **DETAIL-002**: WM_CLASS detection trigger not specified
  - **Gap**: No "detect now" action for missing WM_CLASS
  - **Recommendation**: Add FR for detection trigger (d key, integrates with Enhancement 1)

- [ ] **DETAIL-003**: Suggestion reasoning not specified
  - **Gap**: No requirement to explain why classification suggested
  - **Recommendation**: Add FR for reasoning display (matched categories, keywords highlighted)

#### 2.5 Classification Action (0/4 requirements)
- [ ] **ACT-001**: Single-app classification not specified
  - **Gap**: No requirement for classify-as-scoped/global actions
  - **Recommendation**: Add FR for single-app actions with immediate UI feedback

- [ ] **ACT-002**: Bulk classification not specified
  - **Gap**: No "accept all suggestions" action
  - **Recommendation**: Add FR for bulk actions (accept-all, reject-all, apply-to-filtered)

- [ ] **ACT-003**: Undo/redo not specified
  - **Gap**: No undo capability for misclassifications
  - **Recommendation**: Add FR for undo stack (u key, Ctrl+Z) with configurable depth

- [ ] **ACT-004**: Custom pattern creation not specified
  - **Gap**: No way to create pattern rule from wizard
  - **Recommendation**: Add FR for pattern creation action (integrate with Enhancement 3)

#### 2.6 Review & Approval Workflow (0/4 requirements)
- [ ] **WF-001**: Review mode not specified
  - **Gap**: No mode for reviewing suggestions vs changes
  - **Recommendation**: Add FR for mode switching (suggestions → changes → commit)

- [ ] **WF-002**: Diff/changelog not specified
  - **Gap**: No summary of what changed
  - **Recommendation**: Add FR for changes summary (added N scoped, removed M global, modified K patterns)

- [ ] **WF-003**: Save/commit actions not specified
  - **Gap**: No explicit save requirement
  - **Recommendation**: Add FR for save actions (s=save+exit, S=save+continue, q=discard+exit with confirmation)

- [ ] **WF-004**: Validation not specified
  - **Gap**: No duplicate/conflict detection
  - **Recommendation**: Add FR for validation (prevent app in both scoped and global, detect contradictory patterns)

#### 2.7 Integration with Existing System (0/3 requirements)
- [ ] **SYS-001**: app-classes.json update not specified
  - **Gap**: No atomic write requirement
  - **Existing**: General config validation in FR-007 but not wizard-specific
  - **Recommendation**: Add FR for atomic write (temp file + rename) with backup

- [ ] **SYS-002**: Daemon notification not specified
  - **Gap**: No requirement to reload daemon after classification changes
  - **Recommendation**: Add FR for daemon reload trigger via JSON-RPC

- [ ] **SYS-003**: CLI integration not specified
  - **Gap**: Command syntax not defined
  - **Recommendation**: Add FR for `i3pm app-classes wizard [--filter=unclassified] [--auto-accept]`

#### 2.8 Error Handling (0/3 requirements)
- [ ] **ERR-001**: Error dialogs not specified
  - **Gap**: No error dialog layout/actions
  - **Recommendation**: Add FR for error dialog (title, message, retry/skip/abort actions)

- [ ] **ERR-002**: Edge cases not specified
  - **Gap**: Empty list, all-classified scenarios not handled
  - **Recommendation**: Add FR for edge case handling with friendly messages

- [ ] **ERR-003**: Concurrent modification not specified
  - **Gap**: External modification of app-classes.json not detected
  - **Recommendation**: Add FR for file modification detection with reload/merge/overwrite options

#### 2.9 Performance (0/3 requirements)
- [ ] **PERF-001**: UI responsiveness not specified
  - **Gap**: No rendering time requirement
  - **Existing**: FR-SC-016 requires TUI respond in <50ms (general)
  - **Recommendation**: Add FR specifying <16ms render time for 60fps, virtualization for 1000+ apps

- [ ] **PERF-002**: Detection performance not specified
  - **Gap**: No timeout for Xvfb detection in wizard context
  - **Recommendation**: Add FR for max detection time (10s) with parallel detection (max 3 concurrent)

- [ ] **PERF-003**: Memory usage not specified
  - **Gap**: No memory limit for large app lists
  - **Recommendation**: Add FR for <100MB memory footprint even with 1000+ apps

### Recommended Priority Additions

**CRITICAL (must have before wizard implementation)**:
1. Add FR for wizard command syntax (`i3pm app-classes wizard`)
2. Add FR for table display format (columns, widths)
3. Add FR for keyboard navigation (arrow keys, action keys)
4. Add FR for classification actions (single-app, bulk)
5. Add FR for save/commit workflow
6. Add FR for app-classes.json atomic update

**HIGH (needed for production quality)**:
1. Add FR for color scheme and icons (visual hierarchy)
2. Add FR for detail panel and reasoning display
3. Add FR for undo/redo capability
4. Add FR for validation (duplicates, conflicts)
5. Add FR for error dialogs and edge cases
6. Add FR for daemon notification after changes

**MEDIUM (enhances usability)**:
1. Add FR for filtering and sorting
2. Add FR for confidence score visualization
3. Add FR for focus management
4. Add FR for concurrent modification detection
5. Add FR for performance constraints (virtualization, memory)

---

## Enhancement 3: Pattern-Based Rules

### Current State
**Minimal: 2%** - FR-009 mentions "configurable classification file" but no pattern syntax specified.

### Existing Coverage

**From FR-009**:
- ✅ Configurable classification file exists (`app-classes.json`)
- ❌ No pattern syntax defined (only explicit lists)

### Critical Gaps

#### 3.1 Pattern Syntax (0/4 requirements)
- [ ] **SYN-001**: Glob pattern syntax not specified
  - **Gap**: No requirement for `*`, `?`, `[abc]`, `{foo,bar}` operators
  - **Recommendation**: Add FR defining supported glob syntax (fnmatch-compatible)

- [ ] **SYN-002**: Regex pattern syntax not specified
  - **Gap**: No requirement for regex patterns
  - **Recommendation**: Add FR defining regex flavor (Python `re` module), supported flags

- [ ] **SYN-003**: Pattern prefix not specified
  - **Gap**: No way to distinguish glob from regex
  - **Recommendation**: Add FR for pattern type prefixes (`glob:pwa-*`, `regex:^pwa-.*$`) with default=glob

- [ ] **SYN-004**: Pattern delimiter not specified
  - **Gap**: No format for pattern → classification mapping
  - **Recommendation**: Add FR for JSON format: `{"pwa-*": "global", "terminal-*": "scoped"}`

#### 3.2 Pattern Storage (0/3 requirements)
- [ ] **STOR-001**: Storage location not specified
  - **Gap**: No requirement for where patterns stored
  - **Existing**: FR-009 references `app-classes.json` but not pattern structure
  - **Recommendation**: Add FR extending app-classes.json with `class_patterns` key

- [ ] **STOR-002**: Pattern format not specified
  - **Gap**: No JSON schema for pattern rules
  - **Recommendation**: Add FR defining schema:
    ```json
    {
      "class_patterns": {
        "pwa-*": {"classification": "global", "priority": 50, "description": "PWAs are global", "enabled": true}
      }
    }
    ```

- [ ] **STOR-003**: Pattern migration not specified
  - **Gap**: No migration path from v1 config (explicit lists only)
  - **Recommendation**: Add FR for backward compatibility and migration tool

#### 3.3 Pattern Matching (0/3 requirements)
- [ ] **MATCH-001**: Matching algorithm not specified
  - **Gap**: No precedence order defined
  - **Recommendation**: Add FR for matching order: exact > specific pattern > general pattern > default

- [ ] **MATCH-002**: Case sensitivity not specified
  - **Gap**: Should `PWA-*` match `pwa-youtube`?
  - **Recommendation**: Add FR for case-insensitive matching by default with opt-in case-sensitive flag

- [ ] **MATCH-003**: Performance not specified
  - **Gap**: No requirement for matching speed
  - **Recommendation**: Add FR for <1ms matching time per window, pattern compilation caching

#### 3.4 Pattern Precedence (0/3 requirements)
- [ ] **PREC-001**: Explicit priority not specified
  - **Gap**: No priority value system
  - **Recommendation**: Add FR for priority value (0-100, default 50) with highest priority wins

- [ ] **PREC-002**: Implicit precedence not specified
  - **Gap**: What if pattern contradicts explicit scoped_classes list?
  - **Recommendation**: Add FR for precedence order: explicit lists > patterns > heuristics

- [ ] **PREC-003**: Conflict resolution not specified
  - **Gap**: Multiple patterns match same class
  - **Recommendation**: Add FR for conflict resolution (highest priority wins, warn on equal priority conflicts)

#### 3.5 Pattern Validation (0/3 requirements)
- [ ] **VAL-001**: Syntax validation not specified
  - **Gap**: No requirement to validate glob/regex syntax
  - **Recommendation**: Add FR for validation on add/edit with clear error messages

- [ ] **VAL-002**: Semantic validation not specified
  - **Gap**: Circular patterns, unreachable patterns not detected
  - **Recommendation**: Add FR for semantic validation (detect `*` pattern overriding all others)

- [ ] **VAL-003**: Validation timing not specified
  - **Gap**: When does validation occur?
  - **Recommendation**: Add FR for validation on add, on save, and on daemon load with fail-fast behavior

#### 3.6 Pattern Management CLI (0/4 requirements)
- [ ] **CLI-001**: Pattern add not specified
  - **Gap**: No command to add patterns
  - **Recommendation**: Add FR for `i3pm app-classes add-pattern 'pwa-*' --classification=global --priority=50`

- [ ] **CLI-002**: Pattern list not specified
  - **Gap**: No command to list patterns
  - **Recommendation**: Add FR for `i3pm app-classes list-patterns [--classification=global] [--enabled-only]`

- [ ] **CLI-003**: Pattern remove not specified
  - **Gap**: No command to remove patterns
  - **Recommendation**: Add FR for `i3pm app-classes remove-pattern 'pwa-*' [--force]`

- [ ] **CLI-004**: Pattern edit not specified
  - **Gap**: No command to edit patterns
  - **Recommendation**: Add FR for `i3pm app-classes edit-pattern 'pwa-*' --priority=60 --description="Updated"`

#### 3.7 Pattern Testing (0/3 requirements)
- [ ] **TEST-001**: Pattern test not specified
  - **Gap**: No way to test pattern against class name
  - **Recommendation**: Add FR for `i3pm app-classes test-pattern 'pwa-youtube' --verbose`

- [ ] **TEST-002**: Coverage analysis not specified
  - **Gap**: No way to see which apps matched/unmatched by patterns
  - **Recommendation**: Add FR for coverage report showing matched/unmatched apps

- [ ] **TEST-003**: Debug logging not specified
  - **Gap**: No debug output for pattern matching
  - **Recommendation**: Add FR for `--debug-patterns` mode logging all pattern evaluations

#### 3.8 TUI Wizard Integration (0/3 requirements)
- [ ] **WIZ-001**: Pattern creation from wizard not specified
  - **Gap**: No "create pattern from this app" action in wizard
  - **Recommendation**: Add FR for wizard action (p key) to create pattern based on current app

- [ ] **WIZ-002**: Pattern visualization not specified
  - **Gap**: Wizard doesn't show which apps matched by patterns
  - **Recommendation**: Add FR for "matched by pattern: pwa-*" indicator in wizard app list

- [ ] **WIZ-003**: Bulk pattern application not specified
  - **Gap**: No way to apply pattern to selected apps in wizard
  - **Recommendation**: Add FR for bulk pattern creation from multi-selected apps

#### 3.9 Migration & Compatibility (0/3 requirements)
- [ ] **MIG-001**: Config migration not specified
  - **Gap**: No migration from v1 (explicit lists) to v2 (patterns)
  - **Recommendation**: Add FR for migration tool suggesting patterns for common prefixes

- [ ] **MIG-002**: Version compatibility not specified
  - **Gap**: No config version field
  - **Recommendation**: Add FR for version field in app-classes.json with version upgrade logic

- [ ] **MIG-003**: Daemon compatibility not specified
  - **Gap**: Daemon must support pattern matching
  - **Recommendation**: Add FR for daemon pattern parsing and fallback if unsupported

### Recommended Priority Additions

**CRITICAL (must have before pattern implementation)**:
1. Add FR for glob pattern syntax (SYN-001)
2. Add FR for pattern storage format (STOR-001, STOR-002)
3. Add FR for matching algorithm (MATCH-001)
4. Add FR for CLI pattern management (CLI-001 through CLI-004)
5. Add FR for daemon pattern matching support

**HIGH (needed for production quality)**:
1. Add FR for regex pattern syntax (SYN-002, SYN-003)
2. Add FR for pattern precedence and conflict resolution (PREC-001 through PREC-003)
3. Add FR for pattern validation (VAL-001, VAL-003)
4. Add FR for pattern testing (TEST-001)
5. Add FR for config migration (MIG-001, MIG-002)

**MEDIUM (enhances usability)**:
1. Add FR for case sensitivity rules (MATCH-002)
2. Add FR for performance constraints (MATCH-003)
3. Add FR for semantic validation (VAL-002)
4. Add FR for coverage analysis (TEST-002)
5. Add FR for wizard integration (WIZ-001 through WIZ-003)

---

## Enhancement 4: Real-Time Window Inspection

### Current State
**Minimal: 3%** - FR-047 mentions "monitoring tool" but not window inspection specifically.

### Existing Coverage

**From FR-047**:
- ✅ Real-time monitoring tool exists showing daemon state and events
- ❌ No interactive window selection specified
- ❌ No property inspection interface specified

### Critical Gaps

#### 4.1 Window Selection (0/3 requirements)
- [ ] **SEL-001**: Selection methods not specified
  - **Gap**: No requirement for mouse click or keyboard selection
  - **Recommendation**: Add FR for `i3pm app-classes inspect` with selection modes (--click, --focused, --id)

- [ ] **SEL-002**: Cursor interaction not specified
  - **Gap**: No visual feedback during selection
  - **Recommendation**: Add FR for cursor change to crosshair, hover preview with window highlight

- [ ] **SEL-003**: Multi-window selection not specified
  - **Gap**: Can only inspect one window at a time
  - **Recommendation**: Add FR for multi-window mode (Ctrl+click) with comparison view

#### 4.2 Property Inspection (0/3 requirements)
- [ ] **PROP-001**: Inspected properties not specified
  - **Gap**: Which properties should be displayed?
  - **Recommendation**: Add FR for property list: WM_CLASS, WM_NAME, WM_WINDOW_ROLE, instance, type, _NET_WM_PID, con_id, marks, workspace, output

- [ ] **PROP-002**: Display format not specified
  - **Gap**: No table or tree view specified
  - **Recommendation**: Add FR for rich table format with copy-to-clipboard per property

- [ ] **PROP-003**: Property refresh not specified
  - **Gap**: No real-time updates for changing properties (e.g., title changes)
  - **Recommendation**: Add FR for auto-refresh (1s interval) with manual refresh (F5) and change highlighting

#### 4.3 Classification Status Display (0/3 requirements)
- [ ] **STATUS-001**: Current classification not specified
  - **Gap**: No requirement to show scoped/global/unknown status
  - **Recommendation**: Add FR for classification status with source (explicit, pattern, heuristic, unknown)

- [ ] **STATUS-002**: Suggestion display not specified
  - **Gap**: No requirement to show suggested classification
  - **Recommendation**: Add FR for suggestion with reasoning (matched categories, keywords)

- [ ] **STATUS-003**: Related apps not specified
  - **Gap**: No way to see other windows with same WM_CLASS
  - **Recommendation**: Add FR for "related apps" section showing all windows with same class/instance

#### 4.4 Interactive Classification (0/3 requirements)
- [ ] **ICLASS-001**: Direct classification not specified
  - **Gap**: No way to classify window from inspector
  - **Recommendation**: Add FR for action keys (s=scoped, g=global, u=unclassify, Del=remove)

- [ ] **ICLASS-002**: Pattern creation not specified
  - **Gap**: No "create pattern from this window" action
  - **Recommendation**: Add FR for pattern creation (p key) with suggested pattern based on WM_CLASS

- [ ] **ICLASS-003**: Bulk actions not specified
  - **Gap**: No "apply to all with same WM_CLASS"
  - **Recommendation**: Add FR for bulk actions (S=scoped-all-same-class, G=global-all-same-class) with confirmation

#### 4.5 Real-Time Monitoring (0/3 requirements)
- [ ] **MON-001**: Event subscription not specified
  - **Gap**: No requirement to subscribe to window events for selected window
  - **Recommendation**: Add FR for i3 IPC subscription (window::title, window::mark, window::move)

- [ ] **MON-002**: Update triggering not specified
  - **Gap**: When does inspector refresh?
  - **Recommendation**: Add FR for auto-update on focus change, property change, with throttling (max 10Hz)

- [ ] **MON-003**: Live update display not specified
  - **Gap**: No visual indication of value changes
  - **Recommendation**: Add FR for change highlighting (flash, bold, color) with change history log

#### 4.6 Command Invocation (0/3 requirements)
- [ ] **CMD-001**: CLI invocation not specified
  - **Gap**: Command syntax undefined
  - **Recommendation**: Add FR for `i3pm app-classes inspect [--click|--focused|--id=<winid>] [--format=table|json]`

- [ ] **CMD-002**: Keybinding integration not specified
  - **Gap**: No i3 keybinding example
  - **Recommendation**: Add FR for i3 config integration: `bindsym $mod+i exec i3pm app-classes inspect --click`

- [ ] **CMD-003**: Scripting integration not specified
  - **Gap**: No non-interactive mode for scripts
  - **Recommendation**: Add FR for non-interactive mode with JSON output for scripting

#### 4.7 Display Modes (0/3 requirements)
- [ ] **MODE-001**: TUI display not specified
  - **Gap**: No requirement for Textual-based inspector
  - **Recommendation**: Add FR for TUI mode with properties panel, actions panel, keyboard shortcuts

- [ ] **MODE-002**: CLI display not specified
  - **Gap**: Output format for CLI mode undefined
  - **Recommendation**: Add FR for CLI output formats (table, JSON, YAML) with --format option

- [ ] **MODE-003**: Notification display not specified
  - **Gap**: No requirement for notification integration
  - **Recommendation**: Add FR for notification showing window class with click-to-classify action

#### 4.8 Window Highlighting (0/3 requirements)
- [ ] **HIGH-001**: Highlight visual not specified
  - **Gap**: No requirement to visually highlight selected window
  - **Recommendation**: Add FR for window border highlight (red, 3px, 2s duration or until dismissed)

- [ ] **HIGH-002**: Multi-monitor highlight not specified
  - **Gap**: Highlight may not be visible on different monitor
  - **Recommendation**: Add FR for cross-monitor highlight with focus/bring-to-front option

- [ ] **HIGH-003**: Accessibility not specified
  - **Gap**: Colorblind users may not see highlight
  - **Recommendation**: Add FR for customizable highlight color with high-contrast option

#### 4.9 Error Handling (0/3 requirements)
- [ ] **ERR-W-001**: Selection timeout not specified
  - **Gap**: What if user doesn't click within reasonable time?
  - **Recommendation**: Add FR for 30s timeout with default-to-focused fallback

- [ ] **ERR-W-002**: Invalid window handling not specified
  - **Gap**: What if window closes during inspection?
  - **Recommendation**: Add FR for destroyed window detection with graceful error message

- [ ] **ERR-W-003**: Permission errors not specified
  - **Gap**: What if X11/i3 IPC permissions denied?
  - **Recommendation**: Add FR for permission error handling with clear remediation steps

#### 4.10 Integration (0/3 requirements)
- [ ] **INT-W-001**: Immediate classification not specified
  - **Gap**: After classifying, is UI updated immediately?
  - **Recommendation**: Add FR for immediate UI update + daemon notification (no reload required)

- [ ] **INT-W-002**: Classification persistence not specified
  - **Gap**: Is classification saved to app-classes.json?
  - **Recommendation**: Add FR for atomic write to app-classes.json with backup

- [ ] **INT-W-003**: Conflict resolution not specified
  - **Gap**: What if window class already classified differently?
  - **Recommendation**: Add FR for conflict detection with override confirmation prompt

### Recommended Priority Additions

**CRITICAL (must have before inspector implementation)**:
1. Add FR for window selection modes (SEL-001)
2. Add FR for property inspection list and format (PROP-001, PROP-002)
3. Add FR for classification status display (STATUS-001)
4. Add FR for direct classification actions (ICLASS-001)
5. Add FR for CLI command syntax (CMD-001)

**HIGH (needed for production quality)**:
1. Add FR for cursor interaction and visual feedback (SEL-002)
2. Add FR for property auto-refresh (PROP-003)
3. Add FR for suggestion display (STATUS-002)
4. Add FR for TUI display mode (MODE-001)
5. Add FR for window highlighting (HIGH-001)
6. Add FR for integration (INT-W-001, INT-W-002)

**MEDIUM (enhances usability)**:
1. Add FR for multi-window selection (SEL-003)
2. Add FR for related apps display (STATUS-003)
3. Add FR for pattern creation (ICLASS-002)
4. Add FR for real-time monitoring (MON-001 through MON-003)
5. Add FR for error handling (ERR-W-001 through ERR-W-003)

---

## Cross-Enhancement Integration

### Current State
**Partial: 17%** - Some shared concerns addressed by existing FR-058 through FR-072.

### Existing Coverage

- ✅ FR-058: Unified command namespace (`i3pm`)
- ✅ FR-067: CLI subcommands for all operations
- ✅ FR-072: Shell completion scripts
- ✅ FR-007: JSON schema validation (general config validation)

### Critical Gaps

#### Shared Configuration (0/2 requirements)
- [ ] **CONF-001**: Config format consistency not specified
  - **Gap**: Pattern rules vs explicit lists may have different formats
  - **Recommendation**: Add FR for unified JSON schema covering patterns, lists, wizard state

- [ ] **CONF-002**: Config validation not specified for enhancements
  - **Gap**: FR-007 covers project configs but not app-classes.json
  - **Recommendation**: Add FR extending FR-007 to cover app-classes.json with pattern validation

#### Shared CLI Integration (0/2 requirements)
- [ ] **CLI-X-001**: Command hierarchy for app-classes not fully specified
  - **Existing**: FR-067 mentions subcommands but not detailed hierarchy
  - **Recommendation**: Add FR defining full command tree:
    ```
    i3pm app-classes
      ├── list                  (existing in FR)
      ├── add/remove/check      (existing in FR)
      ├── discover              (existing in FR)
      ├── suggest/auto-classify (existing in FR)
      ├── wizard                (NEW - Enhancement 2)
      ├── add-pattern/list-patterns/remove-pattern (NEW - Enhancement 3)
      ├── inspect               (NEW - Enhancement 4)
      └── detect --isolated     (NEW - Enhancement 1)
    ```

- [ ] **CLI-X-002**: Shared CLI options not fully specified
  - **Existing**: Some options implied but not formalized
  - **Recommendation**: Add FR for consistent options across all app-classes subcommands:
    - `--verbose` for detailed output
    - `--json` for machine-readable output
    - `--dry-run` for preview without changes

#### Shared Daemon Integration (0/2 requirements)
- [ ] **DAEMON-001**: Reload requirements not specified for app-classes changes
  - **Gap**: FR-024 covers project switches but not app-classes updates
  - **Recommendation**: Add FR for daemon reload trigger after app-classes.json modification

- [ ] **DAEMON-002**: Daemon communication for enhancements not specified
  - **Gap**: JSON-RPC protocol specified (FR-023) but not app-classes-specific messages
  - **Recommendation**: Add FR defining JSON-RPC methods:
    - `get_classification(window_class) -> {classification, source, confidence}`
    - `reload_app_classes() -> {success, errors}`
    - `test_pattern(pattern, window_class) -> {matches, classification}`

#### Shared UX (0/3 requirements)
- [ ] **UX-X-001**: Terminology consistency not specified
  - **Gap**: "scoped" vs "project-scoped", "global" vs "cross-project" used inconsistently
  - **Recommendation**: Add FR defining canonical terms with glossary

- [ ] **UX-X-002**: Keybinding consistency not specified
  - **Gap**: No requirement for consistent keys across TUI modes
  - **Recommendation**: Add FR for keybinding scheme (s=scoped, g=global, q=quit consistent across all TUI screens)

- [ ] **UX-X-003**: Color scheme consistency not specified
  - **Gap**: No requirement for semantic colors across CLI/TUI/notifications
  - **Recommendation**: Add FR for color palette (scoped=green, global=blue, error=red, warning=yellow consistent everywhere)

### Recommended Priority Additions

**CRITICAL (must have for coherent enhancements)**:
1. Add FR for app-classes command hierarchy (CLI-X-001)
2. Add FR for daemon reload trigger (DAEMON-001)
3. Add FR for shared CLI options (CLI-X-002)

**HIGH (needed for consistency)**:
1. Add FR for JSON-RPC methods for app-classes (DAEMON-002)
2. Add FR for terminology glossary (UX-X-001)
3. Add FR for keybinding scheme (UX-X-002)

**MEDIUM (polish)**:
1. Add FR for config format consistency (CONF-001)
2. Add FR for app-classes validation (CONF-002)
3. Add FR for color scheme (UX-X-003)

---

## Testing & Documentation

### Current State
**Partial: 31%** - FR-046 through FR-049 cover automated testing, FR-072 covers shell completion.

### Existing Coverage

- ✅ FR-046: Automated test suite exists
- ✅ FR-047: Real-time monitoring tool exists
- ✅ FR-048: Test runner with diagnostics
- ✅ FR-049: Diagnostic mode for bug reports
- ✅ FR-072: Shell completion scripts
- ✅ SC-007: Test suite runs in <60s
- ✅ SC-009: 90% of issues diagnosable with tools
- ✅ SC-015 through SC-020: UX metrics including discoverability

### Critical Gaps

#### Unit Test Requirements (0/2 requirements)
- [ ] **UNIT-001**: Testability for enhancements not specified
  - **Gap**: No requirement for isolated testing of Xvfb detection, pattern matching, etc.
  - **Recommendation**: Add FR for test isolation (mock Xvfb, mock i3 IPC, fixture data)

- [ ] **UNIT-002**: Coverage requirements not specified
  - **Gap**: No coverage threshold for new code
  - **Recommendation**: Add FR for 80% coverage minimum for enhancements with exclusions for interactive UI

#### Integration Test Requirements (0/2 requirements)
- [ ] **INT-T-001**: Integration scenarios for enhancements not specified
  - **Gap**: FR-046 covers project lifecycle but not app discovery workflows
  - **Recommendation**: Add FR for integration test scenarios:
    - Xvfb detection → classification → daemon reload → window marking
    - Wizard classification → pattern creation → pattern matching
    - Inspector classification → app-classes update → daemon reload

- [ ] **INT-T-002**: Test automation for enhancements not specified
  - **Gap**: No CI integration specified for new tests
  - **Recommendation**: Add FR for CI integration with pytest-textual for TUI testing

#### User Acceptance Test Requirements (0/2 requirements)
- [ ] **UAT-001**: UAT criteria for enhancements not specified
  - **Gap**: User stories exist for core system but not enhancements
  - **Recommendation**: Add user acceptance criteria for each enhancement (see recommendations below)

- [ ] **UAT-002**: UX testing not specified
  - **Gap**: No usability testing requirement
  - **Recommendation**: Add FR for usability testing (5 users complete wizard workflow without assistance)

#### User Documentation Requirements (0/2 requirements)
- [ ] **DOC-U-001**: User guide for enhancements not specified
  - **Gap**: No tutorial for wizard, patterns, inspector
  - **Recommendation**: Add FR for user guide sections:
    - "Classifying Apps with the Wizard"
    - "Creating Pattern Rules for Auto-Classification"
    - "Inspecting Windows in Real-Time"
    - "Troubleshooting App Classification"

- [ ] **DOC-U-002**: Troubleshooting guide not specified
  - **Gap**: No common issues documentation
  - **Recommendation**: Add FR for troubleshooting section:
    - "Xvfb detection fails" → install dependencies
    - "Pattern doesn't match" → test with `test-pattern` command
    - "Window not auto-classified" → check app-classes.json, daemon logs

#### Developer Documentation Requirements (0/2 requirements)
- [ ] **DOC-D-001**: API docs for enhancements not specified
  - **Gap**: No docstrings requirement for new modules
  - **Recommendation**: Add FR for API documentation (Google-style docstrings for all public functions in app_discovery.py, pattern matching, inspection)

- [ ] **DOC-D-002**: Architecture docs for enhancements not specified
  - **Gap**: No architecture diagram for app classification system
  - **Recommendation**: Add FR for architecture documentation:
    - App discovery flow diagram (desktop files → parsing → heuristics → detection)
    - Pattern matching algorithm diagram (matching order, precedence, caching)
    - Wizard state machine diagram

### Recommended Priority Additions

**CRITICAL (must have for quality release)**:
1. Add FR for integration test scenarios (INT-T-001)
2. Add FR for user guide sections (DOC-U-001)
3. Add FR for UAT criteria for each enhancement (UAT-001)

**HIGH (needed for maintainability)**:
1. Add FR for unit test isolation (UNIT-001)
2. Add FR for API documentation (DOC-D-001)
3. Add FR for troubleshooting guide (DOC-U-002)

**MEDIUM (improves quality)**:
1. Add FR for coverage requirements (UNIT-002)
2. Add FR for CI integration (INT-T-002)
3. Add FR for architecture docs (DOC-D-002)
4. Add FR for UX testing (UAT-002)

---

## Recommended UAT Criteria

### Enhancement 1: Xvfb Detection

**UAT-XVF-001**: Isolated Detection Success
- **Given** user has Xvfb installed, **When** user runs `i3pm app-classes detect --isolated firefox`, **Then** system launches Firefox in Xvfb, detects WM_CLASS "firefox" within 10s, displays result, and cleans up process

**UAT-XVF-002**: Dependency Missing Graceful Degradation
- **Given** user does not have Xvfb installed, **When** user runs `i3pm app-classes detect --isolated firefox`, **Then** system shows error "xvfb-run not found. Install with: nix-env -iA nixpkgs.xvfb", falls back to guess_wm_class

**UAT-XVF-003**: Bulk Detection
- **Given** user has 10 apps without WM_CLASS, **When** user runs `i3pm app-classes detect --isolated --all-missing`, **Then** system detects all 10 apps in parallel (max 3 concurrent), shows progress, completes in <60s

### Enhancement 2: TUI Wizard

**UAT-WIZ-001**: First-Time Wizard Completion
- **Given** user has never classified apps, **When** user runs `i3pm app-classes wizard`, **Then** user sees 15 discovered apps, uses arrow keys to navigate, presses 's' to classify as scoped, 'g' for global, completes classification in <3 minutes

**UAT-WIZ-002**: Bulk Accept Suggestions
- **Given** wizard shows 10 apps with suggestions (80% confidence), **When** user presses 'A' to accept all, **Then** all 10 apps classified according to suggestions, saved to app-classes.json, daemon reloaded, confirmation shown

**UAT-WIZ-003**: Undo Misclassification
- **Given** user accidentally classified Firefox as scoped, **When** user presses 'u' for undo, **Then** Firefox classification reverted to previous state (unknown), user can reclassify correctly

### Enhancement 3: Pattern Rules

**UAT-PAT-001**: Create Pattern Rule
- **Given** user has 5 PWAs (pwa-youtube, pwa-spotify, etc.), **When** user runs `i3pm app-classes add-pattern 'pwa-*' --classification=global`, **Then** all 5 PWAs automatically classified as global, pattern saved, daemon reloaded

**UAT-PAT-002**: Test Pattern Matching
- **Given** user created pattern `terminal-*` → scoped, **When** user runs `i3pm app-classes test-pattern 'terminal-alacritty'`, **Then** system shows "✓ Matches pattern 'terminal-*' → scoped (priority: 50)"

**UAT-PAT-003**: Pattern Conflict Detection
- **Given** user has pattern `*` → global (priority 10) and `Code` in scoped_classes, **When** user launches VS Code, **Then** system classifies as scoped (explicit list wins over pattern), no error

### Enhancement 4: Window Inspection

**UAT-INS-001**: Click-to-Inspect
- **Given** user has unknown window open, **When** user runs `i3pm app-classes inspect --click`, cursor changes to crosshair, user clicks window, **Then** inspector shows WM_CLASS, classification status, suggestion, allows classifying with 's' key

**UAT-INS-002**: Inspect Focused Window
- **Given** user focuses on VS Code window, **When** user presses Win+I keybinding (configured in i3), **Then** inspector opens immediately showing VS Code properties, current classification (scoped), source (explicit list)

**UAT-INS-003**: Bulk Classify Same Class
- **Given** user inspects Chrome window, sees 3 other Chrome windows with same class, **When** user presses 'G' to classify all as global, **Then** all 4 Chrome windows classified as global, saved, daemon reloaded

---

## Summary of Recommendations

### Immediate Actions (Before Implementation)

1. **Extend spec.md with 420 missing requirements** organized by enhancement
2. **Add 15 user stories** to User Scenarios section (3-4 per enhancement)
3. **Add 50+ Functional Requirements** to Requirements section:
   - FR-073 through FR-100: Xvfb Detection (28 FRs)
   - FR-101 through FR-150: TUI Wizard (50 FRs)
   - FR-151 through FR-180: Pattern Rules (30 FRs)
   - FR-181 through FR-210: Window Inspection (30 FRs)
   - FR-211 through FR-220: Cross-Enhancement Integration (10 FRs)
4. **Add 10 Success Criteria** (SC-021 through SC-030) for enhancements
5. **Add 12 UAT scenarios** to validate each enhancement

### Phased Approach

**Phase 1: Foundation (Week 1)**
- Write all CRITICAL requirements (marked above)
- Write UAT scenarios
- Update tasks.md with new tasks derived from requirements

**Phase 2: Quality (Week 2)**
- Write all HIGH requirements
- Write user documentation outline
- Write test plan

**Phase 3: Polish (Week 3)**
- Write all MEDIUM requirements
- Complete documentation
- Review and validate all requirements against checklist

### Estimated Effort

- **Requirements Writing**: 16-24 hours (420 requirements @ 2-3 min each)
- **User Stories**: 4-6 hours (15 stories with scenarios)
- **UAT Scenarios**: 2-3 hours (12 scenarios with Given/When/Then)
- **Documentation Planning**: 2-3 hours (outline structure)
- **Review & Validation**: 4-6 hours (check against checklist)

**Total**: 28-42 hours of requirements work before implementation begins

### Risk Mitigation

**Risk**: Requirements overwhelming, delay implementation
- **Mitigation**: Implement incrementally, one enhancement at a time (Xvfb → Patterns → Wizard → Inspector)

**Risk**: Requirements drift from implementation
- **Mitigation**: Validate requirements against existing code (`app_discovery.py` already has foundation)

**Risk**: Over-specification reduces flexibility
- **Mitigation**: Use "SHOULD" vs "MUST" appropriately, allow implementation discretion for UX details

---

## Next Steps

1. **Review this gap analysis** with stakeholders
2. **Prioritize enhancements** (recommend: Patterns first, simplest to implement)
3. **Write CRITICAL requirements** for chosen enhancement (start with Enhancement 3: Pattern Rules)
4. **Update tasks.md** with implementation tasks derived from requirements
5. **Begin implementation** once requirements validated

**Estimated time to implementation readiness**: 1-2 weeks of requirements work

---

**End of Gap Analysis**
