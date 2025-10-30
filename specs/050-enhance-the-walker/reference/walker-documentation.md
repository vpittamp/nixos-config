# Walker/Elephant Documentation Reference

**Source**: https://walkerlauncher.com/docs/providers and https://walkerlauncher.com/docs/configuration
**Scraped**: 2025-10-29
**Purpose**: Reference documentation for Feature 050 implementation

---

## Walker Providers Overview

Walker is a launcher application that uses plugins called providers to deliver data. Here's a comprehensive breakdown:

### Available Providers

**Desktop Applications** (`desktopapplications`)
- Launches GUI apps from `.desktop` files
- Features: Searches application names, descriptions, and keywords
- History-aware ranking that prioritizes frequently-used applications

**Calculator** (`calc`, prefix: `=`)
- Mathematical computation tool
- Supports: Basic arithmetic operations, scientific functions, unit conversions, currency exchange calculations

**Command Runner** (`runner`, prefix: `>`)
- Shell execution provider
- Features: Parses shell config for aliases, lists all binaries in PATH with smart command matching

**File Browser** (`files`, prefix: `/`)
- Navigate and open files
- Features: Fast fuzzy file search, drag-and-drop capabilities

**Web Search** (`websearch`, prefix: `@`)
- Queries multiple search engines (Google, DuckDuckGo, Ecosia, Yandex)
- Detects URLs for direct opening

**Clipboard History** (`clipboard`, prefix: `:`)
- Maintains stored clipboard history with timestamped entries
- Supports: Text and image content

**Symbol Picker** (`symbols`, prefix: `.`)
- Provides large collection of symbols across categories
- Categories: arrows, math, currency, etc.

**Unicode** (`unicode`)
- Complete character database searchable by name or code point

**Todo List** (`todo`, prefix: `!`)
- Task management with time tracking
- Features: Status marking (active/inactive/done), notifications

**Custom Commands** (`customcommands`)
- User-defined one-off commands configured in settings
- No separate keybindings required

**Bookmarks** (`bookmarks`)
- Quick access to saved URLs and web links

**Window Switcher** (`windows`)
- Lists open windows for desktop focus switching

**SSH** (`ssh`)
- Parses SSH configuration files for quick host connections

### Configuration

Default providers are specified in the configuration file. Users can:
- Assign custom prefixes
- Set maximum result limits per provider
- Create provider sets for different workflows (development, web browsing, etc.)

---

## Walker Configuration Guide

### Configuration File Location
Walker uses `~/.config/walker/config.toml` for settings, created automatically on first run. A reference configuration exists in the repository's `resources/config.toml`.

### File Format
The configuration uses TOML syntax. Basic structure includes:

#### General Settings
- `force_keyboard_focus` - Keep keyboard focus in Walker
- `close_when_open` - Close if already open when invoked
- `click_to_close` - Close when clicking outside content
- `selection_wrap` - Wrap navigation at list boundaries
- `disable_mouse` - Disable mouse interaction
- `exact_search_prefix` - Character to disable fuzzy matching (default: `'`)
- `global_argument_delimiter` - Pass arguments to items (default: `#`)
- `theme` - Theme name from `~/.config/walker/themes/`

### Provider Configuration

#### Default Providers Section
```toml
[providers]
default = ["desktopapplications", "calc", "runner"]
empty = ["desktopapplications"]
max_results = 50
```

#### Provider Sets
Create custom groupings:
```toml
[providers.sets.mylauncher]
default = ["desktopapplications", "runner"]
```

#### Max Results Per Provider
```toml
[providers.max_results_provider]
desktopapplications = 20
files = 30
```

### Provider Prefixes
Define quick-access prefixes for specific providers:
```toml
[[providers.prefixes]]
prefix = ">"
provider = "runner"

[[providers.prefixes]]
prefix = "/"
provider = "files"
```

Common prefixes:
- `;` - provider switcher
- `>` - runner
- `/` - files
- `.` - symbols
- `!` - todo
- `=` - calc
- `@` - web search
- `:` - clipboard

### Provider-Specific Settings

#### Clipboard Configuration
```toml
[providers.clipboard]
time_format = "%d.%m. - %H:%M"
```

### Action Bindings

Actions define what happens when interacting with items. Key properties:
- `action` - The action name
- `bind` - Keybinding trigger
- `default` - Primary action on Enter
- `after` - Post-execution behavior options:
  - `Nothing` - Keep Walker open
  - `Close` - Close Walker
  - `Reload` - Reload results
  - `ClearReload` - Clear and reload
  - `AsyncReload` - Async reload

#### Example for files provider
```toml
[[providers.actions.files]]
action = "open"
default = true
bind = "Return"
after = "Close"

[[providers.actions.files]]
action = "copypath"
bind = "ctrl shift c"
after = "Nothing"
```

### Keybindings
```toml
[keybinds]
close = ["Escape"]
next = ["Down"]
prev = ["Up"]
toggle_exact = ["ctrl e"]
```

Valid modifiers: `ctrl`, `alt`, `shift`, `super`

### Minimal Configuration Example
A basic setup requires:
- Theme selection
- Default providers list
- Keybindings for functional operation

### Validation
Test configuration with `walker --debug` to check for syntax errors before normal launch.

---

## Implementation Notes for Feature 050

### Providers to Enable
1. **Todo List** (`todo`) - Prefix: `!`
2. **Window Switcher** (`windows`) - No prefix by default
3. **Bookmarks** (`bookmarks`) - No prefix by default
4. **Custom Commands** (`customcommands`) - No prefix by default
5. **Enhanced Web Search** (`websearch`) - Prefix: `@` (already enabled, enhance with more engines)
6. **Clipboard History** (`clipboard`) - Prefix: `:` (already enabled in Wayland mode)

### Provider Prefixes Configuration
```toml
[[providers.prefixes]]
prefix = "!"
provider = "todo"

[[providers.prefixes]]
prefix = ":"
provider = "clipboard"

[[providers.prefixes]]
prefix = "@"
provider = "websearch"
```

### Example Bookmark Configuration
```toml
[[providers.bookmarks.entries]]
name = "GitHub"
url = "https://github.com"
description = "Code repository hosting"
category = "development"

[[providers.bookmarks.entries]]
name = "NixOS Manual"
url = "https://nixos.org/manual/"
description = "Official NixOS documentation"
category = "documentation"
```

### Example Custom Command Configuration
```toml
[[providers.customcommands.commands]]
name = "git-status"
description = "Show git repository status"
cmd = "git status"
after = "Nothing"

[[providers.customcommands.commands]]
name = "rebuild-nixos"
description = "Rebuild NixOS configuration"
cmd = "sudo nixos-rebuild switch --flake .#hetzner-sway"
after = "Close"
```

### Web Search Engine Configuration
```toml
[[providers.websearch.engines]]
name = "Google"
url = "https://www.google.com/search?q=%s"
default = true

[[providers.websearch.engines]]
name = "GitHub"
url = "https://github.com/search?q=%s"

[[providers.websearch.engines]]
name = "Wikipedia"
url = "https://en.wikipedia.org/wiki/Special:Search?search=%s"

[[providers.websearch.engines]]
name = "DuckDuckGo"
url = "https://duckduckgo.com/?q=%s"
```

---

## Testing Checklist

- [ ] Todo provider: Create task with `!buy groceries`
- [ ] Todo provider: View tasks with `!` prefix
- [ ] Todo provider: Complete task
- [ ] Window switcher: Search for open window by partial title
- [ ] Window switcher: Focus window from search results
- [ ] Window switcher: Switch to window on different workspace
- [ ] Bookmarks: Search for bookmark by name
- [ ] Bookmarks: Open bookmark URL in browser
- [ ] Custom commands: Execute custom command
- [ ] Custom commands: Pass parameters to command
- [ ] Web search: Search Google with `@query`
- [ ] Web search: Search GitHub with `@github query`
- [ ] Clipboard history: View clipboard entries with `:` prefix
- [ ] Clipboard history: Select and copy previous entry
- [ ] Verify Walker startup time (should be <200ms increase)
- [ ] Test error handling for missing todo file
- [ ] Test window switcher with no open windows
- [ ] Test bookmark with invalid URL
