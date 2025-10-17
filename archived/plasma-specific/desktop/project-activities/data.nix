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
      wallpaper = "/run/current-system/sw/share/wallpapers/IceCold/contents/images/1920x1080.jpg";  # Cool blue theme for NixOS
      shortcut = "Meta+Ctrl+1";  # Activity shortcut
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
      wallpaper = "/run/current-system/sw/share/wallpapers/Canopee/contents/images/1920x1080.jpg";  # Green forest theme for Stacks
      shortcut = "Meta+Ctrl+2";  # Activity shortcut
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

    "nixos-worktree" = {
      uuid = "767eac66-c2d4-43ff-a533-c5fe375f1223";
      name = "NixOS Worktree";
      description = "Git worktree for experimental NixOS configuration changes.";
      icon = "folder-development";  # Development folder icon
      directory = expandPath "~/nixos-worktree";
      wallpaper = "/run/current-system/sw/share/wallpapers/Kay/contents/images/1920x1080.jpg";  # Purple/violet theme for distinction
      shortcut = "Meta+Ctrl+3";  # Activity shortcut
      colorScheme = {
        # Distinct purple/violet accent for NixOS worktree
        accentColor = "142,68,173";  # Deep purple (#8E44AD)
        windowDecorationColor = "52,44,60";  # Dark purple-gray
      };
      resources = [
        (fileUri "~/nixos-worktree")
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

    "stacks-worktree" = {
      uuid = "a5877cc7-6e8f-4e68-bd8d-5b0f68a63bc9";
      name = "Stacks Worktree";
      description = "Git worktree for experimental stacks configuration changes.";
      icon = "folder-script";  # Script folder icon
      directory = expandPath "~/stacks-worktree";
      wallpaper = "/run/current-system/sw/share/wallpapers/Autumn/contents/images/1920x1080.jpg";  # Warm orange/red theme for distinction
      shortcut = "Meta+Ctrl+4";  # Activity shortcut
      colorScheme = {
        # Distinct orange/red accent for Stacks worktree
        accentColor = "211,84,0";  # Burnt orange (#D35400)
        windowDecorationColor = "60,40,35";  # Dark orange-brown
      };
      resources = [
        (fileUri "~/stacks-worktree")
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
