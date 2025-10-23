# Research Report: Automated Window Rules Discovery and Validation

**Feature**: 031-create-a-new
**Date**: 2025-10-23
**Status**: Architectural Decisions Resolved

## Executive Summary

This research resolves two critical architectural questions (FR-012 and FR-013) for the automated window rules discovery system. Based on i3 documentation analysis, community patterns review, and alignment with Constitution Principle XII (Forward-Only Development), we have selected:

1. **Window Rule Mechanism**: Continue with event-driven Python daemon (NOT native i3 `for_window`)
2. **Pattern Matching**: Simple precedence order (NOT i3king-style multi-criteria scoring)

## Decision 1: Window Rule Application Mechanism (FR-012)

### Decision: Event-Driven Python Daemon

**Selected Approach**: Continue using the existing event-driven Python daemon that subscribes to i3 IPC window::new events and dynamically applies workspace assignments based on JSON configuration.

### Rationale

**Native i3 `for_window` Capabilities (Researched)**:
- **Matching Criteria**: Supports class, instance, title, window_role, window_type, machine, con_mark, floating, workspace, etc. with PCRE regex
- **Actions**: Can move containers to workspaces, set floating/tiling, change borders, apply layouts
- **Critical Limitations**:
  - ❌ Cannot execute external scripts or access external state
  - ❌ Cannot use environment variables or dynamic value substitution
  - ❌ Cannot check project context (scoped vs global applications)
  - ❌ All rules are static - evaluated once at window creation from config file
  - ⚠️ Config reload behavior on existing windows is undocumented

**Event-Driven Daemon Capabilities**:
- ✅ Subscribes to window::new, window::close, window::focus events via i3 IPC
- ✅ Dynamically evaluates patterns from JSON configuration (window-rules.json, app-classes.json)
- ✅ Full project context awareness - can differentiate scoped vs global applications based on active project state
- ✅ Runtime pattern updates without restarting i3 - just reload daemon configuration
- ✅ Parameterized command support - can substitute $PROJECT_DIR and other dynamic values
- ✅ External state integration - can query daemon state, check active project, apply conditional logic
- ✅ Proven architecture - existing i3-project-event-listener daemon demonstrates viability

**Community Validation**:
- Multiple Python daemon projects exist for dynamic i3 workspace management:
  - `i3-workspace-names-daemon`: Dynamic workspace naming based on window content
  - `i3-workspace-groups`: Project-aware workspace grouping with client/server architecture
  - `i3-multimonitor-workspace`: Cross-monitor workspace synchronization
- i3 documentation explicitly states: "i3 focuses on stability with limited new features while encouraging users to implement features using the IPC whenever possible"
- Python `i3ipc` library is mature, well-maintained, and designed for event-driven window management

### Alternatives Considered and Rejected

**Option A: Native i3 `for_window` Rules**
- **Rejected Because**: Cannot support project context awareness or parameterized commands
- **Specific Blocker**: No way to conditionally hide/show windows based on active project state
- **Specific Blocker**: No environment variable expansion or dynamic value substitution

**Option B: Hybrid Approach (Native rules + Daemon for dynamic cases)**
- **Rejected Because**: Adds unnecessary complexity with two different rule systems
- **Violates**: Constitution Principle XII - Forward-Only Development (no dual code paths)
- **Maintainability**: Would require maintaining both static config rules and dynamic daemon rules

### Implementation Notes

1. **Daemon Architecture**:
   - Use `i3ipc.aio` (async) for event subscriptions and window queries
   - Subscribe to `window::new` event for window creation
   - Query i3 GET_TREE for authoritative window properties (WM_CLASS, title, workspace)
   - Apply patterns from JSON configuration with project context evaluation

2. **Pattern Storage**:
   - Continue using `window-rules.json` for pattern definitions and workspace assignments
   - Continue using `app-classes.json` for scoped/global classifications
   - Timestamped backups before any modifications

3. **Daemon Integration**:
   - Reload daemon configuration via systemctl restart or JSON-RPC IPC message
   - No i3 restart required for pattern changes
   - Patterns take effect immediately on next window::new event

4. **Discovery Tool Integration**:
   - Discovery tool generates JSON patterns compatible with daemon format
   - Validation tool tests patterns against daemon's pattern matching logic
   - Migration tool updates JSON files and triggers daemon reload

## Decision 2: Pattern Matching Complexity (FR-013)

### Decision: Simple Precedence Order

**Selected Approach**: Use simple precedence order for pattern matching: exact class match (highest priority) → PWA ID match → title regex → title substring (lowest priority).

### Rationale

**Historical Context - i3king Scoring System**:
- i3king (2021) used multi-criteria scoring: window_role=1pt, class=2pt, instance=3pt, title=10pt
- Designed for complex disambiguation when multiple patterns could match
- Added implementation complexity: weighted scoring, confidence thresholds, tie-breaking

**Modern i3 Capabilities (v4.20+)**:
- Native pattern matching uses PCRE regex with multiple criteria support
- i3 IPC GET_TREE provides comprehensive window properties for precise matching
- Community tools (i3-workspace-names-daemon, i3-workspace-groups) use simple first-match logic successfully

**Our Use Case Analysis**:
- **Application Pattern Characteristics**:
  - GUI applications: Stable WM_CLASS (e.g., `Pavucontrol`, `Code`) - exact match sufficient
  - Terminal applications: Title-based patterns (e.g., `title:lazygit`) - substring match sufficient
  - PWA applications: Unique FFPWA IDs (e.g., `FFPWA-01JAXXX`) - exact match sufficient
- **Pattern Ambiguity Risk**: Low - each application has a distinct pattern type
- **Validation Capability**: Discovery tool will detect false positives/negatives during validation phase

**Simple Precedence Order Advantages**:
- ✅ Easier to understand and debug for users
- ✅ Faster pattern evaluation (no score calculation)
- ✅ Simpler implementation and testing
- ✅ Adequate for our application set (70+ apps with distinct patterns)
- ✅ Validation tool will catch any ambiguous patterns during discovery

### Alternatives Considered and Rejected

**Option A: i3king-style Multi-Criteria Scoring**
- **Rejected Because**: Unnecessary complexity for our use case
- **Analysis**: 70+ applications have distinct WM_CLASS or title patterns - scoring doesn't add value
- **Testing Insight**: Phase 11 testing revealed pattern issues were due to incorrect patterns (not chosen), not ambiguity requiring scoring

**Option B: Machine Learning Pattern Confidence**
- **Rejected Because**: Massive over-engineering for deterministic pattern matching
- **Violates**: Constitution Principle XII - simpler alternative (precedence order) is sufficient

### Implementation Notes

1. **Precedence Order**:
   ```python
   def match_window(window, patterns):
       # 1. Exact WM_CLASS match (highest priority)
       for pattern in patterns:
           if pattern.type == "class" and window.window_class == pattern.value:
               return pattern

       # 2. PWA ID match
       for pattern in patterns:
           if pattern.type == "class" and pattern.value.startswith("FFPWA-"):
               if window.window_class == pattern.value:
                   return pattern

       # 3. Title regex match
       for pattern in patterns:
           if pattern.type == "title_regex":
               if re.search(pattern.value, window.title):
                   return pattern

       # 4. Title substring match (lowest priority)
       for pattern in patterns:
           if pattern.type == "title":
               if pattern.value in window.title:
                   return pattern

       return None  # No match
   ```

2. **Ambiguity Detection**:
   - Validation tool will test each pattern against all open windows
   - Report if pattern matches multiple different applications (false positives)
   - Report if window has no matching pattern (false negatives)
   - Suggest making patterns more specific if ambiguity detected

3. **Pattern Refinement**:
   - If class match is too broad, add instance or title criteria
   - If title substring matches wrong windows, switch to title regex with anchors
   - Interactive mode allows manual pattern refinement with immediate testing

## Additional Research Findings

### i3bar Workspace Protocol

**Reviewed**: https://i3wm.org/docs/i3bar-workspace-protocol.html

**Assessment**: NOT relevant for this feature. The i3bar workspace protocol is exclusively for customizing workspace button display in i3bar (filtering, ordering, naming). It has no interaction with window workspace assignment or automatic window placement rules. Our current i3bar + i3blocks setup already provides workspace indicators and project context display.

**Conclusion**: No changes needed to leverage this protocol.

### Python Development Standards Alignment

**Confirmed Technology Choices**:
- **Language**: Python 3.11+ (aligns with Constitution Principle X - matches existing i3-project daemon)
- **i3 Integration**: `i3ipc-python` with async support (`i3ipc.aio`)
- **Terminal UI**: Rich library for tables, live displays, syntax highlighting
- **Testing**: pytest with pytest-asyncio for async test support
- **Data Models**: Pydantic models for validation and type safety
- **CLI Framework**: argparse for command-line argument parsing

**Hybrid Architecture Decision - Deno CLI + Python Services (Constitution Principles X + XIII)**:
- Constitution Principle XIII mandates Deno for NEW CLI tools ✅
- Constitution Principle X requires Python for i3 IPC integration ✅
- **Decision**: Hybrid architecture - Deno CLI frontend + Python backend services
- **Rationale**:
  - **Deno CLI Frontend**: Fast startup (<100ms), excellent CLI parsing (@std/cli/parse-args), unified `i3pm` interface
  - **Python Backend Services**: Mature i3ipc-python library, async i3 event handling, Rich UI for internal displays
  - **Clean Separation**: JSON-RPC communication between layers
  - **No Backwards Compatibility**: This replaces standalone Python CLIs with unified Deno interface (Principle XII)
- **Benefits**:
  - Users get single `i3pm` command for all operations (rules, daemon, windows, projects, logs, status)
  - Fast CLI responsiveness for interactive use
  - Proven i3 IPC integration without Deno library development
  - TypeScript type safety for CLI layer
  - Established architecture pattern for future i3-integrated tools

### Application Launch Methods

**Rofi Simulation via xdotool**:
- **Requirement**: FR-001 specifies launching applications "by simulating the rofi launcher workflow (Meta+D keybinding via xdotool)"
- **Research Finding**: xdotool can send keystrokes to active window
- **Implementation Pattern**:
  ```python
  import subprocess

  def launch_via_rofi(app_name: str):
      # Trigger rofi with Meta+D
      subprocess.run(["xdotool", "key", "super+d"])
      time.sleep(0.5)  # Wait for rofi to appear

      # Type application name
      subprocess.run(["xdotool", "type", app_name])
      time.sleep(0.2)

      # Press Enter to launch
      subprocess.run(["xdotool", "key", "Return"])
  ```

**Alternative: Direct Command Execution**:
- Faster and more reliable than rofi simulation
- Use for bulk discovery mode (70 applications)
- Fallback if rofi simulation fails

**Application Command Registry** (FR-030A):
- Maintain JSON configuration mapping application names to launch commands
- Support parameterized commands: `{"code": "code $PROJECT_DIR", "lazygit": "ghostty -e lazygit --work-tree=$PROJECT_DIR"}`
- Discovery uses base command (e.g., `code`), validation ensures pattern matches parameterized launches

## Summary of Resolved Clarifications

All "NEEDS CLARIFICATION" items from Technical Context have been resolved:

1. ✅ **Window Rule Mechanism**: Event-driven Python daemon (not native i3 for_window)
2. ✅ **Pattern Matching Logic**: Simple precedence order (not i3king scoring)
3. ✅ **Language/Libraries**: Python 3.11+, i3ipc-python (async), Rich, pytest, Pydantic
4. ✅ **Application Launch**: xdotool rofi simulation + direct command execution fallback
5. ✅ **Command Registry**: JSON-based parameterized command definitions

## Next Steps (Phase 1)

With architectural decisions finalized, proceed to Phase 1:

1. **Generate data-model.md**: Define Pydantic models for Window, Pattern, WindowRule, ApplicationDefinition, DiscoveryResult, ValidationResult, ConfigurationBackup
2. **Generate contracts/**: Define JSON schemas for window-rules.json, app-classes.json, application-registry.json
3. **Generate quickstart.md**: User guide for discovery, validation, migration workflows
4. **Update agent context**: Add window rules discovery technology to Claude context

---

**Research Complete**: All architectural questions resolved. Ready for Phase 1 design.
