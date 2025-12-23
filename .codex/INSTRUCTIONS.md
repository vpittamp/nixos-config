# Codex Custom Instructions

You are operating in a NixOS environment where configuration is managed declaratively via Nix flakes and home-manager.

## Environment Details

- **OS**: NixOS (Linux)
- **Shell**: Bash (managed by home-manager)
- **Configuration**: Declarative via `/etc/nixos/` flake
- **User**: vpittamp
- **Home Directory**: /home/vpittamp

## Key Patterns

### Bash Aliases
When running user-defined aliases (like `nh-hetzner-fresh`), use interactive bash:
```bash
bash -i -c "alias-name"
```

### NixOS Rebuild
Use the `nh` (nix-helper) aliases for rebuilding:
- `nh-hetzner` / `nh-hetzner-fresh` - Hetzner server
- `nh-m1` / `nh-m1-fresh` - Apple Silicon Mac
- `nh-wsl` / `nh-wsl-fresh` - Windows Subsystem for Linux

### Project Management
This system uses i3pm (i3 project manager) for project context:
- `i3pm project switch <name>` - Switch to a project
- `i3pm project current` - Show current project
- Windows are scoped to projects for workspace isolation

### AI CLI Telemetry
All AI CLIs (Claude Code, Codex, Gemini) emit OpenTelemetry traces to Grafana Alloy.
