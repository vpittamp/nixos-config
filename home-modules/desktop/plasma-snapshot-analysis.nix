{ lib, config, ... }:
# Plasma Snapshot Analysis Module
#
# This module imports the plasma-rc2nix snapshot for REFERENCE ONLY.
# It filters out system-generated IDs and runtime state to help identify:
# 1. What settings are captured in the snapshot but not managed declaratively
# 2. What GUI changes you've made that should be adopted into declarative config
# 3. The difference between your current state and declarative intent
#
# Usage:
#   1. Make GUI changes in KDE
#   2. Run: plasma-export (or plasma-sync snapshot)
#   3. Compare snapshot with declarative config
#   4. Adopt useful settings into plasma-config.nix
#
# This module DOES NOT apply the snapshot - it only provides analysis tools.

let
  # Import the generated snapshot
  generatedSnapshot = import ./generated/plasma-rc2nix.nix { inherit lib; };
  rawConfig = generatedSnapshot.programs.plasma.configFile or {};

  # System-generated patterns to filter out
  systemGeneratedPatterns = {
    # Virtual desktop IDs (UUIDs that change per system)
    virtualDesktopIds = [ "Id_1" "Id_2" "Id_3" "Id_4" ];

    # Activity-related dynamic state
    activityState = [
      "currentActivity"
      "runningActivities"
      "stoppedActivities"
    ];

    # Timestamp fields
    timestamps = [
      "ViewPropsTimestamp"
      "timestamp"
      "Timestamp"
    ];

    # Database/version fields
    versions = [
      "dbVersion"
      "version"
    ];
  };

  # Helper: Check if a key matches system-generated patterns
  isSystemGenerated = key:
    # UUID patterns
    (lib.hasInfix "-" key && lib.stringLength key == 36) ||
    # Virtual desktop IDs
    (builtins.elem key systemGeneratedPatterns.virtualDesktopIds) ||
    # Starts with SubSession
    (lib.hasPrefix "SubSession:" key) ||
    # Starts with Tiling/ (layout UUIDs)
    (lib.hasPrefix "Tiling/" key) ||
    # Activities/LastVirtualDesktop mappings
    (lib.hasPrefix "Activities/" key);

  # Helper: Check if a value should be filtered
  shouldFilterValue = attrName: value:
    # Timestamps
    (builtins.elem attrName systemGeneratedPatterns.timestamps) ||
    # Activity state
    (builtins.elem attrName systemGeneratedPatterns.activityState) ||
    # Versions
    (builtins.elem attrName systemGeneratedPatterns.versions);

  # Filter a config section recursively
  filterSection = section:
    lib.filterAttrs
      (key: value:
        # Keep if not system-generated
        !(isSystemGenerated key) &&
        !(shouldFilterValue key value)
      )
      (lib.mapAttrs
        (key: value:
          # Recursively filter nested attrsets
          if lib.isAttrs value && !lib.isDerivation value
          then filterSection value
          else value
        )
        section
      );

  # Filter entire config files
  filterConfigFile = configFile:
    lib.filterAttrs
      (section: attrs:
        let filtered = filterSection attrs;
        in filtered != {}
      )
      configFile;

  # Categorize settings by whether they're managed declaratively
  categorizeSettings = {
    # Settings we manage declaratively in plasma-config.nix
    managedDeclaratively = {
      kwinrc = [
        "Compositing"
        "Windows"
        "Plugins"
        "Effect-Overview"
        "Effect-PresentWindows"
        "TabBox"
        "Desktops" # We manage Number and Rows, not IDs
      ];
      kwalletrc = [ "Wallet" ];
      ksmserverrc = [ "General" ];
      yakuakerc = [ "Shortcuts" ];
    };

    # Settings we should consider managing
    shouldConsider = {
      baloofilerc = [ "Basic Settings" "General" ];
      dolphinrc = [ "General" "KFileDialog Settings" "Search" ];
      katerc = [ "General" "filetree" ];
      plasmanotifyrc = [ "*" ]; # All notification settings
      spectaclerc = [ "*" ]; # Screenshot tool preferences
    };

    # Settings that are purely runtime state (ignore)
    runtimeState = {
      kactivitymanagerdrc = [ "main" ]; # current/running activities
      kwinrc = [
        "Activities/LastVirtualDesktop"
        "SubSession:*"
        "Tiling/*"
        "Desktops" # Only the IDs, not Number/Rows
      ];
    };
  };

  # Extract settings we should consider managing
  settingsToConsider = lib.mapAttrs
    (file: sections:
      let
        fileConfig = rawConfig.${file} or {};
      in
        if sections == [ "*" ]
        then filterConfigFile fileConfig
        else lib.filterAttrs
          (section: _: builtins.elem section sections)
          fileConfig
    )
    categorizeSettings.shouldConsider;

  # Compare: What's in snapshot but not in our declarative config?
  snapshotOnly = lib.filterAttrs
    (file: _: !(lib.hasAttr file categorizeSettings.managedDeclaratively))
    (lib.filterAttrs
      (file: _: file != "kwinrulesrc") # Already handled by kwin-window-rules.nix
      rawConfig
    );

in {
  # Export analysis data for debugging/inspection
  # Access via: nix eval .#nixosConfigurations.hetzner.config.home-manager.users.vpittamp.plasma.analysis
  options.plasma.analysis = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "Plasma configuration snapshot analysis";
  };

  config.plasma.analysis = {
    # Full raw snapshot (unfiltered)
    raw = rawConfig;

    # Filtered snapshot (system IDs removed)
    filtered = lib.mapAttrs (_: filterConfigFile) rawConfig;

    # Settings we should consider managing declaratively
    recommendations = settingsToConsider;

    # Settings in snapshot but not managed declaratively
    unmanaged = snapshotOnly;

    # Categorization for reference
    categories = categorizeSettings;

    # Summary statistics
    summary = {
      totalConfigFiles = builtins.length (lib.attrNames rawConfig);
      managedFiles = builtins.length (lib.attrNames categorizeSettings.managedDeclaratively);
      recommendedFiles = builtins.length (lib.attrNames categorizeSettings.shouldConsider);
      unmanagedFiles = builtins.length (lib.attrNames snapshotOnly);
    };
  };

  # This module is for analysis only - no packages needed
  # Use plasma-sync commands to work with snapshots
}
