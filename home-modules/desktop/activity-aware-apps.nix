{ config, pkgs, lib, ... }:

let
  # Import activity data from the central configuration
  activityData = import ./project-activities/data.nix { inherit lib config pkgs; };

  # Generate JSON mapping file from activity data
  # Maps UUID -> activity details for runtime lookup
  activityMappings = builtins.toJSON (
    lib.listToAttrs (
      lib.mapAttrsToList (name: activity:
        let
          # Handle directory expansion
          dir = if builtins.isString activity.directory then
                  activity.directory
                else
                  # If it's the result of expandPath, it's already expanded
                  activity.directory;
          expandedDir = if lib.hasPrefix "~/" dir
                        then "${config.home.homeDirectory}/${lib.removePrefix "~/" dir}"
                        else dir;
        in
        lib.nameValuePair activity.uuid {
          inherit (activity) name description icon;
          directory = expandedDir;
        }
      ) activityData.rawActivities
    )
  );

  # Create the mapping file
  activityMappingFile = pkgs.writeText "activity-mappings.json" activityMappings;

  # Universal function to get activity directory
  getActivityDirectory = ''
    get_activity_directory() {
      local MAPPING_FILE="${config.home.homeDirectory}/.config/plasma-activities/mappings.json"
      local ACTIVITY_ID=$(qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)

      if [ -z "$ACTIVITY_ID" ] || [ ! -f "$MAPPING_FILE" ]; then
        echo "$HOME"
        return
      fi

      local DIRECTORY=$(${pkgs.jq}/bin/jq -r ".\"$ACTIVITY_ID\".directory // \"$HOME\"" "$MAPPING_FILE" 2>/dev/null)

      # Verify directory exists
      if [ -d "$DIRECTORY" ]; then
        echo "$DIRECTORY"
      else
        echo "$HOME"
      fi
    }
  '';

  # Create the activity-aware launcher script
  activityLauncher = pkgs.writeScriptBin "activity-launcher" ''
    #!/usr/bin/env bash
    # Activity-aware application launcher

    ${getActivityDirectory}

    APP="$1"
    shift

    WORK_DIR=$(get_activity_directory)

    # Launch the application with the appropriate working directory
    case "$APP" in
      konsole)
        konsole --workdir "$WORK_DIR" "$@"
        ;;
      code|vscode)
        code "$WORK_DIR" "$@"
        ;;
      dolphin)
        dolphin "$WORK_DIR" "$@"
        ;;
      *)
        cd "$WORK_DIR" && "$APP" "$@"
        ;;
    esac
  '';

  konsoleActivityScript = pkgs.writeScriptBin "konsole-activity" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    WORK_DIR=$(get_activity_directory)
    # Derive session name from directory basename
    SESSION_NAME=$(basename "$WORK_DIR" | tr '[:upper:]' '[:lower:]')

    # Try to connect to sesh session, fall back to regular konsole if it fails
    if command -v sesh >/dev/null 2>&1; then
      # Launch Konsole with sesh connect command
      konsole --workdir "$WORK_DIR" --profile "Improved Selection" -e bash -lc "sesh connect $SESSION_NAME || exec bash -l"
    else
      # Fall back to regular Konsole without sesh
      konsole --workdir "$WORK_DIR" --profile "Improved Selection"
    fi
  '';

  codeActivityScript = pkgs.writeScriptBin "code-activity" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    WORK_DIR=$(get_activity_directory)
    # Derive session name from directory basename (same as konsole-activity)
    SESSION_NAME=$(basename "$WORK_DIR" | tr '[:upper:]' '[:lower:]')

    # Check if VS Code is already running with this specific workspace
    # Look for a VS Code process with this directory in its arguments
    if pgrep -f "code.*$WORK_DIR" >/dev/null 2>&1; then
      # VS Code is already open with this workspace, just focus it
      # Try to focus VS Code window using wmctrl if available
      if command -v wmctrl >/dev/null 2>&1; then
        wmctrl -a "Visual Studio Code" 2>/dev/null || true
      fi
      # Exit early to prevent opening new windows
      exit 0
    fi

    # Prepare VS Code settings for integrated terminal with sesh
    if command -v sesh >/dev/null 2>&1; then
      # Create a workspace-specific settings file if it doesn't exist
      VSCODE_DIR="$WORK_DIR/.vscode"
      mkdir -p "$VSCODE_DIR"
      SETTINGS_FILE="$VSCODE_DIR/settings.json"

      # Create settings to auto-run sesh in terminal if not exists
      if [ ! -f "$SETTINGS_FILE" ]; then
        cat > "$SETTINGS_FILE" << EOF
{
  "terminal.integrated.defaultProfile.linux": "bash-sesh",
  "terminal.integrated.profiles.linux": {
    "bash-sesh": {
      "path": "bash",
      "args": ["-l", "-c", "sesh connect $SESSION_NAME || exec bash -l"]
    },
    "bash": {
      "path": "bash",
      "args": ["-l"]
    }
  }
}
EOF
      fi
    fi

    # Check if any VS Code instance is running at all
    if pgrep -f "/.vscode-server/|/.vscode/|/code " >/dev/null 2>&1; then
      # VS Code is running but with different workspace, open in existing window
      code -r "$WORK_DIR"
    else
      # No VS Code running at all, start fresh
      code "$WORK_DIR"
    fi
  '';

  dolphinActivityScript = pkgs.writeScriptBin "dolphin-activity" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    WORK_DIR=$(get_activity_directory)
    dolphin "$WORK_DIR"
  '';

  # Simple script to update Yakuake's directory when activity changes
  yakuakeActivitySync = pkgs.writeScriptBin "yakuake-activity-sync" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    # Only proceed if Yakuake is running
    if pgrep -x "yakuake" >/dev/null 2>&1; then
      WORK_DIR=$(get_activity_directory)

      # Get the active session ID and send cd command
      SESSION_ID=$(qdbus org.kde.yakuake /yakuake/sessions org.kde.yakuake.activeSessionId 2>/dev/null || echo "1")
      qdbus org.kde.yakuake /yakuake/sessions org.kde.yakuake.runCommandInTerminal "$${SESSION_ID:-1}" "cd '$WORK_DIR' && clear" 2>/dev/null || true
    fi
  '';

  # Wrapper for Yakuake that sets initial directory based on activity
  yakuakeActivityScript = pkgs.writeScriptBin "yakuake-activity" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    WORK_DIR=$(get_activity_directory)

    # Check if Yakuake is running
    if ! pgrep -x "yakuake" >/dev/null 2>&1; then
      # Start Yakuake
      ${pkgs.kdePackages.yakuake}/bin/yakuake &

      # Wait for Yakuake to start
      for i in {1..20}; do
        if qdbus org.kde.yakuake >/dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      # Get session ID and send cd command to set directory
      sleep 0.5
      SESSION_ID=$(qdbus org.kde.yakuake /yakuake/sessions org.kde.yakuake.activeSessionId 2>/dev/null || echo "1")
      qdbus org.kde.yakuake /yakuake/sessions org.kde.yakuake.runCommandInTerminal "$SESSION_ID" "cd '$WORK_DIR' && clear" 2>/dev/null || true
    else
      # Yakuake is running, toggle it and update directory
      qdbus org.kde.yakuake /yakuake/window org.kde.yakuake.toggleWindowState
      SESSION_ID=$(qdbus org.kde.yakuake /yakuake/sessions org.kde.yakuake.activeSessionId 2>/dev/null || echo "1")
      qdbus org.kde.yakuake /yakuake/sessions org.kde.yakuake.runCommandInTerminal "$SESSION_ID" "cd '$WORK_DIR' && clear" 2>/dev/null || true
    fi
  '';
in
{
  # Install the scripts
  home.packages = [
    activityLauncher
    konsoleActivityScript
    codeActivityScript
    dolphinActivityScript
    yakuakeActivityScript
    yakuakeActivitySync
  ];

  # Install the activity mappings file
  home.file.".config/plasma-activities/mappings.json".source = activityMappingFile;

  # Autostart Yakuake with activity awareness
  home.file.".config/autostart/yakuake.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Exec=yakuake-activity
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    Name=Yakuake
    Comment=Drop-down terminal with activity awareness
  '';

  # Create desktop entries for activity-aware applications
  xdg.desktopEntries = {
    # Single activity-aware Konsole that detects current activity
    konsole-activity = {
      name = "Konsole (Activity)";
      genericName = "Terminal";
      comment = "Opens in current activity's directory";
      icon = "utilities-terminal";
      terminal = false;
      type = "Application";
      categories = [ "System" "TerminalEmulator" ];
      exec = "${konsoleActivityScript}/bin/konsole-activity";
    };

    # Activity-aware VS Code
    code-activity = {
      name = "VS Code (Activity)";
      genericName = "Code Editor";
      comment = "Opens in current activity's directory";
      icon = "code";
      terminal = false;
      type = "Application";
      categories = [ "Development" "IDE" ];
      exec = "${codeActivityScript}/bin/code-activity";
    };

    # Activity-aware Dolphin
    dolphin-activity = {
      name = "Dolphin (Activity)";
      genericName = "File Manager";
      comment = "Opens in current activity's directory";
      icon = "system-file-manager";
      terminal = false;
      type = "Application";
      categories = [ "System" "FileManager" ];
      exec = "${dolphinActivityScript}/bin/dolphin-activity";
    };

    # Activity-aware Yakuake
    yakuake-activity = {
      name = "Yakuake (Activity)";
      genericName = "Drop-down Terminal";
      comment = "Opens Yakuake with sesh session for current activity";
      icon = "yakuake";
      terminal = false;
      type = "Application";
      categories = [ "System" "TerminalEmulator" ];
      exec = "${yakuakeActivityScript}/bin/yakuake-activity";
    };

    # General activity launcher entry (hidden from menu)
    activity-launcher = {
      name = "Activity Launcher";
      genericName = "Application Launcher";
      comment = "Launch applications in activity context";
      icon = "applications-other";
      terminal = false;
      type = "Application";
      categories = [ "System" ];
      exec = "${activityLauncher}/bin/activity-launcher %U";
      noDisplay = true; # Hide from menu, use for MIME associations
    };
  };
}