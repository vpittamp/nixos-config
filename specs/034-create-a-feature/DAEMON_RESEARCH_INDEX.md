# Feature 034: i3pm Daemon Project Context API - Research Index

**Research Date**: 2025-10-24  
**Status**: Complete  
**Thoroughness**: Medium  
**Ready for Implementation**: Yes  

---

## Research Overview

This research explores the i3pm daemon's project context query API for the Feature 034 Unified Application Launcher. The daemon enables querying the current active project and substituting project-aware variables (`$PROJECT_DIR`, `$PROJECT_NAME`, `$SESSION_NAME`) in launcher commands.

---

## Documentation Files

### Primary Research Documents

#### 1. **RESEARCH_COMPLETE.md** (High-Level Summary)
- **Length**: 368 lines (~11 KB)
- **Audience**: Quick overview, decision makers
- **Contains**:
  - Key findings summary
  - Daemon architecture overview
  - Project context API specification
  - Implementation approach recommendation
  - Error handling strategy
  - Next steps for implementation

**Start here if**: You want a quick understanding of the whole system.

---

#### 2. **DAEMON_API_INTEGRATION_GUIDE.md** (Complete Technical Guide)
- **Length**: 799 lines (~20 KB)
- **Audience**: Developers implementing Feature 034
- **Contains**:
  - Detailed connection specifications
  - Socket path discovery (Bash, TypeScript, Python)
  - Complete JSON-RPC method documentation
  - Project data model and schema
  - CLI commands reference
  - Implementation examples in 3 languages
  - Variable substitution patterns
  - Error handling matrix with recovery strategies
  - Performance characteristics and caching guidance
  - Testing and validation procedures
  - Integration checklist

**Start here if**: You need complete technical details for implementation.

---

#### 3. **DAEMON_QUICK_REFERENCE.md** (Lookup Card)
- **Length**: 271 lines (~5.5 KB)
- **Audience**: Developers during implementation
- **Contains**:
  - Socket path formula
  - JSON-RPC method signatures
  - Code snippets for each language
  - Project config file fields
  - Variable reference table
  - Error patterns and recovery
  - Common commands
  - Integration checklist

**Start here if**: You need quick code snippets or reference data.

---

#### 4. **INTEGRATION_EXAMPLES.md** (Production Code)
- **Length**: 294 lines (~7.9 KB)
- **Audience**: Developers implementing Feature 034
- **Contains**:
  - Complete Bash wrapper script (production-ready)
  - Python integration class with async support
  - TypeScript/Deno example with full typing
  - Example Feature 034 launcher configuration (JSON)
  - Integration test script
  - Error handling matrix
  - Performance optimization tips
  - Testing checklist

**Start here if**: You want complete, copy-paste-ready implementations.

---

## Quick Navigation

### Question: "What do I need to implement Feature 034?"

1. Start with **RESEARCH_COMPLETE.md** to understand the architecture
2. Review **INTEGRATION_EXAMPLES.md** for code patterns
3. Reference **DAEMON_API_INTEGRATION_GUIDE.md** for details
4. Use **DAEMON_QUICK_REFERENCE.md** during implementation

### Question: "How do I query the daemon?"

1. Read Socket Path section in **DAEMON_QUICK_REFERENCE.md**
2. Copy appropriate snippet from **INTEGRATION_EXAMPLES.md**
3. Refer to "Method: get_current_project" in **DAEMON_QUICK_REFERENCE.md**

### Question: "What error cases do I need to handle?"

1. See Error Handling section in **DAEMON_API_INTEGRATION_GUIDE.md** (section 7)
2. Review Error Handling Matrix in **INTEGRATION_EXAMPLES.md** (section 5)
3. Check error recovery code in **INTEGRATION_EXAMPLES.md** (section 1)

### Question: "How do I substitute variables?"

1. See Variable Substitution section in **DAEMON_API_INTEGRATION_GUIDE.md** (section 6)
2. Check examples in **INTEGRATION_EXAMPLES.md** (all scripts)
3. Look at launcher configuration in **INTEGRATION_EXAMPLES.md** (section 3)

### Question: "What client libraries are available?"

1. See Client Libraries section in **RESEARCH_COMPLETE.md** (section 8)
2. Check DAEMON_API_INTEGRATION_GUIDE.md for code examples

---

## Key Technical Summary

### Socket Connection
```
Path: /run/user/<uid>/i3-project-daemon/ipc.sock
Protocol: JSON-RPC 2.0 over Unix domain socket
Latency: < 10ms
Timeout: 5 seconds
```

### Query Method
```
Method: get_current_project
Request: {"jsonrpc":"2.0","method":"get_current_project","params":{},"id":1}
Response: {"jsonrpc":"2.0","result":{"project":"nixos"},"id":1}
Response (global): {"jsonrpc":"2.0","result":{"project":null},"id":1}
```

### Project Variables
```
$PROJECT_NAME       - From daemon query (e.g., "nixos")
$PROJECT_DIR        - From config file (e.g., "/etc/nixos")
$SESSION_NAME       - Convention = project name
$PROJECT_DISPLAY_NAME - From config file
$PROJECT_ICON       - From config file
```

### Implementation Approach
```
1. Query daemon for active project name
2. Load project config from ~/.config/i3/projects/<name>.json
3. Substitute variables in launcher command
4. Validate project directory exists
5. Handle global mode (no project active)
6. Error handling (daemon down, missing config, etc.)
```

---

## Implementation Recommendations

### Recommended Language
- **TypeScript/Deno** (type-safe, existing client, recommended)
- **Python** (async support, existing client)
- **Bash** (simple, less error handling)

### Key Performance Points
- Query latency: < 10ms
- End-to-end latency: < 20ms (negligible)
- No caching needed (query is fast)
- Project switches are instant

### Error Handling
- Daemon not running: Restart systemd service
- Global mode: Disable command or prompt user
- Missing config: Validate or create config
- Missing directory: Create directory or update config
- Connection timeout: Retry with exponential backoff

---

## File Map

```
/etc/nixos/specs/034-create-a-feature/
├── DAEMON_RESEARCH_INDEX.md                  ← You are here
├── RESEARCH_COMPLETE.md                      (High-level overview)
├── DAEMON_API_INTEGRATION_GUIDE.md           (Complete technical guide)
├── DAEMON_QUICK_REFERENCE.md                 (Lookup reference card)
├── INTEGRATION_EXAMPLES.md                   (Production code examples)
├── i3pm-project-api-reference.md             (Existing API reference)
└── plan.md                                   (Feature 034 planning)
```

---

## Related Source Code

### Client Libraries

**TypeScript/Deno Client**
- File: `/etc/nixos/home-modules/tools/i3pm-deno/src/client.ts`
- Type: Async JSON-RPC client
- Use: Recommended for Feature 034

**Python Client**
- File: `/etc/nixos/home-modules/tools/i3_project_manager/core/daemon_client.py`
- Type: Async JSON-RPC client
- Use: Alternative to TypeScript

**Bash Wrapper**
- File: `/etc/nixos/scripts/i3-project-current`
- Type: CLI tool
- Use: Simple queries or as reference

### Daemon Implementation

**Daemon Core**
- File: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py`
- Type: Event-driven daemon
- Systemd service: i3-project-event-listener

**IPC Server**
- File: `/etc/nixos/home-modules/desktop/i3-project-event-daemon/ipc_server.py`
- Type: JSON-RPC server over Unix socket
- Handles: All daemon RPC methods

---

## Quick Start for Implementation

### Step 1: Understand the Architecture
**Read**: RESEARCH_COMPLETE.md (5 min)

### Step 2: Choose Implementation Language
**Decide**: Bash/Python/TypeScript

### Step 3: Review Example Code
**Read**: INTEGRATION_EXAMPLES.md section 1-3 (10 min)

### Step 4: Implement Variable Substitution
**Copy**: Example from INTEGRATION_EXAMPLES.md
**Adapt**: For your launcher architecture
**Reference**: DAEMON_API_INTEGRATION_GUIDE.md for details

### Step 5: Add Error Handling
**Reference**: Error Handling Matrix in DAEMON_API_INTEGRATION_GUIDE.md (section 7)
**Copy**: Error handling code from INTEGRATION_EXAMPLES.md

### Step 6: Test Implementation
**Use**: Test script from INTEGRATION_EXAMPLES.md (section 4)
**Verify**: < 20ms latency
**Check**: All error paths

---

## Documentation Statistics

| Document | Lines | Size | Focus |
|----------|-------|------|-------|
| RESEARCH_COMPLETE.md | 368 | 11 KB | Overview |
| DAEMON_API_INTEGRATION_GUIDE.md | 799 | 20 KB | Details |
| DAEMON_QUICK_REFERENCE.md | 271 | 5.5 KB | Lookup |
| INTEGRATION_EXAMPLES.md | 294 | 7.9 KB | Code |
| **Total** | **1732** | **44 KB** | **Complete** |

### Code Examples Included

1. Bash wrapper script (complete, production-ready)
2. Python async client (complete, type-annotated)
3. TypeScript/Deno client (complete, full typing)
4. Integration test script (complete, all cases)
5. Launcher configuration (example JSON)

---

## Next Steps

### For Implementation
1. Review DAEMON_API_INTEGRATION_GUIDE.md
2. Copy appropriate example from INTEGRATION_EXAMPLES.md
3. Adapt for your launcher architecture
4. Add error handling for all paths
5. Write tests (use test script as template)

### For Testing
1. Test daemon connectivity
2. Test variable substitution
3. Test error paths (daemon down, global mode, missing config)
4. Verify performance (< 20ms)
5. Integration test with launcher

### For Documentation
1. Update Feature 034 spec with implementation details
2. Add launcher command examples to user documentation
3. Document project variable usage for users
4. Add troubleshooting guide for daemon issues

---

## Research Completion Status

- [x] Daemon implementation discovered and analyzed
- [x] JSON-RPC API specification documented
- [x] Project context query method identified
- [x] Project metadata storage location identified
- [x] Variable substitution requirements specified
- [x] Client libraries evaluated
- [x] Error cases identified and documented
- [x] Implementation examples provided (3 languages)
- [x] Testing strategy defined
- [x] Performance characteristics measured
- [x] Integration guide completed
- [x] Quick reference card created

**Status**: READY FOR IMPLEMENTATION

---

**Research completed**: 2025-10-24  
**Total documentation**: 1732 lines, 44 KB  
**Code examples**: 5 complete implementations  
**Ready for**: Feature 034 implementation  

