{ ... }:
{
  imports = [
    ./home-modules/profiles/base-home.nix
    # Plasma-home disabled during i3wm migration (Feature 009)
    # Re-enable if switching back to KDE Plasma
    # ./home-modules/profiles/plasma-home.nix
    # ./home-modules/desktop/i3.nix  # Not needed - using manual config file
    ./home-modules/desktop/i3wsr.nix  # Dynamic workspace naming for i3wm (Feature 009)
    ./home-modules/desktop/i3-projects.nix  # Feature 010: Project workspace management
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Enable i3 project workspace management (Feature 010)
  programs.i3Projects = {
    enable = true;

    projects = {
      nixos = {
        displayName = "NixOS Configuration";
        description = "NixOS system configuration development";
        primaryWorkspace = 1;
        workingDirectory = "/etc/nixos";

        workspaces = [
          # Workspace 1: Terminal with sesh session on first monitor (rdp1)
          {
            number = 1;
            output = "rdp1";
            applications = [
              {
                command = "alacritty";
                wmClass = "Alacritty";
                useSesh = true;
                seshSession = "nixos";  # Corresponds to sesh session in sesh.nix
              }
            ];
          }

          # Workspace 2: VS Code on second monitor (rdp2)
          {
            number = 2;
            output = "rdp2";
            applications = [
              {
                command = "code";
                args = ["/etc/nixos"];
                wmClass = "Code";
                launchDelay = 500;  # Give VS Code time to start
              }
            ];
          }
        ];
      };

      stacks = {
        displayName = "Stacks Development";
        description = "Cloud-native reference stacks development";
        primaryWorkspace = 3;
        workingDirectory = "/home/vpittamp/stacks";

        workspaces = [
          # Workspace 3: Terminal with sesh session on first monitor (rdp1)
          {
            number = 3;
            output = "rdp1";
            applications = [
              {
                command = "alacritty";
                wmClass = "Alacritty";
                useSesh = true;
                seshSession = "stacks";  # Corresponds to sesh session in sesh.nix
              }
            ];
          }

          # Workspace 4: VS Code on second monitor (rdp2)
          {
            number = 4;
            output = "rdp2";
            applications = [
              {
                command = "code";
                args = ["/home/vpittamp/stacks"];
                wmClass = "Code";
                launchDelay = 500;  # Give VS Code time to start
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
