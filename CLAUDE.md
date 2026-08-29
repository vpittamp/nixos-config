# NixOS Configuration - LLM Navigation Guide

## Quick Start

```bash
# Test config (ALWAYS before applying)
sudo nixos-rebuild dry-build --flake .#thinkpad     # ThinkPad
sudo nixos-rebuild dry-build --flake .#ryzen        # Ryzen desktop
sudo nixos-rebuild switch --flake .#<target>        # Apply
```

**Targets**: `thinkpad`, `ryzen`, `kubevirt-sway`, `hetzner` (legacy), containers

## Directory Structure

```
flake.nix           # Entry point (flake-parts)
lib/helpers.nix     # Reusable functions
nixos/default.nix   # System definitions
home/default.nix    # Darwin home config
configurations/     # Target configs
hardware/           # Hardware settings
modules/            # System modules
home-modules/       # User environment
```

## Key Keybindings

| Key | Action |
|-----|--------|
| `Meta+D` / `Alt+Space` | Elephant launcher |
| `Mod+M` | Monitoring panel |
| `Mod+Shift+M` | Toggle dock mode (overlay ↔ docked) |
| `Win+C/G/Y` | VS Code / Lazygit / Yazi (global, open in $HOME) |
| `CapsLock` (M1) / `Ctrl+0` | Workspace mode |
| `Mod+Tab` | AI session switcher (hold Super, Tab steps, release commits) |
| `Alt+Tab` | Running-app switcher, MRU, one entry per app (hold Alt, release commits) |
| `Alt+Ctrl+Tab` / 3-finger swipe ↑ | Window exposé grouped by monitor |
| `Mod+grave` / `Mod+Escape` | Cycle focused app's windows / toggle last window (no UI) |
| `Mod+Shift+D` | Cast toggle — TV as wireless display / stop |
| `Mod+Ctrl+K` | Keybinding cheat sheet (launcher "Keys" mode; also `Ctrl+6` / `;k` inside the launcher) |

Bindings are declared once in `home-modules/desktop/sway-keybindings-data.nix`
(key, command, description, group). `sway-keybindings.nix` flattens that into
sway's `bindsym` set and the runtime shell bakes the same list into its Keys
sheet, so the sheet cannot drift from what sway runs — add bindings there, not
as bare attrset lines. Volume keys use `wpctl` (no host has `pactl`);
brightness keys go through `quickshell-brightness-key`, which steps
`brightnessctl` and then shows the OSD.

## Runtime Shell IPC (`runtime-shell`)

Every shell surface is addressable by id, so a keybinding, hook, or script can
open exactly the thing it wants without a wrapper script per function:

```bash
runtime-shell list                                  # surfaces + open state
runtime-shell toggle keybindings                    # open if closed, close if open
runtime-shell summon launcher '{"mode":"files","query":"nix"}'
runtime-shell summon panel '{"section":"sessions"}'
runtime-shell hide notifications
runtime-shell call showOsd brightness 55            # any function on the shell target
```

Surfaces: `launcher` `keybindings` `panel` `settings` `expose` `agent-monitor`
`power-menu` `notifications` `display-selector` `audio` `bluetooth` `cast`
`lock` (summon only — it cannot be hidden over IPC).
The OSD (volume / mic / brightness / touch-mode scale) is reactive for
PipeWire changes from any source and driven by IPC for brightness.

**Notifications persist** across shell restarts
(`~/.local/state/quickshell-runtime-shell/notifications.json`): live toasts
come back with their remaining lifetime, critical ones never expire, history
is kept to `notifications.historyLimit`. Identical open notifications are
coalesced; right-click dismisses a toast. `runtime-shell call
replayNotifications 3` re-shows the last closed ones.

**Agent usage chip** (after "Agents N" in the top bar; hidden until a record
exists): Claude Code / Codex plan, 5-hour and weekly limits with reset times,
today's tokens/prompts/sessions, tokens by day and by model. Left-click opens
the panel, right-click refreshes, middle-click switches subscription;
`runtime-shell summon agents`. Records come from Omarchy's MIT collectors
(`quickshell-runtime-shell/agent-usage/*.py`) run by the
`quickshell-agent-usage.timer` every 15 min into
`~/.local/state/quickshell-runtime-shell/agents/usage/<agent>.json`; the shell
file-watches them. "Sign-in expired" in the panel means `claude auth login`
on that host; local token stats still show without it.

**Themes** live in `quickshell-runtime-shell/themes.nix` (24 semantic base
tokens + a terminal palette per theme): two hand-written zinc themes plus all
22 Omarchy palettes (`themes/omarchy/*.toml`, converted with
`builtins.fromTOML` — tokyo-night, catppuccin, gruvbox, nord, everforest,
kanagawa, rose-pine, matte-black, …). surface runs `tokyo-night`. `Theme.qml`
is generated from the configured theme (`programs.quickshell-runtime-shell.theme`)
— never edit it — and every other token is derived inside it, parametrised
on `dark`. `runtime-theme set <name>|toggle|list|current` restyles the shell
live (it writes `~/.local/state/quickshell-runtime-shell/theme.json`, which
the shell watches) and writes `~/.config/ghostty/theme.conf` for new
terminals (herdr follows the terminal; press `Ctrl+Shift+,` in an open
Ghostty to reload). Launcher "Themes" mode: `Ctrl+3` / `;t`. Add a theme by
adding an attrset to `themes.nix`; no QML changes.

**Lock + idle** are in-shell: `Mod+Ctrl+L` / power menu *Lock* /
`lock-session` engage `windows/LockScreen.qml` (ext-session-lock + PAM
`swaylock` service); `lock-session` falls back to swaylock if the shell is
down. Idle is `programs.quickshell-runtime-shell.idle.{screenOffSeconds,lockSeconds}`
(defaults 300 / 600, 0 disables), honours app idle inhibitors and pauses
while casting or lid-inhibited. If the lock ever misbehaves: Ctrl+Alt+F2,
`systemctl --user restart quickshell-runtime-shell` (sway keeps the session
locked), then `XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 swaylock -f`.

## Walker/Elephant Launcher

`Meta+D` or `Alt+Space` opens Walker. Use prefixes for quick access:

| Prefix | Provider | Description |
|--------|----------|-------------|
| `*` | 1Password | Search vaults (Return=password, Shift+Return=username, Ctrl+Return=OTP) |
| `=` | Calculator | Math expressions |
| `:` | Clipboard | Clipboard history |
| `/` | Files | File browser |
| `@` | Websearch | Web search |
| `>` | Runner | Shell commands |
| `?` | Help | List all providers |
| `;s ` | Sesh | Tmux session switcher |
| `;c ` | Cast | Receiver list + mirror/extend/stop (see Desktop Casting) |
| `;h ` | History | Browser history |

**1Password Integration**: Requires 1Password GUI running and `op` CLI authenticated.

## Monitoring Panel (Features 085, 086, 099, 109, 125)

`Mod+M` toggle visibility | `Mod+Shift+M` toggle dock mode | `Alt+1-7` tabs

**Modes**: 🔳 Overlay (floating) | 📌 Docked (reserved space)
- **Overlay**: Panel floats over windows, clicks pass through when hidden
- **Docked**: Panel reserves screen space, windows resize to fit

**Status**: ● teal=active | ● red=dirty | ↑↓ sync | 💤 stale | ✓ merged | ⚠ conflicts

```bash
systemctl --user restart quickshell-runtime-shell  # Restart
journalctl --user -u quickshell-runtime-shell -f   # Logs
```

## i3pm Runtime Daemon

The project-scoping system (project switch, scoped-app hide/show, per-project
scratchpad/layouts) was **retired** — herdr now owns the terminal/AI-session
workflow. Worktree *discovery* is retired with it: there is no repos.json
inventory, no `i3pm discover`, no `i3pm worktree create/switch/clear`, and no
single "active worktree". CLI agents create worktrees with plain
`git worktree add`, anywhere on disk (37% of them live outside
`~/repos/<account>/<repo>/`).

**Identity model**: a pane's (or window's) **cwd is its identity, and git
answers everything else.** The daemon probes git for that path — repo name,
branch label, checkout path, status — behind a 30s TTL cache, so a worktree
created a minute ago labels itself correctly and a `git checkout` is reflected
within one TTL. Nothing is keyed by `account/repo:branch` any more; that key
was a directory identified by a mutable property of that directory.

The daemon remains the runtime backbone: it builds the dashboard snapshot that
powers the QuickShell bottom bar + herdr panel, routes focus, aggregates local
+ remote herdr, and manages monitors/display. All apps are global (no
hide-on-switch); the bottom-bar context chip shows the focused herdr space's
`repo[:branch]` + git status, and the tmux/prompt badge
(`scripts/i3pm-project-badge.sh`) derives the same label from git in each
pane's own working directory.

```bash
i3pm daemon {status|events}
i3pm monitors {status|reassign|config}
i3pm dashboard {snapshot|watch}
i3pm herdr-proxy {snapshot|events|focus}
i3pm health
git worktree list --porcelain           # the worktree inventory, asked on demand
```

## Worktree Cleanup (`i3pm worktrees`)

The one thing the retired repos.json inventory was actually good for — the
cross-repository view of what can be deleted — is now a CLI command that asks
git instead of a file. It globs `~/repos/*/*/.bare`, fans `git worktree list
--porcelain` out in parallel, and probes status/log/merge state per checkout.
Full sweep of this machine: **37 repos, 490 worktrees, ~1.1s**. Nothing is
cached and nothing is written, so it cannot go stale.

```bash
i3pm worktrees                          # everything git knows about
i3pm worktrees --merged --stale         # cleanup candidates (filters are a union)
i3pm worktrees --missing                # registrations whose checkout is gone
i3pm worktrees --prune --dry-run        # what a prune would drop
i3pm worktrees --merged --paths | xargs -n1 git worktree remove
i3pm worktrees --json                   # full report, machine readable
```

**Flags**: `--merged` `--stale` `--missing` `--prune` `--dry-run` `--json`
`--paths` `--root <path>` `--account <name>` `--stale-days <n>` `--concurrency <n>`

**Row tags**: `missing` (checkout gone) | `locked` | `unreadable` | `detached` |
`merged` | `stale` (tip older than `--stale-days`, default 30) | `dirty`
(staged, modified, or untracked)

**Exit code 1 means the report is incomplete** — a repository that would not
list, a checkout that could not be read, or git that could not be started. A
failure to observe is never printed as though it were a finding; a repository
that fails to enumerate is named, not silently counted as having no worktrees.

Deleting a worktree is still plain git (`git worktree remove <path>`); this
command only tells you which ones to point it at. `--prune` is the exception
and only drops git's bookkeeping for checkouts that are already gone.

## Sway Configuration (Feature 047)

**Dynamic** (hot-reload): `~/.config/sway/{window-rules,appearance}.json`
**Nix-generated** (rebuild): `workspace-assignments.json`, `monitor-profiles/*.json`, `monitor-profile.default`, `active-outputs`
**Static** (rebuild): `home-modules/desktop/sway-keybindings.nix`

```bash
swaymsg reload              # Reload (or Mod+Shift+C)
swayconfig validate         # Validate
swayconfig rollback <hash>  # Rollback
```

## Bars & Device Controls

Bars, panels, and on-screen widgets are driven by Quickshell (`home-modules/desktop/quickshell-runtime-shell/`).

```bash
systemctl --user restart quickshell-runtime-shell  # Bar + panel + notifications
```

Notifications are served natively by Quickshell; there is no separate swaync
unit (sway.nix disables any left over from older generations).

**Device controls**: Volume 󰕾 | Brightness 󰃟 | Bluetooth 󰂯 | Battery 󰁹 (click to expand)
**Devices tab**: `Mod+M` → `Alt+7`

## Desktop Casting

Desktop-level Google Cast drives **Chrome's own cast engine** over the DevTools
Protocol's `Cast` domain — identical receivers, quality, and latency to the
browser's Cast menu, without walking its UI. A dedicated-profile caster Chrome
(`cast-caster.service`, started on demand, port 9333) owns the session.

```bash
cast list                 # receivers the caster discovered (mDNS)
cast extend               # TV as wireless extended display (Mod+Shift+D toggles)
cast start [sink]         # mirror: pick the output in the walker share menu
cast stop                 # stop the cast (+ disable the headless output)
cast status --json        # caster health + live session (feeds the cast chip)
```

`;c ` in the launcher is the same surface as a menu (mirror, extend, stop).
Casting is fully non-interactive: the CLI pins the output choice for the
portal chooser (`cast-extend` → the `HEADLESS-*` output, mirror → the focused
screen) via `cast-portal-chooser` (`modules/desktop/sway.nix`), which falls
back to the walker dmenu for other apps' screen shares (OBS etc.). A receiver
is auto-picked when only one is on the LAN, walker dmenu otherwise. The
top-bar cast chip shows live state; its button is the toggle. Chrome must
stay fresh — the Cast CRL expires 20 weeks after build date
(`configurations/ryzen.nix`).

```bash
journalctl --user -u cast-caster -f
```

## Touch Input

Touchscreens are bound to the output they physically are. Sway maps an absolute
device across the *whole* output layout by default, so the moment a second
monitor is attached, touching the right edge of the built-in panel lands the
cursor on the external screen. `touch-map` fixes that and re-applies on every
hot-plug and every sway reload (a reload silently drops IPC-applied input
config, so `exec_always` re-runs it).

The built-in digitizer goes to the built-in panel; anything else is treated as
an external touchscreen and bound to the external output. On Surface hardware
the raw IPTS node is disabled whenever iptsd is publishing its calibrated
`IPTSD Virtual` twin — libinput binds both otherwise and every finger is
reported twice.

```bash
touch-map --dry-run                     # show the plan without applying it
cat $XDG_RUNTIME_DIR/touch-map.state    # live device → output → type bindings
journalctl --user -u touch-map-watch -f
journalctl --user -u touch-gestures -f
```

Override the heuristic in `~/.config/sway/touch-mapping.json` (hot-read, no
rebuild). `match` is a regex against the sway input identifier; `output` is an
output name or the literals `internal`/`external`; `calibration_matrix` is
optional and only needed for panels whose digitizer is rotated or mirrored:

```json
{ "rules": [ { "match": "Verbatim", "output": "HDMI-A-1" } ] }
```

If iptsd is not running, `touch-map` re-enables the raw digitizer instead, so a
crashed iptsd degrades the screen rather than killing it. That fallback is why
the disable is conditional and is re-evaluated on every run.

**Recovering iptsd** (surface): `systemctl restart iptsd@dev-hidraw1` alone does
*not* work once the daemon has been stopped — it reconnects to the device and
then dies on a HIDIOCSFEATURE ioctl (`Resource temporarily unavailable`, then
`No such device`). Reloading the `ipts` module does not help either; the ME side
of the link stays wedged. Rebinding the MEI device is what actually resets it:

```bash
DEV=0000:00:16.4-3e8d0870-271a-4208-8eb5-9acb9402ae04
echo $DEV | sudo tee /sys/bus/mei/drivers/ipts/unbind
echo $DEV | sudo tee /sys/bus/mei/drivers/ipts/bind
sudo systemctl reset-failed iptsd@dev-hidraw1 && sudo systemctl start iptsd@dev-hidraw1
```

**Gestures**: sway's `bindgesture` is built on libinput *pointer* gestures, which
only touchpads emit — it never sees the glass. `touch-gestures` runs one lisgd
per touchscreen, sized to that screen's output:

| Gesture | Action |
|---------|--------|
| 1 finger, bottom edge ↑ | Toggle on-screen keyboard (wvkbd) |
| 1 finger, top edge ↓ | Window switcher |
| 1 finger, left edge → | Browser back |
| 1 finger, right edge ← | Browser forward |
| 2 fingers, bottom edge ↑ | Toggle touch mode |
| 2 fingers, top edge ↓ | Toggle the runtime panel |
| 3 fingers, ← / → | Next / previous workspace |
| 3 fingers, ↑ | App launcher |
| **Hold still ~0.6s** | **Right click** (`touch-longpress`) |
| **2 fingers, hold still** | **Dictation toggle** (glass twin of the touchpad's `hold:4`) |

Edge gestures use one finger; anything away from an edge needs three. A
one-finger swipe mid-screen is indistinguishable from scrolling a page, while no
ordinary application claims three simultaneous touches. This set deliberately
does *not* mirror the touchpad's 3/4-finger bindings above — multi-finger on
glass means covering the screen with a hand.

**Touch-native surfaces**: in touch mode the launcher and settings window
auto-raise the on-screen keyboard (`osk-toggle auto-show`/`auto-hide` — a
keyboard the user opened manually survives the surface closing; state lives in
`$XDG_RUNTIME_DIR/osk.state` because wvkbd cannot be queried). The launcher card
lifts and shrinks so results clear the keys, its chips grow, and the exposé
close button grows. Rows inside ListViews (launcher results, herdr panel
agents/spaces) carry touch-scoped TapHandlers — MouseArea alone loses the grab
to flick arbitration and taps go nowhere — and their `preventStealing` relaxes
when a touchscreen is bound so finger-drags can scroll the lists at all.

**Long press → right click** (`touch-longpress.py`) exists because a touchscreen
has no second button and nothing else in the stack synthesises one, so context
menus are otherwise unreachable. It watches the digitizer and, after a still
hold, drives `dotool` to place a right click under the finger. Two things to
know: it needs the `uinput` group, which only applies to a session started
*after* the grant (the log says so explicitly if not), and it does not grab the
device — the touch still reaches the application, so in a terminal you may get a
text selection alongside the menu.

**Touch mode** raises the scale of every output that has a touchscreen bound, so
pointer-sized controls become finger-sized. The bars are 30/38 logical px and
some buttons are 22 — about 4mm at the Surface panel's 1.5 scale, against a ~9mm
touch guideline. Scaling fixes all of them at once and is reversible; it only
touches screens you actually touch, so a plain monitor keeps its density.

Scaling is **relative**: each touched output's existing scale is multiplied
(default 1.25x, snapped to quarter steps), not driven to one absolute value. A
fixed target cannot suit both displays — the Surface panel sits at 1.5 where 2.0
is a mild step, while the Verbatim sits at 1.25 where the same 2.0 overshoots.

```bash
touch-mode {on|off|toggle|status} [scale]   # bare = relative step
touch-mode on 1.75                          # explicit absolute scale
TOUCH_MODE_FACTOR=1.5 touch-mode on         # different multiplier, this run only
```

`off` restores the exact scale each output had, recorded at the time it was
enabled — not a guess at the default.

Three ways in, all driving the same state: the **top-bar chip** (finger icon,
right of the keyboard chip — teal when active), the **two-finger bottom-edge
swipe**, and the CLI. The chip reads a state feed
(`quickshell-touch-mode-status`) rather than tracking its own clicks, so it
stays correct when the mode is toggled by gesture or CLI. It hides itself
entirely when no touchscreen is bound, so it is not dead chrome on desktops.
"On" is keyed to the saved-scales file, not to the scale value — a user who
picks 2.0 themselves does not make the chip claim ownership of it.

## Workspace Navigation (Feature 042)

Enter mode (`CapsLock`/`Ctrl+0`) → type digits → `Enter` | `Escape` cancel | `+Shift` move window

## PWA Management

```bash
pwa-install-all   # Install all
pwa-list          # List configured
```

**Workspaces**: Regular apps 1-50, PWAs 50+
Edit `home-modules/tools/firefox-pwas-declarative.nix` → rebuild → `pwa-install-all`

## AI CLI Sessions

**Notifications**: `Enter` returns to terminal, `Escape` dismisses.

**Session Tracking**: QuickShell reads Herdr-native agent state through the i3pm daemon. The panel shows Herdr workspaces/tabs/panes and raw `agent_status` values (`working`, `blocked`, `done`, `idle`, `unknown`).

**Providers shown in the panel**: Herdr-managed Claude Code and Codex CLI sessions. Non-Herdr sessions are intentionally invisible in this panel.

```bash
herdr status --json                                # Server/protocol health
herdr agent list                                   # Agent sessions
herdr pane list                                    # Herdr panes
herdr integration status                           # Claude/Codex hooks
systemctl --user restart quickshell-runtime-shell  # Panel
i3pm health                                        # Runtime health, including Herdr
```

## Observability

**Local observability was removed 2026-07-26** (grafana-alloy OTLP collector,
Feature 129; beyla/pyroscope were never built). herdr tracks AI sessions
natively via its socket, the per-CLI OTEL interceptors were retired earlier,
and nothing else produced telemetry. Local monitoring is journal + desktop
notifications (e.g. `slab-leak-watch` below).

Hub-side K8s observability lives in the PittampalliOrg/stacks repo and is
unaffected: otel-collector + ClickHouse + Grafana on the hub cluster, reachable
via Tailscale Ingresses (`otel-collector-hub.tail286401.ts.net`,
`clickhouse-hub.tail286401.ts.net`, `grafana-hub.tail286401.ts.net`). In-cluster
workloads export there directly; if a local host ever needs remote telemetry
again, push OTLP straight to the hub collector (no local relay needed).

## NVIDIA Slab Leak (ryzen)

The ryzen host's NVIDIA open driver leaks unreclaimable kmalloc-64 slab via a
race in the explicit-sync path — fixed locally by
`patches/nvidia-595.80-semsurf-already-signalled-leak.patch` (mechanism +
history in the `boot.kernelParams` comment block of `configurations/ryzen.nix`).
Leaked slab survives everything except a reboot.

```bash
grep SUnreclaim /proc/meminfo                      # Current leak size
journalctl -t slab-leak-watch -o short-iso         # Trend history (30-min samples, MiB/day + ETA)
slab-reboot [--check|--yes|--force]                # Drain herdr agents, then reboot
```

## Testing

```bash
sway-test run tests/test.json
i3-project-test {run|suite|verify-state}
```

## Quick Debug

```bash
nixos-rebuild dry-build --flake .#<target> --show-trace
nix flake show
i3pm health
journalctl --user -u i3-project-daemon -f
```

## Additional Docs

- `docs/ARCHITECTURE.md` - System design
- `docs/PYTHON_DEVELOPMENT.md` - Python standards
- `docs/PWA_SYSTEM.md` - PWA details
- `docs/M1_SETUP.md` - Apple Silicon
- `docs/ONEPASSWORD.md` - 1Password integration
- `/etc/nixos/specs/<feature>/quickstart.md` - Feature specs

## Tech Stack

- **Daemon**: Python 3.11+, i3ipc.aio, Pydantic, asyncio
- **CLI**: TypeScript/Deno 1.40+, Zod
- **UI**: Quickshell (Qt/QML), including the native notification server
- **Config**: Nix flakes, JSON files in `~/.config/{i3,sway}/`

For per-feature history, see `git log` or `ls specs/`. EWW is no longer in use; see Quickshell (`home-modules/desktop/quickshell-runtime-shell/`) for panel/widget code.
