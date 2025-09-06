# NixOS configuration for M1 MacBook Pro (bare metal)
{ config, lib, pkgs, ... }:

{
  # Import shared package configuration
  imports = [
    ./shared/package-lists.nix
  ];

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
  environment.systemPackages = let
    packageConfig = config.packageConfiguration;
  in
    packageConfig.getProfile.system ++ [
      # Additional bare metal tools
      pkgs.neovim
      pkgs.git
      pkgs.htop
      pkgs.tmux
      pkgs.tailscale
      pkgs.networkmanager
      pkgs.networkmanagerapplet
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
    bash.enableCompletion = true;
    mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  # Environment variables
  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
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
}