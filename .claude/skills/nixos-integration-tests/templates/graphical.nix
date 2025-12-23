# Graphical NixOS Integration Test Template
#
# Full graphical environment with VNC access for debugging.
# Use for testing Sway, GUI applications, and window management.
#
# Usage:
#   nix-build -A default
#   $(nix-build -A default.driverInteractive)/bin/nixos-test-driver
#
# VNC debugging:
#   vncviewer localhost:5900
#
# Replace TODO_TEST_NAME with your test name.
{ pkgs ? import <nixpkgs> { } }:

pkgs.testers.nixosTest {
  name = "TODO_TEST_NAME";

  # Enable OCR for text recognition (optional)
  # enableOCR = true;

  nodes.machine = { config, pkgs, lib, ... }: {
    virtualisation = {
      memorySize = 4096;  # 4GB for GUI
      diskSize = 8192;
      cores = 4;
      resolution = { x = 1920; y = 1080; };
      qemu.options = [
        "-vga none"
        "-device virtio-gpu-pci"
        "-vnc :0"  # VNC on port 5900
      ];
    };

    hardware.graphics.enable = true;

    # Display manager with auto-login
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.sway}/bin/sway";
          user = "testuser";
        };
      };
    };

    # Test user
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
      extraGroups = [ "wheel" "video" ];
    };

    # Sway for Wayland testing
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    # Environment for headless Sway (set WLR_BACKENDS=headless for CI)
    environment.sessionVariables = {
      WLR_RENDERER = "pixman";  # Software rendering
      WLR_NO_HARDWARE_CURSORS = "1";
      GDK_BACKEND = "wayland";
      QT_QPA_PLATFORM = "wayland";
    };

    environment.systemPackages = with pkgs; [
      foot        # Terminal
      jq          # JSON parsing for swaymsg
      grim        # Screenshots
      slurp       # Region selection
    ];
  };

  testScript = ''
    import json

    start_all()

    # Wait for display manager
    machine.wait_for_unit("greetd.service")
    machine.sleep(3)

    # Wait for Sway IPC socket
    machine.wait_for_file("/tmp/sway-ipc.sock")

    # Verify Sway is responding
    version = machine.succeed("su - testuser -c 'swaymsg -t get_version'")
    print(f"Sway version: {version}")

    # Helper: Wait for window by app_id
    def wait_for_window(app_id, timeout=20):
        import time
        start = time.time()
        while time.time() - start < timeout:
            try:
                machine.succeed(
                    f"su - testuser -c 'swaymsg -t get_tree | "
                    f"jq -r \".. | .app_id? // empty\" | grep -q {app_id}'"
                )
                return True
            except:
                machine.sleep(1)
        return False

    # Example: Launch terminal and verify
    machine.succeed("su - testuser -c 'swaymsg exec foot'")
    assert wait_for_window("foot"), "Terminal window not found"

    # Take screenshot for debugging
    machine.screenshot("graphical_test")

    print("Graphical test passed!")
  '';
}
