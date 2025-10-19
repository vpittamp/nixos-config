# Feature 014: i3 Project Management System - Consolidation & Validation

**Status**: 🟡 Phase 1 Complete, Phase 2+ Ready to Begin
**Date**: 2025-10-19
**Type**: System Integration & Constitutional Compliance

---

## 🎯 Feature Overview

This feature consolidates the i3-native project management system (Feature 012) with the i3blocks status bar integration (Feature 013), validates the complete system, and remediates constitutional compliance violations to achieve full NixOS reproducibility.

### Goals
1. ✅ Validate integrated system functionality
2. 🔄 Convert all scripts to declarative Nix generation
3. 🔄 Eliminate hardcoded binary paths (constitutional violation)
4. 🔄 Remove polybar remnants
5. 🔄 Test complete project lifecycle end-to-end

---

## 📊 Current Status

### ✅ Phase 1 Complete (3/94 tasks - 3.2%)

**Completed**:
- T001: i3 schema validation script created
- T002: JSON schema validation script created
- T003: Automated UI test suite created

**Deliverables**:
- `/etc/nixos/tests/validate-i3-schema.sh` - Validates window marks, i3 IPC
- `/etc/nixos/tests/validate-json-schemas.sh` - Validates project configs
- `/etc/nixos/tests/i3-project-test.sh` - Automated xdotool testing

### 🔄 Phase 2-10 Ready to Begin (91 tasks remaining)

**Next Critical Phase**: Phase 2 - Constitutional Compliance (26 tasks)

---

## 📚 Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| **IMPLEMENTATION_GUIDE.md** | Complete how-to with working examples | Developers implementing Phase 2+ |
| **PROGRESS_SUMMARY.md** | Status, timeline, metrics | Project managers, stakeholders |
| **QUICK_REFERENCE.md** | Cheat sheet for script conversion | Developers doing conversions |
| **tasks.md** | Detailed task breakdown (94 tasks) | Implementation tracking |
| **spec.md** | User stories and requirements | Understanding the "why" |
| **plan.md** | Architecture and tech stack | Understanding the "how" |
| **research.md** | Constitutional compliance findings | Context and decisions |
| **data-model.md** | Entity relationships | Data structure reference |

---

## 🚀 Quick Start

### To Continue Implementation

1. **Read the Implementation Guide**:
   ```bash
   cd /etc/nixos/specs/014-create-a-new
   cat IMPLEMENTATION_GUIDE.md
   ```

2. **Understand What's Done**:
   ```bash
   cat PROGRESS_SUMMARY.md
   ```

3. **Get the Cheat Sheet**:
   ```bash
   cat QUICK_REFERENCE.md
   ```

4. **Review the Task List**:
   ```bash
   cat tasks.md
   ```

5. **Start Phase 2**:
   - Begin with T004-T005 (foundation)
   - Follow templates in Implementation Guide
   - Test incrementally

### To Run Validation Scripts

```bash
# Run all validation
cd /etc/nixos/tests
./validate-i3-schema.sh
./validate-json-schemas.sh
./i3-project-test.sh

# Or individually
/etc/nixos/tests/validate-i3-schema.sh
```

---

## 🔑 Key Insights

### What Makes This Feature Critical

1. **Constitutional Compliance** 🚨
   - Current system violates NixOS Principle VI (Declarative Configuration)
   - 21 scripts use imperative file copying
   - 100+ hardcoded binary paths break reproducibility
   - **Must fix before system is truly reproducible**

2. **System Consolidation**
   - Merges Feature 012 + Feature 013
   - Removes polybar remnants
   - Eliminates code duplication
   - Creates unified, validated system

3. **Production Readiness**
   - Comprehensive validation scripts
   - End-to-end testing
   - Performance verification
   - Documentation updates

### Why Phase 2 is Critical

Phase 2 (Constitutional Compliance) is the **bottleneck** - all other phases are blocked until it completes.

**Impact if not fixed**:
- System won't work in minimal containers
- Can't reproduce across different machines
- Violates NixOS principles
- Breaks when PATH changes

**Impact when fixed**:
- ✅ Full reproducibility guaranteed
- ✅ Works in any environment
- ✅ Constitutional compliance achieved
- ✅ Foundation for all other work

---

## 📈 Timeline Estimate

| Phase | Tasks | Estimated Time | Status |
|-------|-------|----------------|--------|
| Phase 1: Setup | 3 | 3-4 hours | ✅ Complete |
| Phase 2: Constitutional | 26 | 45-78 hours | 🔴 Not Started |
| Phase 3-6: P1 Stories | 23 | 8-12 hours | 🔴 Blocked |
| Phase 7-8: P2 Stories | 14 | 5-8 hours | 🔴 Blocked |
| Phase 9: P3 Story | 5 | 2-3 hours | 🔴 Blocked |
| Phase 10: Polish | 23 | 10-15 hours | 🔴 Blocked |
| **TOTAL** | **94** | **73-120 hours** | **3.2% Complete** |

**Realistic Timeline**:
- **Full-time**: 2-3 weeks
- **Part-time**: 4-6 weeks
- **Critical Path**: Phase 2 completion

---

## 🎓 Learning Resources

### For Understanding the System

1. **Start with spec.md** - Understand user stories
2. **Read research.md** - Learn about constitutional issues
3. **Study data-model.md** - Understand entities and relationships
4. **Check contracts/** - See JSON schemas

### For Implementation

1. **IMPLEMENTATION_GUIDE.md** - Your primary resource
2. **QUICK_REFERENCE.md** - Keep this handy
3. **Existing scripts** - In `home-modules/desktop/scripts/`
4. **Nix manual** - https://nixos.org/manual/nixpkgs/stable/

---

## ✅ Success Criteria (When Complete)

### Constitutional Compliance
- ✅ Zero hardcoded binary paths
- ✅ All scripts use `text = ''...''` declarative generation
- ✅ All binaries use `${pkgs.*/bin/*}` format
- ✅ No imperative `source = ./file.sh` patterns

### Functional Requirements
- ✅ All 7 user stories validated independently
- ✅ Complete project lifecycle <60 seconds
- ✅ Status bar updates <1 second
- ✅ i3 restart preserves state
- ✅ Multi-monitor support working

### Quality Metrics
- ✅ All validation scripts pass
- ✅ Zero code duplication
- ✅ Documentation updated
- ✅ No polybar remnants
- ✅ No redundant state files

---

## 🆘 Getting Help

### If Stuck During Implementation

1. **Check Implementation Guide** - Common issues documented
2. **Review Templates** - 3 working examples provided
3. **Run Validation Scripts** - Identify what's broken
4. **Check Logs** - `~/.config/i3/project-system.log`
5. **Test Incrementally** - Don't convert everything at once

### Common Resources

```bash
# Check for hardcoded paths
rg "#!/bin/bash" home-modules/desktop/

# Validate Nix syntax
nixos-rebuild dry-build --flake .#hetzner --show-trace

# Test converted script
~/.config/i3/scripts/project-current.sh

# View generated script
cat ~/.config/i3/scripts/project-current.sh
```

---

## 📁 Repository Structure

```
/etc/nixos/specs/014-create-a-new/
├── README.md                      # ← You are here
├── IMPLEMENTATION_GUIDE.md        # Complete how-to guide
├── PROGRESS_SUMMARY.md            # Status and timeline
├── QUICK_REFERENCE.md             # Cheat sheet
├── tasks.md                       # 94 tasks breakdown
├── spec.md                        # User stories
├── plan.md                        # Architecture
├── research.md                    # Findings
├── data-model.md                  # Entities
├── quickstart.md                  # User guide
├── contracts/                     # JSON schemas
│   ├── project-config-schema.json
│   ├── active-project-schema.json
│   ├── app-classes-schema.json
│   └── logging-format.md
└── checklists/
    └── requirements.md            # ✅ All 16 items complete

/etc/nixos/tests/
├── validate-i3-schema.sh          # ✅ Created
├── validate-json-schemas.sh       # ✅ Created
└── i3-project-test.sh             # ✅ Created

/etc/nixos/home-modules/desktop/
├── i3-project-manager.nix         # 🔄 Needs conversion (Phase 2)
├── scripts/                       # 🔄 21 scripts to convert
│   ├── i3-project-common.sh
│   ├── project-create.sh
│   ├── project-switch.sh
│   └── ... (18 more)
└── i3blocks/
    ├── default.nix                # 🔄 Needs conversion (Phase 2)
    └── scripts/                   # 🔄 5 scripts to convert
        ├── project.sh
        ├── cpu.sh
        ├── memory.sh
        ├── network.sh
        └── datetime.sh
```

---

## 🎯 Next Actions

**Immediate Next Steps**:

1. ✅ **Read IMPLEMENTATION_GUIDE.md** (15-20 minutes)
2. ✅ **Review QUICK_REFERENCE.md** (5 minutes)
3. 🔄 **Start T004**: Study i3-project-manager.nix structure
4. 🔄 **Start T005**: Create commonFunctions let binding
5. 🔄 **Start T010**: Convert project-current.sh (template provided)
6. 🔄 **Test**: nixos-rebuild dry-build and deploy
7. 🔄 **Validate**: Run validation scripts

**Remember**:
- Phase 2 is the critical path - everything else is blocked
- Work incrementally - test after each 2-3 conversions
- Use the templates - don't reinvent the wheel
- Ask for help if stuck - documentation is comprehensive

---

## 📞 Maintenance

### After Implementation Complete

**Update these files**:
- `/etc/nixos/CLAUDE.md` - Update "Project Management Workflow" section
- `/etc/nixos/docs/ARCHITECTURE.md` - If it mentions polybar
- This README.md - Mark as 100% complete

**Archive this feature**:
```bash
# Mark as complete
echo "Status: ✅ Complete" >> README.md

# Tag in git
git tag feature-014-complete
```

---

## 📊 Metrics Dashboard

**Progress**: 3/94 tasks (3.2%)

**Phases**:
- ✅ Phase 1: Setup (100%)
- 🔴 Phase 2: Constitutional Compliance (0%)
- 🔴 Phase 3-6: P1 User Stories (0%)
- 🔴 Phase 7-8: P2 User Stories (0%)
- 🔴 Phase 9: P3 User Story (0%)
- 🔴 Phase 10: Polish (0%)

**Estimated Completion**: 2-6 weeks (depending on pace)

**Blockers**: None (Phase 2 ready to begin)

**Risks**:
- High volume of conversion work
- Testing burden on each conversion
- Need for careful attention to detail

**Mitigation**:
- Comprehensive templates provided
- Validation scripts ready
- Incremental testing approach
- Clear success criteria

---

**Ready to build? Start with `IMPLEMENTATION_GUIDE.md`** 🚀

---

**Document Version**: 1.0
**Last Updated**: 2025-10-19
**Maintained By**: Feature 014 Implementation Team
**Status**: Phase 1 Complete, Ready for Phase 2
