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
  dolphinCmd = workspacePath:
    let
      quoted = lib.escapeShellArg workspacePath;
    in "${pkgs.kdePackages.dolphin}/bin/dolphin ${quoted}";

in rec {
  defaultActivity = "nixos";

  rawActivities = {
    nixos = {
      name = "NixOS";
      description = "System configuration, infra-as-code, and declarative desktop tweaks.";
      icon = "nix-snowflake";
      directory = "/etc/nixos";
      wallpaper = "/run/current-system/sw/share/wallpapers/DarkestHour/contents/images/1920x1080.png";
      colorScheme = {
        # Subtle blue accent for NixOS activity
        accentColor = "104,124,201";  # Nix blue (#687CC9)
        windowDecorationColor = "49,54,68";  # Dark blue-gray
      };
      resources = [
        (fileUri "/etc/nixos")
      ];
      autostart = [
        {
          name = "Konsole — NixOS";
          exec = konsoleCmd "/etc/nixos";
          icon = "utilities-terminal";
        }
      ];
      scoring = {
        pruneRecent = {
          count = 250;
          what = "documents";
        };
        keepMonths = 3;
      };
    };

    stacks = {
      name = "Stacks";
      description = "Platform engineering stacks and deployment playbooks.";
      icon = "folder-gitlab";
      directory = expandPath "~/stacks";
      wallpaper = "/run/current-system/sw/share/wallpapers/Cluster/contents/images/1920x1080.png";
      colorScheme = {
        # Subtle green accent for Stacks activity
        accentColor = "77,150,75";  # Forest green (#4D964B)
        windowDecorationColor = "45,56,45";  # Dark green-gray
      };
      resources = [
        (fileUri "~/stacks")
      ];
      autostart = [
        {
          name = "Dolphin — Stacks";
          exec = dolphinCmd (expandPath "~/stacks");
          icon = "system-file-manager";
        }
      ];
      scoring = {
        pruneRecent = {
          count = 150;
          what = "documents";
        };
        keepMonths = 2;
      };
    };

    backstage = {
      name = "Backstage";
      description = "Backstage developer portal and CNOE platform.";
      icon = "applications-development";  # Developer portal icon
      directory = expandPath "~/backstage-cnoe";
      wallpaper = "/run/current-system/sw/share/wallpapers/Cascade/contents/images/1920x1080.png";
      colorScheme = {
        # Subtle purple accent for Backstage activity
        accentColor = "139,92,168";  # Backstage purple (#8B5CA8)
        windowDecorationColor = "54,45,60";  # Dark purple-gray
      };
      resources = [
        (fileUri "~/backstage-cnoe")
      ];
      autostart = [
        {
          name = "Konsole — Backstage";
          exec = konsoleCmd (expandPath "~/backstage-cnoe");
          icon = "utilities-terminal";
        }
        {
          name = "VS Code — Backstage";
          exec = "${pkgs.vscode}/bin/code ${expandPath "~/backstage-cnoe"}";
          icon = "code";
        }
      ];
      scoring = {
        pruneRecent = {
          count = 200;
          what = "documents";
        };
        keepMonths = 3;
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
