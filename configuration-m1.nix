# NixOS configuration for M1 MacBook Pro (bare metal)
{ config, lib, pkgs, ... }:

{
  # System version
  system.stateVersion = "24.05";

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "vpittamp" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Boot and kernel
  boot = {
    # Clean /tmp on boot
    tmp.cleanOnBoot = true;
    
    # Kernel parameters for Apple Silicon
    kernelParams = [ 
      "quiet"
      "splash"
    ];
  };

  # Timezone and locale
  time.timeZone = "America/Los_Angeles";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  # Networking
  networking = {
    hostName = "nixos-m1";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];  # SSH
    };
  };

  # Users
  users.users.vpittamp = {
    isNormalUser = true;
    description = "Vinod Pittampalli";
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" ];
    shell = pkgs.bash;
    hashedPassword = "$6$rounds=100000$Km5MQm.Q5TGwTg6m$iXGppJ0SRTLso71vYJXxfI0nX3MYdJhL8DlpfINPNNnPYmRrGutEQPQq/N0c1xx/2TZKlMPU8B9OWaveHMzSN.";
  };

  # Enable sudo
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  # System packages
  environment.systemPackages = with pkgs; 
    let 
      vscode-with-wayland = vscode.overrideAttrs (oldAttrs: {
        commandLineArgs = "--enable-features=UseOzonePlatform --ozone-platform=wayland";
      });
    in [
      # Core tools
      neovim
      git
      htop
      tmux
      tailscale
      networkmanager
      networkmanagerapplet
      vim
      wget
      curl
      tree
      unzip
      zip
      ripgrep
      fd
      bat
      eza
      fzf
      jq
      
      # Development tools
      gcc
      gnumake
      python3
      nodejs_20
      nodePackages.npm
      go
      rustc
      cargo
      
      # System tools
      pciutils
      usbutils
      lshw
      
      # Network tools
      iw
      wirelesstools
      dig
      nmap
      netcat
      
      # Nix tools
      nix-prefetch-git
      nixpkgs-fmt
      nil
      nh
      
      # GUI applications
      vscode-with-wayland
      firefox-wayland
      chromium
    ];

  # Services
  services = {
    # SSH daemon
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true;
      };
    };

    # Tailscale VPN
    tailscale.enable = true;

    # Docker (if needed)
    # docker = {
    #   enable = true;
    #   enableOnBoot = true;
    # };

    # Automatic upgrades
    # system.autoUpgrade = {
    #   enable = true;
    #   allowReboot = false;
    # };
  };

  # Programs
  programs = {
    bash.completion.enable = true;
    mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    
    # Sway window manager
    sway = {
      enable = true;
      wrapperFeatures.gtk = true;
      extraPackages = with pkgs; [
        swaylock
        swayidle
        wl-clipboard
        mako
        alacritty
        foot
        wofi
        waybar
        grim
        slurp
        wf-recorder
        light
        pavucontrol
      ];
    };
    
    # Enable Wayland support in Firefox
    firefox.nativeMessagingHosts.packages = [ ];
  };

  # Environment variables
  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

  # Console configuration
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Documentation
  documentation = {
    enable = true;
    man.enable = true;
    info.enable = true;
  };
  
  # XDG desktop portal for Wayland
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  
  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    jetbrains-mono
    font-awesome
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];
}