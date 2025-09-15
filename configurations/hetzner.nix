# Hetzner Cloud Server Configuration
# Primary development workstation with full desktop environment
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Base configuration
    ./base.nix
    
    # Hardware
    ../hardware/hetzner.nix
    
    # QEMU guest optimizations
    (modulesPath + "/profiles/qemu-guest.nix")
    
    # Desktop environment
    ../modules/desktop/kde-plasma.nix
    ../modules/desktop/remote-access.nix
    ../modules/desktop/xrdp-with-sound.nix  # Custom XRDP with --enable-sound flag
    # ../modules/desktop/xrdp-audio.nix  # Not needed - using services.xrdp.audio.enable instead
    # ../modules/desktop/chromium-policies.nix  # Disabled - reverting certificate handling
    # ../modules/desktop/cluster-certificates.nix  # Disabled - reverting certificate handling
    ../modules/desktop/rdp-display.nix
    
    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
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
  ];
  
  # Performance tuning for cloud server
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Audio: prefer PulseAudio for XRDP redirection; disable PipeWire's Pulse shim
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
  users.users.vpittamp.extraGroups = lib.mkAfter [ "audio" ];
  
  # System state version
  system.stateVersion = "24.11";
}

