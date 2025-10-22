# Feature Specification: Dynamic Window Management System

**Feature Branch**: `021-lets-create-a`
**Created**: 2025-10-21
**Status**: Draft
**Input**: User description: "lets create a new feature for this functionality. we should review what we currently have, and then update/replace it. we want to remove the static home-manager configuration and replace with the python based dynamic strategy. we want our implementation to align as closely as possible to i3-ipc.txt, the ipc-python library, and our event-based subscription model. in addition, we want our classification/matching strategy to be robust enough to handle several use cases: regular applications, firefox pwa applications, and terminal based applications. reference the budlabs-i3ass-81e224f956d0eab9.txt section, i3king, and review the rules customization for an example of the customization specificity that we may need to fully implement, albeit we want ours in python and to integrate fully. in addition to 'classification', we also need mappings for applications to workspaces (as we currently have in our home-manager config) with names and icons, and then we will need some logic that maps workspaces to monitors that will need to handle cases of 1 to 3 monitors."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pattern-Based Window Classification Without Rebuilds (Priority: P1)

As a user, I want window classification rules to be applied dynamically without rebuilding my NixOS configuration, so that I can quickly test and iterate on window management rules.

**Why this priority**: This addresses the core requirement violation - the current static home-manager config requires full system rebuild for any window rule change. This is the foundation that enables all other dynamic behaviors.

**Independent Test**: Can be fully tested by modifying a pattern rule in `~/.config/i3/window-rules.json`, opening a new window, and verifying it gets classified correctly without any rebuild. Delivers immediate value by eliminating the rebuild requirement.

**Acceptance Scenarios**:

1. **Given** a new pattern rule is added to window-rules.json with `{"pattern": "glob:pwa-*", "scope": "global", "priority": 100}`, **When** a Firefox PWA with class "FFPWA-01ABCD" is launched, **Then** the window is immediately classified as global without any rebuild
2. **Given** an existing pattern rule is modified to change priority, **When** the daemon detects the file change and reloads, **Then** new windows are classified using the updated priority order
3. **Given** a window class matches multiple patterns, **When** the classification engine evaluates the window, **Then** the highest priority pattern wins (priority-ordered evaluation)
4. **Given** pattern matching is enabled with 100+ rules, **When** a new window is created, **Then** classification completes in <1ms using LRU cache

---

### User Story 2 - Firefox PWA Detection and Classification (Priority: P1)

As a user who uses Firefox PWAs (Progressive Web Apps), I want PWAs to be automatically detected and classified based on their app name/title, so that YouTube, Google AI, and other PWAs can be managed independently.

**Why this priority**: PWAs are a critical use case that doesn't work with simple WM_CLASS matching (all PWAs share `FFPWA-*` class pattern). This is essential for the existing workflow and cannot be deferred.

**Independent Test**: Install a Firefox PWA, launch it, and verify it gets the correct classification and workspace assignment based on title pattern matching. Works independently of other stories.

**Acceptance Scenarios**:

1. **Given** a Firefox PWA for YouTube with class "FFPWA-01K665SPD8EPMP3JTW02JM1M0Z" and title "YouTube", **When** the window is created, **Then** the daemon detects it as a PWA and applies title-based classification
2. **Given** a PWA classification rule with `{"pattern": "pwa:YouTube", "scope": "global", "workspace": 4}`, **When** the YouTube PWA is launched, **Then** it is assigned to workspace 4 and marked as global
3. **Given** multiple PWAs are installed, **When** each is launched, **Then** each gets classified independently based on its title pattern
4. **Given** a PWA changes its title, **When** the title_change event is received, **Then** the classification is re-evaluated if the rule type is TITLE

---

### User Story 3 - Terminal Application Detection (Priority: P1)

As a user who runs terminal-based applications (yazi, lazygit, k9s), I want these to be detected by their window title and classified appropriately, so that terminal apps can have different workspace assignments than the base terminal.

**Why this priority**: Terminal apps require title-based matching since they all share the same WM_CLASS (ghostty, Alacritty, etc.). This is a current workflow requirement.

**Independent Test**: Launch ghostty with title "Yazi: /etc/nixos", verify it gets classified and assigned differently than a plain ghostty terminal. Independent of PWA and regular app stories.

**Acceptance Scenarios**:

1. **Given** a window rule with `{"pattern": "title:^Yazi:.*", "scope": "scoped", "workspace": 5}`, **When** ghostty is launched with title "Yazi: /home/user", **Then** the window is classified as scoped and assigned to workspace 5
2. **Given** a plain ghostty terminal is launched without a custom title, **When** the window is created, **Then** it matches the default ghostty rule and goes to workspace 1
3. **Given** a terminal app changes its title, **When** the daemon receives the title change event, **Then** the window is re-evaluated and potentially moved if the title pattern changes

---

### User Story 4 - Dynamic Workspace-to-Monitor Assignment (Priority: P2)

As a user with 1-3 monitors, I want workspaces to automatically redistribute across available monitors when I connect/disconnect displays, so that my workflow adapts to changing hardware configurations.

**Why this priority**: Multi-monitor support is important but not blocking for single-monitor users. Can be tested independently once basic window classification works.

**Independent Test**: With monitor count detection working, simulate connecting a second monitor and verify workspaces redistribute (WS 1-2 on primary, WS 3-9 on secondary). Works independently of window classification.

**Acceptance Scenarios**:

1. **Given** 1 monitor is connected, **When** the daemon queries i3 outputs using GET_OUTPUTS, **Then** all workspaces 1-9 are assigned to the primary monitor
2. **Given** 2 monitors are connected, **When** the monitor assignment logic runs, **Then** workspaces 1-2 are on primary, workspaces 3-9 are on secondary
3. **Given** 3 monitors are connected, **When** workspaces are distributed, **Then** WS 1-2 on primary, WS 3-5 on secondary, WS 6-9 on tertiary
4. **Given** a monitor is disconnected, **When** the output change event is received, **Then** workspaces are immediately reassigned using the new monitor count

---

### User Story 5 - Workspace Metadata with Names and Icons (Priority: P3)

As a user, I want workspaces to have meaningful names and icons that reflect their purpose, so that the i3bar and workspace switcher are more informative.

**Why this priority**: Nice-to-have UX improvement that doesn't block core functionality. Can be added after workspace assignment works.

**Independent Test**: Configure workspace 1 with name "Terminal" and icon "󰨊", verify i3bar shows the icon and name. Independent of window classification and monitor assignment.

**Acceptance Scenarios**:

1. **Given** workspace configuration with `{"number": 1, "name": "Terminal", "icon": "󰨊"}`, **When** the daemon initializes workspaces, **Then** workspace 1 has both name and icon set
2. **Given** workspaces are configured with icons, **When** i3bar queries workspace information, **Then** the icon and name are included in the response
3. **Given** a workspace has no custom name, **When** it is queried, **Then** it falls back to the default numbered name

---

### User Story 6 - i3king-Style Rule Syntax with Variables (Priority: P3)

As a power user, I want to write window rules with template variables ($CLASS, $INSTANCE, $TITLE, $CONID) and conditional logic (GLOBAL, DEFAULT, ON_CLOSE), so that I can create sophisticated window management automations.

**Why this priority**: Advanced feature for power users. The basic pattern matching (P1) handles most use cases. This adds syntactic sugar and advanced capabilities.

**Independent Test**: Create a rule with `ON_CLOSE instance=firefox` that sends a notification, close a Firefox window, verify notification appears. Independent of other stories.

**Acceptance Scenarios**:

1. **Given** a GLOBAL rule with blacklist `GLOBAL class=URxvt { "notify": "Not URxvt" }`, **When** any non-URxvt window is created, **Then** the notification is sent
2. **Given** a DEFAULT rule, **When** a window doesn't match any normal rules, **Then** the DEFAULT rule is triggered
3. **Given** a rule with variable `exec notify-send $CLASS $TITLE`, **When** triggered, **Then** the variables are substituted with actual window properties
4. **Given** an ON_CLOSE rule, **When** a matching window is closed, **Then** the associated command is executed

---

### Edge Cases

- What happens when a window matches multiple patterns with the same priority? (Use pattern order in config as tiebreaker)
- How does the system handle a window that changes its WM_CLASS after creation? (Re-evaluate on property changes if i3 sends such events, otherwise mark as edge case limitation)
- What happens if window-rules.json has invalid JSON syntax? (Log error, fall back to previous valid config, send desktop notification to user)
- How are windows handled during the brief period when a monitor is being connected? (Queue window events until output configuration stabilizes, then process batch)
- What happens to floating windows during workspace redistribution? (Floating windows stay with their assigned workspace when it moves to new output)
- What happens if a PWA is launched before the daemon has fully initialized? (Buffer window events until daemon is ready, then process retroactively)
- How are rapid title changes handled (e.g., terminal showing real-time updates)? (Debounce title change events with 500ms timeout to avoid thrashing)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST load window classification rules from `~/.config/i3/window-rules.json` without requiring NixOS rebuild
- **FR-002**: System MUST support glob patterns (e.g., `glob:pwa-*`), regex patterns (e.g., `regex:^vim$`), and literal patterns (e.g., `literal:firefox`) for window matching
- **FR-003**: System MUST detect Firefox PWAs by combining WM_CLASS pattern (`FFPWA-*`) with window title matching
- **FR-004**: System MUST detect terminal-based applications by matching window title patterns (e.g., `title:^Yazi:.*`)
- **FR-005**: System MUST use priority-ordered pattern matching where highest priority pattern wins (short-circuit evaluation)
- **FR-006**: System MUST cache pattern matching results using LRU cache with 1024 entry limit to achieve <1ms classification time
- **FR-007**: System MUST subscribe to i3 window events (`window::new`, `window::close`, `window::title`) using i3 IPC SUBSCRIBE message type
- **FR-008**: System MUST subscribe to i3 output events (`output`) to detect monitor connect/disconnect
- **FR-009**: System MUST query current outputs using i3 IPC GET_OUTPUTS to determine monitor count
- **FR-010**: System MUST assign workspaces to monitors based on count: 1 monitor (all WS on primary), 2 monitors (WS 1-2 primary, WS 3-9 secondary), 3+ monitors (WS 1-2 primary, WS 3-5 secondary, WS 6-9 tertiary)
- **FR-011**: System MUST use i3 IPC RUN_COMMAND to execute workspace-to-output assignments (e.g., `workspace 1 output <output-name>`)
- **FR-012**: System MUST use i3 IPC RUN_COMMAND to move windows to workspaces (e.g., `[con_id=<id>] move to workspace <number>`)
- **FR-013**: System MUST use i3 IPC RUN_COMMAND to mark windows with project context (e.g., `[con_id=<id>] mark <project-name>`)
- **FR-014**: System MUST reload window-rules.json when file is modified (detect using inotify or file mtime polling)
- **FR-015**: System MUST handle invalid JSON in window-rules.json by logging error and retaining previous valid configuration
- **FR-016**: System MUST support workspace metadata (name, icon) in configuration file `~/.config/i3/workspaces.json`
- **FR-017**: System MUST integrate with existing i3pm daemon architecture (shared event loop, IPC server)
- **FR-018**: System MUST remove all static window rules from home-manager i3.nix configuration (lines 34-69)
- **FR-019**: System MUST support variable substitution in rule commands: `$CLASS`, `$INSTANCE`, `$TITLE`, `$CONID`, `$WINID`, `$ROLE`, `$TYPE`
- **FR-020**: System MUST support rule modifiers: `GLOBAL` (matches all windows), `DEFAULT` (matches if no other rule matches), `ON_CLOSE` (triggers on window close), `TITLE` (special title formatting rule)
- **FR-021**: System MUST support blacklist syntax in GLOBAL rules to exclude specific windows
- **FR-022**: System MUST validate pattern syntax on config load and reject invalid patterns with error messages
- **FR-023**: System MUST use async/await patterns with i3ipc.aio library for all i3 IPC communication
- **FR-024**: System MUST handle i3 restart events by re-subscribing to events and re-applying rules to existing windows
- **FR-025**: System MUST debounce rapid title change events (500ms timeout) to prevent classification thrashing
- **FR-026**: System MUST integrate with existing Project model schema (scoped_classes, workspace_preferences, auto_launch)
- **FR-027**: System MUST extend AppClassification model to support class_patterns field for dynamic pattern matching
- **FR-028**: System MUST use existing PatternRule dataclass for pattern storage and validation
- **FR-029**: System MUST resolve window rules by combining: global patterns (app-classes.json) + project-specific patterns (project.scoped_classes)
- **FR-030**: System MUST support project workspace_preferences for dynamic workspace assignment overrides

### Schema Alignment with Existing i3pm Models

**CRITICAL**: This feature must maintain full compatibility with existing i3pm data models and CLI tools.

#### Existing Models That Must Be Preserved

1. **Project Model** (`core/models.py` lines 69-277)
   - Fields: name, directory, display_name, icon, scoped_classes, workspace_preferences, auto_launch, saved_layouts
   - File location: `~/.config/i3/projects/{name}.json`
   - **Integration point**: `scoped_classes` field must drive per-project window classification
   - **Integration point**: `workspace_preferences` must override global workspace assignments

2. **AppClassification Model** (`core/models.py` lines 448-537)
   - Fields: scoped_classes, global_classes, class_patterns
   - File location: `~/.config/i3/app-classes.json`
   - **Gap**: Current daemon ignores `class_patterns` field - this feature MUST integrate it
   - **Integration point**: `class_patterns` must support pattern syntax (glob:, regex:, literal:)

3. **PatternRule Model** (`models/pattern.py` lines 10-91)
   - Fields: pattern, scope, priority, description
   - Pattern types: literal, glob:, regex:
   - **Integration point**: Daemon must use PatternRule for all pattern matching
   - **Note**: Already has validation and matches() method - reuse this

#### Required Schema Extensions

1. **AppClassification.class_patterns Enhancement**
   - Current schema: `Dict[str, str]` mapping pattern to scope
   - Required: Support for priority-ordered list of PatternRule objects
   - Proposed schema:
     ```python
     class_patterns: List[PatternRule] = field(default_factory=list)
     # Backward compatibility with dict format for loading
     ```

2. **WorkspaceConfig New Model** (not currently in i3pm)
   - Must align with Project.workspace_preferences schema
   - Proposed location: `models/workspace.py`
   - Schema:
     ```python
     @dataclass
     class WorkspaceConfig:
         number: int  # 1-9
         name: Optional[str] = None
         icon: Optional[str] = None
         default_output_role: str = "auto"  # "auto", "primary", "secondary", "tertiary"
     ```
   - File location: `~/.config/i3/workspace-config.json`

3. **WindowRule Extension** (new model for window-rules.json)
   - Must reference PatternRule as base
   - Schema:
     ```python
     @dataclass
     class WindowRule:
         pattern_rule: PatternRule  # Reuse existing PatternRule
         workspace: Optional[int] = None  # Target workspace (1-9)
         command: Optional[str] = None  # i3 command to execute
         modifier: Optional[str] = None  # GLOBAL, DEFAULT, ON_CLOSE, TITLE
         blacklist: List[str] = field(default_factory=list)  # For GLOBAL rules
     ```

#### Configuration File Hierarchy and Precedence

1. **Global Patterns** (`~/.config/i3/app-classes.json`)
   - Applies to all windows regardless of active project
   - Example: All Firefox PWAs are global
   - Priority: 100 (highest for global defaults)

2. **Window Rules** (`~/.config/i3/window-rules.json`) - NEW FILE
   - Advanced rules with workspace assignments and commands
   - Priority: 200-500 (user-defined per rule)

3. **Project-Specific** (`~/.config/i3/projects/{name}.json`)
   - Project.scoped_classes: List of window classes scoped to this project
   - Project.workspace_preferences: Override global workspace-to-output assignments
   - Priority: 1000 (highest - project overrides everything)

4. **Workspace Config** (`~/.config/i3/workspace-config.json`) - NEW FILE
   - Workspace names, icons, default output assignments
   - No priority (metadata only, not matching rules)

#### Resolution Algorithm

When a window is created, the daemon must resolve its classification and workspace assignment:

```python
def classify_window(window, active_project: Optional[Project]) -> Classification:
    # Step 1: Check project-specific scoped_classes (priority 1000)
    if active_project and window.window_class in active_project.scoped_classes:
        return Classification(scope="scoped", workspace=None, source="project")

    # Step 2: Check window-rules.json patterns (priority 200-500)
    matched_rule = match_window_rules(window)  # PatternMatcher with priorities
    if matched_rule:
        return Classification(
            scope=matched_rule.pattern_rule.scope,
            workspace=matched_rule.workspace,
            source="window_rule"
        )

    # Step 3: Check app-classes.json class_patterns (priority 100)
    matched_pattern = app_classification.match_pattern(window.window_class)
    if matched_pattern:
        return Classification(
            scope=matched_pattern.scope,
            workspace=None,
            source="app_classes"
        )

    # Step 4: Check app-classes.json literal lists
    if window.window_class in app_classification.scoped_classes:
        return Classification(scope="scoped", workspace=None, source="app_classes")
    if window.window_class in app_classification.global_classes:
        return Classification(scope="global", workspace=None, source="app_classes")

    # Step 5: Default to global (unscoped)
    return Classification(scope="global", workspace=None, source="default")
```

#### Workspace Assignment with Project Overrides

```python
def assign_workspace(classification: Classification, active_project: Optional[Project]) -> int:
    # If window rule specifies workspace, use it
    if classification.workspace:
        target_ws = classification.workspace
    else:
        # Use default workspace for window class (from config)
        target_ws = get_default_workspace(window.window_class)

    # Apply project workspace_preferences override
    if active_project and target_ws in active_project.workspace_preferences:
        output_role = active_project.workspace_preferences[target_ws]
        # Map workspace to actual output based on role and current outputs
        actual_output = get_output_by_role(output_role)
        return (target_ws, actual_output)

    # Use global workspace-to-output assignment
    return (target_ws, get_workspace_output(target_ws))
```

### Key Entities

- **WindowRule**: Represents a window matching pattern with associated actions
  - Extends existing PatternRule model
  - Attributes: pattern_rule (PatternRule), workspace (int|null), command (string|null), modifier (GLOBAL|DEFAULT|ON_CLOSE|TITLE|null), blacklist (List[str])
  - Relationships: References PatternRule, multiple rules can match same window, priority from PatternRule determines winner
  - File: `~/.config/i3/window-rules.json`

- **WorkspaceConfig**: Represents workspace metadata (NEW)
  - Attributes: number (1-9), name (string|null), icon (string|null), default_output_role (auto|primary|secondary|tertiary)
  - Relationships: Assigned to one output (monitor), can host multiple windows
  - File: `~/.config/i3/workspace-config.json`

- **Project** (EXISTING - from core/models.py)
  - Attributes: name, directory, scoped_classes, workspace_preferences, auto_launch, saved_layouts
  - **Integration**: scoped_classes drives project-specific window classification
  - **Integration**: workspace_preferences overrides global workspace assignments
  - File: `~/.config/i3/projects/{name}.json`

- **AppClassification** (EXISTING - from core/models.py)
  - Current: scoped_classes, global_classes, class_patterns (Dict[str, str])
  - **Enhancement**: class_patterns must become List[PatternRule] for priority-ordered matching
  - **Integration**: Provides global default classification patterns
  - File: `~/.config/i3/app-classes.json`

- **PatternRule** (EXISTING - from models/pattern.py)
  - Attributes: pattern, scope, priority, description
  - **Reuse**: WindowRule references this as pattern_rule field
  - Methods: matches(window_class) -> bool, _parse_pattern() -> (type, raw_pattern)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can modify window classification rules and see changes applied to new windows within 1 second without any rebuild
- **SC-002**: Pattern matching classifies 100+ rules against a new window in <1ms using LRU cache (measured with get_cache_info())
- **SC-003**: Firefox PWAs are correctly detected and classified in 100% of test cases (YouTube, Google AI, custom PWAs)
- **SC-004**: Terminal applications (yazi, lazygit, k9s) are correctly detected by title pattern in 100% of test cases
- **SC-005**: Workspace redistribution completes within 500ms of monitor connect/disconnect event
- **SC-006**: Invalid window-rules.json syntax is detected and reported with clear error message, system continues with previous valid config
- **SC-007**: Daemon memory usage remains <20MB with 100+ window rules and 50+ active windows
- **SC-008**: Zero race conditions between window creation events and workspace assignment (verified by integration tests)
- **SC-009**: All existing i3pm project management functionality continues to work without regression (verified by existing test suite)
- **SC-010**: 90% of users can create custom window rules without consulting documentation (success measured by syntax error rate)
- **SC-011**: All existing Project JSON files load and work without modification (100% backward compatibility)
- **SC-012**: AppClassification.class_patterns field is properly integrated into daemon classification logic (0 ignored patterns)
- **SC-013**: Project.scoped_classes takes precedence over all other classification methods (verified by integration tests)
- **SC-014**: Project.workspace_preferences correctly overrides global workspace assignments (verified by multi-monitor tests)

### Performance Targets

- Window classification: <1ms per window (cached), <10ms (cache miss)
- Config reload: <100ms for 100+ rules
- Monitor reassignment: <500ms total for all workspaces
- Event processing latency: <50ms from i3 event to rule application
- Memory footprint: <20MB additional memory beyond base daemon

### Quality Targets

- Code coverage: >80% for pattern matching and rule evaluation logic
- Integration test suite: 100% of user scenarios covered
- Zero static home-manager window rules remaining
- Full backward compatibility with existing project management features
- Error handling: All failure modes have graceful degradation paths

## Design Principles *(non-prescriptive)*

### Alignment with i3 IPC Architecture

This feature should align with i3's native IPC patterns:
- Use event subscription model (`SUBSCRIBE` message type) rather than polling
- Leverage `GET_TREE` for window hierarchy queries
- Use `GET_OUTPUTS` for monitor configuration
- Use `GET_WORKSPACES` for workspace-to-output assignments
- Send commands via `RUN_COMMAND` message type
- Handle i3 restart events gracefully

### Integration with Existing Daemon

This feature should integrate with the existing i3pm event-driven daemon:
- Extend existing event handlers (window, output events)
- Reuse daemon IPC server for CLI communication
- Share state management patterns (ApplicationClassification model)
- Leverage existing PatternMatcher class where possible
- Add new JSON-RPC methods for window rule management

### Pattern Syntax Inspiration

Pattern syntax should be inspired by i3king but implemented in Python:
- Support glob, regex, literal, title, and pwa pattern types
- Support GLOBAL/DEFAULT/ON_CLOSE/TITLE modifiers
- Support variable substitution ($CLASS, $INSTANCE, $TITLE, etc.)
- Support priority-based rule ordering
- Support blacklist syntax for GLOBAL rules
- Use declarative JSON format instead of custom DSL

### File-Based Configuration

Configuration should be file-based for easy editing and version control:
- `~/.config/i3/window-rules.json` - Window classification rules
- `~/.config/i3/workspaces.json` - Workspace metadata (names, icons)
- Use JSON schema validation for both files
- Auto-reload on file modification
- Provide clear error messages for syntax errors
- Include example/template files in NixOS package

## Non-Goals

- **Not implementing**: X11-specific window manipulation (use i3 IPC instead)
- **Not implementing**: Custom window decorations or theming
- **Not implementing**: Automatic window layout generation (i3fyra-style tiling)
- **Not implementing**: Window swallowing or tabbing logic
- **Not implementing**: Workspace auto-naming based on window content (keep metadata static)
- **Not implementing**: Cross-monitor window drag-and-drop detection
- **Not implementing**: Integration with external workspace managers (polybar, etc.) - i3blocks only
- **Not implementing**: Wayland support (i3 is X11-only)

## Migration Strategy

### Phase 1: Parallel Implementation (No Breaking Changes)

1. Implement pattern-based classification engine alongside existing static rules
2. Add new JSON config files without removing home-manager rules
3. Users can opt-in by adding rules to window-rules.json
4. Static rules continue to work during testing phase

### Phase 2: Configuration Migration Tool

1. Create `i3pm migrate-rules` command that:
   - Parses existing home-manager i3.nix rules
   - Generates equivalent window-rules.json
   - Backs up original config
   - Validates generated JSON

### Phase 3: Deprecation (Optional)

1. Document migration path in release notes
2. Add warning when static rules are detected
3. Provide grace period (2-3 releases)
4. Remove static rules in future major version

### Rollback Plan

If users encounter issues:
- Keep home-manager rules until confirmed working
- Disable dynamic rules with `i3pm config set window-rules.enabled false`
- Daemon continues working with static ApplicationClassification
- Document rollback procedure in troubleshooting guide

## Testing Strategy

### Unit Tests

- PatternMatcher with 100+ patterns (glob, regex, literal, title, pwa)
- Rule priority evaluation and short-circuit logic
- JSON config parsing and validation
- Variable substitution in rule commands
- GLOBAL/DEFAULT/ON_CLOSE rule modifiers
- LRU cache behavior and performance
- Error handling for invalid patterns/configs

### Integration Tests

- Firefox PWA detection (mock window with FFPWA-* class and title)
- Terminal app detection (mock ghostty with custom title)
- Monitor connect/disconnect simulation
- Workspace redistribution across 1-3 monitors
- Config reload on file modification
- i3 restart handling

### Scenario Tests (End-to-End)

- User Story 1: Add pattern rule, launch window, verify classification (no rebuild)
- User Story 2: Launch YouTube PWA, verify workspace assignment
- User Story 3: Launch yazi in ghostty, verify title-based classification
- User Story 4: Simulate monitor disconnect, verify workspace redistribution
- User Story 5: Configure workspace names/icons, verify i3bar display
- User Story 6: Create ON_CLOSE rule, verify execution on window close

### Performance Tests

- Benchmark pattern matching with 100+ rules (target: <1ms cached, <10ms uncached)
- Load test with 50+ windows and 100+ rules
- Memory leak detection (daemon running 24+ hours)
- Event processing latency measurement

### Regression Tests

- All existing i3pm functionality (project switching, daemon status, etc.)
- Existing Python test suite (17 tests in test_xvfb_detection.py, etc.)
- Manual smoke tests for key workflows

## Documentation Requirements

### User Documentation

- Migration guide from static home-manager rules
- window-rules.json syntax reference with examples
- Pattern types comparison table (glob vs regex vs literal vs title vs pwa)
- Common recipes (PWA detection, terminal apps, keyboard-driven workflows)
- Troubleshooting guide for classification issues

### Developer Documentation

- Architecture overview (how dynamic rules integrate with daemon)
- PatternMatcher API and caching behavior
- Adding new pattern types (extension guide)
- Testing patterns for window rules
- i3 IPC integration patterns

### Configuration Examples

- Template window-rules.json with common patterns
- Template workspaces.json with default layout
- Real-world examples (current i3.nix rules converted to JSON)
- i3king compatibility comparison

## Open Questions

1. Should we support workspace auto-creation when a rule references a workspace number that doesn't exist? (Current behavior: i3 creates workspaces on-demand)
2. Should workspace metadata (names/icons) be managed via JSON file or via daemon IPC commands (or both)?
3. Should we support rule inheritance/composition (e.g., base rules + override rules)?
4. Should we support time-based rules (e.g., different workspace assignments during work hours)?
5. Should we support multi-window rules (e.g., "when Firefox and VS Code are both open, do X")?

## References

- i3 IPC Documentation: `/etc/nixos/docs/i3-ipc.txt`
- i3king Rules Reference: `/etc/nixos/docs/budlabs-i3ass-81e224f956d0eab9.txt` (lines 7159-7360)
- Current Static Rules: `/etc/nixos/home-modules/desktop/i3.nix` (lines 34-69)
- Existing PatternMatcher: `/etc/nixos/home-modules/tools/i3_project_manager/core/pattern_matcher.py`
- Daemon Architecture: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/`
- Daemon Client: `/etc/nixos/home-modules/tools/i3_project_manager/core/daemon_client.py`
