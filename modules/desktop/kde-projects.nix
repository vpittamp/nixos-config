{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.kde-projects;

  # Generate KWin window rules for a project
  mkWindowRules = projectName: project: let
    baseNum = project.desktop * 100;
  in {
    # VS Code rule
    "kwinrulesrc"."${toString baseNum}" = {
      Description = "VS Code - ${project.name}";
      desktop = project.desktop;
      desktoprule = 3;  # Apply Initially
      wmclass = "code";
      wmclassmatch = 1;
      title = ".*${project.path}.*";
      titlematch = 3;  # Regex
    };

    # Konsole rule
    "kwinrulesrc"."${toString (baseNum + 1)}" = {
      Description = "Konsole - ${project.name}";
      desktop = project.desktop;
      desktoprule = 3;
      wmclass = "konsole";
      wmclassmatch = 1;
      title = ".*${projectName}.*|.*${project.path}.*";
      titlematch = 3;
    };

    # Dolphin rule
    "kwinrulesrc"."${toString (baseNum + 2)}" = {
      Description = "Dolphin - ${project.name}";
      desktop = project.desktop;
      desktoprule = 3;
      wmclass = "dolphin";
      wmclassmatch = 1;
      title = ".*${project.path}.*";
      titlematch = 3;
    };
  };

  # Generate systemd user service for project workspace
  mkProjectService = projectName: project: {
    "kde-project-${projectName}" = {
      Unit = {
        Description = "KDE Project Workspace - ${project.name}";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScript "setup-${projectName}-workspace" ''
          # Wait for KDE to be ready
          sleep 2

          # Create project directory if needed
          mkdir -p ${project.path}

          # Set up VS Code workspace if enabled
          ${optionalString (project.vscode.enable or false) ''
            mkdir -p ${project.path}/.vscode
            cat > ${project.path}/.vscode/${projectName}.code-workspace <<'EOF'
            ${builtins.toJSON {
              folders = [ { path = ".."; name = project.name; } ];
              settings = project.vscode.settings or {};
              launch = project.vscode.launch or { version = "0.2.0"; configurations = []; };
              tasks = project.vscode.tasks or { version = "2.0.0"; tasks = []; };
            }}
            EOF
          ''}
        ''}";
      };
    };
  };

  # Generate KDE Service Menu entries (right-click actions)
  mkServiceMenu = projectName: project: {
    name = "servicemenu-${projectName}.desktop";
    value = {
      text = ''
        [Desktop Entry]
        Type=Service
        ServiceTypes=KonqPopupMenu/Plugin
        MimeType=inode/directory;
        Actions=OpenIn${project.name}Workspace;
        X-KDE-Priority=TopLevel
        X-KDE-Submenu=Open in Project Workspace

        [Desktop Action OpenIn${project.name}Workspace]
        Name=Open in ${project.name} Workspace
        Icon=${project.icon}
        Exec=${pkgs.writeShellScript "open-in-${projectName}" ''
          #!/usr/bin/env bash
          # Switch to project desktop
          ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.KWin /KWin setCurrentDesktop ${toString project.desktop}

          # Open directory in project context
          cd "%f"
          ${pkgs.kdePackages.konsole}/bin/konsole --profile "${project.name}" --workdir "%f" &
          ${optionalString (project.vscode.enable or false) "${pkgs.vscode}/bin/code %f &"}
          ${pkgs.kdePackages.dolphin}/bin/dolphin %f &
        ''}
      '';
    };
  };

  # Generate .desktop file for application menu
  mkDesktopEntry = projectName: project: {
    name = "kde-project-${projectName}";
    value = {
      name = "${project.name} Workspace";
      comment = "Open ${project.name} development workspace";
      exec = "${pkgs.writeShellScript "open-${projectName}-workspace" ''
        #!/usr/bin/env bash
        ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.KWin /KWin setCurrentDesktop ${toString project.desktop}
        cd ${project.path}
        ${pkgs.kdePackages.konsole}/bin/konsole --profile "${project.name}" &
        ${optionalString (project.vscode.enable or false) "${pkgs.vscode}/bin/code ${project.path} &"}
        ${optionalString (project.dolphin.enable or true) "${pkgs.kdePackages.dolphin}/bin/dolphin ${project.path} &"}
      ''}";
      icon = project.icon;
      terminal = false;
      type = "Application";
      categories = [ "Development" "ProjectManagement" ];
    };
  };

  # Type for project configuration
  projectType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Display name for the project";
      };

      path = mkOption {
        type = types.str;
        description = "Path to the project directory";
      };

      desktop = mkOption {
        type = types.int;
        description = "Virtual desktop number for this project";
      };

      icon = mkOption {
        type = types.str;
        default = "folder-development";
        description = "Icon name for the project";
      };

      konsole = {
        profile = mkOption {
          type = types.attrs;
          default = {};
          description = "Konsole profile settings";
        };
      };

      vscode = {
        enable = mkEnableOption "VS Code integration";
        settings = mkOption {
          type = types.attrs;
          default = {};
          description = "VS Code workspace settings";
        };
        launch = mkOption {
          type = types.attrs;
          default = { version = "0.2.0"; configurations = []; };
          description = "VS Code launch configurations";
        };
        tasks = mkOption {
          type = types.attrs;
          default = { version = "2.0.0"; tasks = []; };
          description = "VS Code task definitions";
        };
      };

      dolphin = {
        enable = mkEnableOption "Dolphin file manager integration" // { default = true; };
      };

      environment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Environment variables for this project";
      };
    };
  };

in {
  options.programs.kde-projects = {
    enable = mkEnableOption "KDE project-based workspace management";

    projects = mkOption {
      type = types.attrsOf projectType;
      default = {};
      description = "Project workspace definitions";
      example = literalExpression ''
        {
          nixos = {
            name = "NixOS";
            path = "/etc/nixos";
            desktop = 1;
            icon = "nix-snowflake";
            vscode.enable = true;
            vscode.settings = {
              "files.exclude" = { "result" = true; };
            };
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    # Plasma configuration via plasma-manager
    programs.plasma.configFile = mkMerge (
      # Virtual desktop configuration
      [{
        "kwinrc".Desktops = {
          Number = length (attrValues cfg.projects);
          Rows = 2;
        } // (listToAttrs (imap0 (i: project: {
          name = "Name_${toString (i + 1)}";
          value = project.name;
        }) (attrValues cfg.projects)));
      }] ++

      # Window rules for each project
      (mapAttrsToList mkWindowRules cfg.projects)
    );

    # Desktop entries for application menu
    xdg.desktopEntries = listToAttrs (mapAttrsToList mkDesktopEntry cfg.projects);

    # Systemd user services for project setup
    systemd.user.services = mkMerge (mapAttrsToList mkProjectService cfg.projects);

    # Combined home.file definitions
    home.file = mkMerge [
      # KDE Service Menu entries (right-click actions)
      (listToAttrs (mapAttrsToList (n: p: {
        name = ".local/share/kservices5/${(mkServiceMenu n p).name}";
        value = (mkServiceMenu n p).value;
      }) cfg.projects))

      # Konsole profiles for each project
      (mkMerge (mapAttrsToList (projectName: project: {
      ".local/share/konsole/${project.name}.profile" = {
        text = ''
          [Appearance]
          ColorScheme=Breeze
          Font=FiraCode Nerd Font Mono,11,-1,5,50,0,0,0,0,0

          [General]
          Command=/run/current-system/sw/bin/bash -c "cd ${project.path} && exec bash"
          Directory=${project.path}
          Environment=TERM=xterm-256color,PROJECT=${projectName}${optionalString (project.environment != {}) ",${concatStringsSep "," (mapAttrsToList (k: v: "${k}=${v}") project.environment)}"}
          Icon=${project.icon}
          LocalTabTitleFormat=%d : ${project.name}
          Name=${project.name}
          Parent=FALLBACK/

          [Scrolling]
          HistoryMode=2
          ScrollBarPosition=2
        '';
      };
    }) cfg.projects))

      # Dolphin places bookmarks
      {".local/share/user-places.xbel" = {
      text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xbel>
        <xbel xmlns:kdepriv="http://www.kde.org/kdepriv" xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks">
          <info>
            <metadata owner="http://freedesktop.org">
              <bookmark:applications>
                <bookmark:application name="dolphin" exec="dolphin %u" modified="2025-01-01T00:00:00Z" count="1"/>
              </bookmark:applications>
            </metadata>
          </info>
          ${concatStringsSep "\n" (mapAttrsToList (projectName: project: ''
            <bookmark href="file://${project.path}">
              <title>${project.name}</title>
              <info>
                <metadata owner="http://freedesktop.org">
                  <bookmark:icon name="${project.icon}"/>
                </metadata>
              </info>
            </bookmark>
          '') cfg.projects)}
        </xbel>
      '';
    };}
    ];

    # Shell aliases for project navigation
    programs.bash.shellAliases = mkMerge [
      (mapAttrs' (projectName: project: nameValuePair "cd${projectName}" "cd ${project.path}") cfg.projects)
      (mapAttrs' (projectName: project: nameValuePair "work-${projectName}" "systemctl --user start kde-project-${projectName}") cfg.projects)
    ];

    # Global keyboard shortcuts - merge with existing plasma config
    programs.plasma.configFile = mkMerge ([
      (programs.plasma.configFile or {})
    ] ++ (imap0 (i: project: {
      "kglobalshortcutsrc" = {
      "kwin"."Switch to Desktop ${toString (i + 1)}" = "Meta+${toString (i + 1)},none,Switch to Desktop ${toString (i + 1)}";
      "project-${project.name}"."Open ${project.name} Workspace" = "Meta+Alt+${toString (i + 1)},none,Open ${project.name} Workspace";
    }) (attrValues cfg.projects));
  };
}