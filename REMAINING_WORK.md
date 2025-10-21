# Remaining Work - i3 Project Manager

**Last Updated**: 2025-10-21
**Current Status**: Phase 7 Complete (100%), Phase 4 Incomplete

## Summary

The i3 Project Manager has completed **Phase 7: Polish & Documentation** (all 12 tasks, 100%), bringing the core project management functionality to **v0.3.0 (Beta)** production-ready status.

However, **Phase 4: User Story 2 - Automated Window Class Detection** remains incomplete with 14 pending tasks.

## Current Project Status

### ✅ Completed (100%)

**Phases 1-3, 5-7**: Fully Complete

- **Phase 1**: Setup (8/8 tasks) ✅
- **Phase 2**: Foundational (4/4 tasks) ✅
- **Phase 3**: User Story 1 - Pattern-Based Classification (18/18 tasks) ✅
- **Phase 5**: User Story 3 - Interactive Wizard (23/23 tasks) ✅
- **Phase 6**: User Story 4 - Window Inspector (22/22 tasks) ✅
- **Phase 7**: Polish & Documentation (12/12 tasks) ✅

**Total Completed**: 87/101 tasks (86%)

### ⏭️ Remaining Work

**Phase 4**: User Story 2 - Automated Window Class Detection

**Status**: 0/14 tasks complete (0%)

**Purpose**: Automatically detect WM_CLASS for apps without StartupWMClass using Xvfb isolation

**Goal**: Run a single command that detects window classes for 50+ apps by launching them in an isolated virtual display (Xvfb) where they don't appear on screen.

## Pending Tasks Breakdown

### Phase 4: User Story 2 - Window Class Detection (14 tasks)

#### Tests (7 tasks) - Write FIRST

- [ ] **T031** Unit test for isolated_xvfb context manager
  - Verify Xvfb starts on :99, yields DISPLAY, terminates on exit
  - File: `tests/i3_project_manager/unit/test_xvfb_detection.py`

- [ ] **T032** Unit test for graceful termination
  - Verify SIGTERM → wait → SIGKILL sequence
  - File: `tests/i3_project_manager/unit/test_xvfb_detection.py`

- [ ] **T033** Unit test for cleanup on timeout
  - Verify resources cleaned after 10s timeout
  - File: `tests/i3_project_manager/unit/test_xvfb_detection.py`

- [ ] **T034** Unit test for dependency check
  - Verify check_xvfb_available() returns False when xvfb-run missing
  - File: `tests/i3_project_manager/unit/test_xvfb_detection.py`

- [ ] **T035** Unit test for WM_CLASS parsing
  - Verify regex extracts class from xprop output
  - File: `tests/i3_project_manager/unit/test_xvfb_detection.py`

- [ ] **T036** Integration test for detection workflow
  - Mock Xvfb/xdotool/xprop, verify DetectionResult created
  - File: `tests/i3_project_manager/scenarios/test_detection_workflow.py`

- [ ] **T037** Integration test for bulk detection
  - Verify 10 apps detected with progress, <60s total time
  - File: `tests/i3_project_manager/integration/test_xvfb_detection.py`

#### Implementation (7 tasks) - After Tests

- [ ] **T038** Implement isolated_xvfb() context manager
  - Use subprocess.Popen for Xvfb
  - SIGTERM/SIGKILL cleanup in finally block
  - File: `home-modules/tools/i3_project_manager/core/app_discovery.py`

- [ ] **T039** Implement check_xvfb_available()
  - Use shutil.which() to check for Xvfb, xdotool, xprop
  - File: `home-modules/tools/i3_project_manager/core/app_discovery.py`

- [ ] **T040** Implement detect_window_class_xvfb()
  - Launch app in isolated Xvfb display
  - Poll for window with xdotool
  - Extract WM_CLASS with xprop
  - Terminate app and cleanup
  - File: `home-modules/tools/i3_project_manager/core/app_discovery.py`

- [ ] **T041** Add detection result caching
  - Save to `~/.cache/i3pm/detected-classes.json`
  - Invalidate after 30 days
  - File: `home-modules/tools/i3_project_manager/core/app_discovery.py`

- [ ] **T042** Add CLI command `i3pm app-classes detect`
  - Options: --all-missing, --isolated, --timeout, --cache, --verbose
  - Dependency check
  - Progress indication using rich.Progress
  - File: `home-modules/tools/i3_project_manager/cli/commands.py`

- [ ] **T043** Add detection logging
  - Write to `~/.cache/i3pm/detection.log`
  - Include: timestamp, app name, detected class, duration, errors
  - File: `home-modules/tools/i3_project_manager/core/app_discovery.py`

- [ ] **T044** Add fallback to guess algorithm
  - When Xvfb unavailable, timeout expires, or --skip-isolated
  - File: `home-modules/tools/i3_project_manager/core/app_discovery.py`

## Why This Work Remains

The Xvfb detection feature (User Story 2) was **deprioritized** because:

1. **Not essential for core functionality**: Pattern-based classification (US1) and manual wizard classification (US3) provide complete workflow without auto-detection
2. **External dependency**: Requires Xvfb, xdotool, xprop which may not be installed
3. **Complexity vs. value**: Significant implementation complexity for a nice-to-have feature
4. **Alternative exists**: Users can manually specify WM_CLASS in wizard or use existing guess algorithm

The project prioritized **production readiness** (Phase 7) over this optional enhancement.

## Impact of Remaining Work

### Current Capabilities WITHOUT Phase 4

Users can already:
- ✅ Create pattern rules for auto-classification (glob/regex)
- ✅ Use interactive wizard to classify apps
- ✅ Inspect windows to see classification status
- ✅ Manual detection via clicking on windows
- ✅ Guess WM_CLASS from desktop files

### Additional Capabilities WITH Phase 4

Users would gain:
- 🔲 Automatic WM_CLASS detection without manual intervention
- 🔲 Batch detection of 50+ apps in under 60 seconds
- 🔲 Isolated detection (apps don't appear on screen)
- 🔲 Detection caching for faster repeat operations
- 🔲 Detection logging for troubleshooting

## Recommendation

### Option 1: Ship v0.3.0 Beta WITHOUT Phase 4 ✅ RECOMMENDED

**Rationale**:
- Core functionality is complete and production-ready
- Phase 7 polish ensures excellent UX
- Users have complete workflow without auto-detection
- Can add Phase 4 in v0.4.0 as enhancement

**Action**: Tag v0.3.0 Beta release NOW with current features

### Option 2: Complete Phase 4 for v0.3.0

**Effort**: ~14 tasks, estimated 2-3 development sessions
**Risk**: Delays v0.3.0 release
**Benefit**: More complete feature set

**Action**: Implement T031-T044 before tagging v0.3.0

### Option 3: Defer to v0.4.0

**Rationale**: Phase 4 is enhancement, not blocker
**Action**: Ship v0.3.0 now, plan Phase 4 for v0.4.0

## Next Steps

### Immediate (Recommended)

1. **Tag v0.3.0 Beta Release**
   ```bash
   git tag -a v0.3.0-beta -m "i3 Project Manager v0.3.0 (Beta) - Production Ready"
   git push origin v0.3.0-beta
   ```

2. **Update Documentation**
   - Add "Known Limitations" section noting Xvfb detection not yet implemented
   - Document workaround (manual classification via wizard)

3. **Announce Beta Release**
   - Highlight completed features
   - Note Phase 4 planned for v0.4.0

### Short-Term (v0.3.1 or v0.4.0)

1. **Implement Phase 4** (if desired)
   - Follow TDD approach (tests first)
   - Complete all 14 tasks
   - Validate with real Xvfb environment

2. **Gather User Feedback**
   - Is Xvfb detection needed?
   - What other features are more valuable?
   - Prioritize based on user needs

### Long-Term Enhancements

Based on spec.md future enhancements:

1. **Fuzzy shell completion** (fish/zsh support)
2. **Log file rotation** (--log-file flag)
3. **Per-module verbosity** (--verbose-modules flag)
4. **Structured logging** (--log-format=json)
5. **Additional user guides** (Wizard, Xvfb)

## Files Affected

### If Implementing Phase 4

**New Files**:
- `tests/i3_project_manager/unit/test_xvfb_detection.py` (~200 lines)
- `tests/i3_project_manager/scenarios/test_detection_workflow.py` (~150 lines)
- `tests/i3_project_manager/integration/test_xvfb_detection.py` (~100 lines)

**Modified Files**:
- `home-modules/tools/i3_project_manager/core/app_discovery.py` (~300 lines added)
- `home-modules/tools/i3_project_manager/cli/commands.py` (~100 lines added for detect command)

**Total Estimated**: ~850 lines of code and tests

## Current Version Status

### v0.3.0 (Beta) - READY FOR RELEASE ✅

**Status**: Production-ready
**Completeness**: 87/101 tasks (86%)
**Features**:
- ✅ Pattern-based auto-classification
- ✅ Interactive classification wizard
- ✅ Real-time window inspector
- ✅ JSON output for automation
- ✅ Dry-run mode for safety
- ✅ Verbose logging for debugging
- ✅ Shell completion for efficiency
- ✅ Schema validation for integrity
- ✅ Comprehensive documentation
- ✅ Extensive test coverage (90%+)

**Known Limitations**:
- ⚠️ No automatic Xvfb detection (manual classification required)
- ⚠️ Shell completion only for Bash (Fish/Zsh not yet supported)
- ⚠️ Logging to stderr only (no log files)

**Recommended for**: Production use, with understanding that some nice-to-have features are planned for future versions

## Decision Matrix

| Scenario | Ship v0.3.0 Now? | Complete Phase 4? | Defer to v0.4.0? |
|----------|------------------|-------------------|------------------|
| Need production release ASAP | ✅ Yes | ❌ No | ✅ Yes |
| Want complete feature set | ⚠️ Maybe | ✅ Yes | ❌ No |
| Minimize risk | ✅ Yes | ❌ No | ✅ Yes |
| Maximize features | ❌ No | ✅ Yes | ❌ No |
| User feedback first | ✅ Yes | ❌ No | ✅ Yes |

## Conclusion

**i3 Project Manager v0.3.0 (Beta) is production-ready** with 87/101 tasks complete (86%).

The remaining 14 tasks (Phase 4: Xvfb Detection) are **optional enhancements** that do not block release. The core project management functionality is complete, polished, tested, and documented.

**Recommendation**: Ship v0.3.0 Beta NOW and defer Phase 4 to v0.4.0 based on user feedback.

---

**Last Updated**: 2025-10-21
**Current Branch**: `020-update-our-spec`
**Next Action**: Tag v0.3.0-beta release
