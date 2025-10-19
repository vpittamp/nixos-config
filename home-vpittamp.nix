{ ... }:
{
  imports = [
    ./home-modules/profiles/base-home.nix
    # Plasma-home disabled during i3wm migration (Feature 009)
    # Re-enable if switching back to KDE Plasma
    # ./home-modules/profiles/plasma-home.nix
    ./home-modules/desktop/i3.nix  # i3 window manager configuration with keybindings
    ./home-modules/desktop/i3wsr.nix  # Dynamic workspace naming for i3wm (Feature 009)
    ./home-modules/desktop/i3-projects.nix  # Feature 010: Project workspace management
    ./home-modules/desktop/polybar.nix  # Polybar statusbar with project indicator
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Enable i3 project workspace management (Feature 010)
  programs.i3Projects = {
    enable = true;

    projects = {
      nixos = {
        displayName = "NixOS";
        description = "NixOS system configuration development";
        icon = "";  # NixOS snowflake logo
        primaryWorkspace = 1;
        workingDirectory = "/etc/nixos";

        workspaces = [
          # Workspace 1: Terminal with sesh session on first monitor (rdp1)
          {
            number = 1;
            output = "rdp1";
            applications = [
              {
                command = "ghostty";
                wmClass = "com.mitchellh.ghostty";
                useSesh = true;
                seshSession = "nixos";  # Corresponds to sesh session in sesh.nix
                # T010: Add project-scoped classification
                projectScoped = true;  # Project-specific terminal
                monitorPriority = 1;   # High priority - primary monitor
              }
            ];
          }

          # Workspace 2: VS Code on second monitor (rdp0)
          {
            number = 2;
            output = "rdp0";
            applications = [
              {
                command = "code";
                args = ["/etc/nixos"];
                wmClass = "Code";
                launchDelay = 500;  # Give VS Code time to start
                # T010: Add project-scoped classification
                projectScoped = true;  # Project-specific IDE
                monitorPriority = 1;   # High priority - primary monitor
              }
            ];
          }
        ];
      };

      stacks = {
        displayName = "Stacks";
        description = "Cloud-native reference stacks development";
        icon = "";  # Cloud/stack icon
        primaryWorkspace = 3;
        workingDirectory = "/home/vpittamp/stacks";

        workspaces = [
          # Workspace 3: Terminal with sesh session on first monitor (rdp1)
          {
            number = 3;
            output = "rdp1";
            applications = [
              {
                command = "ghostty";
                wmClass = "com.mitchellh.ghostty";
                useSesh = true;
                seshSession = "stacks";  # Corresponds to sesh session in sesh.nix
                # T010: Add project-scoped classification
                projectScoped = true;  # Project-specific terminal
                monitorPriority = 1;   # High priority - primary monitor
              }
            ];
          }

          # Workspace 4: VS Code on second monitor (rdp0)
          {
            number = 4;
            output = "rdp0";
            applications = [
              {
                command = "code";
                args = ["/home/vpittamp/stacks"];
                wmClass = "Code";
                launchDelay = 500;  # Give VS Code time to start
                # T010: Add project-scoped classification
                projectScoped = true;  # Project-specific IDE
                monitorPriority = 1;   # High priority - primary monitor
              }
            ];
          }
        ];
      };
    };
  };

  # Auto-clean home-manager backup conflicts before activation
  home.activation.cleanBackupConflicts = ''
    echo "Cleaning home-manager backup conflicts..."
    # Only clean specific files that home-manager manages
    # Note: mimeapps.list removed - now using associations.added to merge instead of overwrite
    for file in \
      .codex/config.toml \
      .mozilla/firefox/default/search.json.mozlz4 \
      .config/plasma-org.kde.plasma.desktop-appletsrc \
      .config/mimeapps.list; do
      if [ -f "$HOME/$file.backup" ]; then
        echo "Removing conflict: $HOME/$file.backup"
        rm -f "$HOME/$file.backup"
      fi
      if [ -f "$HOME/$file.hm-backup" ]; then
        echo "Removing old conflict: $HOME/$file.hm-backup"
        rm -f "$HOME/$file.hm-backup"
      fi
      if [ -f "$HOME/$file.old" ]; then
        echo "Removing old file: $HOME/$file.old"
        rm -f "$HOME/$file.old"
      fi
    done
  '';
}
