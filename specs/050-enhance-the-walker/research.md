# Research: Enhanced Walker/Elephant Provider Configuration

**Feature**: 050-enhance-the-walker
**Date**: 2025-10-29
**Sources**: https://walkerlauncher.com/docs/providers, https://walkerlauncher.com/docs/configuration

## Summary

Walker/Elephant launcher provides 6 additional providers beyond the currently enabled set. All providers are configured declaratively via TOML files in `~/.config/walker/` and `~/.config/elephant/`. Configuration is straightforward with provider enable/disable flags, prefix assignments, and provider-specific settings. All requested providers are available in Walker ≥1.5 and Elephant ≥2.9.

## Research Findings

### Provider Overview

| Provider | Prefix | Package | Status | Purpose |
|----------|--------|---------|--------|---------|
| todo | `!` | elephant-todo | **NEW** | Simple todo list with time tracking |
| windows | none | elephant-windows | **NEW** | Window switcher for desktop navigation |
| bookmarks | none | elephant-bookmarks | **NEW** | Custom bookmark quick access |
| customcommands | none | elephant-customcommands | **NEW** | User-defined one-off command shortcuts |
| websearch | `@` | elephant-websearch | **ENHANCE** | Already enabled, add more search engines |
| clipboard | `:` | elephant-clipboard | **CONDITIONAL** | Already works on Wayland, X11 unsupported |

### Configuration Structure

Walker/Elephant use TOML configuration files with clear structure:

**Walker config** (`~/.config/walker/config.toml`):
- `[modules]` section enables/disables providers
- `[[providers.prefixes]]` table arrays define prefix → provider mappings
- `[providers.actions.*]` sections configure keybindings and behaviors

**Elephant provider configs** (`~/.config/elephant/*.toml`):
- `websearch.toml` - Search engine definitions
- `bookmarks.toml` - Bookmark entries (NEW)
- `commands.toml` - Custom command definitions (NEW)
- `todo.toml` - Todo list storage (NEW, managed by provider)

### Decision: Todo List Provider

**Chosen**: Enable with `!` prefix
**Configuration**: Auto-managed by elephant-todo provider
**Storage**: `~/.config/elephant/todo.toml` (created automatically)
**Features**: Create/delete tasks, mark active/inactive/done, time tracking, scheduled notifications

**Rationale**: Todo provider handles its own storage declaratively. No manual TOML configuration needed - users interact via `!task description` syntax. Time tracking and scheduling enhance productivity without additional complexity.

**Example Usage**:
```
!buy groceries
!call dentist tomorrow
```

### Decision: Window Switcher Provider

**Chosen**: Enable without prefix (fuzzy search in default mode)
**Configuration**: No provider-specific config needed
**Integration**: Works with Sway/Wayland and i3/X11 window managers

**Rationale**: Window switcher integrates with native window manager protocols. No prefix needed - typing partial window titles in default Walker mode triggers window search. This follows the pattern of the applications provider (no prefix, fuzzy matching).

**Alternatives Considered**:
- Prefix-based (e.g., `#window`) - Rejected: Extra keystrokes reduce productivity for frequent window switching
- Separate keybinding - Rejected: Walker's fuzzy matching already handles this elegantly

### Decision: Bookmarks Provider

**Chosen**: Enable without prefix, configure via `elephant/bookmarks.toml`
**Configuration**: TOML entries with name, URL, optional description/tags
**Storage**: `~/.config/elephant/bookmarks.toml` (declarative in walker.nix)

**Configuration Format**:
```toml
[[bookmarks]]
name = "NixOS Manual"
url = "https://nixos.org/manual/nixos/stable/"
description = "Official NixOS documentation"
tags = ["docs", "nix"]

[[bookmarks]]
name = "GitHub"
url = "https://github.com"
```

**Rationale**: Bookmarks as declarative configuration in walker.nix ensures version control and reproducibility. Users can edit walker.nix to manage bookmarks rather than using separate bookmark manager UI. Fuzzy search without prefix keeps workflow fast.

### Decision: Custom Commands Provider

**Chosen**: Enable without prefix, configure via `elephant/commands.toml`
**Configuration**: TOML map of command name → command string
**Storage**: `~/.config/elephant/commands.toml` (declarative in walker.nix)

**Configuration Format**:
```toml
[customcommands]
"reload sway config" = "swaymsg reload"
"restart waybar" = "killall waybar && waybar &"
"lock screen" = "swaylock -f"
"suspend system" = "systemctl suspend"
"rebuild nixos" = "cd /etc/nixos && sudo nixos-rebuild switch --flake .#hetzner-sway"
```

**Rationale**: Custom commands fill the gap between frequently-used keybindings and one-off operations. Declaring them in walker.nix provides version control and system reproducibility. Users search by command description, not memorizing syntax.

**Use Cases**:
- System operations (rebuild, suspend, reboot)
- Window manager commands (reload config, restart bars)
- Project-specific operations (build commands, deployment scripts)

### Decision: Enhanced Web Search

**Chosen**: Expand existing `websearch.toml` with additional search engines
**Current State**: Already configured with Google, DuckDuckGo, GitHub, YouTube, Wikipedia
**Enhancement**: Add domain-specific engines (Stack Overflow, Arch Wiki, Rust docs, Nix packages)

**Enhanced Configuration**:
```toml
[[engines]]
name = "Stack Overflow"
url = "https://stackoverflow.com/search?q=%s"

[[engines]]
name = "Arch Wiki"
url = "https://wiki.archlinux.org/index.php?search=%s"

[[engines]]
name = "Nix Packages"
url = "https://search.nixos.org/packages?query=%s"

[[engines]]
name = "Rust Docs"
url = "https://doc.rust-lang.org/std/?search=%s"

default = "Google"
```

**Rationale**: Domain-specific search engines reduce friction for development workflows. `@nix hyprland` directly searches nix packages, `@arch bluetooth` searches Arch Wiki. Developers frequently need docs for specific technologies - dedicated search engines eliminate intermediate Google searches.

### Decision: Clipboard History

**Current State**: Already enabled for Wayland/Sway mode, disabled for X11/i3
**Reason**: Elephant's clipboard provider uses wl-clipboard (Wayland-only), X11 clipboard monitoring not supported
**Configuration**: No changes needed - already conditionally enabled in walker.nix

**No Action Required**: The existing walker.nix configuration already handles this correctly with Wayland detection:
```nix
clipboard = ${if isWaylandMode then "true" else "false"}
```

### Configuration Best Practices

1. **Provider Sets**: Use `[providers]` `default` and `empty` arrays to control which providers are queried
   - `default`: Providers queried when typing without prefix
   - `empty`: Providers shown when search field is blank

2. **Performance**: Set `max_results` per provider to optimize response time
   - Recommended: 50 results max globally, 10-20 for file/window providers

3. **Prefix Strategy**: Use single-character prefixes for frequently-used providers
   - `!` todo (common enough to warrant prefix)
   - `@` web search (already standard)
   - `:` clipboard (already standard)
   - No prefix: applications, windows, bookmarks (fuzzy search)

4. **Provider Actions**: Configure keybindings for multi-action providers
   - Return: Default action (open, launch, run)
   - Shift+Return: Alternative action (run in terminal, edit, delete)

## Implementation Approach

### Phase 1: Enable Providers in Walker Config

Modify `xdg.configFile."walker/config.toml"` section in walker.nix:

```toml
[modules]
todo = true
windows = true
bookmarks = true
customcommands = true
# websearch and clipboard already enabled

[[providers.prefixes]]
prefix = "!"
provider = "todo"
# Other prefixes already configured
```

### Phase 2: Add Provider-Specific Configurations

Add new xdg.configFile entries for:
- `elephant/bookmarks.toml` - Curated bookmark list
- `elephant/commands.toml` - Useful custom commands

Enhance existing:
- `elephant/websearch.toml` - Add developer-focused search engines

### Phase 3: Configure Default Provider Behavior

Update `[providers]` section to include new providers in default set:

```toml
[providers]
default = [
  "desktopapplications",
  "windows",          # NEW
  "bookmarks",        # NEW
  "customcommands",   # NEW
  "calc",
  "runner",
  "websearch",
  "menus"
]
empty = ["desktopapplications", "windows"]  # Show apps + windows when blank
max_results = 50
```

### Phase 4: Documentation and Testing

Create quickstart.md with:
- Provider reference table (prefix, purpose, example)
- Usage workflows for each provider
- Configuration examples
- Troubleshooting common issues

Test each provider per acceptance scenarios in spec.md.

## Open Questions Resolved

✅ **Todo storage format**: Auto-managed by elephant-todo provider in `~/.config/elephant/todo.toml`
✅ **Window switcher prefix**: No prefix - fuzzy search in default mode
✅ **Bookmark configuration**: Declarative TOML in walker.nix via xdg.configFile
✅ **Custom command syntax**: Simple map format: `"description" = "command"`
✅ **Web search engines**: TOML array of engines with name + URL template
✅ **Clipboard history**: Already handled conditionally (Wayland only)
✅ **Performance impact**: Minimal - Walker lazy-loads providers, <200ms startup increase expected

## Technology Stack Summary

- **Configuration Language**: TOML (Walker/Elephant standard)
- **Package Management**: NixOS home-manager (xdg.configFile)
- **Provider Packages**: Elephant plugins (built-in to Elephant 2.9.x)
- **Storage**: File-based TOML (version-controlled in walker.nix)
- **Testing**: Manual acceptance scenarios per spec.md

## Next Steps

1. ✅ Phase 0 Complete - Research findings documented
2. → Phase 1: Generate quickstart.md with user-facing documentation
3. → Phase 1: Update agent context (CLAUDE.md) with provider summary
4. → Phase 2 (/speckit.tasks): Generate tasks.md for implementation
