# Hetzner Cloud Server Configuration
# Primary development workstation with full desktop environment
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration
    ./base.nix

    # Disk configuration for nixos-anywhere compatibility
    ../disk-config.nix

    # Environment check
    ../modules/assertions/hetzner-check.nix

    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")
    
    # Phase 1: Core Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    
    # Phase 2: Desktop Environment - Migrated to i3wm (Feature 009)
    # KDE Plasma modules archived to archived/plasma-specific/desktop/
    # ../modules/desktop/kde-plasma.nix  # ARCHIVED
    # ../modules/desktop/remote-access.nix  # Will be replaced by i3-specific modules
    # ../modules/desktop/xrdp-with-sound.nix  # Integrated into hetzner-i3.nix
    # ../modules/desktop/firefox-virtual-optimization.nix  # May still be useful
    # ../modules/desktop/rdp-display.nix  # May still be useful

    # NEW: i3wm desktop environment
    ../modules/desktop/i3wm.nix
    ../modules/desktop/xrdp.nix
    ../modules/desktop/i3-project-workspace.nix  # Feature 010: Project workspace management

    # Services
    ../modules/services/onepassword-automation.nix
    ../modules/services/onepassword-password-management.nix
    ../modules/services/speech-to-text-safe.nix
    ../modules/services/rustdesk.nix # RustDesk remote desktop with autostart
  ];

  # System identification
  networking.hostName = "nixos-hetzner";
  
  # Boot configuration for Hetzner - GRUB for nixos-anywhere compatibility
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  
  # Kernel modules for virtualization
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  
  # Use predictable network interface names
  boot.kernelParams = [ "net.ifnames=0" ];
  
  # Simple DHCP networking (works best with Hetzner)
  networking.useDHCP = true;
  
  # i3 Window Manager (Feature 009)
  services.i3wm.enable = true;

  # XRDP for i3wm remote access
  services.xrdp-i3.enable = true;

  # i3 Project Workspace Management (Feature 010)
  services.i3ProjectWorkspace.enable = true;

  # RustDesk service configuration
  services.rustdesk = {
    enable = true;
    user = "vpittamp";
    enableDirectIpAccess = true;
    permanentPassword = "Nixos123";  # Pre-configured password for headless access
    # Use user-level service for Hetzner (graphical session already running)
    enableSystemService = false;
  };

  # Firewall - open additional ports for services
  networking.firewall = {
    allowedTCPPorts = [
      22     # SSH
      8080   # Web services
      # RustDesk ports managed by rustdesk service
    ];
    interfaces."tailscale0".allowedTCPPorts = [
      3389   # RDP via Tailscale only
    ];
    # Tailscale
    checkReversePath = "loose";
  };
  
  # Enable 1Password password management
  services.onepassword-password-management = {
    enable = true;
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    users.vpittamp = {
      enable = true;
      passwordReference = "op://CLI/NixOS User Password/password";
    };
    updateInterval = "hourly";  # Check for password changes hourly
  };

  # Fallback password for initial setup before 1Password is configured
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";
  
  # SSH settings for initial access
  services.openssh.settings = {
    PermitRootLogin = "yes";  # For initial setup, disable later
    PasswordAuthentication = true;  # For initial setup
  };
  
  # Additional packages specific to Hetzner
  environment.systemPackages = with pkgs; [
    # Firefox PWA support
    # Image processing for PWA icons
    imagemagick  # For converting and manipulating images
    librsvg      # For SVG to PNG conversion

    firefoxpwa  # Native component for Progressive Web Apps

    # Application launcher
    rofi        # Application launcher for i3wm

    # System monitoring
    htop
    btop
    iotop
    nethogs
    neofetch

    # Audio utilities (for testing and management)
    pulseaudio  # For pactl, pacmd, and other audio management tools
    pavucontrol # GUI audio control
    alsa-utils  # For alsamixer and other ALSA utilities

    # Remote access (rustdesk-flutter managed by service module)
    tailscale         # Zero-config VPN
  ];
  
  # Firefox configuration with PWA support
  programs.firefox = {
    enable = lib.mkDefault true;
    nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
  };

  # Performance tuning for cloud server
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Display manager disabled for headless i3wm cloud operation
  # XRDP will start the i3wm session on-demand when you connect
  # No SDDM needed for i3wm (unlike KDE Plasma which required it)
  services.displayManager.sddm.enable = lib.mkForce false;

  # Fully Automated PWA Configuration - Phase 3
  # programs.firefoxpwa-auto = {
  #   enable = true;
  #  autoInstall = true;
  #  addToTaskbar = true;  # Automatically configure KDE taskbar
  #
  #  # Define all PWAs declaratively
  #  pwas = {
  #    # AI & Productivity
  #    claude = {
  #      name = "Claude";
  #      url = "https://claude.ai";
  #      manifest = "https://claude.ai/manifest.json";
  #      icon = ../assets/icons/pwas/claude.png;
  #      description = "Claude AI Assistant by Anthropic";
  #      categories = "Utility;Science;";
  #      keywords = "ai,assistant,anthropic";
  #    };

  #    github = {
  #      name = "GitHub";
  #      url = "https://github.com";
  #      manifest = "https://github.com/manifest.json";
  #      icon = ../assets/icons/pwas/github.png;
  #      description = "Code hosting and collaboration platform";
  #      categories = "Development;";
  #      keywords = "git,code,repository,version control";
  #    };

  #    chatgpt = {
  #      name = "ChatGPT";
  #      url = "https://chatgpt.com";
  #      manifest = "https://chatgpt.com/manifest.json";
  #      icon = ../assets/icons/pwas/chatgpt.png;
  #      description = "OpenAI ChatGPT Assistant";
  #      categories = "Utility;Science;";
  #      keywords = "ai,chat,openai,gpt";
  #    };

  #    # Development Tools
  #    argocd = {
  #      name = "ArgoCD";
  #      url = "https://argocd.cnoe.localtest.me:8443";
  #      id = "01CBD2EC47D2F8D8CF86034280";  # Preserve existing ID
  #      icon = ../assets/icons/pwas/ArgoCD.png;
  #      description = "Declarative GitOps CD for Kubernetes";
  #      categories = "Development;Utility;";
  #      keywords = "kubernetes,gitops,deployment";
  #    };

  #    backstage = {
  #      name = "Backstage";
  #      url = "https://backstage.cnoe.localtest.me:8443";
  #      id = "0199D501A20B94AE3BB038B6BC";  # Preserve existing ID
  #      icon = ../assets/icons/pwas/Backstage.png;
  #      description = "Open platform for building developer portals";
  #      categories = "Development;";
  #      keywords = "platform,developer,portal";
  #    };

  #    gitea = {
  #      name = "Gitea";
  #      url = "https://gitea.cnoe.localtest.me:8443";
  #      id = "01FEA664E5984E1A3E85E944F6";  # Preserve existing ID
  #      icon = ../assets/icons/pwas/Gitea.png;
  #      description = "Self-hosted Git service";
  #      categories = "Development;";
  #      keywords = "git,repository,self-hosted";
  #    };

  #    headlamp = {
  #      name = "Headlamp";
  #      url = "https://headlamp.dev";
  #      id = "0167D0420CC8C9DFCD3751D068";  # Preserve existing ID
  #      icon = ../assets/icons/pwas/Headlamp.png;
  #      description = "Kubernetes web UI";
  #      categories = "Development;System;";
  #      keywords = "kubernetes,dashboard,ui";
  #    };

  #    kargo = {
  #      name = "Kargo";
  #      url = "https://kargo.akuity.io";
  #      id = "01738C30F3A05DAB2C1BC16C0A";  # Preserve existing ID
  #      icon = ../assets/icons/pwas/Kargo.png;
  #      description = "Progressive delivery for Kubernetes";
  #      categories = "Development;";
  #      keywords = "kubernetes,progressive,delivery";
  #    };

  #    # Communication & Social
  #    gmail = {
  #      name = "Gmail";
  #      url = "https://mail.google.com";
  #      manifest = "https://mail.google.com/mail/manifest.json";
  #      icon = ../assets/icons/pwas/gmail.png;
  #      description = "Google email service";
  #      categories = "Network;Email;";
  #      keywords = "email,mail,google";
  #    };

  #    # Media & Entertainment
  #    youtube = {
  #      name = "YouTube";
  #      url = "https://www.youtube.com";
  #      id = "019DB7F7C8868D4C4FA0121E19";  # Preserve existing ID
  #      manifest = "https://www.youtube.com/manifest.json";
  #      icon = ../assets/icons/pwas/youtube.png;
  #      description = "Video sharing and streaming platform";
  #      categories = "AudioVideo;Video;";
  #      keywords = "video,streaming,media,entertainment";
  #    };
  #  };
  # };

  # Enable 1Password automation with service account
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
    tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
  };

  # Note: Certificate sync is handled once at cluster creation via
  # ~/stacks/ref-implementation/recreate-cluster-with-ssh.sh
  # The cluster-certificates.nix module is disabled to prevent ongoing sync issues

  # Enable Speech-to-Text services using safe module
  services.speech-to-text = {
    enable = true;
    model = "base.en";  # Good balance of speed and accuracy
    language = "en";
    enableGlobalShortcut = true;
    voskModelPackage = pkgs.callPackage ../pkgs/vosk-model-en-us-0.22-lgraph.nix {};
  };

  # PWA extensions are handled by regular Firefox profile now
  # (1Password and other extensions work normally in Firefox windows)

  # Audio configuration for XRDP
  # IMPORTANT: PulseAudio works better with XRDP audio redirection
  # Disable PipeWire and use PulseAudio instead for proper RDP audio
  services.pipewire.pulse.enable = lib.mkForce false;
  services.pipewire.enable = lib.mkForce false;

  services.pulseaudio = {
    enable = lib.mkForce true;
    package = pkgs.pulseaudioFull;
    extraModules = [ pkgs.pulseaudio-module-xrdp ];
    extraConfig = ''
      .ifexists module-xrdp-sink.so
      load-module module-xrdp-sink
      .endif
      .ifexists module-xrdp-source.so
      load-module module-xrdp-source
      .endif
    '';
  };

  # Enable rtkit for better audio performance
  security.rtkit.enable = true;

  # Ensure user is in audio group for audio access
  users.users.vpittamp.extraGroups = lib.mkForce [ "wheel" "networkmanager" "audio" "video" "input" "docker" "libvirtd" ];

  # ========== TAILSCALE ==========
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # System state version
  system.stateVersion = "24.11";
}
