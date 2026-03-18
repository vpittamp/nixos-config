{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.disk-guardrails;
  homeDir = config.home.homeDirectory;
  stateDir = "${config.xdg.stateHome}/disk-guardrails";
  reportPath = "${stateDir}/latest-report.txt";
  cleanupLogPath = "${stateDir}/cleanup.log";

  reportScript = pkgs.writeShellScriptBin "disk-usage-report" ''
    set -eu

    STATE_DIR="${stateDir}"
    REPORT_PATH="${reportPath}"
    mkdir -p "$STATE_DIR"

    root_usage="$(${pkgs.coreutils}/bin/df -P / | ${pkgs.gawk}/bin/awk 'NR==2 { gsub(/%/, "", $5); print $5 }')"
    severity="info"
    if [ "$root_usage" -ge ${toString cfg.urgentThresholdPercent} ]; then
      severity="critical"
    elif [ "$root_usage" -ge ${toString cfg.warningThresholdPercent} ]; then
      severity="warning"
    fi

    {
      echo "Disk Guardrails Report"
      echo "Generated: $(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      echo "Root usage: ''${root_usage}%"
      echo
      echo "Filesystem"
      ${pkgs.coreutils}/bin/df -h / "${homeDir}" /nix /var 2>/dev/null || true
      echo
      echo "Top buckets"
      for path in \
        "${homeDir}/.local/share" \
        "${homeDir}/.cache" \
        "${homeDir}/repos" \
        /nix/store \
        /var/lib/systemd/coredump
      do
        if [ -e "$path" ]; then
          ${pkgs.coreutils}/bin/du -xsh "$path" 2>/dev/null || true
        fi
      done
      echo
      echo "PWA and cache detail"
      if [ -d "${homeDir}/.local/share/firefoxpwa/profiles" ]; then
        printf "firefoxpwa profiles: "
        ${pkgs.findutils}/bin/find "${homeDir}/.local/share/firefoxpwa/profiles" -maxdepth 1 -mindepth 1 -type d | ${pkgs.coreutils}/bin/wc -l
        ${pkgs.coreutils}/bin/du -xsh "${homeDir}/.local/share/firefoxpwa" 2>/dev/null || true
      fi
      if [ -d "${homeDir}/.local/share/webapps" ]; then
        printf "webapps directories: "
        ${pkgs.findutils}/bin/find "${homeDir}/.local/share/webapps" -maxdepth 1 -mindepth 1 -type d | ${pkgs.coreutils}/bin/wc -l
        ${pkgs.coreutils}/bin/du -xsh "${homeDir}/.local/share/webapps" 2>/dev/null || true
      fi
      for path in \
        "${homeDir}/.local/share/pnpm" \
        "${homeDir}/.local/share/yarn" \
        "${homeDir}/.local/share/containers" \
        "${homeDir}/.cache/.bun" \
        "${homeDir}/.cache/google-chrome" \
        "${homeDir}/.cache/mozilla"
      do
        if [ -e "$path" ]; then
          ${pkgs.coreutils}/bin/du -xsh "$path" 2>/dev/null || true
        fi
      done
      echo
      echo "Repo-local Nix roots"
      if [ -d "${homeDir}/repos" ]; then
        printf "result symlinks: "
        ${pkgs.findutils}/bin/find "${homeDir}/repos" -maxdepth 5 -type l -name 'result*' 2>/dev/null | ${pkgs.coreutils}/bin/wc -l
        printf ".devenv gc roots: "
        ${pkgs.findutils}/bin/find "${homeDir}/repos" -path '*/.devenv/gc/*' -type l 2>/dev/null | ${pkgs.coreutils}/bin/wc -l
      fi
      echo
      echo "Largest coredumps"
      if [ -d /var/lib/systemd/coredump ]; then
        ${pkgs.findutils}/bin/find /var/lib/systemd/coredump -maxdepth 1 -type f -printf '%s %p\n' 2>/dev/null \
          | ${pkgs.coreutils}/bin/sort -nr \
          | ${pkgs.coreutils}/bin/head -n 10 \
          | ${pkgs.gawk}/bin/awk '{ bytes=$1; $1=""; printf "%.1f MiB %s\n", bytes/1048576, substr($0, 2) }'
      fi
    } | ${pkgs.coreutils}/bin/tee "$REPORT_PATH"

    case "$severity" in
      critical)
        echo "disk-guardrails: CRITICAL root filesystem usage at ''${root_usage}%." >&2
        ;;
      warning)
        echo "disk-guardrails: WARNING root filesystem usage at ''${root_usage}%." >&2
        ;;
      *)
        echo "disk-guardrails: root filesystem usage at ''${root_usage}%." >&2
        ;;
    esac
  '';

  cleanupScript = pkgs.writeShellScriptBin "disk-cleanup-low-risk" ''
    set -eu

    DAYS="''${1:-${toString cfg.cleanupMaxAgeDays}}"
    STATE_DIR="${stateDir}"
    LOG_PATH="${cleanupLogPath}"

    mkdir -p "$STATE_DIR"

    {
      echo "Disk Guardrails Cleanup"
      echo "Started: $(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      echo "Age threshold: ''${DAYS}d"
      echo

      if [ -d "${homeDir}/.local/share/Trash/files" ]; then
        echo "Removing trash entries older than ''${DAYS}d"
        ${pkgs.findutils}/bin/find "${homeDir}/.local/share/Trash/files" -mindepth 1 -maxdepth 1 -mtime "+''${DAYS}" -print -exec ${pkgs.coreutils}/bin/rm -rf {} +
      fi

      if [ -d "${homeDir}/.local/share/webapps" ]; then
        echo "Removing stale test webapp directories older than ''${DAYS}d"
        ${pkgs.findutils}/bin/find "${homeDir}/.local/share/webapps" -mindepth 1 -maxdepth 1 -type d \
          \( -name 'test-1pw*' -o -name 'webapp-TEST-*' \) -mtime "+''${DAYS}" -print -exec ${pkgs.coreutils}/bin/rm -rf {} +
      fi

      if [ -d "${homeDir}/repos" ]; then
        echo "Removing stale repo-local result symlinks older than ''${DAYS}d"
        ${pkgs.findutils}/bin/find "${homeDir}/repos" -maxdepth 5 -type l -name 'result*' -mtime "+''${DAYS}" -print -delete
      fi

      echo
      echo "Finished: $(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
    } | ${pkgs.coreutils}/bin/tee -a "$LOG_PATH"
  '';

  auditScript = pkgs.writeShellScriptBin "disk-nix-roots-audit" ''
    set -eu

    if [ ! -d "${homeDir}/repos" ]; then
      echo "No repo directory at ${homeDir}/repos"
      exit 0
    fi

    echo "Result symlinks"
    ${pkgs.findutils}/bin/find "${homeDir}/repos" -maxdepth 5 -type l -name 'result*' -printf '%TY-%Tm-%Td %TH:%TM %p -> %l\n' 2>/dev/null \
      | ${pkgs.coreutils}/bin/sort || true
    echo
    echo ".devenv GC roots"
    ${pkgs.findutils}/bin/find "${homeDir}/repos" -path '*/.devenv/gc/*' -type l -printf '%TY-%Tm-%Td %TH:%TM %p -> %l\n' 2>/dev/null \
      | ${pkgs.coreutils}/bin/sort || true
  '';
in
{
  options.programs.disk-guardrails = {
    enable = mkEnableOption "periodic disk-usage reporting and low-risk cleanup";

    reportInterval = mkOption {
      type = types.str;
      default = "12h";
      description = "How often to emit a disk-usage report.";
    };

    cleanupInterval = mkOption {
      type = types.str;
      default = "weekly";
      description = "How often to run the low-risk cleanup job.";
    };

    initialDelay = mkOption {
      type = types.str;
      default = "15min";
      description = "Delay before the first report or cleanup run after login.";
    };

    warningThresholdPercent = mkOption {
      type = types.int;
      default = 80;
      description = "Warn when filesystem usage reaches this percentage.";
    };

    urgentThresholdPercent = mkOption {
      type = types.int;
      default = 90;
      description = "Emit a critical warning when filesystem usage reaches this percentage.";
    };

    cleanupMaxAgeDays = mkOption {
      type = types.int;
      default = 14;
      description = "Age threshold for low-risk cleanup candidates.";
    };

    enableLowRiskCleanup = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to run the conservative cleanup timer.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ reportScript cleanupScript auditScript ];

    systemd.user.services.disk-usage-report = {
      Unit = {
        Description = "Disk usage report for known heavy directories";
        Documentation = "file:///etc/nixos/docs/DISK_PRESSURE_RUNBOOK.md";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${reportScript}/bin/disk-usage-report";
        Nice = 19;
        IOSchedulingClass = "best-effort";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "disk-usage-report";
      };
    };

    systemd.user.timers.disk-usage-report = {
      Unit = {
        Description = "Periodic disk usage report";
        Documentation = "file:///etc/nixos/docs/DISK_PRESSURE_RUNBOOK.md";
      };

      Timer = {
        OnBootSec = cfg.initialDelay;
        OnUnitActiveSec = cfg.reportInterval;
        Persistent = true;
      };

      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.disk-cleanup-low-risk = mkIf cfg.enableLowRiskCleanup {
      Unit = {
        Description = "Low-risk disk cleanup for stale local artifacts";
        Documentation = "file:///etc/nixos/docs/DISK_PRESSURE_RUNBOOK.md";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${cleanupScript}/bin/disk-cleanup-low-risk";
        Nice = 19;
        IOSchedulingClass = "best-effort";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "disk-cleanup-low-risk";
      };
    };

    systemd.user.timers.disk-cleanup-low-risk = mkIf cfg.enableLowRiskCleanup {
      Unit = {
        Description = "Periodic low-risk disk cleanup";
        Documentation = "file:///etc/nixos/docs/DISK_PRESSURE_RUNBOOK.md";
      };

      Timer = {
        OnBootSec = cfg.initialDelay;
        OnUnitActiveSec = cfg.cleanupInterval;
        Persistent = true;
      };

      Install.WantedBy = [ "timers.target" ];
    };
  };
}
