# go2rtc — HomeKit hub for the Circle View cameras.
#
# NOT CURRENTLY IMPORTED (removed from configurations/surface-pro3.nix on
# 2026-08-20, same day it was added). Pairing to the cameras worked, but
# streaming never did: go2rtc's HomeKit client requires the camera's
# StreamingStatus characteristic to report "available" and the Circle Views
# never do — on any go2rtc version (pinned 1.9.2 and nixpkgs 1.9.14 tested),
# across reboots, and with HKSV recording disabled. Logitech/ArloBaby-class
# cameras have reported this since 2023, unresolved upstream:
#   https://github.com/AlexxIT/go2rtc/issues/1180
#   https://github.com/AlexxIT/go2rtc/issues/779
# Kept on disk — with the persistence fix, the 1.9.2 pin, and the RTP
# firewall range — for the evening upstream fixes it. Camera pairings live
# in /var/lib/go2rtc/go2rtc.yaml (streams deleted before retiring).
#
# Camera pairings are made from the web UI (http://<host>:1984 -> HomeKit ->
# Pair, with each camera's base code) and are written back into
# /var/lib/go2rtc/go2rtc.yaml — the seed below only provides the listeners
# and is installed only when the file does not exist, so UI/UI-written state
# survives rebuilds and restarts. Outbound HomeKit entries are added to the
# same file after pairing (see docs/HOMEKIT_DEVICES.md).
{ config, lib, pkgs, ... }:

let
  # nixpkgs carries 1.9.14, but go2rtc 1.9.3+ broke Logitech HomeKit camera
  # sources — the Circle View negotiates H.264 then never delivers RTP
  # (github.com/AlexxIT/go2rtc/issues/1180, still open). Pin the last
  # working upstream binary until that regression is fixed.
  go2rtc-pin = pkgs.stdenv.mkDerivation {
    pname = "go2rtc";
    version = "1.9.2";
    src = pkgs.fetchurl {
      url = "https://github.com/AlexxIT/go2rtc/releases/download/v1.9.2/go2rtc_linux_amd64";
      hash = "sha256-cqd3qGWXAuJAoTzO8aUEtpyWpGY0l7gg8tIt/KZUjRw=";
    };
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      install -Dm755 $src $out/bin/go2rtc
    '';
  };

  seedConfig = pkgs.writeText "go2rtc-seed.yaml" ''
    api:
      listen: ":1984"
    rtsp:
      listen: ":8554"
    webrtc:
      listen: ":8555/tcp"
    # HomeKit pairing chatter is the part worth reading in the journal.
    logs:
      homekit: info
  '';
in
{
  systemd.services.go2rtc = {
    description = "go2rtc camera streaming hub";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    preStart = ''
      # Seed only when absent — the pairing API and this file are the source of
      # truth for camera pairings, and an unconditional install would wipe them
      # on every restart (it did, once, on 2026-08-20).
      [ -f /var/lib/go2rtc/go2rtc.yaml ] || install -D -m 0644 ${seedConfig} /var/lib/go2rtc/go2rtc.yaml
    '';

    serviceConfig = {
      Type = "simple";
      ExecStart = "${go2rtc-pin}/bin/go2rtc -config /var/lib/go2rtc/go2rtc.yaml";
      StateDirectory = "go2rtc";
      DynamicUser = true;
      Restart = "on-failure";
      # mDNS (HomeKit discovery/advertising) + RTP/RTSP need these.
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"
      ];
    };
  };

  # 1984 web UI / API, 8554 RTSP, 8555 WebRTC (TCP+UDP for LAN playback).
  #
  # The RTP range: HomeKit cameras deliver media as unsolicited inbound UDP
  # to go2rtc's ephemeral ports — the strict per-port allowlist drops it and
  # streams negotiate but never carry frames. This host is behind the Linksys
  # NAT with no WAN exposure, so the high UDP range is effectively LAN-only.
  networking.firewall.allowedTCPPorts = [ 1984 8554 8555 ];
  networking.firewall.allowedUDPPorts = [ 8555 ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 32768; to = 60999; }
  ];
}
