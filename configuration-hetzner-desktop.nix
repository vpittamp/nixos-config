# Full NixOS configuration for Hetzner Cloud with KDE Plasma 6
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./hardware-configuration.nix  # Will use the generated one on server
  ];

  # Boot configuration for UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Kernel modules
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  
  # Clean /tmp on boot
  boot.tmp.cleanOnBoot = true;

  # Hostname
  networking.hostName = "nixos-hetzner";
  
  # Simple DHCP networking (works best with Hetzner)
  networking.useDHCP = true;
  
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      22     # SSH
      3389   # RDP
      5900   # VNC
      8080   # Web services
      3000   # Development servers
      5173   # Vite
    ];
    allowedUDPPorts = [ 
      3389   # RDP
      41641  # Tailscale
    ];
  };

  # Time zone and locale
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable X11 and KDE Plasma 6
  services.xserver = {
    enable = true;
    
    # Display manager
    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      defaultSession = "plasma";  # Use Wayland by default
      
      # Auto-login for headless server (optional)
      # autoLogin = {
      #   enable = true;
      #   user = "vpittamp";
      # };
    };
    
    # Desktop environment
    desktopManager.plasma6.enable = true;
    
    # Configure for headless operation with virtual display
    videoDrivers = [ "modesetting" "fbdev" ];
    
    # Enable DRI for better performance
    deviceSection = ''
      Option "DRI" "3"
      Option "AccelMethod" "glamor"
    '';
  };

  # Enable RDP for remote desktop access
  services.xrdp = {
    enable = true;
    defaultWindowManager = "startplasma-x11";
    openFirewall = true;
    port = 3389;
  };

  # Sound
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
      X11Forwarding = true;  # Enable X11 forwarding for GUI apps
    };
  };

  # Enable Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # Enable Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # Enable libvirt for VMs
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };

  # Root user
  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
  };

  # Your user account
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" "docker" "libvirtd" "audio" "video" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDzhOKvFTkdSY8/WpeOxd7ZTII7I+klKhiIJxRdMfM5+ vpittamp@devcontainer"
    ];
    # Set initial password (change after first login)
    initialPassword = "nixos";
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # System packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    vim
    git
    wget
    curl
    htop
    tmux
    tree
    ripgrep
    fd
    ncdu
    rsync
    
    # Desktop utilities
    firefox
    chromium
    kate
    konsole
    dolphin
    ark
    spectacle
    
    # Development tools
    vscode
    docker-compose
    kubectl
    terraform
    
    # Remote access tools
    remmina
    tigervnc
    
    # System tools
    tailscale
    neofetch
    btop
    iotop
    nethogs
    
    # Build tools
    gcc
    gnumake
    cmake
    pkg-config
    
    # Nix tools
    nix-prefetch-git
    nixpkgs-fmt
    nh
  ];

  # Enable Nix flakes
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" ];
      auto-optimise-store = true;
      
      # Use cachix for faster builds
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    
    # Garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable flatpak for additional apps
  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

  # Enable CUPS for printing
  services.printing.enable = true;

  # Enable bluetooth (if needed)
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # System state version
  system.stateVersion = "25.05";
}