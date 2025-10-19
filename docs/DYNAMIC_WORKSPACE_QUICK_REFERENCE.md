# Dynamic Workspace Creation - Quick Reference

## One-Line Commands

```bash
# Launch VSCode on workspace 4, Ghostty on workspace 2
/etc/nixos/scripts/demo-workspace-setup.sh

# Launch single app on workspace
/etc/nixos/scripts/workspace-launcher.sh <app> <workspace>

# Launch project from JSON
/etc/nixos/scripts/workspace-project.sh /path/to/project.json

# Example project
/etc/nixos/scripts/workspace-project.sh /etc/nixos/examples/example-project.json
```

## Raw i3-msg Commands

```bash
# Switch to workspace
i3-msg "workspace number 4"

# Launch app
i3-msg "exec --no-startup-id code"

# Combined (switch + launch)
i3-msg "workspace number 4; exec --no-startup-id code"

# Move window to workspace
i3-msg "move container to workspace number 5"

# Focus window by class
i3-msg '[class="Code"] focus'
```

## Query Commands

```bash
# List workspaces
i3-msg -t get_workspaces | jq -r '.[] | "\(.num): \(.name)"'

# Count windows on workspace 4
i3-msg -t get_tree | jq '.. | select(.type? == "workspace" and .num? == 4) | .nodes[] | select(.window_properties?)' | jq -s 'length'

# List windows by class
wmctrl -lx | awk '{print $3}' | sort | uniq
```

## Minimal Project JSON

```json
{
  "name": "my-project",
  "workspaces": [
    {
      "number": 2,
      "apps": [
        {"command": "ghostty", "args": [], "delay": 0}
      ]
    },
    {
      "number": 4,
      "apps": [
        {"command": "code", "args": [], "delay": 500}
      ]
    }
  ]
}
```

## Testing

```bash
# Dry run (see what would happen)
DRY_RUN=true /etc/nixos/scripts/workspace-project.sh project.json

# Validate JSON
jq '.' project.json

# Check i3 connection
i3-msg -t get_version
```

## Common Patterns

### Two Terminal Workspace
```bash
i3-msg "workspace number 2"
i3-msg "exec --no-startup-id ghostty"
sleep 0.5
i3-msg "exec --no-startup-id ghostty"
```

### IDE + Browser
```bash
i3-msg "workspace number 4; exec --no-startup-id code /path/to/project"
i3-msg "workspace number 3; exec --no-startup-id firefox --new-window http://localhost:3000"
```

### Monitor + Terminal
```bash
i3-msg "workspace number 8"
i3-msg "exec --no-startup-id ghostty -e btop"
sleep 0.5
i3-msg "exec --no-startup-id ghostty -e journalctl -f"
```

---

**Full Documentation:** `/etc/nixos/docs/DYNAMIC_WORKSPACE_CREATION.md`
