# Sway Window Mark Storage Research - Complete Index

**Research Date**: November 6, 2025
**Context**: Feature 051 (i3run-Inspired Scratchpad Enhancement)
**Status**: Complete and ready for implementation

---

## Document Overview

This research consists of 4 comprehensive documents covering Sway window mark storage limitations and best practices:

### 1. **SWAY_MARK_SUMMARY.md** (Quick Start - 8.7 KB)
**For**: Quick reference and decision-making
- Executive summary of findings
- Mark format recommendation
- Code snippets (Python, Bash)
- Common pitfalls
- Q&A section

**Start here if**: You need quick answers or are new to the research

---

### 2. **SWAY_MARK_RESEARCH.md** (Detailed Analysis - 20 KB)
**For**: In-depth understanding of limitations and best practices
- Complete testing methodology
- Mark length limits with test data
- Multiple marks per window behavior
- Character restriction analysis
- Performance characteristics
- Serialization format recommendations
- Community best practices from i3run
- Edge cases and limitations
- Implementation recommendations for Feature 051
- Testing and troubleshooting guide

**Start here if**: You're implementing state storage or need comprehensive background

---

### 3. **SWAY_MARK_TECHNICAL_REFERENCE.md** (Implementation Guide - 19 KB)
**For**: Developers implementing Feature 051
- Quick reference for mark lifecycle
- swaymsg syntax examples
- Step-by-step test procedures
- Complete Python code examples
- Async Python + Sway integration
- Shell script examples
- Performance benchmarks
- Data type encoding
- Error handling strategies
- Migration considerations
- Troubleshooting guide

**Start here if**: You're writing code to use marks

---

### 4. **SWAY_MARK_TEST_RESULTS.md** (Empirical Data - 8.7 KB)
**For**: Verification and confidence in findings
- Complete test summary
- Individual test results (10 tests, 100% pass rate)
- Test data and metrics
- Performance measurements
- Recommendations based on testing
- Conclusion and ready-to-implement status

**Start here if**: You want to verify experimental methodology or see raw test data

---

## Quick Navigation

### By Role

**Specification Writer**
→ Read SUMMARY (decisions) + RESEARCH (requirements)

**Implementation Developer**
→ Read SUMMARY (format) + TECHNICAL_REFERENCE (code examples)

**Architecture Reviewer**
→ Read RESEARCH (limitations) + TEST_RESULTS (validation)

**QA/Testing**
→ Read TECHNICAL_REFERENCE (test procedures) + TEST_RESULTS (benchmarks)

### By Question

**"What's the mark length limit?"**
→ SUMMARY (Quick Reference) or RESEARCH (Test 1: Mark Length Limits)

**"Can I store multiple pieces of data?"**
→ SUMMARY (Recommended Format) or RESEARCH (Section 2: Multiple Marks Per Window)

**"What characters are allowed?"**
→ RESEARCH (Section 3: Character Restrictions)

**"How do I implement this?"**
→ TECHNICAL_REFERENCE (Python code examples)

**"Will this survive daemon restart?"**
→ RESEARCH (Section 8: Mark Persistence)

**"How fast is it?"**
→ TEST_RESULTS (Test 5: Performance Benchmarks)

**"Show me test results"**
→ TEST_RESULTS (entire document)

---

## Key Findings Summary

| Finding | Value | Location |
|---------|-------|----------|
| Mark length limit | None detected (tested to 2000+) | RESEARCH §1 |
| Marks per window | 1 (new replaces old) | RESEARCH §2 |
| Character support | All (including `:=,` needed for format) | RESEARCH §3 |
| Mark persistence | Across daemon restart (not Sway) | RESEARCH §8 |
| Operation latency | ~1ms (mark) + ~2ms (query) | TEST_RESULTS §5 |
| Toggle behavior | Add if absent, remove if present | RESEARCH §4 |
| Unicode support | Full | TEST_RESULTS §2 |
| Error handling | Graceful (fallback to defaults) | TEST_RESULTS §8 |

---

## Recommended Implementation Path

### Phase 1: Foundation (Week 1)
1. Review SUMMARY and RESEARCH documents
2. Implement mark parsing/creation (TECHNICAL_REFERENCE code)
3. Add unit tests for mark handling
4. Benchmark on real workloads

### Phase 2: Integration (Week 2)
1. Store marks when terminal hidden
2. Retrieve marks when terminal shown
3. Apply geometry from marks
4. Add integration tests

### Phase 3: Enhancement (Week 3)
1. Implement mouse positioning (uses stored x, y)
2. Add workspace summoning mode
3. Implement floating state preservation
4. Complete Feature 051 requirements

### Phase 4: Testing (Week 4)
1. Edge case testing (from RESEARCH)
2. Performance validation (from TEST_RESULTS)
3. Multi-project scenarios
4. Documentation

---

## Mark Format Specification

### Recommended Format
```
scratchpad_state:{project_name}=floating:{bool},x:{int},y:{int},w:{int},h:{int},ts:{unix_epoch}
```

### Example
```
scratchpad_state:nixos=floating:true,x:500,y:300,w:1000,h:600,ts:1730934000
```

### Field Definitions
- `scratchpad_state` - Mark prefix (identifies as state mark)
- `nixos` - Project name (alphanumeric + underscore/dash)
- `floating` - Window floating state (true or false)
- `x`, `y` - Window position (screen coordinates)
- `w`, `h` - Window size (pixels)
- `ts` - Unix timestamp (seconds since epoch)

### Storage Location
- Stored in: Sway window mark (via `swaymsg mark`)
- Scope: Single window only (one mark per window)
- Persistence: Survives daemon restart, lost on Sway restart
- Query: Via `swaymsg -t get_tree` JSON response

---

## Testing Evidence

### Test Summary
- Total tests: 10
- Passed: 10 (100%)
- Failed: 0
- Date: November 6, 2025
- Environment: Live Sway instance

### Key Test Results
1. ✓ Mark length: No truncation up to 2000 bytes
2. ✓ Multiple marks: Last replaces previous (by design)
3. ✓ Characters: All supported (especially `:=,`)
4. ✓ Toggle: Works reliably for add/remove
5. ✓ Performance: ~1-2ms per operation
6. ✓ State format: Valid and parseable
7. ✓ Persistence: Survives daemon restart
8. ✓ Parsing: Graceful error handling
9. ✓ Querying: Fast and reliable
10. ✓ Edge cases: Handled appropriately

**Conclusion**: Ready for production implementation.

---

## Code Examples Quick Reference

### Create Mark (Python)
```python
def create_mark(project: str, floating: bool, x: int, y: int, w: int, h: int) -> str:
    ts = int(time.time())
    return f"scratchpad_state:{project}=floating:{str(floating).lower()},x:{x},y:{y},w:{w},h:{h},ts:{ts}"
```

### Parse Mark (Python)
```python
def parse_mark(mark: str) -> dict:
    if not mark.startswith("scratchpad_state:"):
        return None
    # ... see TECHNICAL_REFERENCE for full implementation
```

### Set Mark (Shell)
```bash
swaymsg mark "scratchpad_state:nixos=floating:true,x:500,y:300,w:1000,h:600,ts:$(date +%s)"
```

### Get Mark (Shell)
```bash
swaymsg -t get_tree | jq -r '.. | objects | select(.focused==true) | .marks[0]'
```

### Store in Async Python
```python
async with i3ipc.Connection() as sway:
    result = await sway.command(f"[con_id={wid}] mark {mark}")
```

---

## Known Limitations & Workarounds

### Limitation 1: Only One Mark Per Window
- **Issue**: Each new mark replaces previous
- **Solution**: Encode all state in single mark
- **Format**: Use delimiters (`,` and `:`) to separate fields
- **Status**: Accepted, not a blocker

### Limitation 2: Lost on Sway Restart
- **Issue**: Window destroyed on Sway restart, mark lost
- **Solution**: Optional: Store state in JSON file as backup
- **Impact**: Low (Sway restart is rare)
- **Status**: Acceptable for Feature 051

### Limitation 3: No Built-in Validation
- **Issue**: Sway doesn't validate mark format
- **Solution**: Implement parsing with error handling
- **Implementation**: See TECHNICAL_REFERENCE error handling
- **Status**: Manageable in code

---

## Feature 051 Integration Points

### From Spec Requirement FR-005
> "When hiding a scratchpad terminal, the system MUST record its current floating/tiling state in Sway window marks"

**Implementation**: ✓ Covered by mark storage format

### From Spec Requirement FR-011
> "When hiding or repositioning a scratchpad terminal, the system MUST store state data in Sway window marks using the format: `scratchpad_state:{project_name}={key1}:{value1},...`"

**Implementation**: ✓ Exact format recommended in research

### From i3run Pattern
> "Store positioning and state such that it persists across show/hide cycles"

**Implementation**: ✓ Marks persist on hidden windows

---

## Questions Answered by Research

1. **Are there practical limits to mark string length?**
   - No. Tested up to 2000+ characters without truncation.

2. **How many marks can be attached to a single window?**
   - Exactly one. Each new mark replaces the previous.

3. **What characters are allowed in mark names?**
   - All characters, including special characters (`:`, `=`, `,`, etc.)

4. **What are community best practices for mark-based metadata storage?**
   - Use delimited format with semantic prefix and key-value pairs
   - Follow pattern: `prefix:identifier=key:value,key:value`

5. **Are there performance implications for long marks or many marks?**
   - No. Operations are ~1-2ms regardless of mark length (up to 2000+)

6. **What is the recommended serialization format?**
   - Delimited key-value pairs: `scratchpad_state:project=field:value,field:value,...`

---

## Document Statistics

| Document | Size | Lines | Words | Focus |
|----------|------|-------|-------|-------|
| SWAY_MARK_SUMMARY.md | 8.7 KB | 200 | 1800 | Quick reference |
| SWAY_MARK_RESEARCH.md | 20 KB | 450 | 4500 | Comprehensive analysis |
| SWAY_MARK_TECHNICAL_REFERENCE.md | 19 KB | 430 | 4200 | Implementation guide |
| SWAY_MARK_TEST_RESULTS.md | 8.7 KB | 200 | 1900 | Empirical validation |
| **TOTAL** | **56.4 KB** | **1280** | **12400** | Complete package |

---

## Related Resources

### In This Codebase
- `/etc/nixos/specs/051-i3run-scratchpad-enhancement/spec.md` - Feature specification
- `/etc/nixos/docs/budlabs-i3run-c0cc4cc3b3bf7341.txt` - i3run source code
- `/etc/nixos/home-modules/tools/i3pm/models/scratchpad.py` - Existing models

### External References
- Sway documentation: `man sway` (search for "mark")
- i3ipc.aio library: Async Sway IPC Python bindings
- JSON schema validation: For mark format validation (optional)

---

## Next Steps

1. **Review** all four documents (start with SUMMARY for overview)
2. **Discuss** findings with team (special attention to single-mark limitation)
3. **Plan** implementation based on TECHNICAL_REFERENCE
4. **Code** state storage using provided examples
5. **Test** against procedures in TECHNICAL_REFERENCE
6. **Validate** performance against benchmarks in TEST_RESULTS
7. **Implement** Feature 051 with confidence

---

## Approval Checklist

- [x] Research questions answered
- [x] Testing completed (10/10 tests passed)
- [x] Code examples provided
- [x] Implementation guide written
- [x] Edge cases documented
- [x] Performance verified
- [x] Limitations identified
- [x] Workarounds provided
- [x] Documentation complete

**Status**: Ready for Feature 051 implementation

---

## Contact & Feedback

For questions about this research:
1. Check FAQ sections in SUMMARY
2. Review relevant test in TEST_RESULTS
3. See implementation examples in TECHNICAL_REFERENCE
4. Refer to detailed analysis in RESEARCH

For issues or clarifications needed:
- Create issue with reference to specific document section
- Include test case showing the issue
- Attach sample mark format if applicable

---

**Last Updated**: November 6, 2025
**Prepared for**: Feature 051 Implementation
**Confidence Level**: High (100% test pass rate)

