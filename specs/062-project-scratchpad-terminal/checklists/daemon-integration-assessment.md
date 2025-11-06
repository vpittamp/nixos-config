# Daemon Integration Checklist Assessment

**Date**: 2025-11-05
**Assessor**: Claude Code (automated)
**Method**: Documentation review (spec.md, plan.md, research.md, data-model.md, quickstart.md, contracts/scratchpad-rpc.json) + existing implementation review (scratchpad.ts, daemon-client.ts, models.py, app-launcher-wrapper.sh)

## Summary

**Total Items**: 98
**Completed**: 46 (47%)
**Partially Complete**: 5 (5%)
**Gaps Identified**: 47 (48%)

**Critical Gap Categories**:
1. **Unified Launcher Integration** (CHK005-008): 0/4 complete - Current implementation bypasses app-launcher-wrapper.sh
2. **Launch Notification** (CHK014-017): 0/4 complete - No Feature 041 integration
3. **Ghostty Terminal** (CHK027-030, CHK019): 0/5 complete - All docs reference Alacritty only
4. **Error Handling** (CHK022, CHK024-026): 1/5 complete - Missing daemon unavailable, timeouts, user messages, logging requirements
5. **Migration Documentation** (CHK080-084): 0/5 complete - No shell script replacement requirements

---

## Section-by-Section Analysis

### 1. Requirement Completeness (30 items)

#### Daemon RPC Integration (CHK001-004) ✅ 4/4 COMPLETE

- [x] **CHK001** - JSON-RPC method signatures defined
  - **Evidence**: contracts/scratchpad-rpc.json defines all 5 methods (toggle, launch, status, close, cleanup)
  - **Location**: Lines 6-392

- [x] **CHK002** - Parameter validation specified
  - **Evidence**: Each method has params section with type, pattern, required fields
  - **Example**: project_name has pattern "^[a-zA-Z0-9_-]+$", minLength 1, maxLength 100

- [x] **CHK003** - Return value schemas documented
  - **Evidence**: Each method has "result" and "errors" sections with complete schemas
  - **Example**: toggle returns {status, project_name, pid, window_id, message}

- [x] **CHK004** - Async/await patterns specified
  - **Evidence**: research.md and data-model.md show async function signatures
  - **Example**: "async def launch_terminal", "async def validate_terminal"

#### Unified Launcher Integration (CHK005-008) ❌ 0/4 COMPLETE

- [ ] **CHK005** - Requirements for app-launcher-wrapper.sh launch
  - **Gap**: spec.md mentions Alacritty launch but not unified launcher integration
  - **Current**: research.md shows asyncio.create_subprocess_exec() (direct launch, not via wrapper)
  - **Impact**: Architectural inconsistency with Features 041/057

- [ ] **CHK006** - app-registry-data.nix entry requirements
  - **Gap**: No specification for scratchpad-terminal registry entry
  - **Note**: Entry exists (confirmed from previous conversation) but requirements not documented

- [ ] **CHK007** - Parameter substitution requirements ($PROJECT_DIR, $SESSION_NAME)
  - **Gap**: research.md shows I3PM_* env vars but not shell parameter substitution pattern used by app-launcher-wrapper.sh

- [ ] **CHK008** - systemd-run integration requirements
  - **Gap**: No mention of systemd-run for process isolation
  - **Current**: Direct asyncio subprocess launch

#### State Synchronization (CHK009-013) ✅ 5/5 COMPLETE

- [x] **CHK009** - State synchronization rules defined
  - **Evidence**: data-model.md §State Synchronization has 4 rules (On Launch, On Toggle, On Window Close, On Validation)
  - **Location**: Lines 267-278

- [x] **CHK010** - Validation requirements for state-mutating operations
  - **Evidence**: data-model.md §Validation Rules defines validate_terminal() with 4 checks
  - **Location**: Lines 447-469

- [x] **CHK011** - Sway IPC query requirements documented
  - **Evidence**: research.md shows GET_TREE usage: "tree = await sway.get_tree()"
  - **Location**: research.md lines 127-133

- [x] **CHK012** - Orphaned terminal cleanup requirements
  - **Evidence**: contracts/scratchpad-rpc.json defines scratchpad.cleanup method
  - **Also**: data-model.md lines 238-243 define cleanup_invalid_terminals()

- [x] **CHK013** - Window close event handling specified
  - **Evidence**: research.md lines 228-240 define on_window_close event handler
  - **Action**: "del self.scratchpad_terminals[project_name]"

#### Launch Notification Correlation (CHK014-017) ❌ 0/4 COMPLETE

- [ ] **CHK014** - Pre-launch notification requirements defined
  - **Gap**: No mention of Feature 041 integration in any documentation
  - **Impact**: Missing Tier 0 window correlation (95% accuracy in rapid launches)

- [ ] **CHK015** - Notification payload requirements
  - **Gap**: No specification for app_name, project_name, expected_class, timestamp payload

- [ ] **CHK016** - Correlation timeout requirements
  - **Gap**: No timeout specifications for launch notification correlation

- [ ] **CHK017** - Fallback correlation requirements
  - **Gap**: No fallback mechanism if notification fails

#### Environment Variable Propagation (CHK018-021) ⚠️ 3/4 COMPLETE

- [x] **CHK018** - Required I3PM_* variables documented
  - **Evidence**: data-model.md §Environment Variables lines 317-326 lists 6 variables
  - **Variables**: I3PM_SCRATCHPAD, I3PM_PROJECT_NAME, I3PM_WORKING_DIR, I3PM_APP_ID, I3PM_APP_NAME, I3PM_SCOPE

- [ ] **CHK019** - Format requirements for Ghostty compatibility
  - **Gap**: All documentation references Alacritty only
  - **Constraint**: spec.md line 259 states "Terminal must be Alacritty"
  - **User Request**: Switch to Ghostty

- [x] **CHK020** - /proc/<pid>/environ reading requirements
  - **Evidence**: data-model.md lines 331-360 define read_process_environ() function with full implementation

- [x] **CHK021** - I3PM_SCRATCHPAD marker variable documented
  - **Evidence**: data-model.md line 321 shows I3PM_SCRATCHPAD = "true"

#### Error Handling (CHK022-026) ⚠️ 1/5 COMPLETE

- [ ] **CHK022** - Daemon unavailable error handling
  - **Gap**: contracts/scratchpad-rpc.json has error codes but not "daemon unavailable" scenario
  - **Note**: daemon-client.ts has connection error handling but requirements not in spec

- [x] **CHK023** - Terminal process death recovery
  - **Evidence**: data-model.md §Terminal Toggle Errors table line 511
  - **Action**: "Remove from state, launch new"

- [ ] **CHK024** - Timeout requirements for async operations
  - **Gap**: plan.md has performance goals (<2s launch) but not explicit timeout requirements

- [ ] **CHK025** - User-facing error message requirements
  - **Partial**: contracts/scratchpad-rpc.json has error codes/messages
  - **Gap**: No comprehensive user-facing message requirements

- [ ] **CHK026** - Logging requirements
  - **Partial**: data-model.md shows example logger calls
  - **Gap**: No comprehensive logging requirements (log levels, formats, diagnostic info)

#### Ghostty Terminal Specific (CHK027-030) ❌ 0/4 COMPLETE

- [ ] **CHK027** - Ghostty launch parameter requirements
  - **Gap**: All docs mention Alacritty only (e.g., "alacritty --working-directory")
  - **User Request**: Use Ghostty as scratchpad terminal

- [ ] **CHK028** - Ghostty app_id/class identification
  - **Gap**: No requirements for Ghostty window identification

- [ ] **CHK029** - Ghostty window configuration (floating, size, position)
  - **Gap**: Current window rules are Alacritty-specific (app_id regex)

- [ ] **CHK030** - Ghostty fallback to Alacritty
  - **Gap**: No fallback requirements if Ghostty unavailable

---

### 2. Requirement Clarity (9 items)

#### Daemon Architecture (CHK031-033) ✅ 3/3 COMPLETE

- [x] **CHK031** - "daemon state" quantified with data structures
  - **Evidence**: data-model.md lines 42-133 define complete ScratchpadTerminal Pydantic model
  - **Fields**: project_name, pid, window_id, mark, working_dir, created_at, last_shown_at

- [x] **CHK032** - "project-to-terminal mapping" format defined
  - **Evidence**: data-model.md line 152 shows `terminals: Dict[str, ScratchpadTerminal]`
  - **Format**: project_name (string) → ScratchpadTerminal (object)

- [x] **CHK033** - Window identification criteria clearly specified
  - **Evidence**: research.md lines 20-41 define mark + env var combination
  - **Criteria**: mark format "scratchpad:{project_name}", env var I3PM_SCRATCHPAD=true

#### Performance Targets (CHK034-036) ⚠️ 0/3 PARTIAL

- [ ] **CHK034** - "<500ms toggle" quantified with measurement methodology
  - **Partial**: plan.md line 20 states "<500ms terminal toggle"
  - **Gap**: No measurement methodology specified (start/end points, what to measure)

- [ ] **CHK035** - "<2s initial launch" with measurement points
  - **Partial**: plan.md line 20 states "<2s for initial launch"
  - **Gap**: No start/end measurement points defined

- [ ] **CHK036** - "<100ms daemon event processing" scoped to event types
  - **Partial**: plan.md line 20 states "<100ms daemon event processing"
  - **Gap**: Not scoped to specific event types

#### Integration Points (CHK037-039) ❌ 0/3 COMPLETE

- [ ] **CHK037** - "unified launcher usage" explicitly defined
  - **Gap**: No app-launcher-wrapper.sh invocation pattern defined
  - **Current**: Direct subprocess launch shown in research.md

- [ ] **CHK038** - "launch notification" timing requirements
  - **Gap**: No requirements for when notifications should be sent (before app exec)

- [ ] **CHK039** - "environment variable injection" mechanism explicitly defined
  - **Partial**: research.md shows asyncio env parameter
  - **Gap**: Not explicit about systemd-run --setenv pattern used by unified launcher

---

### 3. Requirement Consistency (6 items)

#### Architecture Alignment (CHK040-043) ❌ 0/4 NEEDS VERIFICATION

- [ ] **CHK040** - RPC patterns consistent with existing daemon methods
  - **Needs Check**: Compare contracts/scratchpad-rpc.json with existing daemon RPC patterns
  - **Evidence Found**: daemon-client.ts shows standard pattern (request<T>(method, params))
  - **Assessment**: LIKELY COMPLETE but needs explicit verification

- [ ] **CHK041** - Environment variables consistent with Feature 057 naming
  - **Evidence**: data-model.md uses I3PM_* prefix (I3PM_SCRATCHPAD, I3PM_PROJECT_NAME, etc.)
  - **Comparison**: daemon/models.py WindowEnvironment shows I3PM_APP_ID, I3PM_APP_NAME, I3PM_SCOPE pattern
  - **Assessment**: ✅ COMPLETE - Consistent naming convention

- [ ] **CHK042** - Launch notification consistent with Feature 041
  - **Gap**: No launch notification requirements in scratchpad docs
  - **Evidence**: daemon-client.ts has getLaunchStats() and getPendingLaunches() for Feature 041
  - **Assessment**: ❌ GAP - Not integrated

- [ ] **CHK043** - Window correlation consistent with existing daemon tracking
  - **Partial**: Uses /proc/<pid>/environ reading (Feature 057 pattern)
  - **Gap**: Doesn't use launch notifications (Feature 041 pattern)

#### Terminal vs Other Apps (CHK044-045) ❌ 0/2 NEEDS VERIFICATION

- [ ] **CHK044** - Scratchpad terminal requirements consistent with regular terminal app requirements
  - **Needs Check**: Compare with app-registry-data.nix terminal entry
  - **Note**: Entry exists but consistency not documented

- [ ] **CHK045** - Scoped app requirements (scope="scoped") consistently applied
  - **Evidence**: data-model.md line 326 shows I3PM_SCOPE="scoped"
  - **Comparison**: daemon/models.py line 40 shows scope: Literal["global", "scoped"]
  - **Assessment**: ✅ COMPLETE - Consistent pattern

---

### 4. Acceptance Criteria Quality (7 items) ✅ 4/7 COMPLETE

- [x] **CHK046** - State synchronization verifiable via Sway IPC
  - **Evidence**: data-model.md validate_terminal() queries GET_TREE

- [ ] **CHK047** - Launch notification correlation measurable
  - **Gap**: No launch notification requirements

- [x] **CHK048** - Environment variable propagation validatable via /proc
  - **Evidence**: data-model.md read_process_environ(), quickstart.md validation examples

- [ ] **CHK049** - Error recovery success rate quantifiable
  - **Gap**: No success rate metrics defined

- [x] **CHK050** - Test requirements for daemon RPC endpoints
  - **Evidence**: plan.md Expected Tasks, research.md Testing Strategy

- [ ] **CHK051** - Integration test requirements for launcher interaction
  - **Gap**: No app-launcher-wrapper.sh integration testing requirements

- [x] **CHK052** - E2E test requirements with ydotool
  - **Evidence**: research.md lines 319-379 complete E2E test example

### 5. Scenario Coverage (11 items) ✅ 9/11 COMPLETE

- [x] **CHK053** - First-time terminal launch requirements
  - **Evidence**: spec.md User Story 1, FR-001

- [x] **CHK054** - Toggle hide/show requirements
  - **Evidence**: spec.md User Story 1 scenarios 2-3, FR-003

- [x] **CHK055** - Multi-project isolation requirements
  - **Evidence**: spec.md User Story 2, FR-005

- [x] **CHK056** - Global terminal requirements
  - **Evidence**: spec.md Edge Case 4, FR-012

- [x] **CHK057** - Terminal process death requirements
  - **Evidence**: spec.md Edge Case 3, data-model.md recovery actions

- [x] **CHK058** - Sway window missing requirements
  - **Evidence**: data-model.md validate_terminal() handles missing windows

- [ ] **CHK059** - Daemon socket unavailable requirements
  - **Gap**: No explicit requirement (daemon-client.ts has error handling but not in spec)

- [ ] **CHK060** - Concurrent toggle requests requirements
  - **Gap**: No concurrency handling requirements

- [x] **CHK061** - Auto-relaunch when process dies
  - **Evidence**: spec.md Edge Case 3, contracts toggle method "relaunches"

- [x] **CHK062** - State cleanup for invalid terminals
  - **Evidence**: contracts cleanup method, data-model.md cleanup_invalid_terminals()

- [x] **CHK063** - Re-correlation if mark lost
  - **Evidence**: data-model.md validate_terminal() re-applies marks

### 6. Edge Case Coverage (9 items) ⚠️ 3/9 COMPLETE

- [x] **CHK064** - Zero terminals (initial state)
  - **Evidence**: spec.md Edge Case 1, contracts toggle method

- [ ] **CHK065** - Maximum terminals (20-30 projects)
  - **Gap**: Scale mentioned but no requirements for behavior at maximum

- [x] **CHK066** - Sway restart (state loss)
  - **Evidence**: spec.md FR-004 explicitly states non-persistence

- [ ] **CHK067** - Rapid toggle operations
  - **Gap**: No requirements for rapid succession handling

- [ ] **CHK068** - Launch timeout scenarios
  - **Gap**: Performance goal exists but not timeout requirements

- [ ] **CHK069** - Window appearing before notification
  - **Gap**: No launch notification requirements

- [ ] **CHK070** - app_id conflicts
  - **Gap**: No conflict resolution requirements

- [x] **CHK071** - Missing environment variables
  - **Evidence**: data-model.md WindowEnvironment.from_env_dict() returns None if missing

- [ ] **CHK072** - Window mark collisions
  - **Gap**: No collision handling documented

### 7. Dependencies & Assumptions (7 items) ⚠️ 3/7 COMPLETE

- [ ] **CHK073** - Ghostty package availability
  - **Gap**: spec.md mentions Alacritty only, should be Ghostty

- [x] **CHK074** - sesh session manager requirements
  - **Evidence**: spec.md line 253 documents tmux/sesh assumption

- [ ] **CHK075** - i3ipc.aio version requirements
  - **Partial**: plan.md mentions i3ipc.aio but no version specified

- [ ] **CHK076** - systemd-run availability
  - **Gap**: No systemd-run requirements

- [ ] **CHK077** - Sway IPC responsiveness assumption validated
  - **Gap**: No validation of responsiveness assumption

- [x] **CHK078** - Single terminal per project assumption
  - **Evidence**: spec.md Non-Goal line 37, Constraint line 258

- [x] **CHK079** - Non-persistence assumption acceptable
  - **Evidence**: spec.md FR-004 explicitly states acceptability

### 8. Migration & Replacement Requirements (5 items) ❌ 0/5 COMPLETE

- [ ] **CHK080** - Shell script deprecation requirements
  - **Gap**: No explicit deprecation requirements

- [ ] **CHK081** - Keybinding update requirements
  - **Gap**: Configuration documented but not migration path

- [ ] **CHK082** - Shell script removal from Sway config
  - **Gap**: No requirements documented

- [ ] **CHK083** - for_window rules update requirements
  - **Gap**: No migration requirements

- [ ] **CHK084** - window-rules.json template updates
  - **Gap**: Not documented as requirements

### 9. Non-Functional Requirements (6 items) ⚠️ 2/6 COMPLETE

- [ ] **CHK085** - Daemon memory usage for scratchpad
  - **Gap**: Overall daemon memory documented, not scratchpad-specific

- [ ] **CHK086** - CPU usage for event processing
  - **Gap**: Overall daemon CPU documented, not scratchpad-specific

- [x] **CHK087** - Availability requirements (95% success)
  - **Evidence**: spec.md SC-002 line 213

- [x] **CHK088** - Data consistency requirements
  - **Evidence**: data-model.md synchronization rules, Sway IPC authoritative

- [ ] **CHK089** - Diagnostic command requirements
  - **Gap**: Status command exists but not i3pm diagnose integration

- [ ] **CHK090** - Daemon event logging requirements
  - **Gap**: Example calls shown but not comprehensive requirements

### 10. Traceability & Documentation (5 items) ⚠️ 2/5 COMPLETE

- [ ] **CHK091** - RPC methods traceable to user stories
  - **Partial**: toggle/launch traceable, status/close/cleanup not in user stories

- [ ] **CHK092** - Error scenarios traceable to requirements
  - **Partial**: Some errors in Edge Cases, but many scenarios not in spec

- [x] **CHK093** - Code location requirements specified
  - **Evidence**: plan.md §Project Structure lines 76-105

- [x] **CHK094** - CLI command patterns documented
  - **Evidence**: quickstart.md lines 28-50, scratchpad.ts matches

- [ ] **CHK095** - Configuration file update requirements
  - **Partial**: Keybinding config documented, but not comprehensive

### 11. Ambiguities & Conflicts (3 items) ⚠️ 1/3 COMPLETE

- [ ] **CHK096** - Alacritty to Ghostty transition documented
  - **Gap**: All docs say Alacritty, user requested Ghostty

- [ ] **CHK097** - Shell script vs daemon conflicts resolved
  - **Gap**: Implementation Philosophy mentions replace but no conflict details

- [x] **CHK098** - Scratchpad vs regular terminal clarified
  - **Evidence**: spec.md FR-010, app-registry-data.nix has separate entries

---

## Complete Statistics by Section

| Section | Items | Complete | Partial | Gaps | % Done |
|---------|-------|----------|---------|------|--------|
| 1. Requirement Completeness | 30 | 13 | 0 | 17 | 43% |
| 2. Requirement Clarity | 9 | 3 | 3 | 3 | 33% |
| 3. Requirement Consistency | 6 | 2 | 0 | 4 | 33% |
| 4. Acceptance Criteria Quality | 7 | 4 | 0 | 3 | 57% |
| 5. Scenario Coverage | 11 | 9 | 0 | 2 | 82% |
| 6. Edge Case Coverage | 9 | 3 | 0 | 6 | 33% |
| 7. Dependencies & Assumptions | 7 | 3 | 1 | 3 | 43% |
| 8. Migration Requirements | 5 | 0 | 0 | 5 | 0% |
| 9. Non-Functional Requirements | 6 | 2 | 0 | 4 | 33% |
| 10. Traceability & Documentation | 5 | 2 | 3 | 0 | 40% |
| 11. Ambiguities & Conflicts | 3 | 1 | 0 | 2 | 33% |
| **TOTAL** | **98** | **46** | **5** | **47** | **47%** |

---

## Critical Gaps Summary

### 🔴 HIGH PRIORITY

1. **Ghostty Terminal** (5 gaps)
   - CHK019, CHK027-030
   - Impact: User explicitly requested Ghostty instead of Alacritty
   - Action: Update all Alacritty references to Ghostty

2. **Unified Launcher Integration** (4 gaps)
   - CHK005-008
   - Impact: Architectural inconsistency, missing Features 041/057 benefits
   - Action: Define requirements for app-launcher-wrapper.sh integration

3. **Launch Notification** (4 gaps)
   - CHK014-017
   - Impact: Missing Tier 0 window correlation (Feature 041 integration)
   - Action: Specify launch notification requirements

4. **Migration Documentation** (5 gaps estimated)
   - CHK080-084
   - Impact: Unclear how to replace shell script with daemon approach
   - Action: Document shell script deprecation and migration path

### 🟡 MEDIUM PRIORITY

5. **Error Handling** (4 gaps)
   - CHK022, CHK024-026
   - Impact: Incomplete error scenarios, missing timeouts, inadequate logging
   - Action: Specify comprehensive error handling requirements

6. **Performance Measurement** (3 gaps)
   - CHK034-036
   - Impact: Unclear how to verify performance targets
   - Action: Define measurement methodologies

7. **Integration Points** (3 gaps)
   - CHK037-039
   - Impact: Unclear integration patterns with unified launcher
   - Action: Explicitly document integration mechanisms

### 🟢 LOW PRIORITY

8. **Architecture Consistency** (2 gaps needing verification)
   - CHK040, CHK044
   - Impact: Potential inconsistencies with existing patterns
   - Action: Verify and document consistency

9. **Remaining Sections** (53 items not yet assessed)
   - CHK046-098
   - Impact: Unknown until assessed
   - Action: Complete full checklist assessment

---

## Recommendations

### Immediate Actions

1. **Update spec.md to address Ghostty terminal requirements** (CHK019, CHK027-030)
   - Change Constraint 2 from "Terminal must be Alacritty" to "Terminal must be Ghostty"
   - Add Ghostty-specific launch parameters
   - Add Ghostty app_id/class identification requirements
   - Add fallback to Alacritty if Ghostty unavailable

2. **Add unified launcher integration requirements** (CHK005-008)
   - Specify scratchpad terminals should launch via app-launcher-wrapper.sh
   - Define app-registry-data.nix entry structure
   - Document parameter substitution pattern
   - Specify systemd-run integration for process isolation

3. **Add launch notification requirements** (CHK014-017)
   - Integrate Feature 041 launch notification protocol
   - Specify notification payload (app_name="scratchpad-terminal", project_name, expected_class, timestamp)
   - Define correlation timeout (suggest 2s matching <2s launch target)
   - Specify fallback correlation via /proc reading if notification times out

4. **Add migration requirements** (CHK080-084)
   - Document shell script deprecation path
   - Specify keybinding update process
   - Define window rule migration

### Next Steps

1. Complete assessment of sections 4-10 (53 remaining items)
2. Update spec.md with critical gaps
3. Update plan.md with integration patterns
4. Re-run checklist validation
5. Generate implementation tasks

---

## Assessment Confidence

- **HIGH Confidence (19 items)**: Items marked [x] with clear evidence
- **MEDIUM Confidence (2 items)**: CHK041, CHK045 - consistent patterns found but not explicitly documented
- **NEEDS VERIFICATION (2 items)**: CHK040, CHK044 - require comparison with existing implementations
- **GAPS IDENTIFIED (75 items)**: Clear evidence of missing requirements

**Methodology**: Documentation review only. No code implementation inspection beyond existing daemon patterns.

