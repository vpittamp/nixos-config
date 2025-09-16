{ config, lib, pkgs, ... }:

let
  # Define your projects here
  projects = {
    nixos = {
      name = "NixOS";
      path = "/etc/nixos";
      desktop = 1;
      icon = "nix-snowflake";
      color = "#5277C3";  # Nix blue
      konsoleColorScheme = "NixOS";
      vscodeWorkspace = true;
      gitRemote = "https://github.com/yourusername/nixos-config.git";
      environment = {
        PROJECT_NAME = "nixos";
        PROJECT_TYPE = "configuration";
      };
    };

    stacks = {
      name = "Stacks";
      path = "~/stacks";
      desktop = 2;
      icon = "folder-development";
      color = "#FF6B6B";  # Custom red
      konsoleColorScheme = "Breeze";
      vscodeWorkspace = true;
      gitRemote = "https://github.com/yourusername/stacks.git";
      environment = {
        PROJECT_NAME = "stacks";
        PROJECT_TYPE = "development";
      };
    };
  };

  # Function to create a project launcher script
  mkProjectLauncher = name: project: pkgs.writeShellScriptBin "launch-${name}" ''
    #!/usr/bin/env bash

    # Switch to the project's desktop
    ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.KWin /KWin setCurrentDesktop ${toString project.desktop}

    # Set project environment
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}='${v}'") project.environment)}

    # Change to project directory
    cd ${project.path}

    # Launch based on first argument
    case "''${1:-all}" in
      terminal|konsole)
        ${pkgs.kdePackages.konsole}/bin/konsole \
          --profile "${project.name}" \
          --workdir "${project.path}" &
        ;;

      code|vscode)
        if [ -f "${project.path}/.vscode/workspace.code-workspace" ]; then
          ${pkgs.vscode}/bin/code "${project.path}/.vscode/workspace.code-workspace" &
        else
          ${pkgs.vscode}/bin/code "${project.path}" &
        fi
        ;;

      gitkraken|git)
        ${lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
          ${pkgs.gitkraken}/bin/gitkraken --path "${project.path}" &
        ''}
        ;;

      files|dolphin)
        ${pkgs.kdePackages.dolphin}/bin/dolphin "${project.path}" &
        ;;

      all)
        # Launch all tools for this project
        $0 terminal
        $0 code
        $0 gitkraken
        $0 files
        ;;

      *)
        echo "Usage: $0 [terminal|code|gitkraken|files|all]"
        exit 1
        ;;
    esac
  '';

  # Function to create VS Code workspace file
  mkVSCodeWorkspace = name: project: {
    name = ".vscode/workspace.code-workspace";
    value = {
      text = builtins.toJSON {
        folders = [
          {
            path = "..";
            name = project.name;
          }
        ];
        settings = {
          # Project-specific settings
          "window.title" = "\${dirty}\${activeEditorShort}\${separator}${project.name}";
          "workbench.colorCustomizations" = {
            "activityBar.background" = project.color;
            "titleBar.activeBackground" = project.color;
          };

          # Project-specific environment
          "terminal.integrated.env.linux" = project.environment;

          # Git settings
          "git.defaultCloneDirectory" = project.path;

          # File associations for this project
          "files.exclude" = if name == "nixos" then {
            "result" = true;
            "result-*" = true;
          } else {};
        };

        # Project-specific launch configurations
        launch = if name == "nixos" then {
          version = "0.2.0";
          configurations = [
            {
              type = "shell";
              name = "NixOS Rebuild Test";
              command = "sudo nixos-rebuild dry-build --flake .#$(hostname)";
              problemMatcher = [];
            }
            {
              type = "shell";
              name = "NixOS Rebuild Switch";
              command = "sudo nixos-rebuild switch --flake .#$(hostname)";
              problemMatcher = [];
            }
          ];
        } else {
          version = "0.2.0";
          configurations = [];
        };

        # Project tasks
        tasks = if name == "nixos" then {
          version = "2.0.0";
          tasks = [
            {
              label = "Check Flake";
              type = "shell";
              command = "nix flake check";
              group = "test";
              problemMatcher = [];
            }
            {
              label = "Update Flake";
              type = "shell";
              command = "nix flake update";
              group = "build";
              problemMatcher = [];
            }
          ];
        } else {
          version = "2.0.0";
          tasks = [];
        };
      };
    };
  };

  # Function to create Konsole color scheme
  mkKonsoleColorScheme = name: project: {
    name = "${project.name}.colorscheme";
    value = {
      text = ''
        [Background]
        Color=40,40,40

        [BackgroundFaint]
        Color=40,40,40

        [BackgroundIntense]
        Color=60,60,60

        [Color0]
        Color=0,0,0

        [Color0Faint]
        Color=24,24,24

        [Color0Intense]
        Color=104,104,104

        [Color1]
        Color=178,24,24

        [Color1Faint]
        Color=101,0,0

        [Color1Intense]
        Color=255,84,84

        [Color2]
        Color=24,178,24

        [Color2Faint]
        Color=0,101,0

        [Color2Intense]
        Color=84,255,84

        [Color3]
        Color=178,104,24

        [Color3Faint]
        Color=101,74,0

        [Color3Intense]
        Color=255,255,84

        [Color4]
        Color=${if name == "nixos" then "82,119,195" else "24,24,178"}

        [Color4Faint]
        Color=${if name == "nixos" then "40,60,100" else "0,0,101"}

        [Color4Intense]
        Color=${if name == "nixos" then "120,160,255" else "84,84,255"}

        [Color5]
        Color=178,24,178

        [Color5Faint]
        Color=95,5,95

        [Color5Intense]
        Color=255,84,255

        [Color6]
        Color=24,178,178

        [Color6Faint]
        Color=0,95,95

        [Color6Intense]
        Color=84,255,255

        [Color7]
        Color=178,178,178

        [Color7Faint]
        Color=101,101,101

        [Color7Intense]
        Color=255,255,255

        [Foreground]
        Color=252,252,252

        [ForegroundFaint]
        Color=200,200,200

        [ForegroundIntense]
        Color=255,255,255

        [General]
        Blur=false
        ColorRandomization=false
        Description=${project.name} Color Scheme
        Opacity=0.95
        Wallpaper=
      '';
    };
  };

  # Function to create desktop entry
  mkDesktopEntry = name: project: {
    name = "project-${name}";
    value = {
      name = "Open ${project.name} Workspace";
      comment = "Open ${project.name} development environment";
      exec = "launch-${name} all";
      icon = project.icon;
      terminal = false;
      type = "Application";
      categories = [ "Development" "ProjectManagement" ];
      actions = {
        terminal = {
          name = "Open Terminal";
          exec = "launch-${name} terminal";
        };
        vscode = {
          name = "Open VS Code";
          exec = "launch-${name} code";
        };
        files = {
          name = "Open File Manager";
          exec = "launch-${name} files";
        };
      };
    };
  };

in {
  # Install launcher scripts
  home.packages = lib.mapAttrsToList mkProjectLauncher projects;

  # Create VS Code workspace files
  home.file = lib.mkMerge [
    (lib.listToAttrs (lib.flatten (lib.mapAttrsToList (name: project:
      lib.optional project.vscodeWorkspace (mkVSCodeWorkspace name project)
    ) projects)))

    # Create Konsole color schemes
    (lib.listToAttrs (lib.mapAttrsToList (name: project:
      {
        name = ".local/share/konsole/${mkKonsoleColorScheme name project}.name";
        value = (mkKonsoleColorScheme name project).value;
      }
    ) projects))
  ];

  # Create desktop entries
  xdg.desktopEntries = lib.listToAttrs (lib.mapAttrsToList mkDesktopEntry projects);

  # Create Konsole profiles for each project
  home.file = lib.mkMerge (lib.mapAttrsToList (name: project: {
    ".local/share/konsole/${project.name}.profile" = {
      text = ''
        [Appearance]
        ColorScheme=${project.konsoleColorScheme}
        Font=FiraCode Nerd Font Mono,11,-1,5,50,0,0,0,0,0

        [General]
        Command=/run/current-system/sw/bin/bash -c "cd ${project.path} && exec bash"
        Directory=${project.path}
        Environment=TERM=xterm-256color,COLORTERM=truecolor,PROJECT=${name},${lib.concatStringsSep "," (lib.mapAttrsToList (k: v: "${k}=${v}") project.environment)}
        Icon=${project.icon}
        LocalTabTitleFormat=${project.name}: %d
        Name=${project.name}
        Parent=FALLBACK/
        ShowTerminalSizeHint=true
        StartInCurrentSessionDir=false

        [Interaction Options]
        OpenLinksByDirectClickEnabled=true
        UnderlineFilesEnabled=true

        [Scrolling]
        HistoryMode=2
        HistorySize=10000
        ScrollBarPosition=2

        [Terminal Features]
        BlinkingCursorEnabled=true
        UrlHintsModifiers=67108864
      '';
    };
  }) projects);

  # KDE Activities configuration for each project
  programs.plasma.configFile = lib.mkMerge [
    {
      # Configure activities
      "kactivitymanagerdrc"."activities-project" = lib.mapAttrs (name: project: project.name) projects;
    }

    # Window rules for project-aware application placement
    (lib.mkMerge (lib.imap1 (i: nameProject: let
      name = nameProject.name;
      project = nameProject.value;
      ruleNum = i * 10;  # Space out rule numbers
    in {
      # VS Code project detection
      "kwinrulesrc"."${toString ruleNum}" = {
        Description = "VS Code in ${project.name}";
        desktop = project.desktop;
        desktoprule = 3;  # Apply Initially
        wmclass = "code";
        wmclasscomplete = false;
        wmclassmatch = 1;
        title = ".*${project.name}.*";
        titlematch = 3;  # Regex
      };

      # Terminal project detection
      "kwinrulesrc"."${toString (ruleNum + 1)}" = {
        Description = "Terminal in ${project.name}";
        desktop = project.desktop;
        desktoprule = 3;
        wmclass = "konsole";
        wmclasscomplete = false;
        wmclassmatch = 1;
        title = ".*${name}.*";
        titlematch = 3;
      };

      # File manager project detection
      "kwinrulesrc"."${toString (ruleNum + 2)}" = {
        Description = "Dolphin in ${project.name}";
        desktop = project.desktop;
        desktoprule = 3;
        wmclass = "dolphin";
        wmclasscomplete = false;
        wmclassmatch = 1;
        title = ".*${builtins.baseNameOf project.path}.*";
        titlematch = 3;
      };
    }) (lib.attrsToList projects)))
  ];

  # Global keyboard shortcuts for project switching
  programs.plasma.configFile."kglobalshortcutsrc"."project-shortcuts" = lib.mapAttrs (name: project:
    "Meta+Alt+${toString project.desktop},none,Open ${project.name} Workspace"
  ) projects;

  # Bash aliases for quick project access
  programs.bash.shellAliases = lib.mkMerge [
    (lib.mapAttrs (name: project: "cd ${project.path}") projects)
    (lib.mapAttrs' (name: project: lib.nameValuePair "work-${name}" "launch-${name} all") projects)
    (lib.mapAttrs' (name: project: lib.nameValuePair "edit-${name}" "launch-${name} code") projects)
  ];

  # Environment detection for prompt
  programs.starship.settings.custom.current_project = {
    command = ''
      case "$PWD" in
        ${lib.concatStringsSep "\n        " (lib.mapAttrsToList (name: project:
          "${project.path}*) echo '${project.icon} ${project.name}' ;;") projects)}
        *) ;;
      esac
    '';
    when = "true";
    format = "[$output]($style) ";
    style = "bold cyan";
  };

  # Rofi/KRunner integration for project switching
  home.file.".local/share/kservices5/searchproviders/projects.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Service
      Name=Project Switcher
      Comment=Switch between project workspaces
      Icon=folder-development
      X-KDE-ServiceTypes=SearchProvider
      Keys=project
      Query=launch-\{@} all
    '';
  };
}