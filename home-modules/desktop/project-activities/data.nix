{ lib, config, pkgs, ... }:

let
  homeDir = config.home.homeDirectory or "";

  expandPath = path:
    if lib.hasPrefix "~/" path then
      (if homeDir == "" then throw "home.homeDirectory must be set to expand paths beginning with ~/" else "${homeDir}/${lib.removePrefix "~/" path}")
    else path;

  fileUri = path: let
    expanded = expandPath path;
  in if lib.hasPrefix "/" expanded then "file://${expanded}" else if lib.hasPrefix "file://" expanded then expanded else "file://${expanded}";

  # Reusable commands
  konsoleCmd = workspacePath:
    let
      quoted = lib.escapeShellArg workspacePath;
    in "${pkgs.kdePackages.konsole}/bin/konsole --profile Shell --workdir ${quoted}";

  konsoleSeshCmd = sessionName: workspacePath:
    let
      path = expandPath workspacePath;
      quotedPath = lib.escapeShellArg path;
      quotedSession = lib.escapeShellArg sessionName;
      launchCmd = lib.escapeShellArg (
        "direnv exec ${quotedPath} sesh connect ${quotedSession} || sesh connect ${quotedSession}"
      );
    in "${pkgs.kdePackages.konsole}/bin/konsole --profile Shell --workdir ${quotedPath} -e ${pkgs.runtimeShell} -lc ${launchCmd}";

  yakuakeSessionScript = name: workspacePath:
    let
      path = expandPath workspacePath;
    in pkgs.writeShellScript "activity-yakuake-${name}" ''
      set -euo pipefail

      TARGET=${lib.escapeShellArg path}

      QDBUS_BIN=$(command -v qdbus6 || command -v qdbus || true)
      YAKUAKE=${lib.escapeShellArg "${pkgs.kdePackages.yakuake}/bin/yakuake"}
      PGREP=${lib.escapeShellArg "${pkgs.procps}/bin/pgrep"}

      if [ -z "$QDBUS_BIN" ]; then
        exit 0
      fi

      if ! $PGREP -x yakuake >/dev/null 2>&1; then
        nohup $YAKUAKE >/dev/null 2>&1 &
      fi

      for attempt in $(seq 1 40); do
        if "$QDBUS_BIN" org.kde.yakuake /yakuake/sessions >/dev/null 2>&1; then
          break
        fi
        sleep 0.25
        if [ "$attempt" -eq 40 ]; then
          exit 0
        fi
      done

      if [ -z "$("$QDBUS_BIN" org.kde.yakuake /yakuake/sessions sessionIdList 2>/dev/null)" ]; then
        "$QDBUS_BIN" org.kde.yakuake /yakuake/sessions addSession >/dev/null 2>&1 || true
      fi

      CMD=$(printf 'cd %q && clear' "$TARGET")
      "$QDBUS_BIN" org.kde.yakuake /yakuake/sessions runCommand "$CMD"
    '';
  dolphinCmd = workspacePath:
    let
      quoted = lib.escapeShellArg workspacePath;
    in "${pkgs.kdePackages.dolphin}/bin/dolphin ${quoted}";

  # VS Code with specific directory
  vscodeCmd = workspacePath:
    let
      path = expandPath workspacePath;
      quoted = lib.escapeShellArg path;
    in "${pkgs.vscode}/bin/code ${quoted}";

in rec {
  defaultActivity = "nixos";

  rawActivities = {
    nixos = {
      uuid = "6ed332bc-fa61-5381-511d-4d5ba44a293b";
      name = "NixOS";
      description = "System configuration, infra-as-code, and declarative desktop tweaks.";
      icon = "nix-snowflake";
      directory = "/etc/nixos";
      wallpaper = "/run/current-system/sw/share/wallpapers/DarkestHour/contents/images/1920x1080.png";
      shortcut = "Meta+Ctrl+2";  # Activity shortcut
      colorScheme = {
        # Subtle blue accent for NixOS activity
        accentColor = "104,124,201";  # Nix blue (#687CC9)
        windowDecorationColor = "49,54,68";  # Dark blue-gray
      };
      resources = [
        (fileUri "/etc/nixos")
      ];
      autostart = [];
      scoring = {
        pruneRecent = {
          count = 250;
          what = "documents";
        };
        keepMonths = 3;
      };
    };

    stacks = {
      uuid = "b4f4e6c4-e52c-1f6b-97f5-567b04283fac";
      name = "Stacks";
      description = "Platform engineering stacks and deployment playbooks.";
      icon = "folder-git";  # GitOps folder icon - perfect for infrastructure as code
      directory = expandPath "~/stacks";
      wallpaper = "/run/current-system/sw/share/wallpapers/Cluster/contents/images/1920x1080.png";
      shortcut = "Meta+Ctrl+3";  # Activity shortcut
      colorScheme = {
        # Subtle green accent for Stacks activity
        accentColor = "77,150,75";  # Forest green (#4D964B)
        windowDecorationColor = "45,56,45";  # Dark green-gray
      };
      resources = [
        (fileUri "~/stacks")
      ];
      autostart = [];
      scoring = {
        pruneRecent = {
          count = 150;
          what = "documents";
        };
        keepMonths = 2;
      };
    };

    backstage = {
      uuid = "dcc377c8-d627-4d0b-8dd7-27d83f8282b3";
      name = "Backstage";
      description = "Backstage developer portal and CNOE platform.";
      icon = "applications-development";  # Developer portal icon
      directory = expandPath "~/backstage-cnoe";
      wallpaper = "/run/current-system/sw/share/wallpapers/Cascade/contents/images/1920x1080.png";
      shortcut = "Meta+Ctrl+4";  # Activity shortcut
      colorScheme = {
        # Subtle purple accent for Backstage activity
        accentColor = "139,92,168";  # Backstage purple (#8B5CA8)
        windowDecorationColor = "54,45,60";  # Dark purple-gray
      };
      resources = [
        (fileUri "~/backstage-cnoe")
      ];
      autostart = [];
      scoring = {
        pruneRecent = {
          count = 200;
          what = "documents";
        };
        keepMonths = 3;
      };
    };

    monitoring = {
      uuid = "645bcfb7-e769-4000-93be-ad31eb77ea2e";
      name = "Monitoring";
      description = "System resource monitoring and performance dashboards.";
      icon = "utilities-system-monitor";  # System monitor icon
      directory = expandPath "~/coordination";
      wallpaper = "/run/current-system/sw/share/wallpapers/Flow/contents/images/1920x1080.png";
      shortcut = "Meta+Ctrl+1";  # Activity shortcut
      colorScheme = {
        # Orange/amber accent for monitoring activity
        accentColor = "255,152,0";  # Material Design amber (#FF9800)
        windowDecorationColor = "60,48,36";  # Dark amber-gray
      };
      resources = [
        (fileUri "~/coordination")
      ];
      autostart = [];
      scoring = {
        pruneRecent = {
          count = 100;
          what = "documents";
        };
        keepMonths = 1;
      };
    };
  };

  defaultIcons = [
    "folder-blue"
    "folder-cyan"
    "folder-green"
    "folder-orange"
    "folder-red"
    "folder-violet"
  ];

  activityIds = lib.attrNames rawActivities;
  iconCount = builtins.length defaultIcons;

  pickIcon = idx: provided:
    if provided != null && provided != "" then
      provided
    else if iconCount > 0 then
      let
        quotient = builtins.div idx iconCount;
        remainder = idx - (quotient * iconCount);
      in builtins.elemAt defaultIcons remainder
    else
      "folder";

  activities = lib.listToAttrs (
    lib.imap0 (idx: id: let
      activity = rawActivities.${id};
      providedIcon = if activity ? icon then activity.icon else null;
      resolved = activity // { icon = pickIcon idx providedIcon; };
    in lib.nameValuePair id resolved) activityIds
  );
}
