# Minimal NixOS Integration Test Template
#
# Usage:
#   nix-build -A default
#   $(nix-build -A default.driverInteractive)/bin/nixos-test-driver
#
# Replace TODO_TEST_NAME with your test name.
{ pkgs ? import <nixpkgs> { } }:

pkgs.testers.nixosTest {
  name = "TODO_TEST_NAME";

  nodes.machine = { config, pkgs, ... }: {
    # Virtualization settings
    virtualisation = {
      memorySize = 2048;  # MB
      diskSize = 4096;    # MB
      cores = 2;
    };

    # Test user with auto-login
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
      extraGroups = [ "wheel" ];
    };

    # Essential packages for testing
    environment.systemPackages = with pkgs; [
      curl
      jq
      # Add your test dependencies here
    ];

    # Enable services to test
    # services.nginx.enable = true;
  };

  testScript = ''
    start_all()

    # Wait for system to be ready
    machine.wait_for_unit("multi-user.target")

    # Example: Test a service
    # machine.wait_for_unit("nginx.service")
    # machine.wait_for_open_port(80)
    # output = machine.succeed("curl -s http://localhost")
    # assert "<html>" in output, f"Expected HTML in: {output}"

    # Example: Run a command
    # output = machine.succeed("echo hello")
    # assert output.strip() == "hello"

    print("Test passed!")
  '';
}
