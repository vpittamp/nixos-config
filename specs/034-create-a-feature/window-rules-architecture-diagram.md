# Window Rules Architecture - Visual Diagrams

**Feature**: 034-create-a-feature | **Date**: 2025-10-24

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      User/Administrator                          │
└─────────────────┬───────────────────────────────────────────────┘
                  │
                  │ Edits
                  ▼
         ┌────────────────────┐
         │ application-       │
         │ registry.json      │
         │                    │
         │ {                  │
         │   "name": "vscode",│
         │   "expected_class":│
         │     "Code",        │
         │   "scope": "scoped"│
         │   "workspace": 1   │
         │ }                  │
         └────────┬───────────┘
                  │
                  │ nixos-rebuild switch
                  ▼
         ┌────────────────────┐
         │  Home-Manager      │◄──── Build-Time Generation
         │  (Nix)             │
         │                    │
         │  - Read registry   │
         │  - Transform       │
         │  - Validate        │
         │  - Generate JSON   │
         └────────┬───────────┘
                  │
                  │ Generates
                  ▼
    ┌──────────────────────────┐
    │ window-rules-generated   │◄──── force = true (always overwrite)
    │ .json                    │
    │                          │
    │ [                        │
    │   {                      │
    │     "pattern_rule": {    │
    │       "pattern": "Code", │
    │       "scope": "scoped", │
    │       "priority": 240    │
    │     },                   │
    │     "workspace": 1       │
    │   }                      │
    │ ]                        │
    └──────────────────────────┘
                  │
                  ├─────────────────┐
                  │                 │
                  ▼                 ▼
    ┌──────────────────────┐  ┌──────────────────────┐
    │  File Watcher        │  │ window-rules-manual  │
    │  (watchdog)          │  │ .json                │◄─── User edits
    │                      │  │                      │      (preserved)
    │  - Monitors changes  │  │ [                    │
    │  - 100ms debounce    │  │   {                  │
    │  - Triggers reload   │  │     "pattern_rule": {│
    └──────────┬───────────┘  │       "pattern":"...",│
               │              │       "priority": 250 │
               │              │     },                │
               │              │     "workspace": 3    │
               │              │   }                   │
               │              │ ]                     │
               │              └──────────┬────────────┘
               │                         │
               │                         │
               ▼                         ▼
    ┌──────────────────────────────────────────┐
    │  i3-project-event-daemon                 │◄──── Runtime
    │  (Python)                                │
    │                                          │
    │  1. Load generated rules                 │
    │  2. Load manual rules                    │
    │  3. Merge and sort by priority (↓)      │
    │  4. On window::new event:                │
    │     - Match window against rules         │
    │     - Apply first matching rule          │
    │                                          │
    └──────────────────────────────────────────┘
               │
               │ Window placement
               ▼
    ┌──────────────────────────────────────────┐
    │  i3 Window Manager                       │
    │                                          │
    │  [WS1: Code]  [WS2: Terminal]  [WS3: Firefox] │
    └──────────────────────────────────────────┘
```

---

## Priority Resolution Flow

```
Window opens: WM_CLASS="Code"
    │
    ▼
┌─────────────────────────────────────────┐
│ Daemon: Match against all rules         │
│ (sorted by priority, highest first)     │
└─────────────────┬───────────────────────┘
                  │
                  ▼
         ┌────────────────────┐
         │ Priority 250       │
         │ [Manual]           │
         │ Code → WS3         │◄──── MATCH! (First match wins)
         │ (scoped)           │
         └────────────────────┘
                  │
                  │ Apply rule
                  ▼
         ┌────────────────────┐
         │ Move window to WS3 │
         └────────────────────┘

    (Shadowed rules not evaluated)
         ┌────────────────────┐
         │ Priority 240       │
         │ [Generated]        │
         │ Code → WS1         │◄──── Never reached (shadowed)
         │ (scoped)           │
         └────────────────────┘
```

**Key Insight**: Higher priority rules evaluate first, first match wins, lower priority rules with same pattern are shadowed.

---

## Data Flow: Registry → Window Placement

```
┌────────────────────────────────────────────────────────────────┐
│                     Build Time (Nix)                           │
└────────────────────────────────────────────────────────────────┘

    Registry Entry
    ──────────────
    {
      "name": "vscode",
      "expected_class": "Code",      ─┐
      "scope": "scoped",              │  Transformation
      "preferred_workspace": 1        │  (Nix expression)
    }                                 │
                                      │
                                      ▼
    Generated Rule
    ──────────────
    {
      "pattern_rule": {
        "pattern": "Code",            ◄─ from expected_class
        "scope": "scoped",            ◄─ from scope
        "priority": 240,              ◄─ computed (scoped=240)
        "description": "VS Code - WS1"
      },
      "workspace": 1                  ◄─ from preferred_workspace
    }

┌────────────────────────────────────────────────────────────────┐
│                     Runtime (Daemon)                           │
└────────────────────────────────────────────────────────────────┘

    Window Event
    ────────────
    i3 → daemon: window::new
    {
      "class": "Code",
      "title": "~/project - Visual Studio Code"
    }
                  │
                  ▼
    Pattern Matching
    ────────────────
    Rule: pattern="Code"
    Window: class="Code"
    → MATCH! ✓
                  │
                  ▼
    Action Execution
    ────────────────
    i3-msg 'move container to workspace 1'
                  │
                  ▼
    Window Placement
    ────────────────
    VS Code appears on Workspace 1
```

---

## File Ownership & Update Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    Configuration Files                        │
└──────────────────────────────────────────────────────────────┘

┌─────────────────────────┐     ┌─────────────────────────┐
│ application-registry    │     │ window-rules-generated  │
│ .json                   │     │ .json                   │
│                         │     │                         │
│ Owner: User/HM          │────►│ Owner: Home-Manager     │
│ Edit: Manual or rebuild │     │ Edit: Never (auto-gen)  │
│ Force: false (preserve) │     │ Force: true (overwrite) │
│                         │     │                         │
│ Changes: Require rebuild│     │ Updates: Every rebuild  │
└─────────────────────────┘     └─────────────────────────┘
                                            │
                                            │ File watcher
                                            ▼
                                 ┌─────────────────────────┐
                                 │ i3-project-event-daemon │
                                 │ (loads both files)      │
                                 └─────────────────────────┘
                                            ▲
                                            │ File watcher
                                            │
┌─────────────────────────┐                │
│ window-rules-manual     │                │
│ .json                   │────────────────┘
│                         │
│ Owner: User             │
│ Edit: Anytime (manual)  │
│ Force: false (preserve) │
│                         │
│ Changes: Hot reload     │
└─────────────────────────┘

Legend:
──►  Transformation/Generation
───  Monitoring/Loading
```

---

## Conflict Resolution Visualization

### Scenario: Same Pattern, Different Rules

```
Generated File                    Manual File
──────────────                    ───────────
┌─────────────────────┐          ┌─────────────────────┐
│ Pattern: "Code"     │          │ Pattern: "Code"     │
│ Priority: 240       │          │ Priority: 250       │◄─ Higher!
│ Workspace: 1        │          │ Workspace: 3        │
│ Source: Registry    │          │ Source: User        │
└─────────────────────┘          └─────────────────────┘
         │                                  │
         └──────────┬───────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  Daemon Merge Logic  │
         │                      │
         │  Sort by priority ↓  │
         └──────────┬───────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │ Priority-Sorted List │
         ├──────────────────────┤
         │ 250: Code → WS3      │◄─── ACTIVE (first match)
         │ 240: Code → WS1      │◄─── SHADOWED
         └──────────────────────┘

Result: Manual override wins
```

### Multiple Windows, Multiple Rules

```
Window Events:                   Rule Evaluation:
──────────────                   ────────────────

Window A: class="Code"           250: Code → WS3 ✓ MATCH
    │                                Apply: Move to WS3
    ▼
┌──────────────┐
│ Code on WS3  │
└──────────────┘

Window B: class="Firefox"        250: Code → WS3 ✗ No match
    │                            240: Code → WS1 ✗ No match
    │                            180: Firefox → WS5 ✓ MATCH
    ▼                                Apply: Move to WS5
┌──────────────┐
│Firefox on WS5│
└──────────────┘

Window C: class="Slack"          250: Code → WS3 ✗ No match
    │                            240: Code → WS1 ✗ No match
    │                            180: Firefox → WS5 ✗ No match
    │                            180: Slack → WS6 ✓ MATCH
    ▼                                Apply: Move to WS6
┌──────────────┐
│ Slack on WS6 │
└──────────────┘

Rule: First matching rule wins (by priority order)
```

---

## Error Handling & Resilience

```
┌─────────────────────────────────────────────────────────────────┐
│                    Error Scenarios                              │
└─────────────────────────────────────────────────────────────────┘

Scenario 1: Invalid JSON Syntax
────────────────────────────────
User edits manual file with typo
    │
    ▼
File watcher detects change
    │
    ▼
Daemon attempts reload
    │
    ▼
JSON parse error
    │
    ├──► Log error to journal
    ├──► Show desktop notification
    └──► KEEP old rules (graceful degradation)

Result: System continues working with previous valid rules


Scenario 2: Registry Transformation Error
──────────────────────────────────────────
Registry has invalid entry
    │
    ▼
home-manager rebuild
    │
    ▼
Nix evaluation error
    │
    └──► BUILD FAILS (blocks bad config)

Result: User fixes registry before system changes


Scenario 3: Missing Expected Field
───────────────────────────────────
Registry entry missing expected_class
    │
    ▼
Nix transformation
    │
    ▼
Error: "Application X missing pattern field"
    │
    └──► BUILD FAILS with clear message

Result: User adds missing field
```

---

## Timeline: From Edit to Window Placement

```
T+0ms    User edits application-registry.json
         │
T+0ms    User runs: nixos-rebuild switch --flake .#hetzner
         │
         │ (Nix evaluation + build)
         ▼
T+30s    Home-manager generates window-rules-generated.json
         │
         ▼
T+30s    File watcher detects change
         │ (100ms debounce)
         ▼
T+30.1s  Daemon reloads rules
         │ (parse JSON, merge, sort)
         ▼
T+30.2s  Daemon ready with new rules
         │
         │ ... user launches application ...
         ▼
T+35s    Application window appears
         │ (i3 sends window::new event)
         ▼
T+35s    Daemon matches rule (first-match)
         │ (<1ms evaluation)
         ▼
T+35.01s Daemon sends i3 command: move container to workspace N
         │
         ▼
T+35.02s Window appears on correct workspace

Total: Registry edit → Window placement = ~35s (mostly build time)
       Rule reload = ~100ms (automatic, no rebuild needed)
```

---

## System State Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                        Initial State                         │
└──────────────────────────────────────────────────────────────┘

No Files Exist:
    application-registry.json        ✗
    window-rules-generated.json      ✗
    window-rules-manual.json         ✗

↓ First rebuild with window-rules-generator.nix enabled

┌──────────────────────────────────────────────────────────────┐
│                        After First Build                     │
└──────────────────────────────────────────────────────────────┘

Files Created:
    application-registry.json        ✓ (from registry definition in Nix)
    window-rules-generated.json      ✓ (generated, empty if no apps)
    window-rules-manual.json         ✓ (created empty, never overwritten)

↓ User adds applications to registry + rebuild

┌──────────────────────────────────────────────────────────────┐
│                       After Registry Populated               │
└──────────────────────────────────────────────────────────────┘

Files Updated:
    application-registry.json        ✓ (15 applications defined)
    window-rules-generated.json      ✓ (15 rules generated)
    window-rules-manual.json         ✓ (still empty, preserved)

Daemon State:
    Rules loaded: 15 generated + 0 manual = 15 total
    File watchers: Active on both files

↓ User adds manual override

┌──────────────────────────────────────────────────────────────┐
│                     After Manual Override Added              │
└──────────────────────────────────────────────────────────────┘

Files Updated:
    application-registry.json        ✓ (unchanged)
    window-rules-generated.json      ✓ (unchanged)
    window-rules-manual.json         ✓ (1 override added, no rebuild)

Daemon State:
    Rules loaded: 15 generated + 1 manual = 16 total
    File watcher triggered reload in ~100ms

↓ User updates registry + rebuild

┌──────────────────────────────────────────────────────────────┐
│                     After Registry Update                    │
└──────────────────────────────────────────────────────────────┘

Files Updated:
    application-registry.json        ✓ (20 applications, 5 added)
    window-rules-generated.json      ✓ (20 rules generated)
    window-rules-manual.json         ✓ (1 override preserved!)

Daemon State:
    Rules loaded: 20 generated + 1 manual = 21 total
    File watcher triggered reload in ~100ms
    Manual override still active (priority system)
```

---

## Component Interaction Matrix

| Component | Reads | Writes | Watches | Triggers |
|-----------|-------|--------|---------|----------|
| **User** | Registry | Registry, Manual rules | - | nixos-rebuild |
| **Home-Manager** | Registry | Generated rules | - | File creation |
| **File Watcher** | - | - | Generated + Manual | Daemon reload |
| **Daemon** | Generated + Manual | - | i3 events | Window placement |
| **i3 Window Manager** | - | Window state | - | window::new events |

---

## Decision Tree: Where to Make Changes

```
┌─────────────────────────────────────────────────────────────────┐
│        Want to change window placement behavior?                │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │ Is it a new app?     │
                └──────────────────────┘
                   │              │
                   │ Yes          │ No
                   ▼              ▼
        ┌──────────────────┐  ┌──────────────────┐
        │ Add to registry  │  │ Change existing? │
        │ + rebuild        │  └──────────────────┘
        └──────────────────┘       │          │
                                   │ Yes      │ No
                                   ▼          ▼
                        ┌──────────────────┐  Done
                        │ For all projects?│
                        └──────────────────┘
                            │          │
                            │ Yes      │ No (just me)
                            ▼          ▼
                 ┌──────────────────┐  ┌──────────────────┐
                 │ Update registry  │  │ Add manual rule  │
                 │ + rebuild        │  │ (no rebuild)     │
                 └──────────────────┘  └──────────────────┘
```

**Examples**:

1. **New app "Slack"** → Add to registry + rebuild
2. **Change VS Code workspace for everyone** → Update registry + rebuild
3. **Personal override: VS Code on WS3** → Add manual rule (no rebuild)
4. **Experiment with priorities** → Edit manual rules (instant reload)

---

## References

- Full analysis: [window-rules-generation-research.md](./window-rules-generation-research.md)
- Quick summary: [window-rules-generation-summary.md](./window-rules-generation-summary.md)
- Implementation guide: [QUICKSTART-WINDOW-RULES.md](./QUICKSTART-WINDOW-RULES.md)
