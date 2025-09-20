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
      local ACTIVITY_ID=$(qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)

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
    WORK_DIR=$(get_activity_directory)
    code "$WORK_DIR"
  '';

  dolphinActivityScript = pkgs.writeScriptBin "dolphin-activity" ''
    #!/usr/bin/env bash
    ${getActivityDirectory}
    WORK_DIR=$(get_activity_directory)
    dolphin "$WORK_DIR"
  '';

  yakuakeActivitySync = pkgs.writeScriptBin "yakuake-activity-sync" ''
    #!/usr/bin/env bash
    ${getActivityDirectory}

    if pgrep -f "yakuake" >/dev/null 2>&1; then
      WORK_DIR=$(get_activity_directory)
      ACTIVITY_ID=$(qdbus org.kde.ActivityManager /ActivityManager/Activities CurrentActivity 2>/dev/null)
      ACTIVITY_NAME=$(grep "^$ACTIVITY_ID=" ~/.config/kactivitymanagerdrc 2>/dev/null | cut -d= -f2 | head -1)
      SESSION_TITLE="$ACTIVITY_NAME"

      # Check if a session for this activity already exists
      EXISTING_SESSION=""
      for session_id in $(qdbus org.kde.yakuake /yakuake/sessions sessionIdList 2>/dev/null | tr ',' ' '); do
        title=$(qdbus org.kde.yakuake /yakuake/tabs tabTitle "$session_id" 2>/dev/null || echo "")
        if [[ "$title" == "$SESSION_TITLE" ]]; then
          EXISTING_SESSION="$session_id"
          break
        fi
      done

      if [ -n "$EXISTING_SESSION" ]; then
        qdbus org.kde.yakuake /yakuake/sessions raiseSession "$EXISTING_SESSION" 2>/dev/null || true
      else
        NEW_SESSION=$(qdbus org.kde.yakuake /yakuake/sessions addSession 2>/dev/null)
        if [ -n "$NEW_SESSION" ]; then
          qdbus org.kde.yakuake /yakuake/tabs setTabTitle "$NEW_SESSION" "$SESSION_TITLE" 2>/dev/null || true
          qdbus org.kde.yakuake /yakuake/sessions runCommandInTerminal "$NEW_SESSION" "cd '$WORK_DIR'" 2>/dev/null || true
          qdbus org.kde.yakuake /yakuake/sessions raiseSession "$NEW_SESSION" 2>/dev/null || true
        fi
      fi
    fi
  '';

  yakuakeActivityScript = pkgs.writeScriptBin "yakuake-activity" ''
    #!/usr/bin/env bash
    ${getActivityDirectory}
    WORK_DIR=$(get_activity_directory)

    if pgrep -f "${pkgs.kdePackages.yakuake}/bin/yakuake" >/dev/null 2>&1; then
      qdbus org.kde.yakuake /yakuake/window toggleWindowState 2>/dev/null || true
      sleep 0.2
      yakuake-activity-sync
    else
      cd "$WORK_DIR"
      ${pkgs.kdePackages.yakuake}/bin/yakuake &
      sleep 1
      yakuake-activity-sync
    fi
  '';

  # Generate KWin window rules for activity management
  generateKWinRules = activities: let
    # Create a flat list of rules
    rulesList = lib.flatten (lib.mapAttrsToList (name: activity:
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
          activityrule = 2; # Force
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
  in rulesList;

in
{
  # Install the activity mappings file
  home.file.".config/plasma-activities/mappings.json".source = activityMappingFile;

  # Install the simplified launcher scripts
  home.packages = [
    konsoleActivityScript
    codeActivityScript
    dolphinActivityScript
    yakuakeActivityScript
    yakuakeActivitySync
  ];

  # KWin window rules configuration using plasma-manager
  # These rules automatically assign windows to activities based on their properties
  programs.plasma.configFile."kwinrulesrc" = let
    rules = generateKWinRules activityData.rawActivities;
    ruleCount = lib.length rules;
    ruleIndices = lib.genList (i: toString (i + 1)) ruleCount;

    # Generate rule sections
    ruleSections = lib.concatStringsSep "\n\n" (
      lib.imap1 (idx: rule: ''
        [${toString idx}]
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (key: value:
            "${key}=${toString value}"
          ) rule
        )}''
      ) rules
    );
  in {
    General = {
      count = toString ruleCount;
      rules = lib.concatStringsSep "," ruleIndices;
    };
  } // lib.listToAttrs (
    lib.imap1 (idx: rule:
      lib.nameValuePair (toString idx) rule
    ) rules
  );

  # Create desktop entries with simple launchers
  xdg.desktopEntries = {
    # Activity-aware Konsole
    konsole-activity = {
      name = "Konsole (Activity)";
      genericName = "Terminal";
      comment = "Opens in current activity's directory";
      icon = "utilities-terminal";
      terminal = false;
      type = "Application";
      categories = [ "System" "TerminalEmulator" ];
      exec = "${konsoleActivityScript}/bin/konsole-activity";
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
      settings = {
        Keywords = "yakuake;terminal;dropdown;activity;quake;";
      };
    };

    # VS Code with activity-specific jumplist actions
    "code-activities" = {
      name = "VS Code (Activities)";
      genericName = "Code Editor";
      comment = "Code Editing with Activity Support";
      icon = "vscode";
      terminal = false;
      type = "Application";
      categories = [ "Development" "IDE" ];
      exec = "code";
      startupNotify = true;
      settings = {
        StartupWMClass = "Code";
        Keywords = "vscode;code;editor;development;ide;";
        # Define jumplist actions for each activity
        Actions = lib.concatStringsSep ";" (
          (lib.mapAttrsToList (name: activity: "open-${name}") activityData.rawActivities) ++
          ["new-window"]
        );
      };
      # Add action entries for each activity
      actions = lib.mapAttrs' (name: activity:
        lib.nameValuePair "open-${name}" {
          name = "Open in ${activity.name}";
          icon = activity.icon or "vscode";
          exec = let
            expandedDir = if lib.hasPrefix "~/" activity.directory
                         then "${config.home.homeDirectory}/${lib.removePrefix "~/" activity.directory}"
                         else activity.directory;
          in "code ${expandedDir}";
        }
      ) activityData.rawActivities // {
        "new-window" = {
          name = "New Window";
          icon = "vscode";
          exec = "code --new-window";
        };
      };
    };
  };

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

        # Monitor activity changes
        dbus-monitor --session "type='signal',interface='org.kde.ActivityManager',member='CurrentActivityChanged'" |
        while read -r line; do
          if [[ "$line" == *"CurrentActivityChanged"* ]]; then
            WORK_DIR=$(get_activity_directory)
            # Update environment for new processes
            systemctl --user set-environment ACTIVITY_WORK_DIR="$WORK_DIR"

            # Apply KWin rules to ensure proper window assignment
            qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || true
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