# Herdr to QuickShell/i3pm UX Audit

Last reviewed: 2026-06-09

Upstream source: `/tmp/herdr` at `698eb51f543af47ba7a974d0d78f1bf0cca2cd53`.

Local goal: use Herdr as the semantic model while keeping i3pm the host-local notification owner and QuickShell the visual shell. Herdr direct toast/sound delivery remains disabled in `home-modules/terminal/herdr.nix`.

## Traceability Matrix

| Herdr feature or behavior | Herdr source/reference | Local QuickShell/i3pm equivalent | Decision | Validation evidence |
| --- | --- | --- | --- | --- |
| Agent semantic states: `idle`, `working`, `blocked`, `done`, `unknown` | `/tmp/herdr/src/api/schema.rs:940-948`; `/tmp/herdr/src/ui/status.rs:218-225` | `herdrStatusState()` and `sessionPhase()` in `home-modules/desktop/quickshell-runtime-shell/shell.qml`; `_normalize_herdr_agent_status()` in `home-modules/desktop/i3-project-event-daemon/ipc_server.py` | Already covered | `pytest tests/085-sway-monitoring-widget/test_ai_view_regressions.py`; `pytest home-modules/desktop/i3-project-event-daemon/tests/unit/test_ipc_server_herdr_sessions.py` |
| Blocked means user action required and uses request sound | `/tmp/herdr/src/app/actions.rs:76-100`; `/tmp/herdr/src/app/actions.rs:193-203` | Local i3pm notification mirroring is retired; Herdr remains the semantic source for blocked state and QuickShell renders it from daemon rows | Retired locally | `tests/085-sway-monitoring-widget/test_ai_view_regressions.py::test_legacy_agent_action_toast_path_is_removed` |
| Completion transitions can notify in Herdr | `/tmp/herdr/src/app/actions.rs:20-45`; `/tmp/herdr/src/app/actions.rs:122-160` | Local i3pm completion/user-input notification mirroring is retired | Not applicable by product policy | `tests/085-sway-monitoring-widget/test_ai_view_regressions.py::test_legacy_agent_action_toast_path_is_removed` |
| Active focused pane suppresses redundant notifications | `/tmp/herdr/src/app/actions.rs:47-52`; `/tmp/herdr/src/app/actions.rs:2574-2586` | Current/focused sessions are daemon/Herdr focus state only; no monitoring-data notification debounce remains | Retired locally | daemon focus tests |
| Delayed notifications are rechecked and cancelled if state changes | `/tmp/herdr/src/app/actions.rs:2566-2629`; `/tmp/herdr/src/app/actions.rs:2632-2652`; `/tmp/herdr/src/app/actions.rs:2721-2758` | Local delayed notification scheduling is retired with the monitoring-data AI notifier | Retired locally | `tests/085-sway-monitoring-widget/test_ai_view_regressions.py::test_legacy_agent_action_toast_path_is_removed` |
| Toast delivery can be terminal/system/herdr/off | `/tmp/herdr/src/server/notifications.rs:9-18`; `/tmp/herdr/src/api/schema.rs:135-148` | Herdr `[ui.toast] delivery = "off"`; QuickShell no longer has an `i3pm-agent` toast bypass | Retired locally; broad Herdr delivery intentionally disabled | `tests/085-sway-monitoring-widget/test_ai_view_regressions.py::test_legacy_agent_action_toast_path_is_removed` |
| Agent list exposes terminal, workspace, tab, pane, cwd, foreground cwd, focus, and revision | `/tmp/herdr/src/api/schema.rs:755-781` | Daemon `_herdr_snapshot()` calls `herdr agent list`, `pane list`, `workspace list`, `tab list`; rows carry pane/workspace/tab/terminal/cwd fields | Already covered | `home-modules/desktop/i3-project-event-daemon/tests/unit/test_ipc_server_herdr_sessions.py` |
| Pane list exposes the same presentation fields as agent list | `/tmp/herdr/src/api/schema/panes.rs:228-255` | Daemon merges agents with panes by `pane_id` in `_normalize_herdr_sessions()` | Already covered | `test_herdr_rows_preserve_status_and_targets` |
| `display_agent`, `custom_status`, and `state_labels` are visual-only metadata | `/tmp/herdr/website/src/content/docs/integrations.mdx:164-189`; `/tmp/herdr/src/api/schema.rs:763-770`; `/tmp/herdr/src/ui/sidebar.rs:1104-1155` | Daemon now preserves normalized `display_agent`, `custom_status`, and `state_labels`; QuickShell uses display agent names, state label overrides, and custom status in session text | Implemented | `test_herdr_rows_preserve_status_and_targets`; `test_herdr_visual_metadata_controls_labels_without_changing_icon_family` |
| Known Herdr-supported agents have distinct identities | `/tmp/herdr/website/src/content/docs/integrations.mdx:48-52`; `/tmp/herdr/src/detect/agents/` | `toolLabel()` now names OpenCode, GitHub Copilot, Cursor, Amp, Kimi, Kiro, Droid, Hermes, Qoder, Pi, Grok, Cline, and Kilo; icons remain stable for Codex/Claude/Gemini and fallback for the rest | Implemented where local assets exist or fallback is acceptable | `test_herdr_visual_metadata_controls_labels_without_changing_icon_family` |
| Focus agent by pane target | `/tmp/herdr/src/api/schema.rs:61-74`; `/tmp/herdr/src/app/agents.rs:27-41` | Daemon exposes `herdr.pane.focus`; QuickShell rows use explicit `focus_target` | Already covered | `test_session_rows_focus_by_explicit_herdr_target`; `test_herdr_pane_actions_call_herdr_with_pane_id` |
| Close pane by pane target | `/tmp/herdr/src/api/schema.rs:91-116` | Local rows expose `herdr.pane.close`; remote Herdr rows intentionally omit close target | Already covered; remote destructive control not applicable | `test_side_panel_sessions_close_by_explicit_herdr_target`; `test_herdr_snapshot_merges_local_and_remote_rows` |
| Workspace and tab list/focus | `/tmp/herdr/src/api/schema.rs:29-60`; `/tmp/herdr/src/api/schema.rs:744-753` | Daemon builds Herdr spaces and local `workspace_focus_target`; remote spaces are read-only/focus-only through Herdr app attach | Already covered | `test_herdr_spaces_group_by_host_workspace_and_prioritize_status`; `test_dashboard_snapshot_includes_herdr_spaces` |
| Event subscription/wait API | `/tmp/herdr/src/api/schema.rs:117-122`; `/tmp/herdr/website/src/content/docs/socket-api.mdx:22-30` | i3pm daemon uses local Herdr CLI snapshots plus dashboard watch invalidation; QuickShell does not speak Herdr socket directly | Not applicable for now: daemon remains state owner and current polling/snapshot path avoids adding a second event owner | Audit decision only |
| Agent read/send/start/rename and pane split/zoom/layout APIs | `/tmp/herdr/src/api/schema.rs:61-116`; `/tmp/herdr/website/src/content/docs/socket-api.mdx:22-64` | QuickShell session UI is an overview/focus surface, not a Herdr multiplexer replacement | Not applicable unless explicitly requested | Audit decision only |
| Native session restore and pane history | `/tmp/herdr/website/src/content/docs/session-state.mdx:30-72`; `home-modules/terminal/herdr.nix` | Herdr config enables `resume_agents_on_restore = true` and `pane_history = true`; QuickShell reflects restored Herdr sessions through snapshots | Already covered by Herdr config | Nix eval/rebuild validation |
| Remote attach with local desktop bridge | `/tmp/herdr/website/src/content/docs/persistence-remote.mdx:65-100` | ThinkPad remote Herdr rows focus ryzen panes via SSH-executed Herdr commands and reuse/open the local Herdr app; remote rows stay focus-only | Already covered | `test_herdr_snapshot_merges_local_and_remote_rows`; `i3pm health` on ThinkPad after rebuild |

## Open Follow-Up Candidates

- Add first-class local icon assets for additional Herdr agents if visual parity becomes important. The current implementation preserves correct labels and uses the established fallback icon for agents without local assets.
- Consider a daemon-owned Herdr socket subscription later if CLI snapshot latency becomes a real issue. It should replace, not duplicate, the current snapshot owner.

## Completed Validation

- `pytest tests/085-sway-monitoring-widget/`: 129 passed.
- `pytest home-modules/desktop/i3-project-event-daemon/tests/unit/test_ipc_server_herdr_sessions.py`: 9 passed.
- `git diff --check` and `git diff --cached --check`: clean.
- `nix eval '.#nixosConfigurations.ryzen.config.system.build.toplevel.drvPath' --raw`: `/nix/store/zp4abpp876c6d4n923nnw3bhqyn30ki4-nixos-system-ryzen-26.05.20260130.62c8382.drv`.
- `nix eval '.#nixosConfigurations.thinkpad.config.system.build.toplevel.drvPath' --raw`: `/nix/store/ba815r631xkabsln4xd22y17sq5ki4gh-nixos-system-thinkpad-26.05.20260130.62c8382.drv`.
- `sudo nixos-rebuild switch --flake .#ryzen`: switched to `/nix/store/v9xmk3iwfx7qavlficgfd5nm37sxrsh2-nixos-system-ryzen-26.05.20260130.62c8382`.
- `ssh thinkpad 'cd /home/vpittamp/repos/vpittamp/nixos-config/main && sudo nixos-rebuild switch --flake .#thinkpad'`: switched to `/nix/store/bjp0f004l56sa0bhgxr6q2kkmx8d40rm-nixos-system-thinkpad-26.05.20260130.62c8382`.
- `i3pm health`: OK on ryzen.
- `ssh thinkpad 'i3pm health'`: OK after restarting `mcp-chrome-devtools-browser.service`.
