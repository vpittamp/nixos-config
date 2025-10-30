{ config, pkgs, lib, ... }:

let
  # Walker command manager - add/remove custom commands without rebuild
  walkerCommandManager = pkgs.writeShellScriptBin "walker-cmd" ''
    #!/usr/bin/env bash
    set -euo pipefail

    COMMANDS_FILE="$HOME/.config/elephant/commands.toml"

    usage() {
      cat <<EOF
    Usage: walker-cmd <command> [options]

    Commands:
      add <name> <command>    Add or update a custom command
      remove <name>           Remove a custom command
      list                    List all custom commands
      edit                    Edit commands file directly
      reload                  Reload Elephant service

    Examples:
      walker-cmd add "backup nixos" "sudo rsync -av /etc/nixos /backup/"
      walker-cmd remove "backup nixos"
      walker-cmd list
      walker-cmd edit
      walker-cmd reload

    Note: Commands are stored in $COMMANDS_FILE
    EOF
    }

    ensure_file() {
      if [ ! -f "$COMMANDS_FILE" ]; then
        mkdir -p "$(dirname "$COMMANDS_FILE")"
        {
          echo "# Elephant Custom Commands Configuration"
          echo "# Managed by walker-cmd CLI tool (Feature 050)"
          echo "# Usage: walker-cmd add \"name\" \"command\""
          echo ""
          echo "[customcommands]"
          echo "# System Management Examples"
          echo "\"reload sway config\" = \"swaymsg reload\""
          echo "\"lock screen\" = \"swaylock -f\""
          echo "\"suspend system\" = \"systemctl suspend\""
          echo ""
          echo "# NixOS Examples"
          echo "\"rebuild nixos\" = \"cd /etc/nixos && sudo nixos-rebuild switch --flake .#hetzner-sway\""
          echo "\"update nixos\" = \"cd /etc/nixos && nix flake update && sudo nixos-rebuild switch --flake .#hetzner-sway\""
          echo ""
          echo "# Project Management Examples"
          echo "\"list projects\" = \"i3pm project list\""
          echo "\"show active project\" = \"i3pm project current\""
          echo ""
          echo "# Service Management Examples"
          echo "\"restart elephant\" = \"systemctl --user restart elephant\""
          echo "\"check elephant status\" = \"systemctl --user status elephant\""
        } > "$COMMANDS_FILE"
        echo "✓ Created commands file with examples: $COMMANDS_FILE"
        echo "  Run 'walker-cmd list' to see all commands"
        echo "  Run 'walker-cmd add \"name\" \"command\"' to add more"
      fi
    }

    add_command() {
      local name="$1"
      local cmd="$2"

      ensure_file

      # Check if [customcommands] section exists
      if ! grep -q '^\[customcommands\]' "$COMMANDS_FILE"; then
        echo "" >> "$COMMANDS_FILE"
        echo "[customcommands]" >> "$COMMANDS_FILE"
      fi

      # Remove existing command with same name (if exists)
      ${pkgs.gnused}/bin/sed -i "/^\"$name\" = /d" "$COMMANDS_FILE"

      # Add new command
      echo "\"$name\" = \"$cmd\"" >> "$COMMANDS_FILE"

      echo "✓ Added command: $name"
      echo "  Command: $cmd"

      # Reload Elephant
      systemctl --user restart elephant 2>/dev/null && echo "✓ Elephant reloaded" || echo "⚠ Failed to reload Elephant"
    }

    remove_command() {
      local name="$1"

      if [ ! -f "$COMMANDS_FILE" ]; then
        echo "Error: Commands file not found: $COMMANDS_FILE"
        exit 1
      fi

      # Remove command
      if ${pkgs.gnused}/bin/sed -i "/^\"$name\" = /d" "$COMMANDS_FILE"; then
        echo "✓ Removed command: $name"
        systemctl --user restart elephant 2>/dev/null && echo "✓ Elephant reloaded" || echo "⚠ Failed to reload Elephant"
      else
        echo "Error: Command not found: $name"
        exit 1
      fi
    }

    list_commands() {
      if [ ! -f "$COMMANDS_FILE" ]; then
        echo "No commands file found. Use 'walker-cmd add' to create one."
        exit 0
      fi

      echo "Custom Commands in $COMMANDS_FILE:"
      echo ""

      # Extract commands from TOML
      ${pkgs.gnugrep}/bin/grep -E '^"[^"]+" = ' "$COMMANDS_FILE" | while IFS= read -r line; do
        name=$(echo "$line" | ${pkgs.gnused}/bin/sed 's/^"\([^"]*\)" = .*/\1/')
        cmd=$(echo "$line" | ${pkgs.gnused}/bin/sed 's/^"[^"]*" = "\(.*\)"$/\1/')
        printf "  %-30s %s\n" "$name" "$cmd"
      done
    }

    edit_commands() {
      ensure_file
      ''${EDITOR:-nano} "$COMMANDS_FILE"
      echo "✓ Reloading Elephant..."
      systemctl --user restart elephant
    }

    reload_elephant() {
      systemctl --user restart elephant
      echo "✓ Elephant reloaded"
    }

    # Main command handler
    case "''${1:-}" in
      add)
        if [ $# -lt 3 ]; then
          echo "Error: 'add' requires name and command"
          echo "Usage: walker-cmd add <name> <command>"
          exit 1
        fi
        shift
        name="$1"
        shift
        cmd="$*"
        add_command "$name" "$cmd"
        ;;
      remove)
        if [ $# -lt 2 ]; then
          echo "Error: 'remove' requires command name"
          echo "Usage: walker-cmd remove <name>"
          exit 1
        fi
        remove_command "$2"
        ;;
      list)
        list_commands
        ;;
      edit)
        edit_commands
        ;;
      reload)
        reload_elephant
        ;;
      -h|--help|help|"")
        usage
        ;;
      *)
        echo "Error: Unknown command '$1'"
        echo ""
        usage
        exit 1
        ;;
    esac
  '';

in
{
  home.packages = [ walkerCommandManager ];
}
