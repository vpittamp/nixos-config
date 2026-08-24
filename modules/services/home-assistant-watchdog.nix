# Home Assistant watchdog (surface-pro3).
#
# This host is the house's automation hub and is administered entirely over
# tailscale -- there is no local user to notice a wedge and no screen to notice
# it on. Two failure modes were observed repeatedly and both are documented as
# "restart fixes it", which is exactly the shape a watchdog handles:
#
#   1. BLE scanner wedge. The Marvell 88W8897 AVASTAR is a WiFi/BT composite and
#      its BT side stops accepting scan requests at runtime. habluetooth then
#      logs ScannerStartError once a minute *forever* without recovering:
#
#        habluetooth.scanner.ScannerStartError: hci0: Failed to start Bluetooth:
#        passive scanning ... Try power cycling the Bluetooth hardware.
#
#      Measured on 2026-08-23/24: exactly 60/hour for 8+ hours straight, ending
#      only at the next reboot. This is NOT a BlueZ misconfiguration -- the host
#      runs BlueZ 5.86 with Experimental=true in main.conf (the message names
#      >= 5.56 as the requirement), and a fresh boot scans fine. The adapter
#      itself has to be power cycled, and HA must be restarted *after* it,
#      because bleak's connection-slot bookkeeping lives inside the HA process
#      and does not re-derive itself from a new adapter.
#
#   2. HA API wedge. The event loop occasionally stops serving; the frontend
#      times out and stays that way until home-assistant is restarted.
#
# Deliberately conservative, because a needless restart of a 2-core/3.7 GiB host
# running the whole house is worse than a few more minutes of a wedge:
#   * a consecutive-failure threshold, so one slow poll is never enough;
#   * a grace period after HA starts, so a slow cold start is not read as a
#     wedge (this box takes minutes to come up);
#   * a cooldown between remediations, so a genuinely broken HA is not put into
#     a restart loop -- it fails visibly instead, which is the correct outcome.
{ config, lib, pkgs, ... }:

let
  # Tunables. Timer runs every 5 min, so FAIL_THRESHOLD=2 means ~10 min of
  # sustained unreachability before HA is touched.
  cfg = {
    apiUrl = "http://127.0.0.1:8123/";
    failThreshold = 2;
    graceSeconds = 900;    # 15 min after HA starts before the API is judged
    cooldownSeconds = 1800; # 30 min between remediations
    bleWindow = "12 min ago";
    bleThreshold = 6;      # errors arrive ~1/min; 6 in 12 min = sustained
  };

  watchdog = pkgs.writeShellApplication {
    name = "ha-watchdog";
    runtimeInputs = with pkgs; [ curl systemd coreutils gnugrep gawk ];
    text = ''
      STATE=/var/lib/ha-watchdog
      FAIL_FILE="$STATE/api-failures"
      ACTION_FILE="$STATE/last-action"
      mkdir -p "$STATE"

      now=$(date +%s)

      last_action=0
      if [ -r "$ACTION_FILE" ]; then last_action=$(cat "$ACTION_FILE"); fi
      cooldown_left=$(( ${toString cfg.cooldownSeconds} - (now - last_action) ))

      # Remediate unless we acted recently. Refusing inside a cooldown is the
      # point: it converts "restart loop" into "stays down and is visible".
      remediate() {
        reason="$1"; shift
        if [ "$cooldown_left" -gt 0 ]; then
          echo "wedge detected ($reason) but in cooldown, ''${cooldown_left}s left -- not acting"
          return 0
        fi
        echo "REMEDIATING: $reason"
        "$@"
        date +%s > "$ACTION_FILE"
        rm -f "$FAIL_FILE"
        cooldown_left=${toString cfg.cooldownSeconds}
      }

      # Order matters: power cycle the adapter first, then HA, because HA caches
      # connection-slot state for the adapter it started with.
      restart_bt_then_ha() {
        systemctl restart bluetooth || true
        sleep 5
        systemctl restart home-assistant || true
      }

      restart_ha() {
        systemctl restart home-assistant || true
      }

      # --- 1. BLE scanner wedge -------------------------------------------
      ble_errors=$(journalctl -u home-assistant --since "${cfg.bleWindow}" \
        --no-pager 2>/dev/null | grep -c "ScannerStartError" || true)
      if [ "''${ble_errors:-0}" -ge ${toString cfg.bleThreshold} ]; then
        remediate "BLE scanner wedged ($ble_errors ScannerStartError in the last ${cfg.bleWindow})" \
          restart_bt_then_ha
      fi

      # --- 2. HA API wedge -------------------------------------------------
      # Skip entirely while HA is starting; a cold start on this hardware can
      # outlast several poll intervals and must not be mistaken for a wedge.
      if ! systemctl is-active --quiet home-assistant; then
        echo "home-assistant not active -- leaving it to systemd, not restarting"
        exit 0
      fi

      started_mono=$(systemctl show home-assistant -p ActiveEnterTimestampMonotonic --value)
      uptime_s=$(awk '{printf "%d", $1}' /proc/uptime)
      ha_age=$(( uptime_s - (''${started_mono:-0} / 1000000) ))
      if [ "$ha_age" -lt ${toString cfg.graceSeconds} ]; then
        echo "home-assistant started ''${ha_age}s ago -- inside grace period, skipping API check"
        exit 0
      fi

      code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${cfg.apiUrl}" || echo 000)
      if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        rm -f "$FAIL_FILE"
        exit 0
      fi

      fails=0
      if [ -r "$FAIL_FILE" ]; then fails=$(cat "$FAIL_FILE"); fi
      fails=$(( fails + 1 ))
      echo "$fails" > "$FAIL_FILE"
      echo "HA API unhealthy (http=$code), consecutive failures: $fails"

      if [ "$fails" -ge ${toString cfg.failThreshold} ]; then
        remediate "HA API unreachable $fails polls running (http=$code)" restart_ha
      fi
    '';
  };
in
{
  systemd.services.ha-watchdog = {
    description = "Home Assistant wedge watchdog (BLE scanner + API health)";
    after = [ "home-assistant.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe watchdog;
      StateDirectory = "ha-watchdog";
    };
  };

  systemd.timers.ha-watchdog = {
    description = "Periodic Home Assistant wedge check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # First check well after boot so a cold start is never the first thing
      # the watchdog sees.
      OnBootSec = "20min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
    };
  };
}
