# Networking Services Configuration
{ config, lib, pkgs, ... }:

{
  # Tailscale VPN
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = lib.mkDefault "both";  # Enable subnet routing and exit node features
    # NOT extraUpFlags: NixOS only applies those when services.tailscale.authKeyFile
    # is set (it builds tailscaled-autoconnect.service under `mkIf (authKeyFile !=
    # null)`, and `tailscale up` runs only there). No host here sets an authKeyFile,
    # so every extraUpFlags entry this repo ever declared was silently inert --
    # surface ran with --accept-routes unset for as long as tailscale has been on it,
    # which is what produced "Some peers are advertising routes but --accept-routes
    # is false". extraSetFlags runs `tailscale set` from tailscaled-set.service on
    # every boot regardless, so the pref is genuinely declarative.
    #
    # Tailscale SSH is deliberately not enabled: these hosts are administered over
    # plain OpenSSH on the tailnet (see the openssh block below). The tailnet policy
    # has an `ssh` section, but no host advertises SSH, so those rules stay inert.
    extraSetFlags = [ "--accept-routes" ];
  };

  # DNS resilience floor.
  #
  # Tailscale registers itself as an *exclusive* openresolv subscriber, so
  # /etc/resolv.conf lists only MagicDNS (100.100.100.100). Public names then
  # depend entirely on tailscaled forwarding them to upstreams it captured from
  # the OS at the instant it applied its DNS config. If no resolver is present
  # at that instant -- a DHCP renew, a WAN flap, an ISP gateway switched to
  # bridge mode -- it captures an *empty* upstream list and answers every public
  # query with SERVFAIL:
  #
  #   dns: resolver: forward: no upstream resolvers set, returning SERVFAIL
  #
  # Nothing re-reads the base config afterwards, so the outage lasts until
  # something forces a DNS reconfigure. Tailnet names keep resolving the whole
  # time (MagicDNS answers those itself), which makes it look like the network
  # is fine while every API call fails with ENOTFOUND. Surface sat in this state
  # from 2026-08-06 to 2026-08-24, across reboots.
  #
  # networking.nameservers becomes a permanent `resolvconf -m 1 -a static`
  # record, written at boot and independent of DHCP, so the captured upstream
  # list is never empty. It ranks *after* the DHCP-provided resolver, so LAN
  # names still resolve through the local gateway; these only act as a floor.
  # Verified on surface by blocking the gateway's port 53 outright: public
  # resolution continued via the fallback, and LAN names were unaffected.
  networking.nameservers = lib.mkDefault [ "1.1.1.1" "8.8.8.8" ];

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