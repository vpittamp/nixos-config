# Bare Metal Optimizations Module
# Features that are only available on physical x86_64 hardware
# (not available on: Hetzner VM, M1/Asahi, WSL2)
#
# These features require:
# - Physical hardware access (KVM, TPM, fingerprint readers)
# - Native GPU (hardware video encoding/decoding)
# - Full Linux kernel (not virtualized or ARM)
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.bare-metal;
in
{
  options.services.bare-metal = {
    enable = mkEnableOption "bare-metal optimizations for physical x86_64 hardware";

    enableVirtualization = mkOption {
      type = types.bool;
      default = true;
      description = "Enable full KVM virtualization with virt-manager";
    };

    enablePodman = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Podman rootless containers (in addition to Docker)";
    };

    enablePrinting = mkOption {
      type = types.bool;
      default = true;
      description = "Enable CUPS printing support";
    };

    enableScanning = mkOption {
      type = types.bool;
      default = false;
      description = "Enable SANE scanner support";
    };

    enableGaming = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gaming support (Steam, GameMode, MangoHud)";
    };

    enableFingerprint = mkOption {
      type = types.bool;
      default = false;
      description = "Enable fingerprint reader support (fprintd)";
    };

    enableSecureBoot = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Secure Boot tooling (sbctl)";
    };
  };

  config = mkIf cfg.enable {
    # ========== FULL KVM VIRTUALIZATION ==========
    # Not possible on: Hetzner (no nested KVM), M1 (ARM), WSL2 (no KVM)
    virtualisation.libvirtd = mkIf cfg.enableVirtualization {
      enable = true;
      qemu = {
        package = lib.mkDefault pkgs.qemu_kvm;
        runAsRoot = lib.mkDefault true;
        swtpm.enable = lib.mkDefault true;  # Software TPM for VM testing
        # OVMF (UEFI) images are now automatically available with QEMU
      };
    };

    # virt-manager GUI for VM management
    programs.virt-manager.enable = mkIf cfg.enableVirtualization true;

    # ========== PODMAN ROOTLESS CONTAINERS ==========
    # Complement to Docker - better for user-space containers
    virtualisation.podman = mkIf cfg.enablePodman {
      enable = true;
      dockerCompat = false;  # Don't replace docker - run alongside
      defaultNetwork.settings.dns_enabled = true;

      # Enable rootless support
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    # Container networking for Podman
    virtualisation.containers.enable = mkIf cfg.enablePodman true;

    # ========== PRINTING (CUPS) ==========
    # Not useful on: Hetzner (headless server), WSL2 (use Windows printing)
    services.printing = mkIf cfg.enablePrinting {
      enable = true;
      drivers = with pkgs; [
        gutenprint        # Wide printer support
        hplip            # HP printers
        brlaser          # Brother laser printers
      ];
      browsing = true;
      defaultShared = false;
    };

    # Avahi for network printer discovery
    services.avahi = mkIf cfg.enablePrinting {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # ========== SCANNING (SANE) ==========
    hardware.sane = mkIf cfg.enableScanning {
      enable = true;
      extraBackends = [ pkgs.sane-airscan ];  # Network scanner support
    };

    # ========== GAMING SUPPORT ==========
    # Not possible on: Hetzner (no GPU), M1 (ARM - limited game support)
    programs.steam = mkIf cfg.enableGaming {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      gamescopeSession.enable = true;  # Steam Deck-like gaming mode
    };

    # GameMode - optimize system for gaming
    programs.gamemode = mkIf cfg.enableGaming {
      enable = true;
      enableRenice = true;
      settings = {
        general = {
          renice = 10;
          softrealtime = "auto";
          inhibit_screensaver = 1;
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
        };
      };
    };

    # ========== FINGERPRINT READER ==========
    # Hardware-specific - only on laptops with fingerprint sensors
    services.fprintd = mkIf cfg.enableFingerprint {
      enable = true;
    };

    # PAM configuration for fingerprint auth
    security.pam.services = mkIf cfg.enableFingerprint {
      login.fprintAuth = true;
      sudo.fprintAuth = true;
      # Don't enable for greetd - it can cause issues with auto-login
    };

    # ========== HARDWARE VIDEO ACCELERATION ==========
    # Full hardware video encoding/decoding (not available on Hetzner pixman renderer)
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    # ========== TPM 2.0 SUPPORT ==========
    # Available on modern x86_64 systems, not on VMs or ARM
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;  # TPM-backed PKCS#11
      tctiEnvironment.enable = true;
    };

    # ========== SUSPEND/HIBERNATE ==========
    # Full power management (not useful on: Hetzner server, WSL2)
    services.logind = {
      lidSwitch = "suspend";
      lidSwitchExternalPower = "lock";
      settings.Login = {
        HandlePowerKey = "suspend";
        IdleAction = "suspend";
        IdleActionSec = "30min";
      };
    };

    # ========== ADDITIONAL PACKAGES ==========
    environment.systemPackages = with pkgs; [
      # Secure Boot tooling (when enabled)
    ] ++ optionals cfg.enableSecureBoot [
      sbctl  # Secure Boot key management
    ] ++ optionals cfg.enableVirtualization [
      virt-viewer      # Remote VM viewer
      spice-gtk        # SPICE client for VMs
      vagrant          # VM provisioning
    ] ++ optionals cfg.enablePodman [
      podman-compose   # Docker Compose alternative
      podman-tui       # TUI for Podman
      buildah          # Container image builder
      skopeo           # Container image management
    ] ++ optionals cfg.enableGaming [
      mangohud         # Performance overlay
      gamemode         # Game performance optimizer
      protonup-qt      # Proton version manager
      lutris           # Game launcher
      wine-wayland     # Windows compatibility layer
      winetricks       # Wine helper
    ] ++ optionals cfg.enablePrinting [
      system-config-printer  # Printer configuration GUI
    ] ++ optionals cfg.enableScanning [
      simple-scan      # Scanner GUI
    ] ++ [
      # Always include these on bare metal
      dmidecode        # Hardware information (SMBIOS/DMI)
      lm_sensors       # Hardware monitoring
      i2c-tools        # I2C/SMBus tools
      smartmontools    # S.M.A.R.T. disk monitoring
      nvme-cli         # NVMe management
      hdparm           # HDD/SSD parameters
      tpm2-tools       # TPM 2.0 utilities
      efibootmgr       # EFI boot manager
      efitools         # EFI tools
      fwupd            # Firmware updates (GUI via gnome-firmware)
      gnome-firmware   # Firmware update GUI
    ];

    # User groups for hardware access
    users.users.vpittamp.extraGroups = mkMerge [
      [ "tss" ]  # TPM access
      (mkIf cfg.enableVirtualization [ "libvirtd" "kvm" ])
      (mkIf cfg.enablePrinting [ "lp" ])
      (mkIf cfg.enableScanning [ "scanner" ])
    ];

    # ========== FIREWALL FOR LOCAL SERVICES ==========
    networking.firewall = mkMerge [
      (mkIf cfg.enablePrinting {
        allowedTCPPorts = [ 631 ];  # CUPS
        allowedUDPPorts = [ 631 ];
      })
    ];
  };
}
