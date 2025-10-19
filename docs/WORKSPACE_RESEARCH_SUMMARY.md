# Workspace Parameterization Research Summary

## Research Question

**Can we parameterize workspace creation? Do we need to define in advance or can we do it on the fly? What opensource projects do something similar?**

## Answer: You Can Do Both!

### On-the-Fly Creation (No Pre-Definition Needed)

**Yes!** i3 workspaces are created dynamically when you:
- Switch to them: `i3-msg "workspace number N"`
- Launch apps on them: `i3-msg "exec app"`
- Move windows to them: `i3-msg "move container to workspace N"`

**No rebuild, no pre-configuration required.**

### Parameterized Templates (Optional)

You can also create reusable templates with variable substitution:

```json
{
  "name": "${PROJECT_NAME}",
  "workspaces": [{
    "number": 2,
    "apps": [{"command": "code", "args": ["${PROJECT_DIR}"]}]
  }]
}
```

Then instantiate:

```bash
workspace-parameterized.sh template.json \
    PROJECT_NAME=myproject \
    PROJECT_DIR=/path/to/project
```

## Implementation Created

### Three Approaches

1. **Pure i3-msg** - No files, maximum flexibility
   ```bash
   i3-msg "workspace 4; exec code /my/project"
   ```

2. **Dynamic JSON** - Generate on-the-fly
   ```bash
   echo '{"workspaces":[...]}' | workspace-project.sh -
   ```

3. **Parameterized Templates** - Reusable with variables
   ```bash
   workspace-parameterized.sh template.json VAR=value
   ```

### Tools Created

1. **`workspace-parameterized.sh`** - Variable substitution engine
   - Reads templates with `${VAR}` or `${VAR:-default}` syntax
   - Substitutes variables from command line
   - Supports JSON templates
   - Creates temporary resolved JSON

2. **`workspace-interactive.sh`** - FZF-based launcher
   - Browse templates with preview
   - Interactive prompts for variables
   - Remembers last used values
   - Confirms before launch

3. **Templates** (`/etc/nixos/templates/`)
   - `dev-project.json` - Full dev environment
   - `simple-workspace.json` - Single workspace/app
   - `multi-terminal.json` - Multiple terminals with different directories

## Opensource Projects Research

### i3 Workspace Management Projects

#### 1. **i3-workspace-groups** (Python)
- **URL:** github.com/infokiller/i3-workspace-groups
- **Purpose:** Manage workspaces in groups/namespaces
- **Approach:** Persistent groups, namespace-based organization
- **Use Case:** Multiple projects, each with multiple workspaces
- **Comparison:** Focused on organization, not creation/launching

#### 2. **i3-resurrect** (Python)
- **URL:** github.com/JonnyHaystack/i3-resurrect
- **Purpose:** Save and restore workspace layouts
- **Approach:** Uses i3-save-tree, saves window positions
- **Features:**
  - Saves workspace tree to JSON
  - Restores window layout
  - Re-launches applications
  - Uses xdotool to remap windows
- **Comparison:** Saves existing state vs creating new sessions

#### 3. **i3-layouts** (Python)
- **URL:** github.com/eliep/i3-layouts
- **Purpose:** Dynamic layout switching
- **Approach:** Predefined layouts, switch on command
- **Use Case:** Change window arrangement patterns
- **Comparison:** Layout-focused, not application launching

#### 4. **i3session** (Ruby/Python)
- **URL:** github.com/joepestro/i3session
- **Purpose:** Session manager for i3
- **Approach:** Save/restore complete sessions
- **Features:**
  - Remembers running processes
  - Saves window orientation
  - Restores to workspaces
- **Comparison:** Session persistence vs template instantiation

#### 5. **i3-workspace-manager** (Go)
- **URL:** github.com/ShimmerGlass/i3-workspace-manager
- **Purpose:** Project-based workspace switching
- **Approach:** Opens editor + terminal per project
- **Use Case:** Quick project switching
- **Comparison:** Similar concept, less flexible

### tmux Session Managers (Inspiration)

#### 1. **tmuxp** (Python)
- **URL:** github.com/tmux-python/tmuxp
- **Purpose:** tmux session manager
- **Features:**
  - YAML/JSON configuration
  - Variable substitution
  - Session freeze/restore
  - Import from tmuxinator
- **Comparison:** Works at terminal level, we work at window manager level
- **Similarity:** Template-based with parameters

#### 2. **tmuxinator** (Ruby)
- **Purpose:** tmux session manager
- **Features:**
  - YAML configuration
  - Project-based sessions
  - Automatic session setup
- **Comparison:** Similar but for tmux panes, not i3 workspaces
- **Similarity:** Project templates with customization

### Key Takeaways from Research

1. **No direct equivalent exists** - No project does exactly what we built
2. **i3-resurrect is closest** - But focused on preservation, not templates
3. **tmuxp/tmuxinator model** - Template-based approach proven successful
4. **Workspace groups concept** - Useful for organization, complementary
5. **Most tools are Python** - We chose bash for simplicity and no dependencies

## Our Approach: Best of Both Worlds

### Combines Ideas From:

1. **tmuxp/tmuxinator** - Template-based parameterization
2. **i3-resurrect** - JSON configuration format
3. **i3-workspace-groups** - Project-based organization
4. **Direct i3-msg** - Dynamic creation without pre-definition

### Unique Advantages:

1. **Zero dependencies** (beyond i3, jq, bash)
2. **No rebuild required** - Instant changes
3. **Multiple usage modes** - Pure CLI, templates, or interactive
4. **Variable substitution** - Like tmuxp but for i3
5. **On-the-fly capable** - Don't need templates if you don't want them
6. **NixOS integration** - Templates in `/etc/nixos/templates/`

## Usage Patterns

### 1. Ad-Hoc (No Templates)

```bash
# Quick setup - no files needed
i3-msg "workspace 2; exec ghostty"
i3-msg "workspace 4; exec code /my/project"
```

**When:** One-off setups, quick experiments

### 2. Script-Based (Dynamic Generation)

```bash
#!/usr/bin/env bash
setup_project() {
    local dir="$1"
    i3-msg "workspace 2; exec ghostty --working-directory=$dir"
    sleep 0.5
    i3-msg "workspace 4; exec code $dir"
}

setup_project "/etc/nixos"
```

**When:** Programmatic control, shell functions

### 3. Template-Based (Reusable Configs)

```bash
# Define once, reuse with different parameters
workspace-parameterized.sh dev-project.json \
    PROJECT_NAME=nixos \
    PROJECT_DIR=/etc/nixos
```

**When:** Common patterns, team sharing

### 4. Interactive (User-Friendly)

```bash
# Guided setup with FZF
workspace-interactive.sh
```

**When:** Occasional use, varied projects

## Integration Possibilities

### With Existing Tools

1. **tmux + i3** - Workspace contains tmux session
   ```json
   {"command": "ghostty", "args": ["-e", "tmuxp", "load", "session.yaml"]}
   ```

2. **i3-workspace-groups** - Use groups to organize our workspaces
   ```bash
   i3-workspace-groups assign-workspace project-name 2
   workspace-parameterized.sh template.json
   ```

3. **i3-resurrect** - Save templates created by our system
   ```bash
   workspace-parameterized.sh template.json
   # Use workspace, arrange windows
   i3-resurrect save -w 2
   ```

### With NixOS Configuration

Templates can be version-controlled alongside NixOS config:

```nix
# In flake.nix or configuration
environment.etc."nixos/templates/my-project.json".source = ./templates/my-project.json;
```

Users can maintain personal templates:

```bash
~/.config/i3-workspaces/templates/
```

## Comparison Matrix

| Feature | Our Solution | i3-resurrect | i3-workspace-groups | tmuxp |
|---------|-------------|--------------|-------------------|-------|
| **Parameterization** | ✓ | ✗ | ✗ | ✓ |
| **Templates** | ✓ | ✗ | ✗ | ✓ |
| **On-the-fly** | ✓ | ✗ | ✓ | ✗ |
| **No rebuild** | ✓ | ✓ | ✓ | ✓ |
| **Window launching** | ✓ | ✓ | ✗ | N/A |
| **Layout restore** | ✗ | ✓ | ✗ | N/A |
| **Workspace groups** | ✗ | ✗ | ✓ | N/A |
| **Interactive UI** | ✓ | ✗ | ✓ | ✗ |
| **Variable substitution** | ✓ | ✗ | ✗ | ✓ |
| **Dependencies** | bash, jq | Python | Python | Python |

## Example Use Cases

### 1. Development Environment

```bash
workspace-parameterized.sh dev-project.json \
    PROJECT_NAME=backend-api \
    PROJECT_DIR=/home/user/backend \
    PROJECT_URL=http://localhost:8000/docs
```

**Result:**
- Workspace 1: Firefox with API docs
- Workspace 2: Terminal in project dir
- Workspace 4: VSCode with project open

### 2. Meeting Setup

```bash
workspace-parameterized.sh meeting-setup.json \
    MEETING_NAME="Sprint Planning" \
    MEETING_URL="https://meet.google.com/xyz" \
    NOTES_DIR="$HOME/Documents/meetings"
```

**Result:**
- Workspace 3: Browser with meeting
- Workspace 2: Editor with notes

### 3. Monitoring Dashboard

```bash
workspace-parameterized.sh monitoring.json \
    SERVER_HOST=production.example.com
```

**Result:**
- Workspace 8: Multiple terminals with htop, logs, etc.

## Future Enhancement Ideas

Based on research, potential additions:

1. **Layout restoration** - Integrate with i3-save-tree
2. **Workspace groups** - Organize by project like i3-workspace-groups
3. **Session persistence** - Optional save/restore like i3-resurrect
4. **YAML support** - Like tmuxp (requires yq dependency)
5. **Hooks** - Pre/post launch scripts
6. **Window matching** - Better window targeting for complex layouts
7. **Multi-monitor** - Output-aware workspace assignment

## Conclusion

### What We Built

A **flexible, parameterized workspace creation system** that:
- Works with or without templates
- Requires no rebuild
- Supports variable substitution
- Has interactive and CLI interfaces
- Integrates with existing tools
- Is inspired by best practices from similar projects

### Answer to Original Question

**Can we parameterize?** Yes - `${VAR}` syntax in templates

**Do we need to define in advance?** No - multiple approaches:
- Pure i3-msg commands
- Dynamic JSON generation
- Reusable templates (optional)

**Similar projects?** Many inspirations:
- i3-resurrect (layout restoration)
- tmuxp/tmuxinator (template approach)
- i3-workspace-groups (organization)
- But none do exactly this combination

### Recommendation

Use **hybrid approach**:
- **Ad-hoc**: Direct i3-msg for quick experiments
- **Script-based**: Shell functions for common patterns
- **Template-based**: Reusable configs for frequent setups
- **Interactive**: FZF launcher for occasional use

All coexist peacefully, choose based on situation.

## Files Created

### Scripts
- `scripts/workspace-parameterized.sh` - Variable substitution engine
- `scripts/workspace-interactive.sh` - FZF-based interactive launcher

### Templates
- `templates/dev-project.json` - Full development environment
- `templates/simple-workspace.json` - Single workspace/app
- `templates/multi-terminal.json` - Multiple terminals

### Documentation
- `docs/WORKSPACE_PARAMETERIZATION.md` - Complete guide
- `docs/WORKSPACE_RESEARCH_SUMMARY.md` - This document

---

_Research completed: 2025-10-18_
