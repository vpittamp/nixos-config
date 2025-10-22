# Feature 024 Reconciliation - Quick Reference

**Date**: 2025-10-22
**Command**: `/speckit.plan` with reconciliation analysis
**Status**: ✅ **RECONCILIATION COMPLETE** - Ready for implementation

## What Happened?

Feature 024 planned to implement a comprehensive window management system with 52 tasks. During the planning phase, I discovered **60-70% of the functionality already exists** in the `i3-project-event-daemon` codebase.

## Quick Links

### Primary Documents (Read These First)

1. **[RECONCILIATION_SUMMARY.md](./RECONCILIATION_SUMMARY.md)** - Executive summary, recommendations
2. **[tasks-reconciled.md](./tasks-reconciled.md)** - 24 net-new tasks to implement
3. **[plan-reconciled.md](./plan-reconciled.md)** - Updated implementation plan

### Supporting Documents

4. **[OVERLAP_ANALYSIS.md](./OVERLAP_ANALYSIS.md)** - Detailed technical analysis of overlaps
5. **[tasks.md](./tasks.md)** - Original 52 tasks (deprecated, marked as reference)

### Existing Specification Documents (Still Valid)

6. **[spec.md](./spec.md)** - Feature specification (user stories, requirements)
7. **[data-model.md](./data-model.md)** - Data models (now references existing models)
8. **[quickstart.md](./quickstart.md)** - User guide (still valid)
9. **[research.md](./research.md)** - Technical research (still valid)
10. **contracts/** - JSON schemas and API contracts (still valid)

## Key Findings

### Already Implemented (No Work Needed)

✅ Window rules engine (`window_rules.py`)
✅ Pattern matching (`pattern.py`) - exact, glob, regex, pwa, title
✅ Window classification (`pattern_resolver.py`) - 4-level precedence
✅ Multi-monitor workspace distribution (`workspace_manager.py`)
✅ Project-scoped window management (`handlers.py`)
✅ Event-driven architecture (`daemon.py`)

### Needs Implementation (24 Tasks)

❌ Structured action types (vs string commands)
❌ JSON schema migration (backwards-compatible)
❌ Workspace validation for multi-monitor
❌ Output event handling
❌ CLI validation tools (`i3pm validate-rules`, `i3pm test-rule`)
❌ Hot-reload support
❌ Migration script (old format → new format)

## Task Breakdown

### Original Plan
- **52 tasks** across 7 phases
- **7-11 days** estimated time
- Build entire window management system from scratch

### Reconciled Plan
- **24 tasks** across 5 phases (28 removed as duplicates)
- **7-9 days** estimated time (same, but less new code)
- Enhance existing working system

## Implementation Phases

### Phase 1: Schema Migration & Structured Actions (3 days)
**Tasks**: R001-R006
**Deliverables**: Action types, enhanced WindowRule, migration script

### Phase 2: Action Execution & Multi-Monitor Validation (2 days)
**Tasks**: R007-R013
**Deliverables**: Action executor, workspace validation, output events

### Phase 3: CLI Tools (1-2 days)
**Tasks**: R014-R017
**Deliverables**: `i3pm validate-rules`, `i3pm test-rule`

### Phase 4: Hot-Reload (1 day)
**Tasks**: R018-R020
**Deliverables**: File watch and reload without daemon restart

### Phase 5: Testing & Polish (1 day)
**Tasks**: R021-R024
**Deliverables**: Error handling, monitoring, integration tests, docs

## Decision: Enhance vs Replace

### What We're Doing ✅

- **Enhance** existing `WindowRule` to support structured actions
- **Add** new action types on top of existing pattern matching
- **Integrate** validation into existing workspace management
- **Extend** CLI tools with new validation commands
- **Maintain** backwards compatibility with old format

### What We're NOT Doing ❌

- ❌ Replace `window_rules.py` (already works)
- ❌ Replace `pattern.py` (already comprehensive)
- ❌ Replace `pattern_resolver.py` (4-level precedence works)
- ❌ Replace `workspace_manager.py` (multi-monitor works)
- ❌ Break existing project management (Feature 015)

## Backwards Compatibility Strategy

**Old Format** (current):
```json
[
  {
    "pattern_rule": {"pattern": "Code", "scope": "scoped", "priority": 250},
    "workspace": 2,
    "command": "layout tabbed"
  }
]
```

**New Format** (Feature 024):
```json
{
  "version": "1.0",
  "rules": [
    {
      "name": "vscode-workspace-2",
      "match_criteria": {"class": {"pattern": "Code", "match_type": "exact"}},
      "actions": [
        {"type": "workspace", "target": 2},
        {"type": "layout", "mode": "tabbed"}
      ],
      "priority": "project"
    }
  ]
}
```

**Support Strategy**:
- Both formats work during transition
- Migration script available: `i3pm migrate-rules`
- Old format deprecated in future release (not removed yet)

## Code Locations

### Existing Code (Enhance)
```
home-modules/desktop/i3-project-event-daemon/
├── window_rules.py          # ENHANCE: Add actions field
├── pattern.py               # KEEP: Already works
├── pattern_resolver.py      # KEEP: Already works
├── workspace_manager.py     # ENHANCE: Add validation
├── handlers.py              # ENHANCE: Add output events
├── daemon.py                # ENHANCE: Subscribe to output events
└── models.py                # ENHANCE: Add missing properties
```

### New Code (Create)
```
home-modules/desktop/i3-project-event-daemon/
├── rule_action.py           # NEW: Action types
└── action_executor.py       # NEW: Execute actions

home-modules/tools/i3_project_manager/
├── schemas/
│   └── window_rules.json    # NEW: JSON schema
├── cli/
│   ├── validate_rules.py    # NEW: Validation
│   └── test_rule.py         # NEW: Testing
└── migration/
    └── rules_v1_migration.py # NEW: Migration
```

## Next Steps

1. ✅ **Review reconciliation documents** (you are here)
2. ⏭️ **Choose implementation approach**:
   - Option A: Implement all 24 tasks (7-9 days)
   - Option B: MVP only (Phases 1-2, ~5 days)
   - Option C: Parallel team approach (3 developers, ~5 days)
3. ⏭️ **Begin implementation** following tasks-reconciled.md
4. ⏭️ **Incremental deployment** after each phase

## Questions?

**Q: Why not just use the original plan?**
A: 60% of it is already implemented. Reimplementing would violate Constitution Principle I (no duplication) and waste time.

**Q: Will this break existing functionality?**
A: No - backwards compatibility is maintained. Old format still works.

**Q: When should I migrate to the new format?**
A: Use migration script whenever ready. No rush - both formats work.

**Q: What if I just want basic functionality?**
A: Implement Phases 1-2 only (R001-R013) for MVP, skip CLI and hot-reload.

**Q: Can multiple developers work on this?**
A: Yes - Phases 2, 3, 4 can be developed in parallel after Phase 1.

## Success Metrics

### Code Quality
- ✅ No duplicate functionality (Constitution compliant)
- ✅ Enhances existing working code
- ✅ 60% code reuse vs original plan
- ✅ Backwards compatible

### Performance
- ✅ Maintains existing performance (< 100ms window detection)
- ✅ Adds < 25ms overhead for actions
- ✅ Schema validation < 100ms
- ✅ Hot-reload < 500ms

### User Experience
- ✅ Backwards-compatible format
- ✅ Clear migration path
- ✅ CLI validation tools
- ✅ Comprehensive documentation

## Document Status

**Reconciliation**: ✅ Complete
**Implementation**: ⏭️ Ready to start
**Approval**: ⏳ Awaiting user decision

---

**Prepared by**: Claude Code
**Command**: `/speckit.plan` (reconciliation mode)
**Branch**: 024-update-replace-test
**Date**: 2025-10-22
