# WSL Configuration
# Windows Subsystem for Linux environment (legacy, not primary)
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Base configuration
    ./base.nix
    
    # WSL module
    inputs.nixos-wsl.nixosModules.wsl
    
    # Services (no desktop needed in WSL)
    ../modules/services/development.nix
    ../modules/services/networking.nix
  ];

  # WSL Configuration
  wsl = {
    enable = true;
    defaultUser = "vpittamp";
    startMenuLaunchers = true;
    
    # WSL-specific configurations
    wslConf = {
      automount.root = "/mnt";
      automount.options = "metadata,umask=22,fmask=11";
      
      interop = {
        enabled = true;
        appendWindowsPath = false;  # Clean PATH for Docker Desktop
      };
      
      network.generateHosts = false;  # For Docker Desktop compatibility
    };
    
    # Docker Desktop integration
    docker-desktop.enable = false;  # Enable from Windows side
    
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
      enable = true;
      wantedBy = ["default.target"];
      
      pathConfig.PathChanged = "%h/.vscode-server/bin";
    };
    
    services.vscode-remote-workaround = {
      enable = true;
      
      script = ''
        for i in ~/.vscode-server/bin/*; do
          if [ -e "$i/node" ] && [ ! -e "$i/node-orig" ]; then
            mv "$i/node" "$i/node-orig"
            ln -s "${pkgs.nodejs_20}/bin/node" "$i/node"
          fi
        done
      '';
    };
  };

  # System identification
  networking.hostName = "nixos-wsl";
  
  # Disable Tailscale in WSL (use Windows Tailscale instead)
  services.tailscale.enable = lib.mkForce false;
  
  # Additional WSL-specific packages
  environment.systemPackages = with pkgs; [
    wslu  # WSL utilities
    wsl-open
  ];

  # Performance optimizations for WSL
  boot.kernelParams = [ "cgroup_no_v1=all" "systemd.unified_cgroup_hierarchy=yes" ];
  
  # System state version
  system.stateVersion = "24.11";
}