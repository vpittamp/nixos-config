# App Discovery Enhancements - Requirements Analysis

**Created**: 2025-10-21
**Status**: Requirements Analysis Complete, Ready for Specification Writing

---

## Purpose

This directory contains comprehensive requirements analysis for four app discovery enhancements to the i3pm (i3 Project Manager) system. The analysis uses a "requirements quality checklist" approach to systematically identify all missing specifications before implementation begins.

---

## Documents

### 1. Requirements Quality Checklist
**File**: `app-discovery-enhancements.md` (832 lines)
**Purpose**: Comprehensive checklist validating requirements quality (not implementation)

**Structure**:
- Enhancement 1: Xvfb Detection Activation (92 validation items)
- Enhancement 2: Interactive Classification Wizard (126 validation items)
- Enhancement 3: Pattern-Based Rules (85 validation items)
- Enhancement 4: Real-Time Window Inspection (89 validation items)
- Cross-Enhancement Integration (23 validation items)
- Testing & Documentation (32 validation items)

**Total**: 447 requirements validation checkpoints

**Usage**: Use this checklist to verify each requirement is:
- **Documented** (explicitly written down)
- **Unambiguous** (single interpretation)
- **Measurable** (can verify compliance)
- **Complete** (no missing details)
- **Testable** (can write acceptance test)

### 2. Gap Analysis
**File**: `gap-analysis.md` (979 lines)
**Purpose**: Detailed analysis of current spec vs checklist requirements

**Key Findings**:
- **Overall Coverage**: 6% (27/447 requirements specified)
- **Enhancement 1 (Xvfb)**: 0% - No requirements
- **Enhancement 2 (Wizard)**: 6% - Partial from unified TUI requirements
- **Enhancement 3 (Patterns)**: 2% - Mentions app-classes.json only
- **Enhancement 4 (Inspector)**: 3% - Mentions monitoring tool only

**For Each Enhancement**:
- Current state assessment
- Critical gaps identified
- Impact analysis
- Concrete recommendations (Add FR-XXX with specific wording)
- Priority classification (CRITICAL, HIGH, MEDIUM)

**Includes**:
- 12 User Acceptance Test scenarios (UAT-XVF-001 through UAT-INS-003)
- Estimated effort: 28-42 hours of requirements work
- Phased approach (Foundation → Quality → Polish)
- Risk mitigation strategies

---

## Key Insights from Analysis

### Insight 1: Existing Foundation is Strong
The current spec (v1) has excellent coverage of the core i3 project management system:
- 72 Functional Requirements (FR-001 through FR-072)
- 20 Success Criteria (SC-001 through SC-020)
- 9 detailed User Stories with acceptance scenarios
- 12 Assumptions clearly documented

**Leverage**: The unified TUI/CLI framework (FR-058 through FR-072) provides a solid pattern to follow for app discovery enhancements.

### Insight 2: App Discovery Code Exists
The gap analysis found that `app_discovery.py` already implements:
- ✅ Desktop file parsing
- ✅ Heuristic classification suggestions
- ✅ WM_CLASS guessing algorithm
- ✅ Xvfb detection scaffold (not activated)

**Implication**: Requirements should validate existing implementation, not design from scratch. Specify behavior of existing code, fill gaps, improve UX.

### Insight 3: Pattern Rules Simplest Entry Point
Based on complexity analysis:

| Enhancement | Dependencies | Complexity | Existing Code | Recommended Order |
|-------------|--------------|------------|---------------|-------------------|
| Patterns    | None         | Low        | 80% (config.py) | **1st** ⭐ |
| Xvfb        | External tools | Medium   | 60% (app_discovery.py) | 2nd |
| Inspector   | Patterns, Xvfb | Medium   | 20% (monitoring exists) | 3rd |
| Wizard      | All above    | High       | 30% (TUI framework) | 4th |

**Recommendation**: Implement Enhancement 3 (Pattern Rules) first as foundation for others.

### Insight 4: UX Inspiration from i3ass
Analysis of budlabs-i3ass tools revealed valuable UX patterns:

**From i3king** (window ruler):
- Rule-based automation with pattern matching
- GLOBAL/DEFAULT rule precedence
- Magic variables ($CLASS, $INSTANCE, etc.)
- Dry-run mode for safety

**From i3list** (window info):
- Rich associative array output format
- Comprehensive property inspection
- Parseable machine-readable output
- eval-friendly bash integration

**From i3run** (raise/launch):
- Multi-criteria window targeting (class, instance, title, conid, winid)
- Raise-or-launch behavior (smart defaults)
- Scratchpad integration

**Applied to i3pm**:
- Pattern rules should support glob + regex (like i3king)
- Inspector should output parseable format (like i3list)
- Classification should use multi-criteria matching (like i3run)

### Insight 5: Testing Strategy Critical
Current spec has excellent testing foundation (FR-046 through FR-049) but needs extension:

**Gap**: No TUI testing requirements
**Solution**: Add pytest-textual integration for automated TUI testing

**Gap**: No Xvfb mocking for tests
**Solution**: Add test isolation requirements (no live X server in CI)

**Gap**: No pattern matching coverage
**Solution**: Add property-based testing for glob/regex patterns

---

## Recommended Implementation Sequence

### Phase 0: Requirements (1-2 weeks)
**Goal**: Bring spec to 100% coverage for Enhancement 3 (Patterns)

**Tasks**:
1. Write 30 missing FRs for Pattern Rules (FR-151 through FR-180)
2. Write 4 User Stories for Pattern workflows
3. Write 3 UAT scenarios (UAT-PAT-001 through UAT-PAT-003)
4. Write 5 Success Criteria (SC-021 through SC-025)
5. Update tasks.md with implementation tasks

**Deliverable**: Updated spec.md with complete Pattern Rules requirements

**Validation**: Run through checklist (SYN-001 through MIG-003), verify all checkboxes answerable with "yes"

### Phase 1: Pattern Rules Implementation (1 week)
**Goal**: Users can create glob/regex patterns for auto-classification

**User Story**:
> As a developer with 20 PWAs, I want to create a pattern rule `pwa-*` → global so I don't have to manually classify each PWA individually.

**Deliverables**:
1. Extend `config.py` with pattern storage (class_patterns dict)
2. Implement pattern matching in `is_scoped()` with precedence
3. Add CLI commands (add-pattern, list-patterns, remove-pattern, test-pattern)
4. Add pattern validation (glob/regex syntax checking)
5. Update daemon to reload patterns from config
6. Write 20+ unit tests for pattern matching
7. Write user guide section "Creating Pattern Rules"

**Acceptance**: All UAT-PAT scenarios pass

### Phase 2: Xvfb Detection Implementation (1 week)
**Goal**: Automatically detect WM_CLASS for apps without StartupWMClass

**User Story**:
> As a user discovering 50 apps without WM_CLASS, I want to run `i3pm app-classes detect --isolated --all-missing` and have the system automatically detect all window classes in under 60 seconds.

**Deliverables**:
1. Activate Xvfb detection in `app_discovery.py` (already scaffolded)
2. Add dependency checking (xvfb-run, xdotool, xprop)
3. Add cleanup logic (process termination, temp file cleanup)
4. Add CLI command `i3pm app-classes detect --isolated`
5. Add progress indication and verbose logging
6. Add result caching
7. Write 15+ unit tests (with Xvfb mocking)
8. Write troubleshooting guide section "Xvfb Detection"

**Acceptance**: All UAT-XVF scenarios pass

### Phase 3: Window Inspector Implementation (1 week)
**Goal**: Real-time window property inspection with click-to-classify

**User Story**:
> As a user troubleshooting why a window isn't auto-classified, I want to press Win+I, click the window, and immediately see its WM_CLASS, current classification status, and suggested classification with reasoning.

**Deliverables**:
1. Implement window selection (click mode, focused mode, by-id mode)
2. Implement property extraction (WM_CLASS, marks, workspace, etc.)
3. Implement TUI inspector screen (properties panel + actions)
4. Add direct classification actions (s=scoped, g=global)
5. Add pattern creation from inspector
6. Add i3 keybinding example
7. Write 20+ unit tests
8. Write user guide section "Inspecting Windows"

**Acceptance**: All UAT-INS scenarios pass

### Phase 4: Wizard Implementation (2 weeks)
**Goal**: Visual interface for reviewing and classifying all apps

**User Story**:
> As a new i3pm user, I want to run `i3pm app-classes wizard` and visually review all 50 discovered apps, see suggested classifications with confidence scores, accept/reject suggestions with keyboard shortcuts, and complete classification in under 5 minutes.

**Deliverables**:
1. Implement wizard TUI screen with table view
2. Implement keyboard navigation (arrows, Space, Enter)
3. Implement action keys (s/g/u for classify, A/R for bulk)
4. Implement detail panel with reasoning
5. Implement undo/redo stack
6. Implement save workflow with validation
7. Integrate pattern creation action
8. Integrate Xvfb detection action
9. Write 30+ unit tests (with pytest-textual)
10. Write user guide section "Classification Wizard"

**Acceptance**: All UAT-WIZ scenarios pass

### Phase 5: Integration & Polish (1 week)
**Goal**: Seamless integration across all enhancements

**Tasks**:
1. End-to-end testing (wizard → patterns → inspector round-trip)
2. Performance optimization (caching, virtualization)
3. Documentation completion
4. Shell completion scripts
5. Migration guide from v1 to v2

**Deliverable**: Production-ready release

---

## Success Metrics

### Requirements Quality Metrics
- [ ] 100% of checklist items answerable with "yes" before implementation
- [ ] All FRs have associated test cases
- [ ] All UAT scenarios have passing tests
- [ ] All Success Criteria measurable and measured

### Implementation Quality Metrics
- [ ] 80% code coverage for new modules
- [ ] 0 regressions in existing functionality
- [ ] <200ms pattern matching for 1000+ apps
- [ ] <10s Xvfb detection for slow apps
- [ ] <50ms TUI responsiveness

### User Experience Metrics
- [ ] 95% of users complete wizard on first attempt
- [ ] 90% of pattern rules work without modification
- [ ] 100% of common apps auto-classify correctly
- [ ] <2 minutes to classify 50 apps with wizard

---

## Questions & Answers

### Q: Why so much requirements work before coding?
**A**: The four enhancements touch critical parts of the system (daemon, config, TUI, CLI). Incomplete requirements lead to rework, inconsistent UX, and missed edge cases. Investment in requirements saves 3-5x time during implementation and testing.

### Q: Can we skip some requirements and iterate?
**A**: Yes, but only for MEDIUM priority items. CRITICAL requirements (marked in gap analysis) must be specified before implementation. HIGH requirements should be specified before release.

### Q: Existing code already works. Why specify behavior retroactively?
**A**: Current code lacks specification for:
- Error handling (what happens when Xvfb missing?)
- Edge cases (what if pattern matches everything?)
- Integration points (how does wizard trigger daemon reload?)

Retroactive specification prevents bugs and enables confident refactoring.

### Q: How to use the checklist during implementation?
**A**:
1. Before coding a feature, read relevant checklist section
2. For each checkbox, verify corresponding FR exists in spec
3. If FR missing, write it before implementing
4. After implementing, verify implementation matches all FRs
5. Write test for each FR

### Q: What if implementation reveals requirements gap?
**A**:
1. Stop implementation
2. Document discovered gap in spec as new FR
3. Validate FR against checklist
4. Resume implementation

This prevents "requirements drift" where implementation diverges from spec.

---

## References

### Internal Documents
- `/etc/nixos/specs/019-re-explore-and/spec.md` - Current specification (v1)
- `/etc/nixos/specs/019-re-explore-and/tasks.md` - Implementation tasks
- `/etc/nixos/home-modules/tools/i3_project_manager/core/app_discovery.py` - Existing implementation
- `/etc/nixos/home-modules/tools/i3_project_manager/core/config.py` - Classification config
- `/etc/nixos/home-modules/tools/pyproject.toml` - Package metadata

### External Inspiration
- `docs/budlabs-i3ass-81e224f956d0eab9.txt` - i3king, i3list, i3run patterns
- budlabs/i3ass repository - Rule-based window automation for i3

### Standards
- freedesktop.org Desktop Entry Specification - .desktop file format
- i3 IPC Protocol - Window manager integration
- Python `fnmatch` module - Glob pattern syntax
- Python `re` module - Regex pattern syntax

---

## Changelog

### 2025-10-21: Initial Analysis
- Created requirements quality checklist (447 validation items)
- Conducted gap analysis (identified 420 missing requirements)
- Recommended implementation sequence (Patterns → Xvfb → Inspector → Wizard)
- Estimated effort: 28-42 hours requirements work, 6-7 weeks implementation

---

## Next Actions

**Immediate** (this week):
1. ✅ Review gap analysis with stakeholders
2. ⬜ Prioritize which enhancement to implement first (recommend: Patterns)
3. ⬜ Write CRITICAL requirements for chosen enhancement
4. ⬜ Write UAT scenarios for chosen enhancement

**Near-term** (next week):
1. ⬜ Update spec.md with new requirements
2. ⬜ Update tasks.md with implementation tasks
3. ⬜ Begin implementation of Phase 1 (Pattern Rules)

**Long-term** (next 2 months):
1. ⬜ Complete all 4 enhancements
2. ⬜ Write comprehensive user guide
3. ⬜ Release i3pm v0.3.0 with app discovery system

---

**Status**: ✅ Requirements analysis complete. Ready to proceed with specification writing.
