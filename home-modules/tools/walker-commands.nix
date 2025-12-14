{ config, pkgs, lib, ... }:

let
  # Walker command manager - add/remove custom commands without rebuild
  walkerCommandManager = pkgs.writeShellScriptBin "walker-cmd" ''
    #!/usr/bin/env bash
    set -euo pipefail

    SNIPPETS_FILE="$HOME/.config/elephant/snippets.toml"

    usage() {
      cat <<EOF
    Usage: walker-cmd <command> [options]

    Commands:
      add <name> <command> [description]    Add or update a command snippet
      save <command>                        Save command with interactive name prompt
      remove <name>                         Remove a command snippet
      list                                  List all command snippets
      edit                                  Edit snippets file directly
      reload                                Reload Elephant service

    Examples:
      walker-cmd add "backup nixos" "sudo rsync -av /etc/nixos /backup/" "Backup NixOS config"
      walker-cmd save "git status"  # Prompts for name interactively
      walker-cmd remove "backup nixos"
      walker-cmd list
      walker-cmd edit
      walker-cmd reload

    Usage in Walker:
      Meta+D → type "$" → type command name → Return

    Note: Commands are stored in $SNIPPETS_FILE as snippets ($ prefix in Walker)
    EOF
    }

    ensure_file() {
      if [ ! -f "$SNIPPETS_FILE" ]; then
        mkdir -p "$(dirname "$SNIPPETS_FILE")"
        {
          echo "# Elephant Snippets Configuration"
          echo "# Managed by walker-cmd CLI tool"
          echo "# Usage: walker-cmd add \"name\" \"command\" \"description\""
          echo "# Access in Walker: Meta+D → type '\$' → type command name"
          echo ""
          echo "[[snippets]]"
          echo "name = \"reload sway\""
          echo "snippet = \"swaymsg reload\""
          echo "description = \"Reload Sway configuration\""
          echo ""
          echo "[[snippets]]"
          echo "name = \"lock screen\""
          echo "snippet = \"swaylock -f\""
          echo "description = \"Lock the screen\""
          echo ""
          echo "[[snippets]]"
          echo "name = \"rebuild nixos\""
          echo "snippet = \"cd /etc/nixos && sudo nixos-rebuild switch --flake .#hetzner\""
          echo "description = \"Rebuild NixOS configuration\""
        } > "$SNIPPETS_FILE"
        echo "✓ Created snippets file with examples: $SNIPPETS_FILE"
        echo "  Run 'walker-cmd list' to see all snippets"
        echo "  Use Meta+D then '#' prefix to access snippets in Walker"
      fi
    }

    add_command() {
      local name="$1"
      local cmd="$2"
      local desc="''${3:-Execute $name}"

      ensure_file

      # Remove existing snippet with same name (if exists)
      # This removes the entire [[snippets]] block
      ${pkgs.gawk}/bin/awk -v name="$name" '
        /^\[\[snippets\]\]/ { in_block=1; block="" }
        in_block {
          block = block $0 "\n"
          if (/^name = ".*"$/) {
            if ($0 ~ "name = \"" name "\"") {
              skip_block=1
            }
          }
          if (/^$/ || /^\[\[snippets\]\]/) {
            if (!skip_block && block != "") print block
            in_block=0
            skip_block=0
            block=""
          }
          next
        }
        !in_block { print }
      ' "$SNIPPETS_FILE" > "$SNIPPETS_FILE.tmp"
      mv "$SNIPPETS_FILE.tmp" "$SNIPPETS_FILE"

      # Add new snippet
      {
        echo ""
        echo "[[snippets]]"
        echo "name = \"$name\""
        echo "snippet = \"$cmd\""
        echo "description = \"$desc\""
      } >> "$SNIPPETS_FILE"

      echo "✓ Added snippet: $name"
      echo "  Command: $cmd"
      echo "  Description: $desc"
      echo "  Access: Meta+D → type '\$$name'"

      # Reload Elephant
      systemctl --user restart elephant 2>/dev/null && echo "✓ Elephant reloaded" || echo "⚠ Failed to reload Elephant"
    }

    save_command() {
      local cmd="$1"

      # Suggest a name based on the command (first word)
      local suggested_name=$(echo "$cmd" | ${pkgs.gawk}/bin/awk '{print $1}')

      # Prompt for name using rofi
      local name=$(echo "$suggested_name" | ${pkgs.rofi}/bin/rofi -dmenu -p "Save command as:" -theme-str 'window {width: 400px;}')

      # If user cancelled or provided empty name, exit
      if [ -z "$name" ]; then
        echo "Cancelled - no name provided"
        exit 0
      fi

      # Add the command using the existing function
      add_command "$name" "$cmd"
    }

    remove_command() {
      local name="$1"

      if [ ! -f "$SNIPPETS_FILE" ]; then
        echo "Error: Snippets file not found: $SNIPPETS_FILE"
        exit 1
      fi

      # Remove snippet block
      ${pkgs.gawk}/bin/awk -v name="$name" '
        /^\[\[snippets\]\]/ { in_block=1; block="" }
        in_block {
          block = block $0 "\n"
          if (/^name = ".*"$/) {
            if ($0 ~ "name = \"" name "\"") {
              skip_block=1
            }
          }
          if (/^$/ || /^\[\[snippets\]\]/) {
            if (!skip_block && block != "") print block
            in_block=0
            skip_block=0
            block=""
          }
          next
        }
        !in_block { print }
      ' "$SNIPPETS_FILE" > "$SNIPPETS_FILE.tmp"
      mv "$SNIPPETS_FILE.tmp" "$SNIPPETS_FILE"

      echo "✓ Removed snippet: $name"
      systemctl --user restart elephant 2>/dev/null && echo "✓ Elephant reloaded" || echo "⚠ Failed to reload Elephant"
    }

    list_commands() {
      if [ ! -f "$SNIPPETS_FILE" ]; then
        echo "No snippets file found. Use 'walker-cmd add' to create one."
        exit 0
      fi

      echo "Command Snippets in $SNIPPETS_FILE:"
      echo "(Use Meta+D → '#' prefix to access in Walker)"
      echo ""

      # Extract snippets from TOML
      ${pkgs.gawk}/bin/awk '
        /^\[\[snippets\]\]/ { if (name) printf "  %-25s %-40s %s\n", name, snippet, desc; name=""; snippet=""; desc="" }
        /^name = / { gsub(/^name = "|"$/, ""); name=$0 }
        /^snippet = / { gsub(/^snippet = "|"$/, ""); snippet=$0 }
        /^description = / { gsub(/^description = "|"$/, ""); desc=$0 }
        END { if (name) printf "  %-25s %-40s %s\n", name, snippet, desc }
      ' "$SNIPPETS_FILE" | ${pkgs.gnused}/bin/sed 's/^/  /'
    }

    edit_commands() {
      ensure_file
      ''${EDITOR:-nano} "$SNIPPETS_FILE"
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
      save)
        if [ $# -lt 2 ]; then
          echo "Error: 'save' requires command"
          echo "Usage: walker-cmd save <command>"
          exit 1
        fi
        shift
        cmd="$*"
        save_command "$cmd"
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
