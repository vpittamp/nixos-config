# i3run Boundary Detection Analysis - Complete Research Index

**Feature**: 051-i3run-scratchpad-enhancement
**Phase**: Phase 0 (Research) - COMPLETE ✅
**Date**: 2025-11-06
**Total Documentation**: 2,669 lines across 4 comprehensive documents

---

## Document Overview

### 1. QUICK_REFERENCE.md (274 lines, 8.1 KB)
**Read Time**: 2-3 minutes | **Audience**: Everyone
**Purpose**: Get oriented quickly with the algorithm

**Contents**:
- 4-line core math
- Pseudocode constraint rules
- Visual example walkthrough
- Quadrant lookup table
- 8 edge cases at a glance
- Code template
- Testing checklist
- Common mistakes to avoid

**When to Read**: First document to understand the basics before diving deeper.

---

### 2. ANALYSIS_SUMMARY.md (415 lines, 15 KB)
**Read Time**: 10 minutes | **Audience**: Technical leads, implementers
**Purpose**: Executive summary with decisions and recommendations

**Contents**:
- Executive summary (3-step overview)
- Why the algorithm is elegant
- 8 critical edge cases with solutions
- Quadrant logic visualization
- Test matrix summary (56 tests)
- Python implementation checklist
- Priority breakdown (P0/P1/P2)
- Known limitations
- Key files & code locations
- Decisions made during analysis
- Recommendation to proceed

**When to Read**: After QUICK_REFERENCE, before starting implementation.

---

### 3. BOUNDARY_DETECTION_ANALYSIS.md (963 lines, 35 KB)
**Read Time**: 30+ minutes | **Audience**: Implementation team
**Purpose**: Comprehensive technical deep dive with full context

**Contents**:
- Executive summary
- Algorithm pseudocode explained (6 phases)
- Quadrant logic visualization
- 8 detailed edge cases with:
  - Problem description
  - Impact analysis
  - Root cause analysis
  - Python solution code
- Known limitations (8 listed)
- Complete test case matrix (56 tests grouped by category)
- Python implementation strategy with:
  - Type-hinted function signatures
  - Unit test examples
  - Error handling patterns
  - Recommendations

**When to Read**: During implementation for detailed reference and test cases.

---

### 4. PYTHON_IMPLEMENTATION.md (1,017 lines, 31 KB)
**Read Time**: 30+ minutes | **Audience**: Implementers
**Purpose**: Ready-to-use Python code examples for implementation

**Contents**:
- Module 1: Data Models (models.py)
  - GapConfig, WindowDimensions, WorkspaceGeometry
  - CursorPosition, PositionResult, ScratchpadState
  - Pydantic models with validation
  - Mark serialization/deserialization
- Module 2: Boundary Detection Algorithm (positioning.py)
  - BoundaryDetectionAlgorithm class
  - calculate_position() main entry point
  - _apply_constraints() quadrant logic
  - _handle_oversized_window() fallback
  - _fallback_center_position() for invalid cursor
- Module 3: Unit Tests (test_positioning_algorithm.py)
  - 4 test classes with 10+ examples
  - Covers all edge cases
  - pytest-asyncio patterns
- Module 4: Configuration (config.py)
  - load_gap_config() from env vars
- Integration example: Modified ScratchpadManager
- Performance profiling example
- Implementation notes and file checklist

**When to Read**: During implementation when writing actual code.

---

## How to Use These Documents

### For Project Leads (15 minutes)

1. Read: QUICK_REFERENCE.md (understand basics)
2. Read: ANALYSIS_SUMMARY.md (understand edge cases and priority)
3. Review: PYTHON_IMPLEMENTATION.md (confirm feasibility)
4. Decision: Proceed with implementation or request clarifications

---

### For Implementation Team (2-3 hours)

1. **Day 1**:
   - Read QUICK_REFERENCE.md
   - Read ANALYSIS_SUMMARY.md
   - Skim BOUNDARY_DETECTION_ANALYSIS.md (get familiar with structure)

2. **Day 2 (Setup)**:
   - Read PYTHON_IMPLEMENTATION.md completely
   - Set up project structure (models.py, positioning.py, config.py)
   - Copy type-hinted function signatures

3. **Day 3-5 (Implementation)**:
   - Reference BOUNDARY_DETECTION_ANALYSIS.md for test cases
   - Use PYTHON_IMPLEMENTATION.md for code examples
   - Implement BoundaryDetectionAlgorithm class
   - Write unit tests (56 test cases documented)
   - Profile performance (<50ms target)

4. **Day 6 (Integration)**:
   - Integrate with existing ScratchpadManager
   - Add state persistence via Sway marks
   - Test multi-monitor support
   - Profile end-to-end latency

---

### For Code Reviewers (30 minutes)

1. Read: ANALYSIS_SUMMARY.md (understand what was analyzed)
2. Read: Edge case descriptions in BOUNDARY_DETECTION_ANALYSIS.md
3. Verify: Test matrix in ANALYSIS_SUMMARY.md is fully covered
4. Check: Implementation matches PYTHON_IMPLEMENTATION.md patterns

---

## Key Findings Summary

### The Algorithm (in 4 lines)

```python
break_y = workspace_h - (bottom_gap + window_h)
break_x = workspace_w - (right_gap + window_w)
tmp_y = cursor_y - (window_h // 2)
tmp_x = cursor_x - (window_w // 2)

# Apply quadrant-based constraints
if cursor_y > workspace_h/2: new_y = min(tmp_y, break_y) else new_y = max(tmp_y, top_gap)
if cursor_x < workspace_w/2: new_x = max(tmp_x, left_gap) else new_x = min(tmp_x, break_x)
```

### The 8 Critical Edge Cases

1. **Window larger than space** - break_y becomes negative, need fallback
2. **Multi-monitor with negative coords** - Algorithm assumes positive coordinates
3. **Cursor on wrong monitor** - Need monitor detection, fallback to center
4. **Quadrant boundary ambiguity** - Midpoint assigned to lower/right (acceptable)
5. **Integer division rounding** - 1px off-center (intentional, matches bash)
6. **Workspace resizes** - Async race condition, solve with tight sequencing
7. **Gap config > workspace** - Validation needed at startup
8. **No cursor available** - Fallback to center (important for headless)

### Test Coverage Required

**56 test cases** organized in 8 groups:
- Basic Quadrant Positioning (5)
- Gap Configuration (5)
- Boundary Constraint Enforcement (6)
- Window Size vs. Workspace (4)
- Multi-Monitor (4)
- Rounding and Precision (3)
- Quadrant Boundary Behavior (4)
- Constraint Math Validation (4)

### Implementation Complexity

**Estimated Effort**: 3-5 days for experienced Python developer
- Core algorithm: 2 days
- Tests & edge cases: 1.5 days
- Integration & profiling: 1 day
- Documentation: 0.5 days

**Confidence Level**: HIGH - Algorithm is straightforward, edge cases well-understood

---

## Quick Reference Index

### By Topic

**Understanding the Algorithm**:
- QUICK_REFERENCE.md - Algorithm at a glance
- ANALYSIS_SUMMARY.md - Why it works
- BOUNDARY_DETECTION_ANALYSIS.md §Algorithm Pseudocode - Step-by-step explanation

**Edge Cases**:
- ANALYSIS_SUMMARY.md §Critical Edge Cases - 8 cases summarized
- BOUNDARY_DETECTION_ANALYSIS.md §Edge Cases - Full analysis with solutions
- PYTHON_IMPLEMENTATION.md §Module 3 - Test code for each case

**Implementation**:
- PYTHON_IMPLEMENTATION.md §Module 1 - Data models (copy/use directly)
- PYTHON_IMPLEMENTATION.md §Module 2 - Algorithm implementation (copy/adapt)
- PYTHON_IMPLEMENTATION.md §Module 3 - Unit tests (adapt to your test framework)

**Multi-Monitor Support**:
- BOUNDARY_DETECTION_ANALYSIS.md §Edge Case 2 - Why it matters
- BOUNDARY_DETECTION_ANALYSIS.md §Edge Case 3 - Cursor position validation
- PYTHON_IMPLEMENTATION.md §calculate_position() - Multi-monitor handling

**Testing**:
- ANALYSIS_SUMMARY.md §Test Matrix Summary - Overview of all 56 tests
- BOUNDARY_DETECTION_ANALYSIS.md §Test Case Matrix - Complete matrix with inputs/outputs
- PYTHON_IMPLEMENTATION.md §Module 3 - Pytest examples

**Performance**:
- ANALYSIS_SUMMARY.md §Implementation Priority - Performance targets
- BOUNDARY_DETECTION_ANALYSIS.md §Python Implementation Strategy - Performance requirements
- PYTHON_IMPLEMENTATION.md §Performance Profiling - Profiling code example

---

## Document Statistics

| Document | Lines | Size | Focus |
|----------|-------|------|-------|
| QUICK_REFERENCE.md | 274 | 8.1 KB | 2-min overview |
| ANALYSIS_SUMMARY.md | 415 | 15 KB | 10-min summary |
| BOUNDARY_DETECTION_ANALYSIS.md | 963 | 35 KB | 30-min deep dive |
| PYTHON_IMPLEMENTATION.md | 1,017 | 31 KB | Code examples |
| **TOTAL** | **2,669** | **89 KB** | Comprehensive |

---

## Reading Paths by Role

### Product Manager / Tech Lead
```
QUICK_REFERENCE.md (5 min)
    ↓
ANALYSIS_SUMMARY.md (10 min)
    ↓
Decision checkpoint
```
**Total Time**: 15 minutes

---

### Software Engineer (Implementing)
```
QUICK_REFERENCE.md (5 min)
    ↓
ANALYSIS_SUMMARY.md (10 min)
    ↓
BOUNDARY_DETECTION_ANALYSIS.md - Edge Cases §1-8 (20 min)
    ↓
PYTHON_IMPLEMENTATION.md (30 min)
    ↓
BOUNDARY_DETECTION_ANALYSIS.md - Test Case Matrix (30 min)
    ↓
Start coding
```
**Total Time**: 1.5-2 hours

---

### QA / Test Engineer
```
QUICK_REFERENCE.md §Testing Checklist (2 min)
    ↓
ANALYSIS_SUMMARY.md §Test Matrix Summary (5 min)
    ↓
BOUNDARY_DETECTION_ANALYSIS.md §Test Case Matrix (30 min)
    ↓
PYTHON_IMPLEMENTATION.md §Module 3 - Unit Tests (20 min)
    ↓
Create test plan
```
**Total Time**: 1 hour

---

### Code Reviewer
```
ANALYSIS_SUMMARY.md §Decisions Made During Analysis (5 min)
    ↓
BOUNDARY_DETECTION_ANALYSIS.md §Known Limitations (10 min)
    ↓
PYTHON_IMPLEMENTATION.md §Implementation Notes (5 min)
    ↓
Review checklist
```
**Total Time**: 20 minutes

---

## Verification Checklist

Use this to verify implementation matches analysis:

- [ ] Core algorithm implemented in `calculate_position()`
- [ ] All 4 quadrant rules implemented correctly
- [ ] All 8 edge cases have handling code
- [ ] 56 unit tests match test case matrix
- [ ] Type hints on all public functions
- [ ] Async/await patterns throughout
- [ ] Multi-monitor support implemented
- [ ] Cursor validation with fallback
- [ ] Oversized window handling
- [ ] State persistence via Sway marks
- [ ] Performance profiling shows <50ms
- [ ] Gap configuration from env vars
- [ ] Error logging implemented
- [ ] Docstrings match PEP 257
- [ ] Tests pass with 100% code coverage

---

## Next Steps After Research

1. **Phase 1 Design** (Planned)
   - Generate data-model.md (Pydantic models details)
   - Generate contracts/ directory (Sway IPC contracts)
   - Generate quickstart.md (User-facing guide)

2. **Phase 2 Planning** (Planned)
   - Generate tasks.md (Implementation subtasks)
   - Estimate effort per task
   - Assign responsibilities

3. **Phase 3 Implementation** (Planned)
   - Code implementation
   - Unit test development
   - Integration testing
   - Performance validation
   - Documentation updates

---

## Glossary

| Term | Definition |
|------|-----------|
| **break_y** | Maximum Y coordinate before window hits bottom gap boundary |
| **break_x** | Maximum X coordinate before window hits right gap boundary |
| **Quadrant** | One of 4 regions defined by cursor position relative to workspace midpoint |
| **Gap** | Minimum distance from screen edge to floating window (top/bottom/left/right) |
| **Boundary Constraint** | Rule limiting window position to stay within gaps |
| **Centering** | Positioning window so cursor is at window center |
| **Fallback** | Alternate positioning logic when primary fails (e.g., cursor invalid) |
| **Monitor-relative** | Coordinates where (0,0) is monitor top-left |
| **Absolute coordinates** | Screen-relative coordinates (account for monitor offset) |

---

## Issues & Clarifications

**None** - All edge cases have solutions documented.

**To Request Clarification**: Reference the specific document and section:
- "See BOUNDARY_DETECTION_ANALYSIS.md §Edge Case 2 for multi-monitor handling"
- "See PYTHON_IMPLEMENTATION.md §Module 2 for algorithm implementation details"

---

## Archive & Maintenance

**Last Updated**: 2025-11-06
**Author**: Research Phase (Claude Code)
**Status**: Complete - Ready for Phase 1 Design

**To Update These Documents**:
1. Edit the specific document (don't split across files)
2. Update this index if structure changes
3. Keep line count comments current
4. Verify cross-references work

---

## Contact & Questions

For questions about:
- **Algorithm logic**: See BOUNDARY_DETECTION_ANALYSIS.md
- **Implementation approach**: See PYTHON_IMPLEMENTATION.md
- **Test cases**: See BOUNDARY_DETECTION_ANALYSIS.md §Test Case Matrix
- **Edge case handling**: See ANALYSIS_SUMMARY.md §Critical Edge Cases
- **Quick answer**: See QUICK_REFERENCE.md

