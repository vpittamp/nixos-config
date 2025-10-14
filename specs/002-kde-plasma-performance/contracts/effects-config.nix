# Visual Effects Configuration Contract
# Purpose: Defines the interface for KDE visual effects settings
# Module: home-modules/desktop/plasma-config.nix
# Entity: EffectsConfig

{ lib, ... }:

{
  # Desktop effects configuration
  effects = {
    # Expensive effects (high CPU cost)
    blur = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable blur effect behind windows and panels.
        CPU cost: 15-25% in VMs without GPU.
        Disable for VM optimization.
      '';
      example = false;
    };

    backgroundContrast = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable background contrast effect.
        CPU cost: 10-15% in VMs.
        Disable for VM optimization.
      '';
      example = false;
    };

    translucency = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable window translucency effects.
        CPU cost: 10-20% in VMs.
        Disable for VM optimization.
      '';
      example = false;
    };

    wobblyWindows = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable wobbly windows animation effect.
        CPU cost: 8-12% in VMs.
        Disable for VM optimization.
      '';
      example = false;
    };

    magicLamp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable magic lamp minimize/restore animation.
        CPU cost: 5-8% in VMs.
        Disable for VM optimization.
      '';
      example = false;
    };

    desktopCube = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable desktop cube virtual desktop switching.
        CPU cost: 15-25% in VMs.
        Keep disabled.
      '';
      example = false;
    };

    # Acceptable effects (low CPU cost)
    slide = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable slide animation for workspace switching.
        CPU cost: 3-5% (acceptable).
        Set duration to 0 for instant transition.
      '';
      example = true;
    };

    fade = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable fade animation for window open/close.
        CPU cost: 2-4% (acceptable).
        Set duration to 0 for instant transition.
      '';
      example = true;
    };
  };

  # Validation function
  validate = config:
    let
      expensiveEffectsEnabled = lib.any (effect: effect) [
        config.effects.blur
        config.effects.backgroundContrast
        config.effects.translucency
        config.effects.wobblyWindows
        config.effects.magicLamp
        config.effects.desktopCube
      ];
    in
    lib.warnIf expensiveEffectsEnabled
      "Expensive effects enabled - may cause poor performance in VM environments"
      config;
}
