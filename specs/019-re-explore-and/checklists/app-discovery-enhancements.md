# Requirements Quality Checklist: App Discovery Enhancements

**Feature**: i3pm App Discovery & Classification System Enhancements
**Scope**: Four enhancements to improve app discovery automation and UX
**Depth**: Comprehensive (Option C)
**Created**: 2025-10-21

---

## Enhancement 1: Xvfb Detection Activation

### 1.1 Dependency Management Requirements

- [ ] **DEP-001**: Are xvfb-run installation requirements explicitly specified with version constraints?
  - Are alternative packages documented (e.g., xvfb, Xvfb)?
  - Is minimum/maximum version compatibility range defined?
  - Are NixOS-specific installation paths documented?

- [ ] **DEP-002**: Are xdotool dependency requirements explicitly specified?
  - Is the required version documented?
  - Are alternative tools (xwininfo, wmctrl) considered as fallbacks?
  - Is the tool availability check requirement defined?

- [ ] **DEP-003**: Are xprop dependency requirements explicitly specified?
  - Is the required version documented?
  - Is the WM_CLASS property extraction requirement defined?
  - Are alternative property extraction methods documented?

- [ ] **DEP-004**: Are dependency availability check requirements defined?
  - Is the pre-execution validation requirement specified?
  - Is the error message format for missing dependencies documented?
  - Are graceful degradation requirements specified when dependencies unavailable?

### 1.2 Isolation Execution Requirements

- [ ] **ISO-001**: Are Xvfb display number allocation requirements defined?
  - Is the auto-allocation algorithm specified (e.g., `xvfb-run -a`)?
  - Are display number collision handling requirements documented?
  - Is the display number range constraint specified?

- [ ] **ISO-002**: Are Xvfb framebuffer size requirements specified?
  - Is the default resolution documented (e.g., 1920x1080)?
  - Are resolution customization requirements defined?
  - Is the color depth requirement specified (e.g., 24-bit)?

- [ ] **ISO-003**: Are app launch timeout requirements measurable?
  - Is the default timeout value specified (e.g., 10 seconds)?
  - Is the timeout customization interface defined?
  - Are timeout extension requirements for slow apps documented?

- [ ] **ISO-004**: Are window appearance detection requirements defined?
  - Is the polling interval specified (e.g., 100ms)?
  - Is the maximum polling count documented?
  - Are alternative detection methods (i3 IPC subscribe vs polling) compared?

### 1.3 Window Class Extraction Requirements

- [ ] **EXT-001**: Are WM_CLASS property extraction requirements specified?
  - Is the xprop command syntax documented?
  - Is the output parsing algorithm defined?
  - Are malformed WM_CLASS handling requirements specified?

- [ ] **EXT-002**: Are window ID to WM_CLASS mapping requirements defined?
  - Is the xdotool window search algorithm specified?
  - Are multi-window handling requirements documented?
  - Is the "first match" vs "all matches" behavior specified?

- [ ] **EXT-003**: Are extraction failure handling requirements defined?
  - Is the retry logic specified (count, interval)?
  - Are fallback extraction methods documented?
  - Is the failure reporting format specified?

### 1.4 Cleanup & Safety Requirements

- [ ] **CLN-001**: Are process termination requirements specified?
  - Is the graceful shutdown timeout defined (e.g., SIGTERM + 1s wait)?
  - Is the force kill requirement documented (SIGKILL)?
  - Are zombie process prevention requirements specified?

- [ ] **CLN-002**: Are temporary resource cleanup requirements defined?
  - Are Xvfb lock file cleanup requirements specified?
  - Are temporary socket cleanup requirements documented?
  - Is the cleanup verification requirement defined?

- [ ] **CLN-003**: Are error state cleanup requirements specified?
  - Are cleanup requirements defined for timeout scenarios?
  - Are cleanup requirements defined for crash scenarios?
  - Are cleanup requirements defined for user interruption (SIGINT)?

### 1.5 Fallback Strategy Requirements

- [ ] **FALL-001**: Are fallback requirements defined when Xvfb unavailable?
  - Is the fallback to guess_wm_class requirement specified?
  - Is the fallback to manual input requirement defined?
  - Is the fallback to skip detection requirement documented?

- [ ] **FALL-002**: Are fallback requirements defined when detection fails?
  - Is the retry count requirement specified?
  - Are alternative detection methods (launch in real X server) documented?
  - Is the user notification requirement specified?

- [ ] **FALL-003**: Are detection success criteria requirements defined?
  - Is "successful detection" unambiguously defined?
  - Are partial success scenarios documented (e.g., window appeared but no WM_CLASS)?
  - Is the confidence score requirement specified (if applicable)?

### 1.6 Integration Requirements

- [ ] **INT-001**: Are CLI integration requirements specified?
  - Is the `i3pm app-classes detect --isolated` command syntax defined?
  - Are CLI option requirements documented (timeout, fallback, dry-run)?
  - Is the CLI output format requirement specified?

- [ ] **INT-002**: Are bulk detection requirements defined?
  - Is the batch processing interface specified?
  - Are parallel vs sequential execution requirements documented?
  - Is the progress reporting requirement defined?

- [ ] **INT-003**: Are caching requirements defined?
  - Is the detection result caching requirement specified?
  - Is the cache invalidation strategy documented?
  - Is the cache storage location requirement defined?

### 1.7 UX & Observability Requirements

- [ ] **UX-001**: Are progress indication requirements defined?
  - Is the progress message format specified for each detection phase?
  - Are percentage completion requirements documented?
  - Is the ETA calculation requirement specified?

- [ ] **UX-002**: Are verbose logging requirements defined?
  - Is the log level hierarchy specified (ERROR, WARN, INFO, DEBUG)?
  - Are Xvfb stdout/stderr capture requirements documented?
  - Is the log file location requirement specified?

- [ ] **UX-003**: Are error message requirements defined?
  - Is the error message format specified for each failure mode?
  - Are actionable remediation suggestions required in error messages?
  - Are error codes defined for programmatic error handling?

---

## Enhancement 2: Interactive Classification Wizard (TUI)

### 2.1 Discovery & Data Loading Requirements

- [ ] **LOAD-001**: Are app discovery trigger requirements defined?
  - Is the `i3pm app-classes wizard` command syntax specified?
  - Are auto-discovery vs manual app list requirements documented?
  - Is the discovery progress indication requirement specified?

- [ ] **LOAD-002**: Are app filtering requirements defined?
  - Is the "apps without WM_CLASS" filter requirement specified?
  - Are "unclassified apps" filter requirements documented?
  - Is the custom filter syntax requirement defined?

- [ ] **LOAD-003**: Are app sorting requirements defined?
  - Is the default sort order specified (alphabetical, category, confidence)?
  - Are custom sort column requirements documented?
  - Is the sort direction toggle requirement specified?

### 2.2 Presentation & Visual Hierarchy Requirements

- [ ] **PRES-001**: Are app list display requirements specified?
  - Is the table column layout defined (Name, Exec, WM Class, Suggestion, Status)?
  - Are column width requirements documented (fixed, percentage, auto)?
  - Is the row height requirement specified?

- [ ] **PRES-002**: Are color scheme requirements defined?
  - Are semantic color requirements specified (scoped=green, global=blue, unknown=yellow)?
  - Are accessibility requirements documented (colorblind-friendly, high contrast)?
  - Is the theme customization requirement specified?

- [ ] **PRES-003**: Are icon/glyph requirements defined?
  - Are status indicator glyphs specified (✓, ✗, ?, ⚠)?
  - Are classification type indicators documented (🔒 scoped, 🌍 global)?
  - Is the Unicode vs ASCII fallback requirement specified?

- [ ] **PRES-004**: Are confidence score visualization requirements defined?
  - Is the confidence score display format specified (percentage, stars, bar)?
  - Are confidence threshold requirements documented (high >80%, medium 50-80%, low <50%)?
  - Is the confidence calculation algorithm requirement referenced?

### 2.3 Keyboard Navigation Requirements

- [ ] **NAV-001**: Are list navigation key bindings defined?
  - Are up/down arrow requirements specified?
  - Are Page Up/Page Down requirements documented?
  - Are Home/End key requirements specified?
  - Are Vim-style keybindings (j/k) requirements defined?

- [ ] **NAV-002**: Are selection key bindings defined?
  - Is the Space bar toggle requirement specified?
  - Is the Enter key "approve and next" requirement documented?
  - Are multi-select requirements defined (Shift+arrows)?

- [ ] **NAV-003**: Are action key bindings defined?
  - Are classification action keys specified (s=scoped, g=global, u=unknown)?
  - Are bulk action keys documented (A=accept all, R=reject all, I=invert)?
  - Is the quit key requirement specified (q, Esc)?

- [ ] **NAV-004**: Are focus management requirements defined?
  - Is the tab order requirement specified (list → buttons → filters)?
  - Is the focus indicator requirement documented (highlight color, border)?
  - Are focus restoration requirements specified (after dialog, after error)?

### 2.4 App Details & Inspection Requirements

- [ ] **DETAIL-001**: Are detail panel requirements defined?
  - Is the detail panel layout specified (location, size, toggle)?
  - Are displayed fields documented (all desktop file fields, current classification, suggestion reason)?
  - Is the detail panel update timing requirement specified (real-time vs on-demand)?

- [ ] **DETAIL-002**: Are WM_CLASS detection trigger requirements defined?
  - Is the "detect now" action key binding specified (d, D, F5)?
  - Is the detection method selection requirement documented (guess vs Xvfb)?
  - Is the detection result display requirement specified (inline, modal, detail panel)?

- [ ] **DETAIL-003**: Are suggestion reasoning display requirements defined?
  - Is the reason format specified (bullet points, prose, technical)?
  - Are matched categories/keywords highlighted requirement specified?
  - Is the confidence score explanation requirement documented?

### 2.5 Classification Action Requirements

- [ ] **ACT-001**: Are single-app classification requirements defined?
  - Is the "classify as scoped" action requirement specified?
  - Is the "classify as global" action requirement specified?
  - Is the "classify as unknown/skip" action requirement specified?
  - Is the immediate UI feedback requirement documented?

- [ ] **ACT-002**: Are bulk classification requirements defined?
  - Is the "accept all suggestions" action requirement specified?
  - Is the "reject all suggestions" action requirement specified?
  - Is the "classify filtered subset" action requirement documented?

- [ ] **ACT-003**: Are undo/redo requirements defined?
  - Is the undo action key binding specified (u, Ctrl+Z)?
  - Is the redo action key binding specified (Ctrl+Y)?
  - Is the undo stack depth limit requirement documented?

- [ ] **ACT-004**: Are custom pattern requirements defined?
  - Is the "add pattern rule" action requirement specified?
  - Is the pattern syntax requirement defined (glob, regex)?
  - Is the pattern validation requirement documented?

### 2.6 Review & Approval Workflow Requirements

- [ ] **WF-001**: Are review mode requirements defined?
  - Is the "review suggestions" mode requirement specified?
  - Is the "review changes" mode requirement specified?
  - Is the mode switching requirement documented?

- [ ] **WF-002**: Are diff/changelog requirements defined?
  - Is the changes summary display requirement specified (added, modified, removed)?
  - Is the before/after comparison requirement documented?
  - Is the change export requirement specified (diff format, JSON)?

- [ ] **WF-003**: Are save/commit requirements defined?
  - Is the "save and exit" action requirement specified?
  - Is the "save and continue" action requirement specified?
  - Is the "discard and exit" action requirement documented?

- [ ] **WF-004**: Are validation requirements defined?
  - Are duplicate classification prevention requirements specified?
  - Are conflict resolution requirements documented (app in both scoped and global)?
  - Is the validation error display requirement specified?

### 2.7 Integration with Existing System Requirements

- [ ] **SYS-001**: Are app-classes.json update requirements defined?
  - Is the atomic write requirement specified (temp file + rename)?
  - Is the backup requirement documented (before overwrite)?
  - Is the JSON format validation requirement specified?

- [ ] **SYS-002**: Are daemon notification requirements defined?
  - Is the daemon reload trigger requirement specified?
  - Is the daemon unavailable handling requirement documented?
  - Is the reload verification requirement specified?

- [ ] **SYS-003**: Are CLI integration requirements defined?
  - Is the `i3pm app-classes wizard` command integration specified?
  - Are CLI option requirements documented (--filter, --sort, --auto-accept)?
  - Is the exit code requirement specified (0=success, 1=cancelled, 2=error)?

### 2.8 Error Handling & Edge Cases Requirements

- [ ] **ERR-001**: Are error dialog requirements defined?
  - Is the error dialog layout specified (title, message, actions)?
  - Are error recovery actions documented (retry, skip, abort)?
  - Is the error dialog dismissal requirement specified?

- [ ] **ERR-002**: Are edge case requirements defined?
  - Are empty app list handling requirements specified?
  - Are all-apps-classified handling requirements documented?
  - Are no-suggestions-available handling requirements specified?

- [ ] **ERR-003**: Are concurrent modification requirements defined?
  - Are app-classes.json external modification detection requirements specified?
  - Are conflict resolution requirements documented (reload, merge, overwrite)?
  - Is the user notification requirement specified?

### 2.9 Performance & Responsiveness Requirements

- [ ] **PERF-001**: Are UI responsiveness requirements defined?
  - Is the maximum rendering time specified (e.g., <16ms for 60fps)?
  - Are large list handling requirements documented (virtualization, pagination)?
  - Is the input lag requirement specified (e.g., <50ms)?

- [ ] **PERF-002**: Are detection performance requirements defined?
  - Is the Xvfb detection timeout requirement specified?
  - Are parallel detection requirements documented (max concurrency)?
  - Is the detection result caching requirement specified?

- [ ] **PERF-003**: Are memory usage requirements defined?
  - Is the maximum memory footprint specified (e.g., <100MB)?
  - Are large dataset handling requirements documented (1000+ apps)?
  - Is the memory leak prevention requirement specified?

---

## Enhancement 3: Pattern-Based Rules

### 3.1 Pattern Syntax Requirements

- [ ] **SYN-001**: Are glob pattern syntax requirements specified?
  - Are supported glob operators documented (`*`, `?`, `[abc]`, `{foo,bar}`)?
  - Are escaping requirements defined (`\*` for literal asterisk)?
  - Are case sensitivity requirements specified (case-sensitive by default)?

- [ ] **SYN-002**: Are regex pattern syntax requirements specified?
  - Is the regex flavor documented (PCRE, POSIX, Python re)?
  - Are supported flags documented (i=ignore case, m=multiline)?
  - Are performance constraints specified (no catastrophic backtracking)?

- [ ] **SYN-003**: Are pattern prefix requirements defined?
  - Is the glob prefix syntax specified (e.g., `glob:pwa-*`)?
  - Is the regex prefix syntax specified (e.g., `regex:^pwa-.*$`)?
  - Is the default pattern type requirement documented (glob vs regex)?

- [ ] **SYN-004**: Are pattern delimiter requirements defined?
  - Is the pattern/classification delimiter specified (e.g., ` → `, `: `, `=`)?
  - Are whitespace handling requirements documented (trim, preserve)?
  - Are multi-line pattern requirements specified?

### 3.2 Pattern Storage Requirements

- [ ] **STOR-001**: Are pattern storage location requirements specified?
  - Is the file path documented (`~/.config/i3/app-classes.json`)?
  - Is the JSON structure requirement defined (new `class_patterns` key)?
  - Are alternative storage locations requirements documented (project-specific)?

- [ ] **STOR-002**: Are pattern format requirements specified?
  - Is the JSON schema defined for pattern rules?
  - Are pattern metadata requirements documented (description, enabled, priority)?
  - Is the format versioning requirement specified?

- [ ] **STOR-003**: Are pattern migration requirements defined?
  - Are existing config migration requirements specified?
  - Is the backward compatibility requirement documented?
  - Is the migration validation requirement specified?

### 3.3 Pattern Matching Requirements

- [ ] **MATCH-001**: Are matching algorithm requirements specified?
  - Is the pattern evaluation order defined (specific → general)?
  - Are pattern precedence rules documented (regex > glob > exact)?
  - Is the first-match vs best-match behavior requirement specified?

- [ ] **MATCH-002**: Are case sensitivity requirements defined?
  - Is the default case sensitivity specified (sensitive vs insensitive)?
  - Is the case override syntax documented (flag, suffix)?
  - Are locale-aware matching requirements specified?

- [ ] **MATCH-003**: Are performance requirements defined?
  - Is the maximum matching time specified (e.g., <1ms per window)?
  - Are pattern compilation caching requirements documented?
  - Are pathological pattern prevention requirements specified (regex bombs)?

### 3.4 Pattern Precedence & Priority Requirements

- [ ] **PREC-001**: Are explicit pattern priority requirements defined?
  - Is the priority value range specified (e.g., 0-100)?
  - Is the default priority documented (e.g., 50)?
  - Are priority tie-breaking requirements specified?

- [ ] **PREC-002**: Are implicit precedence requirements defined?
  - Are exact match > pattern match precedence requirements specified?
  - Are explicit classification > pattern classification precedence requirements documented?
  - Is the scoped_classes/global_classes priority requirement specified?

- [ ] **PREC-003**: Are conflict resolution requirements defined?
  - Are multiple pattern match handling requirements specified (first, last, highest priority)?
  - Are contradictory pattern detection requirements documented?
  - Is the conflict warning requirement specified?

### 3.5 Pattern Validation Requirements

- [ ] **VAL-001**: Are syntax validation requirements defined?
  - Is the glob syntax validation algorithm specified?
  - Is the regex syntax validation algorithm specified?
  - Is the validation error message format requirement documented?

- [ ] **VAL-002**: Are semantic validation requirements defined?
  - Are circular pattern detection requirements specified?
  - Are unreachable pattern detection requirements documented?
  - Are pattern overlap warning requirements specified?

- [ ] **VAL-003**: Are validation timing requirements defined?
  - Is the validation-on-add requirement specified?
  - Is the validation-on-save requirement specified?
  - Is the validation-on-load requirement documented?

### 3.6 Pattern Management CLI Requirements

- [ ] **CLI-001**: Are pattern add requirements defined?
  - Is the `i3pm app-classes add-pattern` command syntax specified?
  - Are required arguments documented (pattern, classification)?
  - Are optional arguments documented (priority, description, enabled)?

- [ ] **CLI-002**: Are pattern list requirements defined?
  - Is the `i3pm app-classes list-patterns` command output format specified?
  - Are filtering requirements documented (by classification, by enabled status)?
  - Are sorting requirements specified (by priority, by pattern)?

- [ ] **CLI-003**: Are pattern remove requirements defined?
  - Is the `i3pm app-classes remove-pattern` command syntax specified?
  - Is the pattern identifier requirement documented (by pattern string, by index)?
  - Is the confirmation requirement specified (--force flag)?

- [ ] **CLI-004**: Are pattern edit requirements defined?
  - Is the `i3pm app-classes edit-pattern` command syntax specified?
  - Are editable fields documented (pattern, classification, priority)?
  - Is the edit validation requirement specified?

### 3.7 Pattern Testing & Debugging Requirements

- [ ] **TEST-001**: Are pattern test requirements defined?
  - Is the `i3pm app-classes test-pattern` command syntax specified?
  - Are test input requirements documented (window class string, app name)?
  - Is the test output format requirement specified (matched pattern, classification, reason)?

- [ ] **TEST-002**: Are pattern coverage requirements defined?
  - Is the coverage report format specified (matched/unmatched apps)?
  - Are uncovered app detection requirements documented?
  - Is the coverage threshold requirement specified (optional goal)?

- [ ] **TEST-003**: Are pattern debug logging requirements defined?
  - Is the debug log format specified (timestamp, input, matched pattern, result)?
  - Are debug log level requirements documented (per-pattern, global)?
  - Is the debug log output requirement specified (stderr, file)?

### 3.8 TUI Wizard Integration Requirements

- [ ] **WIZ-001**: Are pattern creation from wizard requirements defined?
  - Is the "create pattern from this app" action requirement specified?
  - Is the pattern suggestion algorithm requirement documented?
  - Is the pattern preview requirement specified?

- [ ] **WIZ-002**: Are pattern visualization requirements defined?
  - Is the "matched by pattern" indicator requirement specified?
  - Is the pattern name display requirement documented?
  - Is the pattern edit action requirement specified?

- [ ] **WIZ-003**: Are bulk pattern application requirements defined?
  - Is the "apply pattern to selected apps" action requirement specified?
  - Is the pattern application preview requirement documented?
  - Is the confirmation requirement specified?

### 3.9 Migration & Backward Compatibility Requirements

- [ ] **MIG-001**: Are config migration requirements defined?
  - Is the migration from explicit lists to patterns requirement specified?
  - Is the migration trigger requirement documented (automatic, manual)?
  - Is the migration reversibility requirement specified?

- [ ] **MIG-002**: Are version compatibility requirements defined?
  - Is the minimum config version requirement specified?
  - Is the version upgrade requirement documented?
  - Is the version downgrade handling requirement specified?

- [ ] **MIG-003**: Are daemon compatibility requirements defined?
  - Is the daemon config reload requirement specified?
  - Is the daemon pattern parsing requirement documented?
  - Is the daemon fallback requirement specified (if patterns unsupported)?

---

## Enhancement 4: Real-Time Window Inspection

### 4.1 Window Selection Requirements

- [ ] **SEL-001**: Are selection method requirements defined?
  - Is the mouse click selection requirement specified?
  - Is the keyboard-driven selection requirement documented (arrow keys)?
  - Is the focused window selection requirement specified (default)?

- [ ] **SEL-002**: Are cursor interaction requirements defined?
  - Is the cursor change requirement specified (crosshair, pointer)?
  - Is the hover preview requirement documented (highlight target window)?
  - Is the click cancellation requirement specified (Esc, right-click)?

- [ ] **SEL-003**: Are multi-window selection requirements defined?
  - Is the single-window mode requirement specified?
  - Is the multi-window mode requirement documented (Ctrl+click)?
  - Is the selection state indicator requirement specified?

### 4.2 Property Inspection Requirements

- [ ] **PROP-001**: Are inspected property requirements defined?
  - Is the property list specified (WM_CLASS, WM_NAME, WM_WINDOW_ROLE, instance, type)?
  - Are X11 property requirements documented (_NET_WM_PID, etc.)?
  - Are i3-specific property requirements specified (con_id, marks, workspace)?

- [ ] **PROP-002**: Are property display format requirements defined?
  - Is the table format requirement specified (key-value pairs)?
  - Are nested property display requirements documented (JSON tree)?
  - Is the copy-to-clipboard requirement specified (per property, all)?

- [ ] **PROP-003**: Are property refresh requirements defined?
  - Is the auto-refresh interval requirement specified (real-time, on-demand)?
  - Is the manual refresh action requirement documented (F5, r)?
  - Are change indicators requirements specified (highlight changed values)?

### 4.3 Classification Status Display Requirements

- [ ] **STATUS-001**: Are current classification display requirements defined?
  - Is the classification status format specified (scoped, global, unknown, pattern-matched)?
  - Is the classification source requirement documented (explicit, pattern, heuristic)?
  - Are confidence indicators requirements specified?

- [ ] **STATUS-002**: Are suggestion display requirements defined?
  - Is the suggested classification format specified?
  - Is the suggestion reasoning requirement documented?
  - Are alternative suggestions requirements specified (ranked list)?

- [ ] **STATUS-003**: Are related apps display requirements defined?
  - Is the "same WM_CLASS" app list requirement specified?
  - Is the "same instance" app list requirement documented?
  - Is the navigation to related apps requirement specified?

### 4.4 Interactive Classification Requirements

- [ ] **ICLASS-001**: Are direct classification action requirements defined?
  - Is the "classify as scoped" action key binding specified (s)?
  - Is the "classify as global" action key binding specified (g)?
  - Is the "remove classification" action requirement documented (u, Del)?

- [ ] **ICLASS-002**: Are pattern creation requirements defined?
  - Is the "create pattern from this window" action requirement specified?
  - Is the pattern suggestion algorithm requirement documented?
  - Is the pattern preview requirement specified?

- [ ] **ICLASS-003**: Are bulk action requirements defined?
  - Is the "apply to all with same WM_CLASS" action requirement specified?
  - Is the "apply to all with same instance" action requirement documented?
  - Is the confirmation requirement specified?

### 4.5 Real-Time Monitoring Requirements

- [ ] **MON-001**: Are event subscription requirements defined?
  - Is the i3 IPC subscription requirement specified (window events)?
  - Is the property change detection requirement documented?
  - Is the subscription cleanup requirement specified (on exit)?

- [ ] **MON-002**: Are update triggering requirements defined?
  - Is the update-on-focus-change requirement specified?
  - Is the update-on-property-change requirement documented?
  - Is the update throttling requirement specified (max frequency)?

- [ ] **MON-003**: Are live update display requirements defined?
  - Is the live value update requirement specified (no page refresh)?
  - Is the change highlighting requirement documented (flash, color)?
  - Is the change history requirement specified (log, timeline)?

### 4.6 Command Invocation Requirements

- [ ] **CMD-001**: Are CLI invocation requirements defined?
  - Is the `i3pm app-classes inspect` command syntax specified?
  - Are selection mode arguments documented (--click, --focused, --id)?
  - Is the output format requirement specified (--format=table|json|yaml)?

- [ ] **CMD-002**: Are keybinding integration requirements defined?
  - Is the i3 keybinding configuration requirement specified?
  - Is the rofi/dmenu launcher requirement documented?
  - Is the notification integration requirement specified?

- [ ] **CMD-003**: Are scripting integration requirements defined?
  - Is the non-interactive mode requirement specified (--window-id)?
  - Is the JSON output requirement documented?
  - Is the exit code requirement specified (0=success, 1=cancelled)?

### 4.7 Display Modes Requirements

- [ ] **MODE-001**: Are TUI display requirements defined?
  - Is the Textual-based inspector requirement specified?
  - Is the layout requirement documented (properties panel, actions panel)?
  - Are keyboard shortcuts requirements specified?

- [ ] **MODE-002**: Are CLI display requirements defined?
  - Is the table output format requirement specified?
  - Is the JSON output format requirement documented?
  - Is the YAML output format requirement specified?

- [ ] **MODE-003**: Are notification display requirements defined?
  - Is the notification content requirement specified?
  - Is the notification action requirement documented (click to classify)?
  - Is the notification timeout requirement specified?

### 4.8 Window Highlighting Requirements

- [ ] **HIGH-001**: Are highlight visual requirements defined?
  - Is the highlight border requirement specified (color, width)?
  - Is the highlight duration requirement documented (persistent, timeout)?
  - Is the highlight animation requirement specified (fade, blink)?

- [ ] **HIGH-002**: Are multi-monitor highlight requirements defined?
  - Is the cross-monitor highlight requirement specified?
  - Is the highlight focus requirement documented (bring to front)?
  - Is the highlight restore requirement specified (after inspection)?

- [ ] **HIGH-003**: Are highlight accessibility requirements defined?
  - Are colorblind-friendly options requirements specified?
  - Are high-contrast options requirements documented?
  - Is the screen reader compatibility requirement specified?

### 4.9 Error Handling & Edge Cases Requirements

- [ ] **ERR-W-001**: Are selection timeout requirements defined?
  - Is the timeout duration specified (e.g., 30 seconds)?
  - Is the timeout action requirement documented (cancel, default to focused)?
  - Is the timeout notification requirement specified?

- [ ] **ERR-W-002**: Are invalid window handling requirements defined?
  - Is the invalid window ID handling requirement specified?
  - Is the destroyed window handling requirement documented?
  - Is the inaccessible window handling requirement specified?

- [ ] **ERR-W-003**: Are permission error requirements defined?
  - Is the X11 permission error handling requirement specified?
  - Is the i3 IPC permission error handling requirement documented?
  - Is the error recovery requirement specified?

### 4.10 Integration with Classification System Requirements

- [ ] **INT-W-001**: Are immediate classification requirements defined?
  - Is the immediate UI update requirement specified (no reload)?
  - Is the daemon notification requirement documented?
  - Is the verification requirement specified (read-back)?

- [ ] **INT-W-002**: Are classification persistence requirements defined?
  - Is the app-classes.json update requirement specified?
  - Is the atomic write requirement documented?
  - Is the backup requirement specified?

- [ ] **INT-W-003**: Are conflict resolution requirements defined?
  - Is the existing classification override requirement specified?
  - Is the pattern conflict detection requirement documented?
  - Is the user confirmation requirement specified?

---

## Cross-Enhancement Integration Requirements

### X.1 Shared Configuration Requirements

- [ ] **CONF-001**: Are shared config file requirements defined?
  - Is the config file format consistency requirement specified?
  - Is the config versioning requirement documented?
  - Is the config migration requirement specified?

- [ ] **CONF-002**: Are config validation requirements defined?
  - Is the validation timing requirement specified (on load, on save)?
  - Is the validation error handling requirement documented?
  - Is the validation reporting requirement specified?

### X.2 Shared CLI Integration Requirements

- [ ] **CLI-X-001**: Are command namespace requirements defined?
  - Is the command hierarchy specified (`i3pm app-classes <subcommand>`)?
  - Is the subcommand naming convention documented?
  - Are command aliases requirements specified?

- [ ] **CLI-X-002**: Are shared CLI option requirements defined?
  - Is the `--verbose` option behavior requirement specified?
  - Is the `--json` option output format requirement documented?
  - Are output redirection requirements specified?

### X.3 Shared Daemon Integration Requirements

- [ ] **DAEMON-001**: Are daemon reload requirements defined?
  - Is the reload trigger mechanism specified (signal, IPC)?
  - Is the reload atomicity requirement documented?
  - Is the reload verification requirement specified?

- [ ] **DAEMON-002**: Are daemon communication requirements defined?
  - Is the IPC protocol requirement specified (JSON-RPC, custom)?
  - Is the request/response format requirement documented?
  - Is the timeout requirement specified?

### X.4 Shared UX Requirements

- [ ] **UX-X-001**: Are consistent terminology requirements defined?
  - Is the term glossary requirement specified (scoped, global, pattern)?
  - Are term usage guidelines documented?
  - Are term localization requirements specified (if applicable)?

- [ ] **UX-X-002**: Are consistent keybinding requirements defined?
  - Is the keybinding scheme requirement specified (across TUI modes)?
  - Are keybinding conflicts prevention requirements documented?
  - Is the keybinding customization requirement specified?

- [ ] **UX-X-003**: Are consistent color scheme requirements defined?
  - Is the color palette requirement specified?
  - Are semantic color meanings requirements documented?
  - Is the theme consistency requirement specified (CLI, TUI, notifications)?

---

## Testing & Validation Requirements

### T.1 Unit Test Requirements

- [ ] **UNIT-001**: Are testability requirements defined?
  - Is the test isolation requirement specified (no live X server)?
  - Are mock/stub requirements documented (Xvfb, i3 IPC)?
  - Is the test data requirement specified (fixtures)?

- [ ] **UNIT-002**: Are coverage requirements defined?
  - Is the minimum coverage threshold specified (e.g., 80%)?
  - Are coverage exclusions documented (UI code, interactive code)?
  - Is the coverage reporting requirement specified?

### T.2 Integration Test Requirements

- [ ] **INT-T-001**: Are integration test scenarios defined?
  - Are end-to-end workflows requirements specified?
  - Are cross-enhancement integration requirements documented?
  - Are error scenario requirements specified?

- [ ] **INT-T-002**: Are test automation requirements defined?
  - Is the CI integration requirement specified?
  - Are automated TUI testing requirements documented (pytest-textual)?
  - Is the test result reporting requirement specified?

### T.3 User Acceptance Test Requirements

- [ ] **UAT-001**: Are UAT criteria requirements defined?
  - Are user scenario requirements specified (from spec.md user stories)?
  - Are success criteria requirements documented?
  - Is the UAT environment requirement specified?

- [ ] **UAT-002**: Are UX testing requirements defined?
  - Are usability testing requirements specified?
  - Are accessibility testing requirements documented?
  - Is the feedback collection requirement specified?

---

## Documentation Requirements

### D.1 User Documentation Requirements

- [ ] **DOC-U-001**: Are user guide requirements defined?
  - Is the tutorial requirement specified (step-by-step workflows)?
  - Is the reference documentation requirement documented (all commands)?
  - Are examples requirements specified (common use cases)?

- [ ] **DOC-U-002**: Are troubleshooting guide requirements defined?
  - Is the error message index requirement specified?
  - Are common issues solutions requirements documented?
  - Is the diagnostic command requirement specified?

### D.2 Developer Documentation Requirements

- [ ] **DOC-D-001**: Are API documentation requirements defined?
  - Is the API reference requirement specified (all public functions)?
  - Are type hints requirements documented?
  - Are docstring requirements specified (Google style)?

- [ ] **DOC-D-002**: Are architecture documentation requirements defined?
  - Is the architecture diagram requirement specified?
  - Are component interaction requirements documented?
  - Is the data flow requirement specified?

---

## Success Metrics & Observability Requirements

### M.1 Performance Metrics Requirements

- [ ] **PERF-M-001**: Are performance metric requirements defined?
  - Is the detection time metric requirement specified (p50, p95, p99)?
  - Is the classification time metric requirement documented?
  - Is the UI responsiveness metric requirement specified?

- [ ] **PERF-M-002**: Are performance logging requirements defined?
  - Is the performance log format requirement specified?
  - Are performance bottleneck detection requirements documented?
  - Is the performance regression detection requirement specified?

### M.2 Usage Metrics Requirements

- [ ] **USAGE-001**: Are usage metric requirements defined?
  - Is the usage tracking requirement specified (opt-in, privacy-preserving)?
  - Are tracked events requirements documented (detections, classifications)?
  - Is the usage reporting requirement specified?

- [ ] **USAGE-002**: Are error metrics requirements defined?
  - Is the error rate metric requirement specified?
  - Is the error categorization requirement documented?
  - Is the error alerting requirement specified?

---

## Notes on Checklist Usage

This checklist validates requirements **quality** (completeness, clarity, testability), not implementation correctness.

- Each checkbox represents a **requirements verification question**
- Answering "yes" means the requirement is **documented and unambiguous**
- Answering "no" indicates a **requirements gap** that needs specification before implementation
- References to budlabs i3ass UX patterns:
  - **i3king**: Rule-based window automation, pattern matching, GLOBAL/DEFAULT rules
  - **i3list**: Rich window property inspection, parseable output format
  - **i3run**: Smart window raising/launching, WM_CLASS-based matching, scratchpad integration

**Checklist Completion**: [ ] items / total items = % complete

---

**End of Requirements Quality Checklist**
