{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/desktop/kde-projects.nix
  ];

  # Enable the KDE projects module
  programs.kde-projects = {
    enable = true;

    projects = {
      nixos = {
        name = "NixOS";
        path = "/etc/nixos";
        desktop = 1;
        icon = "nix-snowflake";

        vscode = {
          enable = true;
          settings = {
            "window.title" = "\${dirty}\${activeEditorShort}\${separator}NixOS Config";
            "workbench.colorCustomizations" = {
              "activityBar.background" = "#5277C3";
              "titleBar.activeBackground" = "#5277C3";
            };
            "files.exclude" = {
              "result" = true;
              "result-*" = true;
            };
          };

          tasks = {
            version = "2.0.0";
            tasks = [
              {
                label = "NixOS Rebuild Test";
                type = "shell";
                command = "sudo nixos-rebuild dry-build --flake .#\${input:hostname}";
                group = "test";
                problemMatcher = [];
              }
              {
                label = "NixOS Rebuild Switch";
                type = "shell";
                command = "sudo nixos-rebuild switch --flake .#\${input:hostname}";
                group = "build";
                problemMatcher = [];
              }
              {
                label = "Update Flake";
                type = "shell";
                command = "nix flake update";
                group = "none";
                problemMatcher = [];
              }
              {
                label = "Check Flake";
                type = "shell";
                command = "nix flake check";
                group = "test";
                problemMatcher = [];
              }
            ];
            inputs = [
              {
                id = "hostname";
                type = "pickString";
                description = "Select target hostname";
                options = [ "hetzner" "m1" "wsl" ];
                default = "hetzner";
              }
            ];
          };

          launch = {
            version = "0.2.0";
            configurations = [
              {
                name = "Debug Nix Module";
                type = "shell";
                request = "launch";
                command = "nix repl '<nixpkgs/nixos>' --show-trace";
                args = [];
              }
            ];
          };
        };

        environment = {
          PROJECT_NAME = "nixos";
          PROJECT_TYPE = "configuration";
          NIX_PATH = "nixpkgs=/etc/nixos";
        };

        konsole.profile = {
          colorScheme = "NixOS";
        };

        dolphin.enable = true;
      };

      stacks = {
        name = "Stacks";
        path = builtins.toString (config.home.homeDirectory + "/stacks");
        desktop = 2;
        icon = "folder-development";

        vscode = {
          enable = true;
          settings = {
            "window.title" = "\${dirty}\${activeEditorShort}\${separator}Stacks";
            "workbench.colorCustomizations" = {
              "activityBar.background" = "#FF6B6B";
              "titleBar.activeBackground" = "#FF6B6B";
            };
          };

          tasks = {
            version = "2.0.0";
            tasks = [
              {
                label = "Build";
                type = "shell";
                command = "make build";
                group = {
                  kind = "build";
                  isDefault = true;
                };
                problemMatcher = [ "$gcc" ];
              }
              {
                label = "Test";
                type = "shell";
                command = "make test";
                group = {
                  kind = "test";
                  isDefault = true;
                };
                problemMatcher = [];
              }
            ];
          };
        };

        environment = {
          PROJECT_NAME = "stacks";
          PROJECT_TYPE = "development";
        };

        konsole.profile = {
          colorScheme = "Breeze";
        };

        dolphin.enable = true;
      };
    };
  };

  # Additional Plasma configuration that complements the projects
  programs.plasma.configFile = {
    # Configure desktop switching animations
    "kwinrc".Plugins = {
      slideEnabled = true;
      slideSpeed = 3;
    };

    # Configure Overview effect for project overview
    "kwinrc".Effect-overview = {
      BorderActivate = 9;  # Top-right corner
      LayoutMode = 1;  # Automatic
      ShowDesktopMode = 1;  # Show desktop bar
    };

    # Configure Present Windows per desktop
    "kwinrc".Effect-PresentWindows = {
      BorderActivate = 7;  # Top-left corner
      BorderActivateAll = 0;
      LayoutMode = 0;  # Natural
      ShowPanel = false;
      ShowDesktop = false;
    };

    # Task Manager - show only current desktop's tasks
    "plasmashellrc".TaskManager = {
      showOnlyCurrentDesktop = true;
      showOnlyCurrentActivity = true;
      separateLaunchers = true;
      sortingStrategy = 1;  # Desktop
    };

    # Panel configuration
    "plasmashellrc".General = {
      "immutability" = 1;  # User can modify
    };

    # Shortcuts for desktop grid view
    "kglobalshortcutsrc".kwin = {
      "ShowDesktopGrid" = "Meta+Tab,none,Show Desktop Grid";
      "Overview" = "Meta+W,none,Toggle Overview";
    };
  };

  # Starship prompt integration with project detection
  programs.starship.settings.custom.kde_project = {
    command = ''
      if [ -n "$PROJECT_NAME" ]; then
        case "$PROJECT_NAME" in
          nixos) echo "󱄅" ;;
          stacks) echo "󰆧" ;;
          *) echo "󰉋" ;;
        esac
      fi
    '';
    when = ''test -n "$PROJECT_NAME"'';
    format = "[$output $env:PROJECT_NAME]($style) ";
    style = "bold blue";
  };

  # Integration with tmux/sesh for terminal multiplexing
  home.file.".config/sesh/sesh.toml".text = ''
    [[session]]
    name = "nixos"
    path = "/etc/nixos"
    startup_command = "nvim flake.nix"

    [[session]]
    name = "stacks"
    path = "~/stacks"
    startup_command = "nvim"
  '';

  # KRunner web shortcuts for documentation
  programs.plasma.configFile."kuriikwsfilterrc" = {
    "General" = {
      DefaultWebShortcut = "ddg";
      EnableWebShortcuts = true;
    };

    "nix" = {
      Query = "https://search.nixos.org/packages?query=\\{@}";
      Name = "NixOS Packages";
    };

    "nixopt" = {
      Query = "https://search.nixos.org/options?query=\\{@}";
      Name = "NixOS Options";
    };

    "nixwiki" = {
      Query = "https://wiki.nixos.org/index.php?search=\\{@}";
      Name = "NixOS Wiki";
    };
  };
}