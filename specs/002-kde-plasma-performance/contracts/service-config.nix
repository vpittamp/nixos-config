# Desktop Service Configuration Contract
# Purpose: Defines the interface for KDE background service management
# Module: modules/services/kde-optimization.nix (to be created)
# Entity: ServiceConfig

{ lib, config, ... }:

{
  options.services.kde-optimization = {
    enable = lib.mkEnableOption "KDE performance optimization for VM environments";

    # Baloo file indexer settings
    baloo = {
      disable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Disable Baloo file indexer completely.

          Resource savings:
          - RAM: ~300MB
          - CPU: 10-30% during indexing
          - Disk I/O: 50-200 IOPS during indexing

          Trade-off: Lose file search functionality in Dolphin.
          Recommended for VM environments where file search not critical.
        '';
        example = true;
      };
    };

    # Akonadi PIM services settings
    akonadi = {
      disable = lib.mkOption {
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
        example = true;
      };
    };

    # KDE Connect settings
    kdeConnect = {
      disable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Disable KDE Connect (mobile device integration).

          Resource savings:
          - RAM: ~50MB
          - CPU: <5%

          Trade-off: Lose mobile device integration features.
          Disable if not using KDE Connect with mobile devices.
        '';
        example = false;
      };
    };
  };

  config = lib.mkIf config.services.kde-optimization.enable {
    # Baloo disabling implementation
    home.file = lib.mkIf config.services.kde-optimization.baloo.disable {
      ".config/baloofilerc".text = lib.generators.toINI {} {
        "Basic Settings" = {
          Indexing-Enabled = false;
        };
      };
    };

    systemd.user.services = lib.mkMerge [
      # Disable Baloo services
      (lib.mkIf config.services.kde-optimization.baloo.disable {
        baloo_file.enable = false;
        baloo_file_extractor.enable = false;
      })

      # Disable Akonadi services
      (lib.mkIf config.services.kde-optimization.akonadi.disable {
        akonadi_control.enable = false;
        # Additional Akonadi services are stopped automatically when control is disabled
      })

      # Disable KDE Connect
      (lib.mkIf config.services.kde-optimization.kdeConnect.disable {
        kdeconnect.enable = false;
        kdeconnect-indicator.enable = false;
      })
    ];

    # Akonadi configuration
    home.file = lib.mkIf config.services.kde-optimization.akonadi.disable {
      ".config/akonadi/akonadiserverrc".text = lib.generators.toINI {} {
        "%General" = {
          StartServer = false;
        };
      };
    };
  };

  # Validation function
  validate = config:
    assert lib.assertMsg
      (config.services.kde-optimization.enable ->
        (config.services.kde-optimization.baloo.disable ||
         config.services.kde-optimization.akonadi.disable))
      "kde-optimization enabled but no services disabled - enable has no effect";
    config;
}
