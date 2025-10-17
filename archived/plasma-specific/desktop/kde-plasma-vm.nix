{ config, lib, pkgs, ... }:

{
  options.desktop.kde-vm-optimization = {
    enable = lib.mkEnableOption "KDE Plasma VM performance optimizations";

    # Compositor configuration options (T007)
    compositor = {
      backend = lib.mkOption {
        type = lib.types.enum [ "OpenGL" "XRender" ];
        default = "XRender";
        description = ''
          Compositor rendering backend.
          - OpenGL: GPU-accelerated (requires GPU or uses slow llvmpipe fallback)
          - XRender: CPU-based 2D acceleration (optimal for VMs without GPU)
        '';
      };

      maxFPS = lib.mkOption {
        type = lib.types.ints.between 10 144;
        default = 30;
        description = ''
          Maximum frames per second for compositor rendering.
          For remote desktop, 30 FPS is optimal (remote protocols cap at 20-30 FPS anyway).
        '';
      };

      vSync = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable vertical synchronization.
          Disabled by default for VMs to reduce input latency (tearing not visible over remote desktop).
        '';
      };

      hiddenPreviews = lib.mkOption {
        type = lib.types.ints.between 0 10;
        default = 5;
        description = ''
          Number of hidden window previews to generate.
          Lower values reduce memory and CPU usage.
        '';
      };
    };

    # Visual effects configuration options (T012)
    effects = {
      disableExpensive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Disable expensive visual effects (blur, translucency, wobbly windows, etc.)
          Saves 40-80% CPU usage in VM environments.
        '';
      };
    };

    # Animation configuration options (T012)
    animations = {
      instant = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Set all animations to instant (duration = 0).
          Improves perceived responsiveness in remote desktop scenarios.
        '';
      };
    };
  };

  config = lib.mkIf config.desktop.kde-vm-optimization.enable {
    # Qt Platform Configuration for X11 (T021)
    environment.sessionVariables = {
      QT_QPA_PLATFORM = "xcb";  # Force X11 backend for RustDesk compatibility
      QT_AUTO_SCREEN_SCALE_FACTOR = "0";  # Disable auto-scaling for predictable behavior
      QT_SCALE_FACTOR = "1";  # Manual scaling control
    };
  };
}
