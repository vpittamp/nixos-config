# Multi-Machine NixOS Integration Test Template
#
# Tests client/server architectures and network communication.
#
# Usage:
#   nix-build -A default
#   $(nix-build -A default.driverInteractive)/bin/nixos-test-driver
#
# Replace TODO_TEST_NAME with your test name.
{ pkgs ? import <nixpkgs> { } }:

pkgs.testers.nixosTest {
  name = "TODO_TEST_NAME";

  nodes = {
    # Server node
    server = { config, pkgs, ... }: {
      virtualisation = {
        memorySize = 2048;
        cores = 2;
        vlans = [ 1 ];  # Shared network with client
      };

      networking.firewall.allowedTCPPorts = [ 80 ];

      services.nginx = {
        enable = true;
        virtualHosts."default" = {
          root = pkgs.writeTextDir "index.html" "<html><body>Hello from server</body></html>";
        };
      };
    };

    # Client node
    client = { config, pkgs, ... }: {
      virtualisation = {
        memorySize = 1024;
        cores = 1;
        vlans = [ 1 ];  # Same VLAN as server
      };

      environment.systemPackages = with pkgs; [
        curl
        netcat
      ];
    };
  };

  testScript = ''
    start_all()

    # Wait for server to be ready
    server.wait_for_unit("nginx.service")
    server.wait_for_open_port(80)

    # Test network connectivity
    client.wait_for_unit("network.target")
    client.succeed("ping -c 1 server")

    # Test HTTP communication
    output = client.succeed("curl -s http://server")
    assert "Hello from server" in output, f"Expected greeting in: {output}"

    # Example: Test bidirectional communication
    # server.succeed("ping -c 1 client")

    print("Multi-machine test passed!")
  '';
}
