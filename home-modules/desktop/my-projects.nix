{ config, lib, pkgs, ... }:

let
  # ============================================================================
  # EDIT THIS SECTION: Define your active projects
  # ============================================================================
  # Each project automatically gets:
  # - A dedicated virtual desktop (numbered in order)
  # - Keyboard shortcuts (Meta+N to switch, Meta+Alt+N to open workspace)
  # - Window rules for automatic placement
  # - Konsole profile with the project name
  # - Shell aliases (cd<project>, work-<project>)
  # - Dolphin bookmarks
  # - VS Code workspace configuration

  myProjects = {
    nixos = {
      path = "/etc/nixos";
      icon = "nix-snowflake";
      color = "#5277C3";  # Nix blue
      vscode.tasks = [
        {
          label = "Test Configuration";
          command = "sudo nixos-rebuild dry-build --flake .#$(hostname)";
          group = "test";
        }
        {
          label = "Apply Configuration";
          command = "sudo nixos-rebuild switch --flake .#$(hostname)";
          group = "build";
        }
      ];
    };

    stacks = {
      path = "~/stacks";
      icon = "folder-development";
      color = "#FF6B6B";  # Red
    };

    # Add more projects as needed:
    # myproject = {
    #   path = "~/projects/myproject";
    #   icon = "folder-blue";
    #   color = "#4287f5";
    # };
  };

  # ============================================================================
  # IMPLEMENTATION (usually no need to edit below)
  # ============================================================================

  # Helper to generate window rules for a project
  mkWindowRules = desktop: name: project: let
    baseNum = desktop * 100;
  in {
    # VS Code
    "${toString baseNum}" = {
      Description = "VS Code - ${name}";
      desktop = desktop;
      desktoprule = 3;  # Apply Initially
      wmclass = "code";
      wmclassmatch = 1;
      title = ".*${project.path}.*";
      titlematch = 3;
    };
    # Konsole
    "${toString (baseNum + 1)}" = {
      Description = "Konsole - ${name}";
      desktop = desktop;
      desktoprule = 3;
      wmclass = "konsole";
      wmclassmatch = 1;
      title = ".*${name}.*|.*${project.path}.*";
      titlematch = 3;
    };
    # Dolphin
    "${toString (baseNum + 2)}" = {
      Description = "Dolphin - ${name}";
      desktop = desktop;
      desktoprule = 3;
      wmclass = "dolphin";
      wmclassmatch = 1;
      title = ".*${builtins.baseNameOf project.path}.*";
      titlematch = 3;
    };
  };

  projectList = lib.attrsToList myProjects;
  projectCount = lib.length projectList;

in {
  # KDE Plasma configuration
  programs.plasma.configFile = lib.mkMerge ([
    {
      # Virtual desktops - one per project
      "kwinrc".Desktops = {
        Number = lib.mkForce projectCount;
        Rows = lib.mkForce (if projectCount <= 2 then 1 else 2);
      } // lib.listToAttrs (lib.imap1 (i: proj: {
        name = "Name_${toString i}";
        value = proj.name;
      }) projectList);

      # Desktop effects
      "kwinrc".Plugins = {
        slideEnabled = true;
        desktopgridEnabled = true;
        overviewEnabled = true;
      };

      # Hot corners
      "kwinrc".Effect-overview = {
        BorderActivate = lib.mkDefault 9;  # Top-right
      };

      "kwinrc".Effect-desktopgrid = {
        BorderActivate = lib.mkDefault 3;  # Bottom-right
      };

      # Window rules
      "kwinrulesrc" = lib.mkMerge (lib.imap1 (i: proj:
        mkWindowRules i proj.name proj.value
      ) projectList);

      # Global shortcuts
      "kglobalshortcutsrc".kwin = lib.mkMerge (lib.imap1 (i: proj: {
        "Switch to Desktop ${toString i}" = "Meta+${toString i},none,Switch to ${proj.name}";
        "Window to Desktop ${toString i}" = "Meta+Shift+${toString i},none,Move to ${proj.name}";
      }) projectList);
    }
  ] ++
  # Project workspace shortcuts
  (lib.imap1 (i: proj: {
    "kglobalshortcutsrc"."project-${proj.name}" = {
      "Open Workspace" = "Meta+Alt+${toString i},none,Open ${proj.name} workspace";
    };
  }) projectList));

  # Shell aliases for each project
  programs.bash.shellAliases = lib.mkMerge (lib.mapAttrsToList (name: project: {
    "cd${name}" = "cd ${project.path}";
    "work-${name}" = ''
      cd ${project.path} && \
      ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.KWin /KWin setCurrentDesktop ${toString (lib.findFirst (x: x.name == name) 1 (lib.imap1 (i: p: {name = p.name; num = i;}) projectList)).num}
    '';
  }) myProjects);

  # File definitions (konsole profiles, bookmarks, VS Code workspaces)
  home.file = lib.mkMerge ([
    # Konsole profiles for each project
    (lib.mkMerge (lib.mapAttrsToList (name: project: {
    ".local/share/konsole/${name}.profile" = {
      text = ''
        [Appearance]
        ColorScheme=Breeze
        Font=FiraCode Nerd Font Mono,11,-1,5,50,0,0,0,0,0

        [General]
        Command=/run/current-system/sw/bin/bash -c "cd ${project.path} && exec bash"
        Directory=${project.path}
        Environment=TERM=xterm-256color,PROJECT=${name}
        Icon=${project.icon or "folder"}
        LocalTabTitleFormat=%d : ${name}
        Name=${name}
        Parent=FALLBACK/

        [Scrolling]
        HistoryMode=2
        ScrollBarPosition=2
      '';
    };
  }) myProjects))

    # Dolphin bookmarks
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
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: project: ''
          <bookmark href="file://${project.path}">
            <title>${name}</title>
            <info>
              <metadata owner="http://freedesktop.org">
                <bookmark:icon name="${project.icon or "folder"}"/>
              </metadata>
            </info>
          </bookmark>
        '') myProjects)}
      </xbel>
    '';
  };}
  ] ++

  # VS Code workspaces for projects that define them
  (lib.mapAttrsToList (name: project:
    lib.optionalAttrs (project ? vscode) {
      "${project.path}/.vscode/${name}.code-workspace" = {
        text = builtins.toJSON {
          folders = [{ path = ".."; name = name; }];
          settings = {
            "window.title" = "\${dirty}\${activeEditorShort}\${separator}${name}";
            "workbench.colorCustomizations" = lib.optionalAttrs (project ? color) {
              "activityBar.background" = project.color;
              "titleBar.activeBackground" = project.color;
            };
          } // (project.vscode.settings or {});
          tasks = if project.vscode ? tasks then {
            version = "2.0.0";
            tasks = project.vscode.tasks;
          } else null;
        };
      };
    }
  ) myProjects) ++

  # Tmux/sesh sessions
  [{".config/sesh/sesh.toml" = {
    text = ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: project: ''
        [[session]]
        name = "${name}"
        path = "${project.path}"
        startup_command = "nvim"
      '') myProjects)}
    '';
  };}]
  );

  # Desktop entries in application menu
  xdg.desktopEntries = lib.listToAttrs (lib.imap1 (i: proj: {
    name = "project-${proj.name}";
    value = {
      name = "${proj.name} Workspace";
      comment = "Open ${proj.name} development environment";
      icon = proj.value.icon or "folder";
      exec = "${pkgs.writeShellScript "open-${proj.name}" ''
        #!/usr/bin/env bash
        ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.KWin /KWin setCurrentDesktop ${toString i}
        cd ${proj.value.path}
        ${pkgs.kdePackages.konsole}/bin/konsole --profile ${proj.name} &
        ${lib.optionalString (proj.value ? vscode) "${pkgs.vscode}/bin/code ${proj.value.path} &"}
      ''}";
      terminal = false;
      type = "Application";
      categories = [ "Development" ];
    };
  }) projectList);

  # Starship prompt integration
  programs.starship.settings.custom.project = {
    command = ''
      case "$PWD" in
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList (name: project:
          "${project.path}*) echo '${project.icon or "📁"} ${name}' ;;") myProjects)}
        *) ;;
      esac
    '';
    when = "true";
    format = "[$output]($style) ";
    style = "bold blue";
  };
}