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
    environment.systemPackages = with pkgs; let
      overlayPackages = import ./overlays/packages.nix { inherit pkgs lib; };
    in [
      # WSL-specific packages only
      wslu              # WSL utilities for Windows integration
      
      # VSCode wrapper for WSL integration
      (pkgs.writeShellScriptBin "code" ''
        # Launch VSCode from WSL
        /mnt/c/Users/VinodPittampalli/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code "$@"
      '')
    ] ++ overlayPackages.allPackages;

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

    # WSL2 clipboard integration (minimal)
    system.activationScripts.wslClipboard = ''
      # Only create clip.exe symlink for WSL2
      if [ -f /mnt/c/Windows/System32/clip.exe ]; then
        mkdir -p /usr/local/bin
        ln -sf /mnt/c/Windows/System32/clip.exe /usr/local/bin/clip.exe
        # Provide a resilient wrapper that prefers wl-copy (WSLg) and falls back to Windows clipboard
        cat > /usr/local/bin/wsl-clip << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Usage: wsl-clip
# Reads stdin and copies to Wayland clipboard if available, otherwise to Windows clipboard
if command -v wl-copy >/dev/null 2>&1; then
  wl-copy --type text/plain 2>/dev/null || cat >/usr/local/bin/.wsl-clip-discard
else
  /mnt/c/Windows/System32/clip.exe
fi
EOF
        chmod +x /usr/local/bin/wsl-clip

        # Provide a paste helper that prefers wl-paste and falls back to Windows clipboard
        cat > /usr/local/bin/wsl-paste << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Usage: wsl-paste
# Prints clipboard contents to stdout, preferring Wayland when available
if command -v wl-paste >/dev/null 2>&1; then
  wl-paste --no-newline 2>/dev/null | sed 's/\r$//'
else
  /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command 'Get-Clipboard -Raw' | sed 's/\r$//'
fi
EOF
        chmod +x /usr/local/bin/wsl-paste

        # Provide a filter to strip emojis and private-use glyphs (Nerd Font icons)
        cat > /usr/local/bin/strip-fancy << 'EOF'
#!/usr/bin/env python3
import sys

def is_private(c):
    o = ord(c)
    return (0xE000 <= o <= 0xF8FF) or (0xF0000 <= o <= 0xFFFFD) or (0x100000 <= o <= 0x10FFFD)

def is_emoji(c):
    o = ord(c)
    return (
        0x1F300 <= o <= 0x1F5FF or  # Misc Symbols & Pictographs
        0x1F600 <= o <= 0x1F64F or  # Emoticons
        0x1F680 <= o <= 0x1F6FF or  # Transport & Map
        0x1F900 <= o <= 0x1F9FF or  # Supplemental Symbols & Pictographs
        0x1FA70 <= o <= 0x1FAFF or  # Symbols & Pictographs Extended-A
        0x2600  <= o <= 0x26FF  or  # Misc Symbols
        0x2700  <= o <= 0x27BF  or  # Dingbats
        0x1F1E6 <= o <= 0x1F1FF     # Regional Indicator Symbols
    )

def main():
    data = sys.stdin.read()
    out = "".join(c for c in data if not (is_private(c) or is_emoji(c)))
    sys.stdout.write(out)

if __name__ == '__main__':
    main()
EOF
        chmod +x /usr/local/bin/strip-fancy

        # Clean copy helper: strip emojis/icons before sending to Windows clipboard
        cat > /usr/local/bin/wsl-clip-clean << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 /usr/local/bin/strip-fancy | /usr/local/bin/clip.exe
EOF
        chmod +x /usr/local/bin/wsl-clip-clean
      fi
    '';

    # Networking configuration
    networking = {
      hostName = "nixos-wsl";
    };


    # Enable nix flakes
    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    system.stateVersion = "25.05";
  }
