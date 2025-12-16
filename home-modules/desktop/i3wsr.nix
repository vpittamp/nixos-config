# i3wsr - Dynamic Workspace Renaming for i3wm
# Automatically renames i3 workspaces to reflect running applications
{ config, lib, pkgs, ... }:

with lib;

let
  # Import PWA site definitions from shared location
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
  pwaSites = pwaSitesConfig.pwaSites;

  # Define emoji/icon mappings for PWAs (fallback if no custom icon)
  pwaEmojiMap = {
    # Core PWAs from shared/pwa-sites.nix
    "YouTube" = "";
    "Google AI" = "🔍";
    "Claude" = "";
    "GitHub" = "";
    "Gmail" = "📧";
    "Google Calendar" = "📅";
    "Notion" = "";
    "Figma" = "🎨";
    "Linear" = "";
    "Slack" = "";
    "WhatsApp" = "";
    "Spotify" = "";
    "Netflix" = "";
    "Discord" = "";
    "Excalidraw" = "✏";
  };

  # Script to generate i3wsr config with current PWA IDs
  generateI3wsrConfig = pkgs.writeShellScript "generate-i3wsr-config" ''
    CONFIG_FILE="$HOME/.config/i3wsr/config.toml"
    MAPPING_FILE="$HOME/.config/i3wsr/pwa-mappings.json"

    mkdir -p "$(dirname "$CONFIG_FILE")"
    mkdir -p "$(dirname "$MAPPING_FILE")"

    # Generate base config
    cat > "$CONFIG_FILE" <<'EOF'
    [general]
    separator = "  "
    default_icon = ""

    [options]
    remove_duplicates = true
    no_names = true  # Show icons only

    [icons]
    # Standard applications
    firefox = ""
    code = ""
    "Code" = ""
    alacritty = ""
    "Alacritty" = ""
    EOF

    # Generate PWA ID mapping from currently installed PWAs
    echo "{}" > "$MAPPING_FILE"
    ${pkgs.firefoxpwa}/bin/firefoxpwa profile list 2>/dev/null | grep "^- " | while IFS=: read -r name_part rest; do
      NAME=$(echo "$name_part" | sed 's/^- //' | xargs)
      ID=$(echo "$rest" | awk -F'[()]' '{print $2}' | xargs)
      if [ ! -z "$ID" ] && [ ! -z "$NAME" ]; then
        ${pkgs.jq}/bin/jq --arg name "$NAME" --arg id "$ID" \
          '.[$name] = $id' "$MAPPING_FILE" > "$MAPPING_FILE.tmp" && \
          mv "$MAPPING_FILE.tmp" "$MAPPING_FILE"
      fi
    done

    # Add PWA-specific icons based on IDs from mapping
    echo "" >> "$CONFIG_FILE"
    ${pkgs.jq}/bin/jq -r 'to_entries[] | "\(.key)=\(.value)"' "$MAPPING_FILE" | while IFS== read -r name id; do
      # Map names to emojis (from shared/pwa-sites.nix)
      case "$name" in
        "YouTube") ICON="" ;;
        "Google AI") ICON="🔍" ;;
        "Claude") ICON="" ;;
        "GitHub") ICON="" ;;
        "Gmail") ICON="📧" ;;
        "Google Calendar") ICON="📅" ;;
        "Notion") ICON="" ;;
        "Figma") ICON="🎨" ;;
        "Linear") ICON="" ;;
        "Slack") ICON="" ;;
        "WhatsApp") ICON="" ;;
        "Spotify") ICON="" ;;
        "Netflix") ICON="" ;;
        "Discord") ICON="" ;;
        "Excalidraw") ICON="✏" ;;
        *) ICON="🌐" ;;  # Default for any other PWA
      esac

      if [ ! -z "$ICON" ]; then
        echo "\"FFPWA-$id\" = \"$ICON\"" >> "$CONFIG_FILE"
      fi
    done

    # Add aliases section (optional, for fallback names)
    echo "" >> "$CONFIG_FILE"
    echo "[aliases.class]" >> "$CONFIG_FILE"
    echo "\"^Code$\" = \"VSCode\"" >> "$CONFIG_FILE"
  '';

in
{
  # Install i3wsr package
  home.packages = [
    pkgs.i3wsr
    (pkgs.writeShellScriptBin "i3wsr-update-config" ''
      ${generateI3wsrConfig}
      echo "i3wsr config updated with current PWA IDs"
      # Restart i3wsr if running
      pkill -USR1 i3wsr 2>/dev/null || echo "i3wsr not running (will use new config on next start)"
    '')
  ];

  # Generate initial config (will be updated by PWA management)
  xdg.configFile."i3wsr/config.toml".text = ''
    [general]
    separator = "  "
    default_icon = ""

    [options]
    remove_duplicates = true
    no_names = true  # Show icons only

    [icons]
    # Standard applications
    firefox = ""
    code = ""
    "Code" = ""
    alacritty = ""
    "Alacritty" = ""

    # Generic Firefox PWA fallback
    "FFPWA-.*" = "🌐"

    [aliases.class]
    "^Code$" = "VSCode"
  '';

  # Start i3wsr automatically with i3
  # Note: This adds to the manual i3 config at ~/.config/i3/config
  # We use a separate autostart script to avoid modifying the manual config
  home.file.".config/i3/scripts/i3wsr-start.sh" = {
    text = ''
      #!/usr/bin/env bash
      # Start i3wsr daemon
      ${pkgs.i3wsr}/bin/i3wsr
    '';
    executable = true;
  };

  # Create systemd user service for i3wsr
  systemd.user.services.i3wsr = {
    Unit = {
      Description = "i3 workspace renamer";
      # Feature 121: Use sway-session.target for proper Sway lifecycle binding
      After = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.i3wsr}/bin/i3wsr";
      Restart = "on-failure";
      RestartSec = 3;
      # Import i3 socket path from environment
      Environment = "PATH=/run/wrappers/bin:${pkgs.coreutils}/bin";
    };
    Install = {
      # Feature 121: Auto-start with Sway session (Sway workspace renamer)
      WantedBy = [ "sway-session.target" ];
    };
  };
}
