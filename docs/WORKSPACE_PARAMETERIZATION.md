# Workspace Parameterization

## Overview

Create reusable workspace templates with variable substitution - **no NixOS rebuild required**. Define templates once, instantiate them with different parameters on-the-fly.

**Inspired by:** tmuxp, tmuxinator, i3-resurrect, i3-workspace-groups

## Key Concepts

### Do You Need to Define in Advance?

**No!** You have three approaches:

1. **Pre-defined Templates** - Create reusable templates, instantiate with parameters
2. **On-the-Fly JSON** - Generate JSON dynamically in scripts
3. **Direct i3-msg** - No files at all, pure command-line

All three work without rebuilds. Choose based on your workflow:

| Approach | Reusability | Flexibility | Complexity |
|----------|-------------|-------------|------------|
| Templates | High | Medium | Low |
| Dynamic JSON | Medium | High | Medium |
| Direct i3-msg | Low | Very High | Very Low |

## Template System

### Basic Template Format

Templates support variable substitution using `${VAR}` or `${VAR:-default}` syntax:

```json
{
  "name": "${PROJECT_NAME:-my-project}",
  "workspaces": [
    {
      "number": 2,
      "apps": [
        {
          "command": "ghostty",
          "args": ["--working-directory=${PROJECT_DIR}"],
          "delay": 0
        }
      ]
    },
    {
      "number": 4,
      "apps": [
        {
          "command": "code",
          "args": ["${PROJECT_DIR}"],
          "delay": 500
        }
      ]
    }
  ]
}
```

### Variable Syntax

```json
"${VAR}"              // Required variable (error if not provided)
"${VAR:-default}"     // Optional with default value
"${VAR:-.}"           // Default to current directory
"${VAR:-$HOME}"       // Can use environment variables in defaults
```

## Usage Methods

### Method 1: Parameterized Script

```bash
workspace-parameterized.sh <template> VAR1=value1 VAR2=value2 ...

# Example
workspace-parameterized.sh /etc/nixos/templates/dev-project.json \
    PROJECT_NAME=nixos-dev \
    PROJECT_DIR=/etc/nixos \
    PROJECT_URL=https://nixos.org/manual
```

**What happens:**
1. Reads template file
2. Substitutes all `${VAR}` with provided values
3. Creates temporary JSON with substituted values
4. Launches workspace using workspace-project.sh

### Method 2: Interactive Launcher

```bash
workspace-interactive.sh [template-dir]

# Uses /etc/nixos/templates by default
workspace-interactive.sh
```

**Interactive flow:**
1. FZF menu to select template (with preview)
2. Prompts for each variable (remembers last used values)
3. Shows summary and confirms
4. Launches workspace

**Features:**
- Template preview in FZF
- Remembers recent values in `~/.cache/workspace-interactive-recent.txt`
- Default values from template
- Confirmation before launch

### Method 3: On-the-Fly JSON Generation

Generate JSON dynamically without template files:

```bash
#!/usr/bin/env bash
PROJECT_DIR="/home/user/myproject"
PROJECT_NAME="myproject"

cat > /tmp/workspace-$$.json <<EOF
{
  "name": "$PROJECT_NAME",
  "workspaces": [
    {
      "number": 2,
      "apps": [{"command": "ghostty", "args": [], "delay": 0}]
    },
    {
      "number": 4,
      "apps": [{"command": "code", "args": ["$PROJECT_DIR"], "delay": 500}]
    }
  ]
}
EOF

workspace-project.sh /tmp/workspace-$$.json
rm /tmp/workspace-$$.json
```

### Method 4: Pure i3-msg (No Templates)

Most flexible - no files needed:

```bash
#!/usr/bin/env bash
PROJECT_DIR="/etc/nixos"

# Function for parameterized workspace setup
setup_dev_workspace() {
    local dir="$1"
    local ws_terminal="${2:-2}"
    local ws_editor="${3:-4}"

    i3-msg "workspace number $ws_terminal"
    sleep 0.1
    i3-msg "exec --no-startup-id ghostty --working-directory=$dir"

    sleep 0.3

    i3-msg "workspace number $ws_editor"
    sleep 0.1
    i3-msg "exec --no-startup-id code $dir"
}

# Use it
setup_dev_workspace "$PROJECT_DIR" 2 4
```

## Available Templates

### 1. Development Project (`dev-project.json`)

Full development environment with browser, terminal, and editor:

```bash
workspace-parameterized.sh /etc/nixos/templates/dev-project.json \
    PROJECT_NAME=my-app \
    PROJECT_DIR=/home/user/projects/my-app \
    PROJECT_URL=http://localhost:3000
```

**Variables:**
- `PROJECT_NAME` - Project identifier (default: dev-project)
- `PROJECT_DIR` - Project directory (default: .)
- `PROJECT_URL` - URL to open in browser (default: http://localhost:3000)

**Workspaces:**
- 1: Firefox with project URL
- 2: Ghostty terminal
- 4: VSCode with project directory

### 2. Simple Workspace (`simple-workspace.json`)

Single workspace, single app:

```bash
workspace-parameterized.sh /etc/nixos/templates/simple-workspace.json \
    WORKSPACE_NAME=monitoring \
    WORKSPACE_NUM=8 \
    APP_COMMAND=btop
```

**Variables:**
- `WORKSPACE_NAME` - Workspace identifier (default: simple-workspace)
- `WORKSPACE_NUM` - Workspace number (default: 9)
- `APP_COMMAND` - Application to launch (default: ghostty)
- `APP_ARGS` - JSON array of arguments (default: [])

### 3. Multi-Terminal (`multi-terminal.json`)

Multiple terminals with different working directories:

```bash
workspace-parameterized.sh /etc/nixos/templates/multi-terminal.json \
    PROJECT_NAME=microservices \
    WORKSPACE_NUM=7 \
    DIR1=/home/user/service-api \
    DIR2=/home/user/service-web \
    DIR3=/home/user/service-worker
```

**Variables:**
- `PROJECT_NAME` - Project identifier (default: multi-terminal)
- `WORKSPACE_NUM` - Workspace number (default: 8)
- `DIR1`, `DIR2`, `DIR3` - Working directories (default: $HOME)

## Creating Custom Templates

### Template Structure

```json
{
  "name": "${TEMPLATE_VAR:-default}",
  "description": "Template description",
  "workspaces": [
    {
      "number": ${WORKSPACE_NUM:-1},
      "apps": [
        {
          "command": "${APP_COMMAND}",
          "args": ${APP_ARGS:-[]},
          "delay": ${DELAY:-0}
        }
      ]
    }
  ]
}
```

### Best Practices

1. **Always provide defaults** - Use `${VAR:-default}` syntax
2. **Use uppercase for variables** - Matches environment variable convention
3. **Document variables** - Add description field with variable documentation
4. **Test with dry-run** - Use `DRY_RUN=true` to test before execution
5. **Store in templates directory** - Keep organized in `/etc/nixos/templates/` or `~/.config/i3-workspaces/templates/`

### Example: Custom Template

Create `~/.config/i3-workspaces/templates/meeting-setup.json`:

```json
{
  "name": "${MEETING_NAME:-meeting}",
  "description": "Meeting workspace setup. Variables: MEETING_NAME, MEETING_URL, NOTES_DIR",
  "workspaces": [
    {
      "number": 3,
      "apps": [
        {
          "command": "firefox",
          "args": ["--new-window", "${MEETING_URL}"],
          "delay": 0
        }
      ]
    },
    {
      "number": 2,
      "apps": [
        {
          "command": "code",
          "args": ["${NOTES_DIR:-$HOME/Documents/meetings}"],
          "delay": 500
        }
      ]
    }
  ]
}
```

Use it:

```bash
workspace-parameterized.sh ~/.config/i3-workspaces/templates/meeting-setup.json \
    MEETING_NAME="Sprint Planning" \
    MEETING_URL="https://meet.google.com/xyz-abc-def" \
    NOTES_DIR="$HOME/Documents/meetings/2025-10"
```

## Integration Examples

### Shell Alias

Add to `~/.bashrc`:

```bash
# Workspace management
alias ws-new='workspace-interactive.sh'
alias ws-dev='workspace-parameterized.sh /etc/nixos/templates/dev-project.json'

# Project-specific
ws-nixos() {
    workspace-parameterized.sh /etc/nixos/templates/dev-project.json \
        PROJECT_NAME=nixos-config \
        PROJECT_DIR=/etc/nixos \
        PROJECT_URL=https://nixos.org/manual
}
```

### FZF Integration

Quick launcher for common projects:

```bash
#!/usr/bin/env bash
# ~/bin/ws-quick

PROJECT=$(cat <<EOF | fzf --prompt="Select project> "
nixos-config|/etc/nixos|https://nixos.org
dotfiles|$HOME/.config|
myapp|$HOME/projects/myapp|http://localhost:3000
EOF
)

[[ -z "$PROJECT" ]] && exit 0

IFS='|' read -r name dir url <<< "$PROJECT"

workspace-parameterized.sh /etc/nixos/templates/dev-project.json \
    PROJECT_NAME="$name" \
    PROJECT_DIR="$dir" \
    PROJECT_URL="${url:-about:blank}"
```

### i3 Keybinding

Add to i3 config:

```nix
# Interactive workspace launcher
bindsym $mod+Shift+p exec /etc/nixos/scripts/workspace-interactive.sh

# Quick dev workspace for current directory
bindsym $mod+Ctrl+p exec /etc/nixos/scripts/workspace-parameterized.sh /etc/nixos/templates/dev-project.json PROJECT_DIR=$(pwd)
```

## Comparison with Similar Projects

### i3-resurrect

**i3-resurrect:**
- Saves current workspace state to JSON
- Restores windows with layout positioning
- Uses xdotool to remap existing windows
- Best for: Preserving existing sessions

**Our approach:**
- Creates new workspaces from templates
- Parameterized variable substitution
- Launches fresh applications
- Best for: Starting new project sessions

### tmuxp / tmuxinator

**tmuxp/tmuxinator:**
- Session managers for tmux
- YAML-based configuration
- Manages panes within terminal
- Works inside terminal multiplexer

**Our approach:**
- Workspace manager for i3wm
- JSON/YAML templates with parameters
- Manages windows across workspaces
- Works at window manager level

**Integration:** Use both together!

```json
{
  "name": "tmux-project",
  "workspaces": [
    {
      "number": 2,
      "apps": [
        {
          "command": "ghostty",
          "args": ["-e", "tmuxp", "load", "${TMUX_SESSION}"],
          "delay": 0
        }
      ]
    }
  ]
}
```

### i3-workspace-groups

**i3-workspace-groups:**
- Groups workspaces by project
- Namespace-based workspace management
- Python-based CLI
- Persistent groups across sessions

**Our approach:**
- Template-based workspace creation
- On-demand instantiation
- Bash-based scripts
- Ephemeral by default (recreate as needed)

**Complementary:** Use workspace-groups for persistence, our templates for creation

## Advanced Techniques

### Conditional Templates

Use default values to make templates work in multiple contexts:

```json
{
  "name": "${PROJECT_NAME}",
  "workspaces": [
    {
      "number": 2,
      "apps": [
        {
          "command": "${TERMINAL:-ghostty}",
          "args": [],
          "delay": 0
        }
      ]
    },
    {
      "number": 4,
      "apps": [
        {
          "command": "${EDITOR:-code}",
          "args": ["${PROJECT_DIR:-.}"],
          "delay": 500
        }
      ]
    }
  ]
}
```

### Environment Variable Integration

Templates can reference environment variables:

```bash
workspace-parameterized.sh template.json \
    PROJECT_DIR="$PWD" \
    USER_HOME="$HOME" \
    DISPLAY="$DISPLAY"
```

Or use defaults that reference environment:

```json
{
  "command": "ghostty",
  "args": ["--working-directory=${PROJECT_DIR:-$PWD}"]
}
```

### Workspace Number Calculation

Generate workspace numbers dynamically:

```bash
#!/usr/bin/env bash
# Find first empty workspace
EMPTY_WS=$(i3-msg -t get_workspaces | jq -r '
  [range(1;10)] - [.[] | .num] | .[0]
')

workspace-parameterized.sh template.json WORKSPACE_NUM="$EMPTY_WS"
```

### Template Composition

Combine multiple templates:

```bash
#!/usr/bin/env bash
# Launch base workspace
workspace-project.sh base-workspace.json

# Wait for windows to appear
sleep 2

# Add additional workspace
workspace-project.sh extra-workspace.json
```

## Troubleshooting

### Variables Not Substituted

Check variable name format:
- Must be uppercase: `${PROJECT_DIR}` not `${project_dir}`
- Must start with letter or underscore
- Can contain letters, numbers, underscores

### Invalid JSON After Substitution

Test substitution manually:

```bash
# Show what will be generated
TEMPLATE="template.json"
PROJECT_NAME="test"

# Substitute and validate
cat "$TEMPLATE" | \
  sed "s/\${PROJECT_NAME}/$PROJECT_NAME/g" | \
  jq '.'
```

### Template Not Found

Check paths:

```bash
# List available templates
find /etc/nixos/templates -name "*.json" -o -name "*.yaml"

# Use absolute path
workspace-parameterized.sh "$(realpath templates/dev-project.json)" ...
```

## Files Reference

| File | Purpose |
|------|---------|
| `scripts/workspace-parameterized.sh` | Variable substitution engine |
| `scripts/workspace-interactive.sh` | FZF-based interactive launcher |
| `templates/dev-project.json` | Full dev environment template |
| `templates/simple-workspace.json` | Single workspace template |
| `templates/multi-terminal.json` | Multi-terminal template |
| `~/.cache/workspace-interactive-recent.txt` | Remembered parameter values |

## Next Steps

1. **Try interactive launcher:** `workspace-interactive.sh`
2. **Create custom template:** Copy and modify existing template
3. **Add shell aliases:** Make frequent setups one command
4. **Integrate with i3:** Add keybindings for quick access

---

_Last updated: 2025-10-18_
