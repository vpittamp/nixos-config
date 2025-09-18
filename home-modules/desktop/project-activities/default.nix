{ config, lib, pkgs, ... }:

let
  data = import ./data.nix { inherit lib config pkgs; };
  inherit (data) activities defaultActivity;

  activityIds = lib.attrNames activities;

  mkUUID = id:
    let
      hash = builtins.hashString "sha256" id;
    in "${builtins.substring 0 8 hash}-${builtins.substring 8 4 hash}-${builtins.substring 12 4 hash}-${builtins.substring 16 4 hash}-${builtins.substring 20 12 hash}";

  activityUUIDs = lib.mapAttrs (
    id: activity:
      if activity ? uuid && activity.uuid != "" then activity.uuid else mkUUID id
  ) activities;

  panels = import ./panels.nix { inherit lib activities mkUUID; };

  qdbus = "${pkgs.libsForQt5.qttools.bin}/bin/qdbus";
  kactivitymanagerd = "${pkgs.kdePackages.kactivitymanagerd}/bin/kactivitymanagerd";

  activityShortcut = idx: "Meta+Ctrl+${toString (idx + 1)}";

  activityShortcuts =
    lib.listToAttrs (
      lib.imap0 (idx: id: let
        uuid = activityUUIDs.${id};
        name = activities.${id}.name;
      in {
        name = "switch-to-activity-${uuid}";
        value = "${activityShortcut idx},none,Switch to activity \"${name}\"";
      }) activityIds
    );

  bootstrapScript = pkgs.writeShellScript "project-activities-bootstrap" ''
    set -euo pipefail

    QDBUS=${lib.escapeShellArg qdbus}
    SERVICE="org.kde.ActivityManager"

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

    start_activity() {
      local uuid="$1"
      $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.StartActivity "$uuid" >/dev/null 2>&1 || true
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

    # Ensure daemon picks up declarative config
    ${kactivitymanagerd} --replace >/dev/null 2>&1 &
    sleep 2
    if ! wait_for_service 60; then
      echo "[project-activities] ActivityManager did not return after restart; skipping bootstrap" >&2
      exit 0
    fi

    desired_activities='${lib.concatMapStrings (id: "${activityUUIDs.${id}}\n") activityIds}'
    current_activities=$($QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.ListActivities 2>/dev/null || true)
    for candidate in $current_activities; do
      if ! grep -qx "$candidate" <<<"$desired_activities"; then
        $QDBUS "$SERVICE" /ActivityManager/Activities org.kde.ActivityManager.Activities.RemoveActivity "$candidate" >/dev/null 2>&1 || true
      fi
    done

${lib.concatMapStrings (id: let
      activity = activities.${id};
      uuid = activityUUIDs.${id};
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
    ensure_section ${lib.escapeShellArg uuid} ${name}
    set_metadata ${lib.escapeShellArg uuid} ${name} ${description} ${icon}
    start_activity ${lib.escapeShellArg uuid}
${resourceCmds}${pruneRecentCmd}${pruneEarlierCmd}
'') activityIds}

    pin_current_activity ${lib.escapeShellArg activityUUIDs.${defaultActivity}}
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
    programs.plasma.configFile."kglobalshortcutsrc".ActivityManager =
      { "_k_friendly_name" = "Activity Manager"; }
      // activityShortcuts;

    programs.bash.shellAliases = shellAliases;

    home.file =
      autostartFiles //
      {
        ".config/plasma-org.kde.plasma.desktop-appletsrc" = {
          force = true;
          text = panels.panelIniText;
        };
      };

    systemd.user.services."project-activities-bootstrap" = {
      Unit = {
        Description = "Ensure KDE project activities exist and are configured";
        After = [ "plasma-workspace.target" "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = bootstrapScript;
        Environment = [ "QT_QPA_PLATFORM=offscreen" ];
      };
      Install = {
        WantedBy = [ "plasma-workspace.target" "graphical-session.target" ];
      };
    };
  };
}
