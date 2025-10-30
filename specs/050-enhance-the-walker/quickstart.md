# Quickstart: Enhanced Walker/Elephant Launcher

**Feature**: 050-enhance-the-walker | **Branch**: `050-enhance-the-walker`
**Status**: Ready for implementation

## What Changed

Walker launcher now includes 6 additional providers for enhanced productivity:

1. **Todo List** (`!` prefix) - Quick task management without leaving your workflow
2. **Window Switcher** (no prefix) - Fuzzy window search and focus
3. **Bookmarks** (no prefix) - Quick access to frequently visited URLs
4. **Custom Commands** (no prefix) - User-defined system operation shortcuts
5. **Enhanced Web Search** (`@` prefix) - Additional developer-focused search engines
6. **Clipboard History** (`:` prefix) - Already enabled for Wayland/Sway mode

All providers integrate seamlessly with the existing Walker keyboard-driven launcher.

## Provider Reference

| Provider | Prefix | Example | Purpose |
|----------|--------|---------|---------|
| **Todo List** | `!` | `!buy groceries` | Create/manage tasks with time tracking |
| **Window Switcher** | (none) | Type window title | Focus open windows via fuzzy search |
| **Bookmarks** | (none) | Type bookmark name | Open saved URLs in browser |
| **Custom Commands** | (none) | Type command name | Execute configured system commands |
| **Web Search** | `@` | `@nix hyprland` | Search multiple engines (Google, GitHub, etc.) |
| **Clipboard History** | `:` | `:` then search | Access clipboard history (Wayland only) |
| **Files** | `/` | `/nixos` | Search files in home directory |
| **Calculator** | `=` | `=2+2` | Quick calculations |
| **Symbols** | `.` | `.lambda` | Unicode symbol picker |
| **Runner** | `>` | `>git status` | Execute shell commands |

## Usage Workflows

### Task Management (`!` prefix)

**Create a task**:
```
Meta+D → !buy groceries → Return
```

**View all tasks**:
```
Meta+D → ! → (shows task list)
```

**Mark task complete**:
```
Meta+D → ! → Select task → Mark as done
```

**Scheduled tasks**:
```
Meta+D → !call dentist tomorrow → Return
```

Tasks persist across Walker restarts and support time tracking. Todo storage is in `~/.config/elephant/todo.toml`.

### Window Navigation

**Switch to window**:
```
Meta+D → firefox → Return (focuses Firefox window)
Meta+D → term → Return (focuses terminal)
```

**Cross-workspace navigation**:
```
Meta+D → code → Return (switches workspace and focuses VS Code)
```

Window switcher works with both Sway (Wayland) and i3 (X11) window managers. No prefix needed - just type partial window title.

### Quick Bookmark Access

**Open bookmark**:
```
Meta+D → github → Return (opens GitHub)
Meta+D → nix manual → Return (opens NixOS manual)
```

**Configured bookmarks** (in walker.nix):
- NixOS Manual - https://nixos.org/manual/nixos/stable/
- GitHub - https://github.com
- Google AI Studio - https://aistudio.google.com
- (Add more in walker.nix configuration)

Bookmarks are declaratively configured in `/etc/nixos/home-modules/desktop/walker.nix` via `elephant/bookmarks.toml`.

### Custom Command Shortcuts

**Execute system command**:
```
Meta+D → reload sway → Return (executes swaymsg reload)
Meta+D → rebuild nixos → Return (runs nixos-rebuild switch)
```

**Configured commands** (examples):
- "reload sway config" → `swaymsg reload`
- "restart waybar" → `killall waybar && waybar &`
- "lock screen" → `swaylock -f`
- "suspend system" → `systemctl suspend`
- "rebuild nixos" → `cd /etc/nixos && sudo nixos-rebuild switch --flake .#hetzner-sway`

Commands are declaratively configured in walker.nix via `elephant/commands.toml`. Add your frequently-used operations for quick access.

### Enhanced Web Search (`@` prefix)

**Search multiple engines**:
```
Meta+D → @rust error handling → Return (Google search)
Meta+D → @github walker → Return (GitHub search)
Meta+D → @nix hyprland → Return (NixOS packages search)
Meta+D → @arch bluetooth → Return (Arch Wiki search)
Meta+D → @so rust async → Return (Stack Overflow search)
```

**Available search engines**:
- **Google** (default) - General web search
- **DuckDuckGo** - Privacy-focused search
- **GitHub** - Code and repository search
- **YouTube** - Video search
- **Wikipedia** - Encyclopedia search
- **Stack Overflow** - Programming Q&A (NEW)
- **Arch Wiki** - Linux documentation (NEW)
- **Nix Packages** - NixOS package search (NEW)
- **Rust Docs** - Rust standard library (NEW)

Search engines are configured in walker.nix via `elephant/websearch.toml`.

### Clipboard History (`:` prefix, Wayland only)

**Access clipboard history**:
```
Meta+D → : → (shows recent clipboard entries)
```

**Search clipboard**:
```
Meta+D → :error message → Return (finds clipboard entry containing "error message")
```

**Clipboard actions**:
- Return: Copy to clipboard
- Delete: Remove entry from history
- Edit: Modify clipboard entry

**Note**: Clipboard history requires Wayland/Sway. Not available in X11/i3 mode (Elephant uses wl-clipboard).

## Configuration Location

All Walker/Elephant configuration is declaratively managed in NixOS home-manager:

**Primary config file**: `/etc/nixos/home-modules/desktop/walker.nix`

**Generated config files** (via xdg.configFile):
- `~/.config/walker/config.toml` - Walker provider settings
- `~/.config/elephant/websearch.toml` - Search engine definitions
- `~/.config/elephant/bookmarks.toml` - Bookmark entries
- `~/.config/elephant/commands.toml` - Custom command definitions
- `~/.config/elephant/todo.toml` - Todo list storage (auto-managed)

## Customization

### Adding Bookmarks

Edit `/etc/nixos/home-modules/desktop/walker.nix`, add entries to `bookmarks.toml`:

```toml
[[bookmarks]]
name = "My Project"
url = "https://example.com/project"
description = "Project management dashboard"
tags = ["work", "project"]
```

Rebuild: `home-manager switch --flake .#hetzner-sway`

### Adding Custom Commands

Edit walker.nix, add entries to `commands.toml`:

```toml
[customcommands]
"my command" = "my-script.sh"
"docker cleanup" = "docker system prune -af"
```

Rebuild: `home-manager switch --flake .#hetzner-sway`

### Adding Search Engines

Edit walker.nix, add entries to `websearch.toml`:

```toml
[[engines]]
name = "My Engine"
url = "https://example.com/search?q=%s"
```

Rebuild: `home-manager switch --flake .#hetzner-sway`

### Changing Provider Prefixes

Edit walker.nix, modify `providers.prefixes` section:

```toml
[[providers.prefixes]]
prefix = "?"
provider = "todo"  # Change ! to ?
```

Rebuild: `home-manager switch --flake .#hetzner-sway`

## Troubleshooting

### Provider not appearing

**Symptom**: Type prefix but provider doesn't activate

**Solutions**:
1. Check provider is enabled in walker.nix `[modules]` section
2. Verify prefix is defined in `[[providers.prefixes]]`
3. Restart Elephant service: `systemctl --user restart elephant`
4. Check Elephant logs: `journalctl --user -u elephant -f`

### Window switcher not showing windows

**Symptom**: Window provider doesn't list open windows

**Solutions**:
1. Verify Sway/i3 window manager is running
2. Check window manager IPC socket is accessible
3. Ensure `windows = true` in walker.nix modules section

### Clipboard history empty

**Symptom**: Clipboard provider shows no entries

**Solutions**:
1. Verify running Wayland/Sway (clipboard provider requires Wayland)
2. Check wl-clipboard is installed: `which wl-copy`
3. Copy something to clipboard, wait a moment, then check Walker
4. On X11/i3: Clipboard history is not supported (Elephant uses wl-clipboard)

### Todo list not persisting

**Symptom**: Tasks disappear after Walker restart

**Solutions**:
1. Check `~/.config/elephant/todo.toml` exists and is writable
2. Verify Elephant service is running: `systemctl --user status elephant`
3. Check Elephant logs for write errors: `journalctl --user -u elephant -f`

### Custom command not executing

**Symptom**: Command appears in search but doesn't run

**Solutions**:
1. Verify command syntax in `commands.toml` is correct (valid shell)
2. Check command has executable permissions if calling a script
3. Test command manually in terminal first
4. Use absolute paths for executables: `/run/current-system/sw/bin/command`

### Bookmarks not appearing

**Symptom**: Bookmarks don't show in Walker search

**Solutions**:
1. Verify `bookmarks = true` in walker.nix modules section
2. Check `~/.config/elephant/bookmarks.toml` is valid TOML
3. Rebuild home-manager after editing: `home-manager switch --flake .#hetzner-sway`
4. Restart Elephant: `systemctl --user restart elephant`

## Performance Notes

- Walker startup time increase: <200ms with all providers enabled
- Provider lazy-loading: Providers initialize on first use
- Result limits: Max 50 results globally, 20 for windows/files
- Memory usage: ~15-20MB additional for all providers

## Integration with i3pm Project System

Walker providers work seamlessly with i3pm project management:

**Project-aware launches**: Applications launched from Walker inherit project context via `I3PM_PROJECT_NAME` environment variable (see Feature 035 for details).

**Project switcher**: Use `;p` prefix to switch projects from Walker:
```
Meta+D → ;p nixos → Return
```

**Tmux session switcher**: Use `;s` prefix for tmux sessions:
```
Meta+D → ;s main → Return
```

These custom plugins are already configured in walker.nix.

## Documentation Updates

This feature updates the following documentation:

- **CLAUDE.md** - Walker section includes provider reference table
- **spec.md** - Feature specification with user stories and requirements
- **research.md** - Provider documentation and implementation decisions
- **quickstart.md** - This file (user-facing usage guide)

## Next Steps

After implementation:
1. Test each provider per acceptance scenarios in spec.md
2. Verify all keybindings and prefixes work correctly
3. Validate bookmarks, commands, and search engines open properly
4. Check todo list persistence across Walker restarts
5. Confirm window switcher navigates workspaces correctly
6. Update CLAUDE.md with provider summary for future reference
