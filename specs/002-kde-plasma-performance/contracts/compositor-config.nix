# Compositor Configuration Contract
# Purpose: Defines the interface for KDE KWin compositor optimization settings
# Module: home-modules/desktop/plasma-config.nix
# Entity: CompositorConfig

{ lib, ... }:

{
  # Compositor backend and rendering settings
  compositor = {
    # Rendering backend selection
    backend = lib.mkOption {
      type = lib.types.enum [ "OpenGL" "XRender" ];
      default = "OpenGL";
      description = ''
        Compositor rendering backend.
        - OpenGL: GPU-accelerated (requires GPU or uses slow llvmpipe fallback)
        - XRender: CPU-based 2D acceleration (optimal for VMs without GPU)
      '';
      example = "XRender";
    };

    # OpenGL settings (ignored when backend = "XRender")
    glCore = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use OpenGL core profile (modern OpenGL).
        Set to false for VM environments using XRender.
      '';
      example = false;
    };

    glPreferBufferSwap = lib.mkOption {
      type = lib.types.enum [ "a" "c" "p" "e" "n" ];
      default = "a";
      description = ''
        Buffer swap method preference:
        - a: auto (let driver decide)
        - c: copy (always copy buffer)
        - p: paint (repaint entire buffer)
        - e: extend (use damaged regions)
        - n: none (no buffer swapping, lowest latency)

        For VMs, "n" (none) provides lowest latency.
      '';
      example = "n";
    };

    # Frame rate and vsync settings
    maxFPS = lib.mkOption {
      type = lib.types.ints.between 10 144;
      default = 60;
      description = ''
        Maximum frames per second for compositor rendering.
        For remote desktop, 30 FPS is optimal (remote protocols cap at 20-30 FPS anyway).
      '';
      example = 30;
    };

    vSync = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable vertical synchronization.
        Disable for VMs to reduce input latency (tearing not visible over remote desktop).
      '';
      example = false;
    };

    # Performance tuning
    hiddenPreviews = lib.mkOption {
      type = lib.types.ints.between 0 10;
      default = 6;
      description = ''
        Number of hidden window previews to generate.
        Lower values reduce memory and CPU usage.
      '';
      example = 5;
    };

    openGLIsUnsafe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Mark OpenGL as unsafe (disables GL if issues detected).
        Generally keep false.
      '';
      example = false;
    };

    windowsBlockCompositing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Allow fullscreen windows to disable compositing for better performance.
        Recommended to keep enabled.
      '';
      example = true;
    };
  };

  # Validation function
  validate = config:
    assert lib.assertMsg
      (config.compositor.backend == "XRender" -> config.compositor.glCore == false)
      "glCore must be false when using XRender backend";
    assert lib.assertMsg
      (config.compositor.maxFPS <= 60)
      "maxFPS > 60 wasteful for remote desktop scenarios";
    config;
}
