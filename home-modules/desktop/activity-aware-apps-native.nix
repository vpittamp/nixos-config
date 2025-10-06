{ config, pkgs, lib, ... }:

let
  # Import activity data from the central configuration
  activityData = import ./project-activities/data.nix { inherit lib config pkgs; };

  # Generate JSON mapping file from activity data
  activityMappings = builtins.toJSON (
    lib.listToAttrs (
      lib.mapAttrsToList (name: activity:
        let
          dir = if builtins.isString activity.directory then
                  activity.directory
                else
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

  # Helper to get activity directory
  getActivityDirectory = ''
    get_activity_directory() {
      local MAPPING_FILE="${config.home.homeDirectory}/.config/plasma-activities/mappings.json"
      local QDBUS_BIN
      QDBUS_BIN=$(command -v qdbus6 || command -v qdbus || true)

      if [ -z "$QDBUS_BIN" ]; then
        echo "$HOME"
        return
      fi

      local ACTIVITY_ID=$("$QDBUS_BIN" org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)

      if [ -z "$ACTIVITY_ID" ]; then
        echo "$HOME"
        return
      fi

      # Get activity name from kactivitymanagerdrc
      local ACTIVITY_NAME=$(grep "^$ACTIVITY_ID=" ~/.config/kactivitymanagerdrc 2>/dev/null | cut -d= -f2 | head -1)

      if [ -z "$ACTIVITY_NAME" ] || [ ! -f "$MAPPING_FILE" ]; then
        echo "$HOME"
        return
      fi

      # Look up directory by activity name
      local DIRECTORY=$(${pkgs.jq}/bin/jq -r ".[] | select(.name==\"$ACTIVITY_NAME\") | .directory // \"$HOME\"" "$MAPPING_FILE" 2>/dev/null)

      # Verify directory exists
      if [ -d "$DIRECTORY" ]; then
        echo "$DIRECTORY"
      else
        echo "$HOME"
      fi
    }
  '';

  # All-activities launcher scripts (open in all activities, no specific directory)
  firefoxAllActivities = pkgs.writeScriptBin "firefox-all-activities" ''
    #!/usr/bin/env bash
    firefox "$@"
  '';

  gitkrakenAllActivities = pkgs.writeScriptBin "gitkraken-all-activities" ''
    #!/usr/bin/env bash
    gitkraken "$@"
  '';

  # Simplified launcher scripts that just set working directory
  # KWin rules will handle activity assignment
  konsoleActivityScript = pkgs.writeScriptBin "konsole-activity" ''
    #!/usr/bin/env bash
    ${getActivityDirectory}
    WORK_DIR=$(get_activity_directory)
    SESSION_NAME=$(basename "$WORK_DIR" | tr '[:upper:]' '[:lower:]')

    if command -v sesh >/dev/null 2>&1; then
      konsole --workdir "$WORK_DIR" --profile "Improved Selection" -e bash -lc "sesh connect $SESSION_NAME || exec bash -l"
    else
      konsole --workdir "$WORK_DIR" --profile "Improved Selection"
    fi
  '';

  codeActivityScript = pkgs.writeScriptBin "code-activity" ''
    #!/usr/bin/env bash
    ${getActivityDirectory}
    ${qdbusLocator}

    WORK_DIR=$(get_activity_directory)

    # Determine activity name from directory for profile matching
    MAPPING_FILE="${config.home.homeDirectory}/.config/plasma-activities/mappings.json"
    ACTIVITY_ID=""
    ACTIVITY_NAME=""

    if [ -n "$QDBUS_BIN" ]; then
      ACTIVITY_ID=$("$QDBUS_BIN" org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)
    fi

    if [ -n "$ACTIVITY_ID" ]; then
      # Get activity name from kactivitymanagerdrc
      ACTIVITY_NAME=$(grep "^$ACTIVITY_ID=" ~/.config/kactivitymanagerdrc 2>/dev/null | cut -d= -f2 | head -1)
    fi

    # Convert activity name to lowercase profile name (e.g., "NixOS" -> "nixos")
    PROFILE_NAME=$(echo "$ACTIVITY_NAME" | tr '[:upper:]' '[:lower:]')

    # Launch VSCode with activity-specific profile for reliable window rule matching
    # The --profile flag sets a unique WM_CLASS that KWin can match immediately
    if [ -n "$PROFILE_NAME" ]; then
      code --profile "$PROFILE_NAME" "$WORK_DIR"
    else
      # Fallback to regular launch if activity name not found
      code "$WORK_DIR"
    fi
  '';

  dolphinActivityScript = pkgs.writeScriptBin "dolphin-activity" ''
    #!/usr/bin/env bash
    ${getActivityDirectory}
    WORK_DIR=$(get_activity_directory)
    dolphin "$WORK_DIR"
  '';

  # Helper snippet reused by the Yakuake scripts to locate qdbus(6)
  qdbusLocator = ''
    QDBUS_BIN="$(command -v qdbus6 || command -v qdbus || true)"
  '';

  # Yakuake Activity Sync - keeps the drop-down session aligned with the active activity
  yakuakeActivitySync = pkgs.writeScriptBin "yakuake-activity-sync" ''
    #!/usr/bin/env bash
    set -euo pipefail

    ${getActivityDirectory}
    ${qdbusLocator}

    if [ -z "$QDBUS_BIN" ] || ! command -v yakuake >/dev/null 2>&1; then
      exit 0
    fi

    while true; do
      if pgrep -x yakuake >/dev/null 2>&1; then
        WORK_DIR="$(get_activity_directory)"
        if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
          "$QDBUS_BIN" org.kde.yakuake /yakuake/sessions runCommand "cd $WORK_DIR" >/dev/null 2>&1 || true
        fi
      fi
      sleep 2
    done
  '';

  # Yakuake Activity Script - launches or toggles Yakuake using the current activity directory
  yakuakeActivityScript = pkgs.writeScriptBin "yakuake-activity" ''
    #!/usr/bin/env bash
    set -euo pipefail

    ${getActivityDirectory}
    ${qdbusLocator}

    WORK_DIR="$(get_activity_directory)"

    if ! command -v yakuake >/dev/null 2>&1; then
      exec konsole --workdir "$WORK_DIR"
    fi

    if [ -z "$QDBUS_BIN" ]; then
      exec yakuake "$@"
    fi

    if ! pgrep -x yakuake >/dev/null 2>&1; then
      yakuake &
      for _ in $(seq 1 30); do
        sleep 0.2
        if "$QDBUS_BIN" org.kde.yakuake /yakuake/sessions sessionIdList >/dev/null 2>&1; then
          break
        fi
      done
    else
      "$QDBUS_BIN" org.kde.yakuake /yakuake/window toggleWindowState >/dev/null 2>&1 || true
    fi

    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
      "$QDBUS_BIN" org.kde.yakuake /yakuake/sessions runCommand "cd $WORK_DIR" >/dev/null 2>&1 || true
    fi
  '';

  # Generate KWin window rules for activity management
  generateKWinRules = activities: let
    # Explicit rules for applications that should appear in all activities
    # Matches the structure created by KDE GUI: Settings → Window Rules → Activities → Force → All Activities
    # NOTE: These rules work with regular application launchers - no special launchers needed
    allActivitiesRules = [
      {
        Description = "Firefox - All Activities";
        wmclass = "firefox";
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        activities = "";  # Empty = all activities
        activitiesrule = 2;  # Force
        types = 1;
      }
      {
        Description = "GitKraken - All Activities";
        wmclass = "gitkraken";
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        activities = "";  # Empty = all activities
        activitiesrule = 2;  # Force
        types = 1;
      }
      {
        Description = "Firefox PWAs - All Activities";
        wmclass = "FFPWA";  # Legacy X11 WM_CLASS prefix for Firefox PWAs
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        activities = "";  # Empty = all activities
        activitiesrule = 2;  # Force
        types = 1;
      }
      {
        Description = "Firefox PWAs (Wayland) - All Activities";
        wmclass = "firefoxpwa";  # Wayland WM_CLASS reported by firefoxpwa launcher
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        activities = "";  # Empty = all activities
        activitiesrule = 2;  # Force
        types = 1;
      }
      {
        Description = "Chromium - All Activities";
        wmclass = "chromium-browser";
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        activities = "";  # Empty = all activities
        activitiesrule = 2;  # Force
        types = 1;
      }
    ];

    # Create a flat list of rules
    activitySpecificRules = lib.flatten (lib.mapAttrsToList (name: activity:
      let
        # Get clean directory name for matching
        dirName = lib.last (lib.splitString "/" activity.directory);
        expandedDir = if lib.hasPrefix "~/" activity.directory
                     then "${config.home.homeDirectory}/${lib.removePrefix "~/" activity.directory}"
                     else activity.directory;
      in [
        # Rule for VS Code windows
        {
          Description = "VS Code - ${activity.name}";
          clientmachine = "localhost";
          wmclass = "code";
          wmclassmatch = 1; # Substring
          title = expandedDir;
          titlematch = 1; # Substring
          types = 1; # Normal window
          activity = activity.uuid;
          activityrule = 2; # Force (overrides default all-activities rule)
          wmclasscomplete = false;
        }
        # Rule for Konsole windows
        {
          Description = "Konsole - ${activity.name}";
          clientmachine = "localhost";
          wmclass = "konsole";
          wmclassmatch = 1;
          title = dirName;
          titlematch = 1;
          types = 1;
          activity = activity.uuid;
          activityrule = 2;
          wmclasscomplete = false;
        }
        # Rule for Dolphin windows
        {
          Description = "Dolphin - ${activity.name}";
          clientmachine = "localhost";
          wmclass = "dolphin";
          wmclassmatch = 1;
          title = dirName;
          titlematch = 1;
          types = 1;
          activity = activity.uuid;
          activityrule = 2;
          wmclasscomplete = false;
        }
      ]
    ) activities);

    # Combine all rules: PWAs for all activities + activity-specific rules
    rulesList = allActivitiesRules ++ activitySpecificRules;
  in rulesList;

in
{
  # Install the activity mappings file
  home.file.".config/plasma-activities/mappings.json".source = activityMappingFile;

  # Install the launcher scripts
  home.packages = [
    # Activity-specific launchers
    konsoleActivityScript
    codeActivityScript
    dolphinActivityScript
    # Yakuake drop-down terminal with activity-aware defaults
    yakuakeActivityScript
    yakuakeActivitySync
    # All-activities launchers
    firefoxAllActivities
    gitkrakenAllActivities
  ];

  # KWin window rules configuration
  # NOTE: KDE dynamically manages kwinrulesrc and may modify/remove rules
  # The current rules (GitKraken, Firefox PWAs) work when manually configured via KDE GUI
  # Firefox main browser rule is consistently removed by KDE - needs manual configuration
  #
  # To manually add Firefox all-activities rule:
  # 1. System Settings → Window Management → Window Rules
  # 2. Add New → Window class: firefox, substring match
  # 3. Add Property → Activities → Force → All Activities

  # Override default desktop entries to use activity-aware launchers
  # This ensures ALL launches (KRunner, menu, shortcuts) use our activity-aware behavior
  # Using home.file instead of xdg.desktopEntries to ensure they're actually created
  home.file = {
    ".local/share/applications/org.kde.konsole.desktop".text = ''
      [Desktop Entry]
      Name=Konsole
      GenericName=Terminal
      Comment=Command line terminal (activity-aware)
      Icon=utilities-terminal
      Type=Application
      Categories=Qt;KDE;System;TerminalEmulator;
      Exec=${konsoleActivityScript}/bin/konsole-activity
      Terminal=false
      Keywords=shell;prompt;command;commandline;cmd;
    '';

    ".local/share/applications/code.desktop".text = ''
      [Desktop Entry]
      Name=Visual Studio Code
      GenericName=Text Editor
      Comment=Code Editing. Redefined. (activity-aware)
      Icon=vscode
      Type=Application
      Categories=Utility;TextEditor;Development;IDE;
      Exec=${codeActivityScript}/bin/code-activity %F
      Terminal=false
      MimeType=text/plain;inode/directory;
      StartupNotify=true
      StartupWMClass=Code
      Keywords=vscode;
    '';

    ".local/share/applications/org.kde.dolphin.desktop".text = ''
      [Desktop Entry]
      Name=Dolphin
      GenericName=File Manager
      Comment=File Manager (activity-aware)
      Icon=system-file-manager
      Type=Application
      Categories=Qt;KDE;System;FileManager;
      Exec=${dolphinActivityScript}/bin/dolphin-activity %u
      Terminal=false
      MimeType=inode/directory;
      Keywords=file manager;filemanager;browser;explorer;
    '';

    ".local/share/applications/org.kde.yakuake.desktop".text = ''
      [Desktop Entry]
      Name=Yakuake
      GenericName=Drop-down Terminal
      Comment=A drop-down terminal emulator (activity-aware)
      Icon=yakuake
      Type=Application
      Categories=Qt;KDE;System;TerminalEmulator;
      Exec=${yakuakeActivityScript}/bin/yakuake-activity
      Terminal=false
      Keywords=terminal;console;
    '';
  };

  # Yakuake autostart disabled - manual launch preferred
  # home.file.".config/autostart/yakuake.desktop".text = ''
  #   [Desktop Entry]
  #   Type=Application
  #   Exec=yakuake-activity
  #   Hidden=false
  #   NoDisplay=false
  #   X-GNOME-Autostart-enabled=true
  #   Name=Yakuake
  #   Comment=Drop-down terminal with activity awareness
  # '';

  # Rebuild KDE application cache when desktop files change
  home.activation.rebuildKdeCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Rebuild KDE's application cache to register new desktop entries
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
      $DRY_RUN_CMD kbuildsycoca6 --noincremental 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
      $DRY_RUN_CMD kbuildsycoca5 --noincremental 2>/dev/null || true
    fi
  '';

  # Activity Manager integration service
  systemd.user.services.activity-directory-sync = {
    Unit = {
      Description = "Activity Directory Synchronization";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeScript "activity-sync" ''
        #!/usr/bin/env bash
        ${getActivityDirectory}
        ${qdbusLocator}

        # Monitor activity changes
        dbus-monitor --session "type='signal',interface='org.kde.ActivityManager',member='CurrentActivityChanged'" |
        while read -r line; do
          if [[ "$line" == *"CurrentActivityChanged"* ]]; then
            WORK_DIR=$(get_activity_directory)
            # Update environment for new processes
            systemctl --user set-environment ACTIVITY_WORK_DIR="$WORK_DIR"

            # Apply KWin rules to ensure proper window assignment
            if [ -n "$QDBUS_BIN" ]; then
              "$QDBUS_BIN" org.kde.KWin /KWin reconfigure 2>/dev/null || true
            fi
          fi
        done
      '';
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
