# KubeVirt VM Configuration - Full Production Image (Runtime Configuration)
#
# Strategy: Two-Image Approach
# =============================
# This is the FULL Hetzner-equivalent configuration with home-manager integration.
# It is NOT used for initial image builds, but applied at runtime via nixos-rebuild.
#
# Initial Boot: kubevirt-desktop.nix (minimal base image, ~2-3 GB, fast boot)
# Production: THIS FILE (full features, matches Hetzner exactly)
#
# Apply this configuration inside a running KubeVirt VM:
#   sudo nixos-rebuild switch --flake github:vpittamp/nixos-config#vm-hetzner
#
# This configuration is identical to hetzner.nix, ensuring production VMs match
# the local Hetzner development workstation for consistency.
#
# Full-featured development workstation with KDE Plasma desktop environment
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration
    ./base.nix

    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")

    # Phase 1: Core Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix

    # Phase 2: Desktop Environment
    ../modules/desktop/kde-plasma.nix
    ../modules/desktop/remote-access.nix
    ../modules/desktop/xrdp-with-sound.nix
    # Note: firefox-virtual-optimization.nix requires home-manager (not available in image build)
    # Firefox optimizations can be configured manually after VM deployment
    ../modules/desktop/rdp-display.nix

    # Services
    ../modules/services/onepassword-automation.nix
    ../modules/services/speech-to-text-safe.nix
  ];

  # System identification
  networking.hostName = "nixos-kubevirt-vm";

  # Boot configuration for KubeVirt
  # CRITICAL: No GRUB for VMs - KubeVirt boots via hypervisor
  boot.loader = {
    grub.enable = lib.mkForce false;
    systemd-boot.enable = false;
    timeout = 0;
  };

  # Cloud-init support for KubeVirt (REQUIRED)
  # This allows dynamic configuration via cloud-init from VirtualMachine spec
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # Kernel modules for virtualization
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  # Filesystem configuration for pre-built VM image
  # The qcow2 image already has partitions set up
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # Simple DHCP networking (works best with KubeVirt pod network)
  networking.useDHCP = true;

  # Firewall - open ports for services
  # Note: In KubeVirt, ports are exposed via Service resources, not directly
  networking.firewall.allowedTCPPorts = [
    22     # SSH
    3389   # RDP
    8080   # Web services
  ];

  # Enable root login for emergency console access
  users.users.root.initialHashedPassword = "";  # Empty password for root
  services.openssh.settings.PermitRootLogin = "yes";

  # Firefox optimizations for virtual environment (from firefox-virtual-optimization.nix)
  environment.sessionVariables = {
    # Force software rendering for Firefox
    MOZ_DISABLE_RDD_SANDBOX = "1";
    MOZ_X11_EGL = "0";  # Disable EGL on X11
    LIBGL_ALWAYS_SOFTWARE = "1";  # Force software rendering

    # WebRender software mode
    MOZ_WEBRENDER = "1";
    MOZ_WEBRENDER_COMPOSITOR = "0";  # Disable compositor

    # Disable GPU process
    MOZ_DISABLE_GPU_PROCESS = "1";
  };

  # Additional packages (same as Hetzner)
  environment.systemPackages = with pkgs; [
    # Firefox PWA support
    imagemagick  # For converting and manipulating images
    librsvg      # For SVG to PNG conversion
    firefoxpwa   # Native component for Progressive Web Apps

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

  # Firefox configuration with PWA support
  programs.firefox = {
    enable = lib.mkDefault true;
    nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
  };

  # Performance tuning for VM
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Disable SDDM display manager for headless cloud operation
  # Critical: This prevents auto-starting a console KDE session on boot
  # Without this, both console (tty2) and RDP would try to run KDE simultaneously,
  # causing D-Bus conflicts and breaking global shortcuts and other services
  # XRDP will start the single KDE session on-demand when you connect
  services.displayManager.sddm.enable = lib.mkForce false;

  # Use X11 session by default for XRDP compatibility
  services.displayManager.defaultSession = lib.mkForce "plasmax11";

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
    voskModelPackage = pkgs.callPackage ../pkgs/vosk-model-en-us-0.22-lgraph.nix {};
  };

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

  # System state version
  system.stateVersion = lib.mkDefault "24.11";
}
