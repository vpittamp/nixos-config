# Hetzner Cloud Server Configuration
# Primary development workstation with full desktop environment
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration
    ./base.nix

    # Environment check
    ../modules/assertions/hetzner-check.nix

    # Hardware
    ../hardware/hetzner.nix
    
    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")
    
    # Desktop environment
    ../modules/desktop/kde-plasma.nix
    ../modules/desktop/kde-multi-panel.nix  # Multi-monitor panel support
    ../modules/desktop/remote-access.nix
    # ../modules/desktop/firefox-pwa.nix  # Old firefoxpwa-based approach
    # ../modules/desktop/pwa-extensions.nix  # No longer needed with declarative approach
    # ../modules/desktop/pwa-icons-v2.nix  # Replaced by pwa-declarative
    ../modules/desktop/firefoxpwa-full-auto.nix  # Fixed and re-enabled
    ../modules/desktop/xrdp-with-sound.nix  # Custom XRDP with --enable-sound flag
    # ../modules/desktop/xrdp-audio.nix  # Not needed - using services.xrdp.audio.enable instead
    # ../modules/desktop/chromium-policies.nix  # Disabled - reverting certificate handling
    ../modules/desktop/cluster-certificates.nix
    ../modules/desktop/rdp-display.nix
    ../modules/peripherals/logitech-mx-master3.nix
    
    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    ../modules/services/onepassword-automation.nix
    ../modules/services/speech-to-text.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix
    ../modules/desktop/chromium-1password.nix
    
    # Kubernetes modules
    ../modules/kubernetes/agentgateway.nix

    # Tmux Supervisor Dashboard
    # ../modules/tmux-supervisor.nix  # Disabled - missing scripts

    # Multi-Agent Orchestrator
    # ../modules/claude-orchestrator.nix  # Disabled - missing scripts
  ];

  # System identification
  networking.hostName = "nixos-hetzner";
  
  # Boot configuration for Hetzner
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Kernel modules for virtualization
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  
  # Use predictable network interface names
  boot.kernelParams = [ "net.ifnames=0" ];
  
  # Simple DHCP networking (works best with Hetzner)
  networking.useDHCP = true;
  
  # Firewall - open additional ports for services
  networking.firewall.allowedTCPPorts = [
    22     # SSH
    3389   # RDP
    8080   # Web services
  ];
  
  # Set initial password for user (change after first login!)
  users.users.vpittamp.initialPassword = "nixos";
  
  # SSH settings for initial access
  services.openssh.settings = {
    PermitRootLogin = "yes";  # For initial setup, disable later
    PasswordAuthentication = true;  # For initial setup
  };
  
  # Additional packages specific to Hetzner
  environment.systemPackages = with pkgs; [
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
  ];
  
  # Performance tuning for cloud server
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Use X11 session by default for XRDP compatibility
  services.displayManager.defaultSession = lib.mkForce "plasmax11";
  
  # AgentGateway configuration
  services.agentgateway = {
    enable = true;
    autoDeployOnBoot = false;  # Manual deployment for now
    enableAIBackends = true;   # Enable AI routing capabilities
  };

  # Fully Automated PWA Configuration
  programs.firefoxpwa-auto = {
    enable = true;
   autoInstall = true;
   addToTaskbar = true;  # Automatically configure KDE taskbar

   # Define all PWAs declaratively
   pwas = {
     # AI & Productivity
     claude = {
       name = "Claude";
       url = "https://claude.ai";
       manifest = "https://claude.ai/manifest.json";
       icon = ../assets/icons/pwas/claude.png;
       description = "Claude AI Assistant by Anthropic";
       categories = "Utility;Science;";
       keywords = "ai,assistant,anthropic";
     };

     github = {
       name = "GitHub";
       url = "https://github.com";
       manifest = "https://github.com/manifest.json";
       icon = ../assets/icons/pwas/github.png;
       description = "Code hosting and collaboration platform";
       categories = "Development;";
       keywords = "git,code,repository,version control";
     };

     chatgpt = {
       name = "ChatGPT";
       url = "https://chatgpt.com";
       manifest = "https://chatgpt.com/manifest.json";
       icon = ../assets/icons/pwas/chatgpt.png;
       description = "OpenAI ChatGPT Assistant";
       categories = "Utility;Science;";
       keywords = "ai,chat,openai,gpt";
     };

     # Development Tools
     argocd = {
       name = "ArgoCD";
       url = "https://argocd.cnoe.localtest.me:8443";
       id = "01CBD2EC47D2F8D8CF86034280";  # Preserve existing ID
       icon = ../assets/icons/pwas/ArgoCD.png;
       description = "Declarative GitOps CD for Kubernetes";
       categories = "Development;Utility;";
       keywords = "kubernetes,gitops,deployment";
     };

     backstage = {
       name = "Backstage";
       url = "https://backstage.cnoe.localtest.me:8443";
       id = "0199D501A20B94AE3BB038B6BC";  # Preserve existing ID
       icon = ../assets/icons/pwas/Backstage.png;
       description = "Open platform for building developer portals";
       categories = "Development;";
       keywords = "platform,developer,portal";
     };

     gitea = {
       name = "Gitea";
       url = "https://gitea.cnoe.localtest.me:8443";
       id = "01FEA664E5984E1A3E85E944F6";  # Preserve existing ID
       icon = ../assets/icons/pwas/Gitea.png;
       description = "Self-hosted Git service";
       categories = "Development;";
       keywords = "git,repository,self-hosted";
     };

     headlamp = {
       name = "Headlamp";
       url = "https://headlamp.dev";
       id = "0167D0420CC8C9DFCD3751D068";  # Preserve existing ID
       icon = ../assets/icons/pwas/Headlamp.png;
       description = "Kubernetes web UI";
       categories = "Development;System;";
       keywords = "kubernetes,dashboard,ui";
     };

     kargo = {
       name = "Kargo";
       url = "https://kargo.akuity.io";
       id = "01738C30F3A05DAB2C1BC16C0A";  # Preserve existing ID
       icon = ../assets/icons/pwas/Kargo.png;
       description = "Progressive delivery for Kubernetes";
       categories = "Development;";
       keywords = "kubernetes,progressive,delivery";
     };

     # Communication & Social
     gmail = {
       name = "Gmail";
       url = "https://mail.google.com";
       manifest = "https://mail.google.com/mail/manifest.json";
       icon = ../assets/icons/pwas/gmail.png;
       description = "Google email service";
       categories = "Network;Email;";
       keywords = "email,mail,google";
     };

     # Media & Entertainment
     youtube = {
       name = "YouTube";
       url = "https://www.youtube.com";
       id = "019DB7F7C8868D4C4FA0121E19";  # Preserve existing ID
       manifest = "https://www.youtube.com/manifest.json";
       icon = ../assets/icons/pwas/youtube.png;
       description = "Video sharing and streaming platform";
       categories = "AudioVideo;Video;";
       keywords = "video,streaming,media,entertainment";
     };
   };
 };

  # Enable 1Password automation with service account
  services.onepassword-automation = {
    enable = true;
    user = "vpittamp";
  };

  # Enable Speech-to-Text services
  services.speech-to-text = {
    enable = true;
    model = "base.en";  # Good balance of speed and accuracy
    language = "en";
    enableGlobalShortcut = true;
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

  # Tmux Supervisor Dashboard configuration - DISABLED
  # programs.tmuxSupervisor = {
  #   enable = true;
  #   enableKonsoleIntegration = true;
  #   enableSystemdService = false;  # Don't auto-start, launch manually
  # };

  # Multi-Agent Claude Orchestrator configuration - DISABLED
  # programs.claudeOrchestrator = {
  #   enable = true;
  #   cliTool = "claude";  # or "codex-cli"
  #   defaultModel = "opus";
  #   defaultManagers = [ "nixos" "backstage" "stacks" ];
  #   engineersPerManager = 2;
  #   enableKonsoleIntegration = true;
  #   enableSystemdService = false;  # Launch manually
  # };
  # Ensure user is in audio group for audio access
  users.users.vpittamp.extraGroups = lib.mkForce [ "wheel" "networkmanager" "audio" "video" "input" "docker" "libvirtd" ];
  
  # System state version
  system.stateVersion = "24.11";
}
