# Wi-Fi link watchdog.
#
# Written after 2026-09-12, when surface-pro3 -- the house's Home Assistant hub,
# reachable only over Wi-Fi -- sat with no network for 18h43m while fully
# powered on and logging. The sequence, from its own journal:
#
#   15:45:54  mwifiex: successfully disconnected from <Linksys BSSID>, reason 3
#   15:52:58  wpa_supplicant: Trying to associate with SSID 'XFSETUP-37B4'
#   15:52:59  ASSOC_RESP: failed, status code=2 / AUTH timeout        (x6)
#   15:54:14  NetworkManager: Activation: failed for connection 'XFSETUP-37B4'
#             -> wpa_supplicant goes idle. Nothing retries. Ever.
#   10:37:19  (next day) manual reboot
#
# The upstream trigger was a WAN blip that knocked the association down. The
# *damage* was NetworkManager falling through to a stale saved profile, failing
# it, and then giving up permanently -- tailscaled logged "Rebind; defIf=\"\",
# ips=[]" for the next 18 hours. Deleting the stale profile (see the
# ensureProfiles block in configurations/surface-pro3.nix) removes that
# particular trap, but not the class of bug: NM declaring terminal failure on a
# headless host is silent and unbounded, and any future profile, driver wedge,
# or AP flap re-creates it.
#
# So this watchdog answers one question -- "can I reach my default gateway?" --
# and escalates until the answer is yes. It deliberately checks the gateway
# rather than the internet: an ISP outage is not this host's problem to fix, and
# remediating one would mean thrashing the radio during every WAN blip. Losing
# layer 2 to your own router is the condition worth acting on.
#
# Escalation is tiered because the cheap fix handles the observed failure and
# the expensive ones are genuinely disruptive:
#
#   tier 1  nmcli connection up <profile>   -- fixes "NM gave up", the case above
#   tier 2  systemctl restart NetworkManager -- fixes NM-internal state wedges
#   tier 3  modprobe -r/-a <module>          -- fixes firmware wedges (the Marvell
#                                               88W8897's BT half is already
#                                               documented doing this; see
#                                               home-assistant-watchdog.nix)
#   tier 4  reboot                           -- last resort, opt-in
#
# Each tier has to fail its own threshold before the next is tried, and a
# successful ping resets everything. A host that cannot be fixed by tier 3 stays
# broken and visible rather than rebooting in a loop, unless rebootAfter is set.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.wifiWatchdog;

  watchdog = pkgs.writeShellApplication {
    name = "wifi-watchdog";
    runtimeInputs = with pkgs; [
      iputils
      iproute2
      networkmanager
      systemd
      coreutils
      kmod
      gnugrep
      gawk
    ];
    text = ''
      STATE=/var/lib/wifi-watchdog
      FAIL_FILE="$STATE/failures"
      TIER_FILE="$STATE/last-tier"
      mkdir -p "$STATE"

      # Gateway: the configured one if given, else whatever the default route
      # says. No default route at all is itself the failure we are looking for
      # -- that is exactly the state the host was stuck in -- so an empty result
      # must fall through to the escalation path, never to a clean exit.
      gw="${cfg.gateway}"
      if [ -z "$gw" ]; then
        gw=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
      fi

      reachable() {
        [ -n "$gw" ] || return 1
        ping -c ${toString cfg.pingCount} -W ${toString cfg.pingTimeout} -I ${cfg.interface} "$gw" >/dev/null 2>&1
      }

      if reachable; then
        # Only log the recovery edge, not every healthy poll -- this runs every
        # few minutes forever on a host whose journal is already noisy.
        if [ -s "$FAIL_FILE" ]; then
          echo "gateway $gw reachable again after $(cat "$FAIL_FILE") failed checks"
        fi
        rm -f "$FAIL_FILE" "$TIER_FILE"
        exit 0
      fi

      fails=0
      if [ -r "$FAIL_FILE" ]; then fails=$(cat "$FAIL_FILE"); fi
      fails=$(( fails + 1 ))
      echo "$fails" > "$FAIL_FILE"

      last_tier=0
      if [ -r "$TIER_FILE" ]; then last_tier=$(cat "$TIER_FILE"); fi

      echo "gateway ''${gw:-<none>} unreachable via ${cfg.interface}; consecutive failures: $fails (last tier: $last_tier)"

      # Below the first threshold this is a blip, not an outage. Say nothing
      # more and let the next poll decide.
      if [ "$fails" -lt ${toString cfg.failThreshold} ]; then
        exit 0
      fi

      act() {
        tier="$1"; reason="$2"; shift 2
        echo "REMEDIATING tier $tier: $reason"
        "$@" || true
        echo "$tier" > "$TIER_FILE"
        # Clear the counter so the next tier needs its own full threshold of
        # failures. Without this, one bad stretch would run straight through
        # every tier to a reboot.
        rm -f "$FAIL_FILE"
      }

      if [ "$last_tier" -lt 1 ]; then
        act 1 "bringing up '${cfg.connection}' (NetworkManager may have given up)" \
          nmcli connection up "${cfg.connection}"
        exit 0
      fi

      if [ "$last_tier" -lt 2 ]; then
        act 2 "restarting NetworkManager" \
          systemctl restart NetworkManager.service
        exit 0
      fi

      ${lib.optionalString (cfg.kernelModule != null) ''
        if [ "$last_tier" -lt 3 ]; then
          # Invoked indirectly, as "$@" inside act; shellcheck cannot see that.
          # shellcheck disable=SC2329
          reload_module() {
            modprobe -r ${cfg.kernelModule}
            sleep 3
            modprobe ${cfg.kernelModule}
            sleep 5
            systemctl restart NetworkManager.service
          }
          act 3 "reloading ${cfg.kernelModule} (suspected firmware wedge)" reload_module
          exit 0
        fi
      ''}

      ${if cfg.rebootAfter then ''
        if [ "$last_tier" -lt 4 ]; then
          act 4 "every lesser tier failed; rebooting" systemctl reboot
          exit 0
        fi
      '' else ''
        echo "every remediation tier has been tried and the link is still down."
        echo "not rebooting (services.wifiWatchdog.rebootAfter = false); this host needs hands."
      ''}
    '';
  };
in
{
  options.services.wifiWatchdog = {
    enable = lib.mkEnableOption "Wi-Fi link watchdog (gateway reachability, escalating remediation)";

    interface = lib.mkOption {
      type = lib.types.str;
      example = "wlp1s0";
      description = "Wireless interface to test through and remediate.";
    };

    connection = lib.mkOption {
      type = lib.types.str;
      example = "Linksys 416";
      description = "NetworkManager profile name to bring up at tier 1.";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "192.168.1.1";
      description = ''
        Address to ping. Empty (the default) means "whatever the default route
        points at", which is usually right and survives a subnet change. Pin it
        only if this host must reach one specific gateway.
      '';
    };

    kernelModule = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "mwifiex_pcie";
      description = ''
        Driver module to unload/reload at tier 3. Null skips that tier, which is
        the right choice for drivers that do not survive a reload.
      '';
    };

    failThreshold = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Consecutive failed checks before a tier fires, and before each
        subsequent tier fires. With the default 2 min interval that is ~6 min of
        sustained unreachability before anything is touched.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "2min";
      description = "How often to check (systemd time span).";
    };

    pingCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Pings per check. More than one so a single dropped frame is not a failure.";
    };

    pingTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Per-ping timeout in seconds.";
    };

    rebootAfter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Reboot if every lesser tier has failed. Off by default: a reboot loop is
        worse than a visibly broken host. Turn it on only where prolonged
        unreachability is itself the greater harm -- a headless always-on hub
        with no local user to notice, which is precisely surface-pro3.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.wifi-watchdog = {
      description = "Wi-Fi link watchdog (gateway reachability)";
      after = [ "NetworkManager.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe watchdog;
        StateDirectory = "wifi-watchdog";
      };
    };

    systemd.timers.wifi-watchdog = {
      description = "Periodic Wi-Fi link check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Late enough that a cold boot has finished associating and DHCP has
        # completed; the first check must never race bring-up.
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "30s";
      };
    };
  };
}
