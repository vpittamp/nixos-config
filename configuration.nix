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
          appendWindowsPath = false;  # Changed to false for Docker Desktop
        };

        network.generateHosts = false;  # Changed to false for Docker Desktop
      };
    
    # Docker Desktop integration  
    docker-desktop.enable = false;  # Keep false, enable from Windows side
    
    # Extra binaries needed for Docker Desktop wsl-distro-proxy
    extraBin = with pkgs; [
      { src = "${coreutils}/bin/mkdir"; }
      { src = "${coreutils}/bin/cat"; }
      { src = "${coreutils}/bin/whoami"; }
      { src = "${coreutils}/bin/ls"; }
      { src = "${busybox}/bin/addgroup"; }
      { src = "${su}/bin/groupadd"; }
      { src = "${su}/bin/usermod"; }
    ];
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

    # 1Password configuration
    programs._1password.enable = true;
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "vpittamp" ];
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
      # Docker tools for Docker Desktop integration
      docker-compose    # Docker Compose for multi-container apps
    ];

    # Enable Docker (native NixOS docker package)
    # Temporarily disabled to use Docker Desktop integration
    virtualisation.docker = {
      enable = false;  # Changed to false to use Docker Desktop
      enableOnBoot = false;
      autoPrune.enable = false;
    };
    
    # Patch the docker-desktop-proxy script
    systemd.services.docker-desktop-proxy.script = lib.mkForce ''
      ${config.wsl.wslConf.automount.root}/wsl/docker-desktop/docker-desktop-user-distro proxy --docker-desktop-root ${config.wsl.wslConf.automount.root}/wsl/docker-desktop "C:\Program Files\Docker\Docker\resources"
    '';
    
    # Create Docker Desktop wrapper script and symlink
    system.activationScripts.dockerDesktopIntegration = ''
      # Create docker wrapper script
      mkdir -p /etc/nixos
      cat > /etc/nixos/docker-wrapper.sh << 'EOF'
#!/bin/bash
# Docker Desktop wrapper script for NixOS WSL2
exec sudo DOCKER_HOST=unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock /mnt/wsl/docker-desktop/cli-tools/usr/bin/docker "$@"
EOF
      chmod +x /etc/nixos/docker-wrapper.sh
      
      # Create symlink for docker command
      mkdir -p /usr/local/bin
      ln -sf /etc/nixos/docker-wrapper.sh /usr/local/bin/docker
    '';

    # Networking configuration
    networking = {
      hostName = "nixos-wsl";
    };


    # Enable nix flakes
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    system.stateVersion = "25.05";
  }
