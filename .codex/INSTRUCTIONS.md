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
Primary targets: `thinkpad`, `ryzen`. Use `sudo nixos-rebuild switch --flake .#<target>`.

Legacy `nh` (nix-helper) aliases also exist:
- `nh-hetzner` / `nh-hetzner-fresh` - Hetzner server (legacy)
- `nh-wsl` / `nh-wsl-fresh` - Windows Subsystem for Linux

### Project Management
This system uses i3pm (i3 project manager) for project context:
- `i3pm project switch <name>` - Switch to a project
- `i3pm project current` - Show current project
- Windows are scoped to projects for workspace isolation

### AI CLI Telemetry
All AI CLIs (Claude Code, Codex, Gemini) emit OpenTelemetry traces to Grafana Alloy.
