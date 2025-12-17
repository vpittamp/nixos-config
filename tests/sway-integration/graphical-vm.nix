# Graphical VM Test - Real Sway UI via VNC
#
# This VM runs Sway with actual graphics rendering visible via VNC.
# No headless mode - you'll see the real desktop.
#
# Usage:
#   $(nix-build tests/sway-integration/graphical-vm.nix -A interactive.driverInteractive)/bin/nixos-test-driver
#   # Then: start_all() and connect VNC to localhost:5900

{ pkgs ? import <nixpkgs> { config.allowUnfree = true; }
, system ? builtins.currentSystem
}:

let
  flake = builtins.getFlake (toString ../..);
  inputs = flake.inputs;
  home-manager = inputs.home-manager;

  # Required extraSpecialArgs for home-modules
  pkgs-unstable = import inputs.nixpkgs-bleeding {
    inherit system;
    config.allowUnfree = true;
  };

  # Feature 106: Assets package
  assetsPackage = import ../../lib/assets.nix { inherit pkgs; };

  graphicalNode = { config, pkgs, lib, ... }: {
    imports = [
      home-manager.nixosModules.home-manager
      ../../modules/services/sway-tree-monitor.nix
      ../../modules/desktop/sway.nix
    ];

    # VM with real graphics
    virtualisation = {
      memorySize = 8192;
      diskSize = 32768;
      cores = 4;
      resolution = { x = 1920; y = 1080; };
      qemu.options = [
        # Disable default VGA - required for Sway to render to virtio-gpu
        "-vga none"
        # Use virtio-gpu for better graphics
        "-device virtio-gpu-pci"
        # VNC server on port 5900
        "-vnc :0"
        # Also enable SPICE for better experience (optional)
        # "-spice port=5930,disable-ticketing=on"
      ];
    };

    # Graphics and Wayland support
    hardware.graphics.enable = true;

    # Sway WITHOUT headless - use real rendering
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    # Environment for graphical Sway (NOT headless)
    environment.sessionVariables = {
      # Use software rendering for VM compatibility
      WLR_RENDERER = "pixman";
      # Disable hardware cursors (not supported in VM)
      WLR_NO_HARDWARE_CURSORS = "1";
      # Standard Wayland settings
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = "sway";
      QT_QPA_PLATFORM = "wayland";
      GDK_BACKEND = "wayland";
      # Force single output for VM
      WLR_DRM_NO_MODIFIERS = "1";
    };

    # User
    users.users.vpittamp = {
      isNormalUser = true;
      extraGroups = [ "wheel" "input" "video" ];
      initialPassword = "";
      home = "/home/vpittamp";
    };

    # Home-manager with eww monitoring panel
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {
        inherit inputs pkgs-unstable assetsPackage;  # Required for home-modules
        self = flake;    # Required for home-modules that reference the flake itself
        monitorConfig = {
          "graphical-vm" = {
            outputs = [ "Virtual-1" "HDMI-A-1" "DP-1" ];
            primary = "Virtual-1";
            secondary = "Virtual-1";
            tertiary = "Virtual-1";
            quaternary = "Virtual-1";
          };
        };
      };
      users.vpittamp = { config, pkgs, lib, ... }: {
        imports = [
          # Import the hetzner home-manager configuration (VM-friendly)
          ../../home-modules/hetzner.nix
        ];

        # Override stateVersion for VM
        home.stateVersion = lib.mkForce "24.11";

        # Override i3pm daemon log level to reduce spam
        programs.i3-project-daemon.logLevel = lib.mkForce "WARNING";

        # Test project config
        home.file.".config/i3/projects/test-project.json".text = builtins.toJSON {
          name = "test-project";
          display_name = "Test Project";
          directory = "/home/vpittamp/test-repos/test-project";
          scope = "scoped";
          icon = "folder";
        };

        # Disable hardware-specific services that don't work in VM
        systemd.user.services.wayvnc = {
          Unit.ConditionPathExists = lib.mkForce "/nonexistent";  # Disable service
        };
        systemd.user.services.eww-workspace-bar = {
          Unit.ConditionPathExists = lib.mkForce "/nonexistent";  # Disable service
        };

        # Override eww service to reduce log spam
        systemd.user.services.eww-monitoring-panel = {
          Service = {
            StandardError = lib.mkForce "null";
          };
        };
      };
    };

    # Auto-login with graphical Sway
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.writeShellScript "sway-graphical-session" ''
            # Graphical session - no headless
            export WLR_RENDERER=pixman
            export WLR_NO_HARDWARE_CURSORS=1
            export XDG_SESSION_TYPE=wayland
            export XDG_CURRENT_DESKTOP=sway
            export QT_QPA_PLATFORM=wayland
            export GDK_BACKEND=wayland
            export HOME=/home/vpittamp
            export XDG_RUNTIME_DIR=/run/user/$(id -u)
            mkdir -p "$XDG_RUNTIME_DIR"
            chmod 700 "$XDG_RUNTIME_DIR"

            # Start Sway - redirect debug output to file to prevent console spam
            exec ${pkgs.sway}/bin/sway 2>/tmp/sway.log
          ''}";
          user = "vpittamp";
        };
      };
    };

    environment.systemPackages = with pkgs; [
      sway
      git
      jq
      foot
      eww
      wl-clipboard
      (python3.withPackages (ps: [ ps.i3ipc ps.pyxdg ps.pydantic ]))
      htop
      tmux
    ];

    networking.hostName = "graphical-vm";
    networking.firewall.enable = false;
    services.udisks2.enable = false;
    documentation.enable = false;
    system.stateVersion = "24.11";
  };

in {
  interactive = pkgs.testers.nixosTest {
    name = "graphical-vm";
    nodes.machine = graphicalNode;
    testScript = ''
print("""
Graphical VM - Real Sway UI via VNC

Connect VNC to localhost:5900 to see the actual Sway desktop!

Commands:
  machine.succeed("cmd")     - Run command
  machine.screenshot("x")    - Take screenshot
  machine.shell_interact()   - Interactive shell
""")

start_all()
machine.wait_for_unit("multi-user.target")
machine.wait_for_unit("greetd.service")

# Wait for Sway to start (may take longer with graphics)
machine.sleep(5)

# Set up git for Feature 120 testing
machine.succeed("su - vpittamp -c 'git config --global user.email test@test.com'")
machine.succeed("su - vpittamp -c 'git config --global user.name Test'")
machine.succeed("su - vpittamp -c 'git config --global init.defaultBranch main'")

# Create test repo with dirty state
machine.succeed("""
su - vpittamp -c '
mkdir -p ~/test-repos && cd ~/test-repos
git init test-project && cd test-project
echo "Initial content" > README.md
git add . && git commit -m "Initial commit"
echo "Modified content" > README.md
echo "New file line 1" > newfile.txt
echo "New file line 2" >> newfile.txt
'
""")

print("\nVM ready! Connect VNC to localhost:5900")
print("Git repos created for Feature 120 testing")
    '';
  };
}
