# Feature 038: Window State Preservation - Requirements Checklist

**Feature**: Window State Preservation Across Project Switches
**Branch**: `038-create-a-new`
**Status**: Specification Complete
**Date**: 2025-10-25

## Specification Quality Checklist

### User Scenarios & Testing ✅

- [x] **P1 User Story Defined**: Preserve Tiled Window State - Core functionality that fixes the floating window bug
- [x] **P2 User Story Defined**: Preserve Floating Window State - Maintains intentionally floated windows
- [x] **P1 User Story Defined**: Preserve Workspace Assignment - Critical for multi-workspace workflows
- [x] **P3 User Story Defined**: Handle Scratchpad Native Windows - Less common but important edge case
- [x] **Independent Testing**: Each user story includes clear independent test scenarios
- [x] **Acceptance Criteria**: Given/When/Then scenarios provided for all user stories
- [x] **Edge Cases Documented**: 5 edge cases identified with proposed solutions
- [x] **Priority Justification**: Each user story includes "Why this priority" explanation

### Requirements ✅

- [x] **Functional Requirements**: 10 specific FR requirements defined (FR-001 through FR-010)
- [x] **Key Entities Defined**: WindowState entity with existing and new attributes documented
- [x] **Data Persistence**: FR-009 specifies persistence requirement for daemon restarts
- [x] **State Handling**: Requirements cover both tiled and floating window states
- [x] **Workspace Management**: Requirements address exact workspace restoration (not current)

### Success Criteria ✅

- [x] **Measurable Outcomes**: 6 specific success criteria defined (SC-001 through SC-006)
- [x] **Quantifiable Metrics**: Includes percentages (100%), thresholds (<10px, <50ms), and counts (0%)
- [x] **Performance Targets**: SC-004 and SC-006 define performance expectations
- [x] **Reliability Targets**: SC-005 specifies zero data loss requirement
- [x] **User Experience Targets**: SC-001-SC-003 define correct behavior percentages

### Implementation Guidance ✅

- [x] **Technical Analysis**: Detailed analysis of i3ass (i3run/i3king) behavior patterns
- [x] **Root Cause Identified**: Current implementation issues documented with code references
- [x] **Solution Proposed**: 3-step solution with code examples provided
- [x] **Files to Modify**: 3 specific files identified with change descriptions
- [x] **Testing Strategy**: Manual testing steps and future automated testing direction provided
- [x] **Performance Analysis**: Expected impact documented (<10ms for 10 windows)
- [x] **Compatibility**: Backward compatibility with existing data files confirmed

### Documentation Quality ✅

- [x] **Clear Problem Statement**: User's original issue quoted and explained
- [x] **Technical Context**: i3 scratchpad behavior insights from i3ass documentation
- [x] **Code References**: Line numbers and file paths provided for current issues
- [x] **JSON Schema Examples**: Extended schema shown with comments
- [x] **Python Code Examples**: Implementation pseudocode provided for key operations
- [x] **Integration Points**: References to existing systems (window-workspace-map.json, filter_windows_by_project)

## Compliance Assessment

### Mandatory Sections ✅
- [x] User Scenarios & Testing section complete
- [x] Requirements section complete
- [x] Success Criteria section complete
- [x] Edge cases documented
- [x] Implementation notes provided

### User Story Quality ✅
- [x] All user stories independently testable
- [x] Priorities assigned (P1, P2, P3)
- [x] Priority justifications provided
- [x] Clear acceptance criteria in Given/When/Then format

### Technical Completeness ✅
- [x] Root cause analysis complete
- [x] Solution architecture defined
- [x] Data model changes specified
- [x] Performance impact analyzed
- [x] Backward compatibility addressed

## Risk Assessment

### Low Risk Items ✅
- **Backward Compatibility**: New fields in JSON are optional, missing fields use defaults
- **Performance**: <10ms overhead is negligible for user experience
- **Data Persistence**: Extends existing proven persistence mechanism

### Medium Risk Items ⚠️
- **i3 Tiling Algorithm**: Cannot guarantee pixel-perfect tiled window positions (FR-008 acknowledges this)
- **Rapid Switching**: Need to verify worker queue handles rapid project switches correctly (SC-006)

### Mitigation Strategies
- **Tiling Position**: User story P1 acceptance criteria focuses on "remain tiled" not pixel-perfect positioning
- **Rapid Switching**: Existing worker queue mechanism should handle this, but needs testing

## Implementation Readiness

### Prerequisites ✅
- [x] Existing window tracking system in place (`window-workspace-map.json`)
- [x] i3ipc library provides rect (geometry) and floating properties
- [x] Scratchpad hide/show mechanisms already working
- [x] Mark-based window identification system functional (Feature 037)

### Dependencies ✅
- [x] No external dependencies required
- [x] Uses existing Python i3ipc library
- [x] Extends existing JSON storage format
- [x] Leverages existing daemon state management

### Testing Readiness ✅
- [x] Manual testing procedure documented
- [x] Test scenarios cover all P1 and P2 user stories
- [x] Success criteria provide clear pass/fail conditions
- [x] Existing i3-project-test framework available for future automation

## Approval Checklist

- [x] **Specification Complete**: All mandatory sections filled out
- [x] **User Stories Prioritized**: P1 (critical), P2 (important), P3 (nice-to-have)
- [x] **Requirements Clear**: 10 functional requirements with specific MUST conditions
- [x] **Success Criteria Measurable**: 6 quantifiable success criteria
- [x] **Implementation Guided**: Technical approach, files to modify, and code examples provided
- [x] **Risks Identified**: Known limitations documented (tiling algorithm, rapid switching)
- [x] **Testing Defined**: Manual testing procedure ready for immediate use

## Next Steps

1. **Review & Approve**: User/stakeholder reviews specification for completeness
2. **Implementation Planning**: Break down into tasks (T001-T00X) based on user stories
3. **P1 Implementation**: Start with User Story 1 (Preserve Tiled Window State) as MVP
4. **Testing**: Execute manual testing procedure after P1 implementation
5. **Iteration**: Implement P2 and P3 stories based on P1 success
6. **Documentation**: Update quickstart.md with new window state behavior

---

**Specification Status**: ✅ **APPROVED FOR IMPLEMENTATION**

**Confidence Level**: High
- Clear problem statement from user experience
- Root cause identified in current code
- Solution validated against i3ass documentation patterns
- Backward compatible implementation approach
- Measurable success criteria defined
