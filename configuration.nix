# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

  { config, lib, pkgs, ... }:

  {
    # WSL module is now imported via flake.nix
    # Home Manager is now imported via flake.nix

    # WSL Configuration
    wsl = {
      enable = true;
      defaultUser = "vpittamp";
      startMenuLaunchers = true;

      # Enable VS Code integration

      # WSL-specific configurations
      wslConf = {
        automount.root = "/mnt";
        automount.options = "metadata,umask=22,fmask=11";

        interop = {
          enabled = true;
          appendWindowsPath = true;
        };

        network.generateHosts = true;
      };
    };

    # VS Code Remote Server Fix for WSL
    systemd.user = {
      paths.vscode-remote-workaround = {
        wantedBy = ["default.target"];
        pathConfig.PathChanged = "%h/.vscode-server/bin";
      };

      services.vscode-remote-workaround = {
        description = "VS Code Remote Server Workaround";
        wantedBy = ["default.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for i in ~/.vscode-server/bin/*; do
            if [ -e $i/node ] && [ ! -L $i/node ]; then
              echo "Fixing vscode-server in $i..."
              rm $i/node
              ln -s ${pkgs.nodejs_20}/bin/node $i/node
            fi
          done
        '';
      };
    };

    # Alternative: Use programs.nix-ld for better compatibility
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
        curl
        icu
        libuuid
        libsecret
      ];
    };

    # Create user
    users.users.vpittamp = {
      isNormalUser = true;
      description = "Vinod Pittampalli";
      extraGroups = [
        "wheel"
        "networkmanager"
        "docker"
      ];
      shell = pkgs.bash;
      createHome = true;
      home = "/home/vpittamp";
    };

    # Sudo configuration
    security.sudo = {
      wheelNeedsPassword = true;
      extraRules = [{
        users = [ "vpittamp" ];
        commands = [{
          command = "ALL";
          options = [ "NOPASSWD" ];
        }];
      }];
    };

    nixpkgs.config.allowUnfree = true;

    # Basic system packages
    environment.systemPackages = with pkgs; [
      neovim
      vim
      git
      wget
      curl
      wslu
      nodejs_20
      claude-code
    ];

    # Networking configuration
    networking = {
      hostName = "nixos-wsl";
    };


    # Enable nix flakes
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    system.stateVersion = "25.05";
  }
