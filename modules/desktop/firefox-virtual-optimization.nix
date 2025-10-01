# Firefox optimizations for virtual/cloud environments (Hetzner)
# Addresses GPU acceleration issues and memory optimization
{ config, lib, pkgs, ... }:

{
  # Add Firefox environment variables for software rendering
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

  # Firefox user preferences for virtual environment
  home-manager.users.vpittamp = { config, ... }: {
    programs.firefox.profiles.default.settings = {
        # Disable hardware acceleration
        "layers.acceleration.disabled" = true;
        "layers.acceleration.force-enabled" = false;
        "gfx.webrender.software" = true;
        "gfx.webrender.software.opengl" = true;

        # Disable WebGL (causes issues without proper GPU)
        "webgl.disabled" = true;
        "webgl.force-enabled" = false;
        "webgl2.disabled" = true;

        # Memory optimization
        "dom.ipc.processCount" = 4;  # Limit content processes
        "dom.ipc.processCount.webIsolated" = 2;  # Limit isolated processes
        "browser.tabs.unloadOnLowMemory" = true;  # Auto-unload tabs
        "browser.sessionstore.interval" = 60000;  # Save session less frequently (60 seconds)

        # Cache optimization
        "browser.cache.memory.enable" = true;
        "browser.cache.memory.capacity" = 256000;  # 256MB memory cache
        "browser.cache.disk.enable" = true;
        "browser.cache.disk.capacity" = 1048576;  # 1GB disk cache

        # Disable animations to reduce CPU usage
        "toolkit.cosmeticAnimations.enabled" = false;
        "browser.tabs.animate" = false;
        "browser.fullscreen.animate" = false;

        # Disable smooth scrolling (reduces CPU)
        "general.smoothScroll" = false;

        # Disable video autoplay
        "media.autoplay.default" = 5;  # Block audio and video
        "media.autoplay.blocking_policy" = 2;

        # Disable GPU video decoding (override existing settings)
        "media.hardware-video-decoding.enabled" = lib.mkForce false;
        "media.hardware-video-decoding.force-enabled" = lib.mkForce false;
        "media.ffmpeg.vaapi.enabled" = lib.mkForce false;

        # X11 specific settings
        "gfx.x11-egl.force-disabled" = true;
        "widget.disable-swizzle" = true;
    };
  };
}