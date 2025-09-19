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
  # This now works with any UUID by looking up the activity name first
  getActivityDirectory = ''
    get_activity_directory() {
      local MAPPING_FILE="${config.home.homeDirectory}/.config/plasma-activities/mappings.json"
      local ACTIVITY_ID=$(qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)

      if [ -z "$ACTIVITY_ID" ]; then
        echo "$HOME"
        return
      fi

      # Get activity name from kactivitymanagerdrc (works with any UUID)
      local ACTIVITY_NAME=$(grep "^$ACTIVITY_ID=" ~/.config/kactivitymanagerdrc 2>/dev/null | cut -d= -f2 | head -1)

      if [ -z "$ACTIVITY_NAME" ] || [ ! -f "$MAPPING_FILE" ]; then
        echo "$HOME"
        return
      fi

      # Look up directory by activity name instead of UUID
      local DIRECTORY=$(${pkgs.jq}/bin/jq -r ".[] | select(.name==\"$ACTIVITY_NAME\") | .directory // \"$HOME\"" "$MAPPING_FILE" 2>/dev/null)

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

  # Script to sync Yakuake sessions with activities
  yakuakeActivitySync = pkgs.writeScriptBin "yakuake-activity-sync" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    # Only proceed if Yakuake is running
    if pgrep -f "yakuake" >/dev/null 2>&1; then
      WORK_DIR=$(get_activity_directory)
      ACTIVITY_ID=$(qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)
      ACTIVITY_NAME=$(grep "^$ACTIVITY_ID=" ~/.config/kactivitymanagerdrc 2>/dev/null | cut -d= -f2 | head -1)

      # Use activity name as session title for better readability
      SESSION_TITLE="$ACTIVITY_NAME"

      # Check if a session for this activity already exists
      EXISTING_SESSION=""
      for session_id in $(qdbus org.kde.yakuake /yakuake/sessions sessionIdList 2>/dev/null | tr ',' ' '); do
        # Get session title
        title=$(qdbus org.kde.yakuake /yakuake/tabs tabTitle "$session_id" 2>/dev/null || echo "")
        if [[ "$title" == "$SESSION_TITLE" ]]; then
          EXISTING_SESSION="$session_id"
          break
        fi
      done

      if [ -n "$EXISTING_SESSION" ]; then
        # Switch to existing session for this activity
        qdbus org.kde.yakuake /yakuake/sessions raiseSession "$EXISTING_SESSION" 2>/dev/null || true
      else
        # Create new session for this activity
        NEW_SESSION=$(qdbus org.kde.yakuake /yakuake/sessions addSession 2>/dev/null)
        if [ -n "$NEW_SESSION" ]; then
          # Set the session title
          qdbus org.kde.yakuake /yakuake/tabs setTabTitle "$NEW_SESSION" "$SESSION_TITLE" 2>/dev/null || true
          # Change to activity directory
          qdbus org.kde.yakuake /yakuake/sessions runCommandInTerminal "$NEW_SESSION" "cd '$WORK_DIR'" 2>/dev/null || true
          # Switch to the new session
          qdbus org.kde.yakuake /yakuake/sessions raiseSession "$NEW_SESSION" 2>/dev/null || true
        fi
      fi
    fi
  '';

  # Wrapper for Yakuake that ensures it starts in activity directory
  yakuakeActivityScript = pkgs.writeScriptBin "yakuake-activity" ''
    #!/usr/bin/env bash

    ${getActivityDirectory}

    WORK_DIR=$(get_activity_directory)

    # Check if Yakuake is already running
    if pgrep -f "${pkgs.kdePackages.yakuake}/bin/yakuake" >/dev/null 2>&1; then
      # Yakuake is running, toggle it and sync directory
      qdbus org.kde.yakuake /yakuake/window toggleWindowState 2>/dev/null || true

      # Wait for window to be visible
      sleep 0.2

      # Sync the directory for current session
      yakuake-activity-sync
    else
      # Start Yakuake in the activity directory
      cd "$WORK_DIR"
      ${pkgs.kdePackages.yakuake}/bin/yakuake &

      # Wait for Yakuake to start
      sleep 1

      # Sync directory after startup
      yakuake-activity-sync
    fi
  '';

  # Yakuake wrapper that replaces the default yakuake command
  yakuakeWrapper = pkgs.symlinkJoin {
    name = "yakuake";
    paths = [ pkgs.kdePackages.yakuake ];
    postBuild = ''
      # Remove the original yakuake binary
      rm $out/bin/yakuake

      # Create our wrapper script that includes activity awareness
      cat > $out/bin/yakuake << 'EOF'
      #!/usr/bin/env bash

      ${getActivityDirectory}

      # If this is the first start, set the initial directory
      if ! pgrep -f "${pkgs.kdePackages.yakuake}/bin/yakuake" >/dev/null 2>&1; then
        WORK_DIR=$(get_activity_directory)
        cd "$WORK_DIR"
        exec ${pkgs.kdePackages.yakuake}/bin/yakuake "$@"
      else
        # Yakuake is already running, just forward the command
        exec ${pkgs.kdePackages.yakuake}/bin/yakuake "$@"
      fi
      EOF

      chmod +x $out/bin/yakuake
    '';
  };
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

  # Rebuild KDE application cache when desktop files change
  home.activation.rebuildKdeCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Rebuild KDE's application cache to register new desktop entries
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
      $DRY_RUN_CMD kbuildsycoca6 --noincremental 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
      $DRY_RUN_CMD kbuildsycoca5 --noincremental 2>/dev/null || true
    fi
  '';

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
      # Make visible in KRunner and application menu
      settings = {
        Keywords = "konsole;terminal;activity;shell;bash;";
      };
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
      # Make visible in KRunner and application menu
      settings = {
        Keywords = "vscode;code;editor;activity;development;ide;";
      };
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
      # Make visible in KRunner and application menu
      settings = {
        Keywords = "dolphin;files;file manager;activity;explorer;";
      };
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
      # Make visible in KRunner and application menu
      settings = {
        Keywords = "yakuake;terminal;dropdown;activity;quake;";
      };
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