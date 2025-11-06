i want to create a test suite for my custom configurations for sway window manager.  this includes a python module that i use to extend the functionality of sway to
  manage "projects" which are collections of workspaces, as well as a deno cli tool that handles the user facing interaction functionality via i3pm commands.  sway is a
  wayland based implementation that was originally based on i3wm which was for x11.  i want tests that can mimic the user's experience in executing commands, arranging
  workspaces, switching between projects, etc.  we want the tests to simulate user's actions as closely as possible, such as using dotool to execute key commands to
  simulate user key presses, mouse clicks, etc.  in addition, we want to capture the state of our system/layout/windows, etc. to determine if our actions resulted in the
  desired state of our system/layout.  ideally, we could also run these tests in a somewhat isolated environment -- perhaps in an instance of wayland, or by ssh'ing into
  another instance, etc.  here is documentation on tests from i3 that they use which may serve as an example of testing, but we may not be fully compatible with our use
  case and architecture.  refer to other online documentation on best practices around testing the functionality we're interested in, and the present a solution for a
  comprehensive test suite



# Sway Project Test Suite Proposal

Date: 2025-11-06

## Objectives
- Validate Sway-based project workflows (workspace orchestration, project switching, layout persistence) through user-centric automation.
- Exercise both the Python project manager/daemon stack and the Deno `i3pm` CLI in realistic Wayland environments.
- Provide deterministic, headless-friendly runs that can execute locally or in CI without a physical display server.
- Capture rich state (window trees, IPC events, logs) to diagnose regressions quickly.

## Scope & Assumptions
- Target Sway ≥ 1.9 with wlroots ≥ 0.18 and support for the headless backend.
- Tests must run on Nix-managed environments (flakes, `nix develop`, or `nix build` derivations).
- User input simulation relies on wlroots-compatible injectors (`dotool`, `wtype`).
- System under test includes:
  - Python project manager modules (`home-modules/tools/i3_project_manager`, `desktop/i3-project-event-daemon`).
  - Deno CLI (`home-modules/tools/i3pm-deno`).
  - Sway configuration manager modules and NixOS configuration glue.

## Test Layers
1. **Static & Unit**
   - Python: type checking (`pyright`), unit tests for models/validators/IPC clients.
   - Deno: `deno test` suites for command parsing, IPC wrappers, data formatting.
2. **Service Integration**
   - Python async IPC tests against in-memory or mocked sockets to verify JSON-RPC surfaces.
   - Deno CLI integration that spins up ephemeral daemon fixtures via asyncio subprocesses.
3. **Sway Integration (Headless)**
   - Launch nested Sway with bespoke config (WLR headless backend, pixman renderer, virtual outputs).
   - Run daemon + CLI against live compositor; validate workspace/window state through `swaymsg` and `i3ipc`.
4. **End-to-End Scenarios**
   - Simulate user journeys (project create/switch/clear, layout save & restore, project-specific app launch) using `dotool`/`wtype` for keybindings and pointer actions.
   - Validate final state through IPC snapshots, CLI output assertions, and recorded screenshots where applicable.
5. **Regression & Stress**
   - Replay historical bug scripts, ensure resilience to rapid project switching, concurrent CLI invocations, and daemon restarts.

## Test Environment Setup
- **Headless Sway Harness**
  - Environment variables: `WLR_BACKENDS=headless`, `WLR_HEADLESS_OUTPUTS=3`, `WLR_RENDERER=pixman`, `WLR_LIBINPUT_NO_DEVICES=1`.
  - Dynamically generated Sway config with deterministic keybindings matching production defaults.
  - Optional nested Wayland backend (`WLR_BACKENDS=wayland,headless`) when running under a developer’s graphical session for visual debugging.
- **Process Orchestration**
  - Python fixture (`pytest` plugin) to:
    1. Create temp `XDG_RUNTIME_DIR` + sockets.
    2. Start Sway with debug logging.
    3. Launch daemon and wait for health check.
    4. Yield handles for `swaymsg`, `i3ipc`, Deno CLI wrapper, and input injectors.
  - Ensure cleanup collects logs (`sway.log`, daemon journal, CLI transcripts).
- **Input Simulation**
  - `dotool` for low-level keycode/button injection; enable `/dev/uinput` via Nix modules.
  - `wtype` for high-level text input where timing tolerance is acceptable.
  - Abstracted helper API to compose user gestures (mod tap, workspace moves, mouse drags).
- **State Capture**
  - Standardized snapshots: `swaymsg -t get_tree`, `swaymsg -t get_workspaces`, daemon status JSON, CLI responses.
  - Event tracing: subscribe to IPC events (window/workspace/output) for timeline assertions.
  - Optional screenshot capture via `grim` + `slurp` when running with virtual outputs.

## Directory Layout (proposed)
```
tests/
  sway/
    conftest.py           # pytest fixtures for Sway harness
    assets/               # minimal configs/templates
    helpers.py            # input & state helper utilities
    integration/
      test_project_lifecycle.py
      test_workspace_layouts.py
      test_error_recovery.py
    e2e/
      scenarios/
        test_user_project_switching.py
        test_layout_save_restore.py
        test_cli_tui_interop.py
      resources/
        sample_projects/
    regression/
      test_issue_###.py
  shared/
    cli.py                # wrappers for i3pm CLI
    ipc.py                # sway/i3ipc helpers
```

## Tooling & Dependencies
- Python: `pytest`, `pytest-asyncio`, `i3ipc`, `trio`/`asyncio`, `tenacity` for retries.
- Deno: pinned `deno` runtime with `deno.json` tasks for test runs.
- Input: `dotool`, `wtype`, optional `ydotool` fallback.
- Utils: `grim`, `slurp`, `jq`, `swaymsg`, `cage` (optional nested viewer), `wayvnc` for remote viewing.
- Packaging: Nix derivation exposing a `swayTests` package with all runtime deps and wrappers.

## Execution Modes
1. **Local Developer Loop**
   - `nix develop .#sway-tests` provides shell with dependencies, `just sway-tests` runs targeted suites.
   - Optional live preview via `WAYLAND_DISPLAY` to existing compositor (`cage sway --config tests/...`).
2. **CI Pipeline**
   - Flake output `checks.sway-e2e` builds VM/container that runs headless Sway integration tests.
   - Publish artifacts: HTML logs, JSON summaries, screen recordings.
3. **Remote Host (SSH)**
   - Scripts to bootstrap tmux session on headless Wayland host, forwarding VNC optional.

## Reporting
- Emit structured JSON with per-test timings, sway tree diffs, and CLI transcripts.
- Generate HTML dashboard summarizing project/workspace layout comparisons.
- Integrate with existing `tests/i3pm` reporting utilities for consistency.

## Implementation Roadmap
1. **Foundations (Week 1-2)**
   - Finalize Nix test environment derivation.
   - Build pytest fixtures for headless Sway lifecycle.
   - Implement helper APIs for input + state capture.
2. **Core Scenarios (Week 3-4)**
   - Port existing i3-focused scenarios to Sway harness.
   - Author baseline project lifecycle, workspace arrangement, and CLI smoke tests.
3. **Advanced Coverage (Week 5-6)**
   - Add stress cases (rapid project switching, concurrent CLI invocations).
   - Integrate layout export/import verification.
   - Capture coverage metrics for Python/Deno components.
4. **Observability & CI (Week 7)**
   - Wire logs, artifacts, dashboards.
   - Add flaky-test detection and retries.
5. **Polish & Docs (Week 8)**
   - Document developer workflow, troubleshooting guide, infra requirements.
   - Define acceptance criteria for regression suites.

## Risks & Mitigations
- **Input Permissions**: Ensure `uinput` access via systemd tmpfiles/uaccess rules; fallback to `swaymsg` focus commands when unavailable.
- **Timing Sensitivity**: Use IPC sync (e.g., `swaymsg -t command '[con_id=...] focus' && swaymsg -t sync`) and adaptive waits.
- **Resource Usage**: Limit concurrent Sway instances; serialize e2e suites in CI.
- **Version Drift**: Pin wlroots/Sway versions in flake; add compatibility matrix tests.

## Open Questions
- Preferred format for storing layout baselines (JSON vs. golden swaymsg snapshots).
- Requirement for video capture in CI (ffmpeg vs. image diffs).
- Level of backward compatibility needed with i3-era tests.

