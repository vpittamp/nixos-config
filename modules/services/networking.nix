# Networking Services Configuration
{ config, lib, pkgs, ... }:

{
  # Tailscale VPN
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = lib.mkDefault "both";  # Enable subnet routing and exit node features
    extraUpFlags = [ "--ssh" "--accept-routes" ];  # Enable Tailscale SSH
  };

  # Enhanced SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = lib.mkDefault true;
      X11Forwarding = lib.mkDefault true;
      # Security hardening
      KbdInteractiveAuthentication = false;
      UseDns = false;
      StrictModes = true;
    };
    # Extra config for better security and agent forwarding
    extraConfig = ''
      MaxAuthTries 3
      MaxSessions 10
      ClientAliveInterval 300
      ClientAliveCountMax 2

      # SSH Agent Forwarding - allows remote git operations with local 1Password agent
      AllowAgentForwarding yes

      # Allow Unix domain socket forwarding for agent
      StreamLocalBindUnlink yes
    '';
  };

  # Firewall configuration
  networking.firewall = {
    enable = lib.mkDefault true;
    allowedTCPPorts = [
      22     # SSH
      41641  # Tailscale
      # Home Assistant ports are configured in home-assistant.nix when enabled
    ];
    allowedUDPPorts = [
      41641  # Tailscale
      # Home Assistant ports are configured in home-assistant.nix when enabled
    ];
    # Log dropped packets for debugging
    logRefusedConnections = false;
  };

  # Network management tools
  environment.systemPackages = with pkgs; [
    tailscale
    networkmanager
    inetutils
    dig
    nmap
    netcat
    iperf3
    tcpdump
    wireshark-cli
    mtr
    traceroute
    bandwhich
    nethogs
  ];

  # Enable network manager (useful for desktop systems)
  networking.networkmanager = {
    enable = lib.mkDefault false;  # Enable per-system as needed
  };

  # mDNS for local network discovery
  services.avahi = {
    enable = lib.mkDefault false;  # Enable if needed
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}