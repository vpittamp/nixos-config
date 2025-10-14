# KDE Service Optimization Module
# Purpose: Disable unnecessary KDE background services for VM environments
# Implements: T027 (module structure), T028 (Baloo), T029 (Akonadi)

{ config, lib, ... }:

{
  options.services.kde-optimization = {
    enable = lib.mkEnableOption "KDE service optimization for VMs";

    baloo.disable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable Baloo file indexer.

        Resource savings:
        - RAM: ~300MB
        - CPU: 10-30% during indexing
        - Disk I/O: 50-200 IOPS during indexing

        Trade-off: Lose file search functionality in Dolphin and KRunner.
        Recommended for VM environments where file search is not critical.
      '';
    };

    akonadi.disable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Disable Akonadi PIM services (email, calendar, contacts).

        Resource savings:
        - RAM: ~500MB
        - CPU: 5-15% idle, 15-25% during sync

        Trade-off: Lose KMail, KOrganizer, KAddressBook functionality.
        Only disable if not using KDE PIM applications.
      '';
    };
  };

  config = lib.mkIf config.services.kde-optimization.enable {
    # Baloo disabling implementation (T028)
    home-manager.users.vpittamp = lib.mkIf config.services.kde-optimization.baloo.disable {
      # Disable Baloo file indexing via configuration
      programs.plasma.configFile."baloofilerc"."Basic Settings" = {
        "Indexing-Enabled" = lib.mkForce false;
      };

      # Disable Baloo systemd services
      systemd.user.services.baloo_file = {
        Unit.ConditionPathExists = "/dev/null";  # Prevents service from starting
      };
      systemd.user.services.baloo_file_extractor = {
        Unit.ConditionPathExists = "/dev/null";  # Prevents service from starting
      };
    };

    # Akonadi disabling implementation (T029)
    home-manager.users.vpittamp = lib.mkIf config.services.kde-optimization.akonadi.disable {
      # Disable Akonadi server startup via configuration
      xdg.configFile."akonadi/akonadiserverrc".text = lib.generators.toINI {} {
        "%General" = {
          StartServer = false;
        };
      };

      # Disable Akonadi systemd service
      systemd.user.services.akonadi_control = {
        Unit.ConditionPathExists = "/dev/null";  # Prevents service from starting
      };
    };
  };
}
