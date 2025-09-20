{ config, lib, pkgs, ... }:

let
  data = import ./data.nix { inherit lib config pkgs; };
  inherit (data) activities defaultActivity;

  # Order activities to match keyboard shortcuts: Meta+1=NixOS, Meta+2=Stacks, Meta+3=Backstage, Meta+4=Dev, Meta+5=Monitoring
  activityIds = [ "nixos" "stacks" "backstage" "dev" "monitoring" ];

  mkUUID = id:
    let
      hash = builtins.hashString "sha256" id;
    in "${builtins.substring 0 8 hash}-${builtins.substring 8 4 hash}-${builtins.substring 12 4 hash}-${builtins.substring 16 4 hash}-${builtins.substring 20 12 hash}";

  # Use the explicit UUIDs from data.nix
  activityUUIDs = lib.mapAttrs (id: activity: activity.uuid) activities;

  panels = import ./panels.nix { inherit lib activities mkUUID; };

  qdbus = "${pkgs.libsForQt5.qttools.bin}/bin/qdbus";
  kactivitymanagerd = "${pkgs.kdePackages.kactivitymanagerd}/bin/kactivitymanagerd";

  deriveShortcutPair = idx: activity:
    let
      fallback = "Meta+${toString (idx + 1)}";
      raw = activity.shortcut or null;
      sanitizeList = shortcuts:
        lib.filter (s: s != null && s != "") shortcuts;
    in if raw == null then {
      primary = fallback;
      secondary = "none";
    } else if builtins.isList raw then
      let
        sanitized = sanitizeList raw;
        primaryCandidate =
          if sanitized == [] then fallback
          else if builtins.elemAt sanitized 0 == "none" then fallback
          else builtins.elemAt sanitized 0;
        secondaryCandidate =
          if builtins.length sanitized > 1 then builtins.elemAt sanitized 1 else fallback;
        secondary =
          if secondaryCandidate == primaryCandidate || secondaryCandidate == "" then "none" else secondaryCandidate;
      in {
        primary = primaryCandidate;
        secondary = secondary;
      }
    else if builtins.isString raw then
      let
        primaryCandidate = if raw == "" then fallback else raw;
        secondaryCandidate = if primaryCandidate == fallback then "none" else fallback;
        secondary =
          if secondaryCandidate == primaryCandidate || secondaryCandidate == "" then "none" else secondaryCandidate;
      in {
        primary = primaryCandidate;
        secondary = secondary;
      }
    else {
      primary = fallback;
      secondary = "none";
    };

  activityShortcuts =
    lib.listToAttrs (
      lib.imap0 (idx: id: let
        activity = activities.${id};
        uuid = activityUUIDs.${id};
        name = activity.name;
        shortcutPair = deriveShortcutPair idx activity;
      in {
        name = "switch-to-activity-${uuid}";
        value = lib.mkForce "${shortcutPair.primary},${shortcutPair.secondary},Switch to activity \"${name}\"";
      }) activityIds
    );

  bootstrapScript = pkgs.writeShellScript "project-activities-bootstrap" ''
    set -euo pipefail

    QDBUS=${lib.escapeShellArg qdbus}
    SERVICE="org.kde.ActivityManager"
    CONFIG_FILE="$HOME/.config/kactivitymanagerdrc"
    MAPPING_FILE="$HOME/.config/plasma-activities/mappings.json"

    wait_for_service() {
      local max_attempts="$1"
      local attempt=0
      while ! $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.CurrentActivity >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if (( attempt >= max_attempts )); then
          return 1
        fi
        sleep 1
      done
      return 0
    }

    feature_available() {
      local feature="$1"
      local out
      if ! out=$($QDBUS "$SERVICE" /ActivityManager/Features org.kde.ActivityManager.Features.IsFeatureOperational "$feature" 2>/dev/null); then
        return 1
      fi
      [[ "$out" == "true" ]]
    }

    ensure_section() {
      mkdir -p "$HOME/.config"
    }

    set_metadata() {
      local uuid="$1" name="$2" description="$3" icon="$4"
      if [[ -n "$name" ]]; then
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.SetActivityName "$uuid" "$name" >/dev/null 2>&1 || true
      fi
      if [[ -n "$description" ]]; then
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.SetActivityDescription "$uuid" "$description" >/dev/null 2>&1 || true
      fi
      if [[ -n "$icon" ]]; then
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.SetActivityIcon "$uuid" "$icon" >/dev/null 2>&1 || true
      fi
    }

    create_or_ensure_activity() {
      local uuid="$1"
      local name="$2"

      # Check if activity with this UUID already exists
      if $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.ListActivities 2>/dev/null | grep -q "$uuid"; then
        echo "Activity $name ($uuid) already exists"
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.StartActivity "$uuid" >/dev/null 2>&1 || true
      else
        echo "Creating activity: $name"
        # Create new activity (gets temporary UUID)
        local temp_uuid=$($QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.AddActivity "$name" 2>/dev/null || echo "")

        if [[ -n "$temp_uuid" ]]; then
          echo "Created temporary activity $temp_uuid, will be remapped via config"
          # The config file will handle the UUID mapping
        fi
      fi
    }

    pin_current_activity() {
      local uuid="$1"
      $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.SetCurrentActivity "$uuid" >/dev/null 2>&1 || true
    }

    link_resource() {
      local uuid="$1" resource="$2"
      $QDBUS "$SERVICE" /ActivityManager/Resources/Linking org.kde.ActivityManager.ResourcesLinking.LinkResourceToActivity "project-activities" "$resource" "$uuid" >/dev/null 2>&1 || true
    }

    unlink_resource() {
      local uuid="$1" resource="$2"
      $QDBUS "$SERVICE" /ActivityManager/Resources/Linking org.kde.ActivityManager.ResourcesLinking.UnlinkResourceFromActivity "project-activities" "$resource" "$uuid" >/dev/null 2>&1 || true
    }

    prune_recent() {
      local uuid="$1" count="$2" what="$3"
      $QDBUS "$SERVICE" /ActivityManager/Resources/Scoring org.kde.ActivityManager.ResourcesScoring.DeleteRecentStats "$uuid" "$count" "$what" >/dev/null 2>&1 || true
    }

    prune_earlier() {
      local uuid="$1" months="$2"
      $QDBUS "$SERVICE" /ActivityManager/Resources/Scoring org.kde.ActivityManager.ResourcesScoring.DeleteEarlierStats "$uuid" "$months" >/dev/null 2>&1 || true
    }

    # Fast check – in headless sessions skip quietly
    if ! wait_for_service 5; then
      ${kactivitymanagerd} --replace >/dev/null 2>&1 &
      sleep 2
      if ! wait_for_service 60; then
        echo "[project-activities] ActivityManager not available; skipping bootstrap" >&2
        exit 0
      fi
    fi

    linking_available=0
    scoring_available=0
    if feature_available "resources/linking"; then
      linking_available=1
    fi
    if feature_available "resources/scoring"; then
      scoring_available=1
    fi

    echo "[project-activities] Starting activity bootstrap"

    # Clean up any incorrect activities first
    echo "Cleaning up incorrect activities..."
    desired_activities='${lib.concatMapStrings (id: "${activities.${id}.uuid}\n") activityIds}'
    current_activities=$($QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.ListActivities 2>/dev/null || true)

    for candidate in $current_activities; do
      if ! grep -qx "$candidate" <<<"$desired_activities"; then
        echo "Removing unwanted activity: $candidate"
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.StopActivity "$candidate" >/dev/null 2>&1 || true
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.RemoveActivity "$candidate" >/dev/null 2>&1 || true
      fi
    done

    echo "Creating/ensuring activities..."
${lib.concatMapStrings (id: let
      activity = activities.${id};
      uuid = activity.uuid;
      name = lib.escapeShellArg activity.name;
      description = lib.escapeShellArg (activity.description or "");
      icon = lib.escapeShellArg (activity.icon or "");
      resources = activity.resources or [];
      scoring = activity.scoring or {};
      pruneRecent = scoring.pruneRecent or null;
      keepMonths = scoring.keepMonths or null;
      resourceCmds = lib.concatMapStrings (resource:
        "    if (( linking_available )); then\n      link_resource ${lib.escapeShellArg uuid} ${lib.escapeShellArg resource}\n    fi\n") resources;
      pruneRecentCmd = lib.optionalString (pruneRecent != null)
        "    if (( scoring_available )); then\n      prune_recent ${lib.escapeShellArg uuid} ${toString pruneRecent.count} ${lib.escapeShellArg pruneRecent.what}\n    fi\n";
      pruneEarlierCmd = lib.optionalString (keepMonths != null)
        "    if (( scoring_available )); then\n      prune_earlier ${lib.escapeShellArg uuid} ${toString keepMonths}\n    fi\n";
    in ''
    echo "Processing activity: ${activity.name}"
    create_or_ensure_activity ${lib.escapeShellArg uuid} ${name}
    set_metadata ${lib.escapeShellArg uuid} ${name} ${description} ${icon}
${resourceCmds}${pruneRecentCmd}${pruneEarlierCmd}
'') activityIds}

    # The plasma configuration will be applied through home-manager activation
    echo "Declarative configuration will be applied by home-manager..."

    # Restart activity manager to load the correct configuration
    echo "Restarting activity manager to apply configuration..."
    ${kactivitymanagerd} --replace >/dev/null 2>&1 &
    sleep 3

    if ! wait_for_service 30; then
      echo "[project-activities] Warning: ActivityManager restart took longer than expected" >&2
    fi

    # Set the default activity
    echo "Setting default activity to ${activities.${defaultActivity}.name}..."
    pin_current_activity ${lib.escapeShellArg activities.${defaultActivity}.uuid}

    # Verify activities were created
    echo "Verifying activities..."
    final_activities=$($QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.ListActivities 2>/dev/null || true)
    echo "Active activities: $final_activities"

    echo "[project-activities] Bootstrap complete"
  '';

  autostartFiles =
    let
      entries = lib.concatMap (
        activityId:
          let
            activity = activities.${activityId};
            uuid = activityUUIDs.${activityId};
            autostart = activity.autostart or [];
          in lib.imap0 (idx: entry:
            {
              name = ".config/autostart/${activityId}-${toString idx}-project.desktop";
              value = {
                force = true;
                text = lib.concatStringsSep "\n" [
                  "[Desktop Entry]"
                  "Type=Application"
                  "OnlyShowIn=KDE;"
                  "X-KDE-Activities=${uuid}"
                  "X-KDE-Autostart-Delay=5"
                  "X-DBUS-StartupType=none"
                  "Name=${entry.name}"
                  ("Exec=${entry.exec}")
                  ("Icon=${entry.icon or "application-x-executable"}")
                ] + "\n";
              };
            }
          ) autostart
      ) activityIds;
    in lib.listToAttrs entries;

  shellAliases = lib.mapAttrs (id: _: "${qdbus} org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.SetCurrentActivity ${activityUUIDs.${id}}") activities;

in {
  config = {
    programs.plasma.configFile."kactivitymanagerdrc" = {
      # Define all activities
      activities = lib.mapAttrs' (id: activity:
        lib.nameValuePair activity.uuid activity.name
      ) activities;

      # Main configuration
      main = {
        currentActivity = lib.mkForce activities.${defaultActivity}.uuid;
        runningActivities = lib.mkForce (lib.concatStringsSep "," (map (id: activities.${id}.uuid) activityIds));
      };
    } // (
      # Activity-specific sections with metadata
      lib.listToAttrs (
        map (id: let
          activity = activities.${id};
        in {
          name = activity.uuid;
          value = {
            Name = activity.name;
            Description = activity.description or "";
            Icon = activity.icon or "";
          };
        }) activityIds
      )
    );

    programs.plasma.configFile."kglobalshortcutsrc" = {
      # Activity Manager with comprehensive shortcuts
      ActivityManager = lib.mkForce (
        {
          "_k_friendly_name" = "Activity Manager";
          # Global activity management
          "switch to next activity" = "Meta+Tab,none,Switch to Next Activity";
          "switch to previous activity" = "Meta+Shift+Tab,none,Switch to Previous Activity";
          "manage activities" = "Meta+Q,Meta+Q,Manage Activities";
        }
        // activityShortcuts
      );

      # Override plasmashell task manager shortcuts to free up Meta+1-4 for activities
      plasmashell = lib.mkForce {
        "_k_friendly_name" = "plasmashell";
        "activate task manager entry 1" = "none,Meta+1,Activate Task Manager Entry 1";
        "activate task manager entry 2" = "none,Meta+2,Activate Task Manager Entry 2";
        "activate task manager entry 3" = "none,Meta+3,Activate Task Manager Entry 3";
        "activate task manager entry 4" = "none,Meta+4,Activate Task Manager Entry 4";
        "activate task manager entry 5" = "none,Meta+5,Activate Task Manager Entry 5";
        "activate task manager entry 6" = "none,Meta+6,Activate Task Manager Entry 6";
        "activate task manager entry 7" = "none,Meta+7,Activate Task Manager Entry 7";
        "activate task manager entry 8" = "none,Meta+8,Activate Task Manager Entry 8";
        "activate task manager entry 9" = "none,Meta+9,Activate Task Manager Entry 9";
        "activate task manager entry 10" = "none,Meta+0,Activate Task Manager Entry 10";
      };

      # Keyboard shortcuts for activity-aware applications
      "services/konsole-activity.desktop" = {
        _launch = lib.mkForce "Ctrl+Alt+T,none,Launch Konsole in Activity Directory";
      };
      "services/code-activity.desktop" = {
        _launch = lib.mkForce "Ctrl+Alt+C,none,Launch VS Code in Activity Directory";
      };
      "services/dolphin-activity.desktop" = {
        _launch = lib.mkForce "Ctrl+Alt+F,none,Launch Dolphin in Activity Directory";
      };

      # Override the entire yakuake section to disable default F12
      yakuake = lib.mkForce {
        _k_friendly_name = "Yakuake";
        toggle-window-state = "none,none,Open/Retract Yakuake";
      };

      # Set our activity-aware Yakuake to use F12
      "services/yakuake-activity.desktop" = {
        _launch = lib.mkForce "F12,none,Toggle Yakuake in Activity Directory";
      };
    };

    programs.bash.shellAliases = shellAliases;

    home.file =
      autostartFiles //
      {
        ".config/plasma-org.kde.plasma.desktop-appletsrc" = {
          force = true;
          text = panels.panelIniText;
        };
      };

    # Bootstrap service to ensure activities are created with correct UUIDs
    systemd.user.services."project-activities-bootstrap" = {
      Unit = {
        Description = "Bootstrap KDE project activities with correct UUIDs";
        After = [ "plasma-workspace.target" "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = bootstrapScript;
        RemainAfterExit = true;
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install = {
        WantedBy = [ "plasma-workspace.target" ];
      };
    };
  };
}
