# Archive completed Codex CLI session directories (~/.codex/sessions/YYYY/MM)
# older than minAgeDays to a configured rclone remote (e.g. Google Drive) as
# zstd-compressed tarballs, verifying remote size before pruning local files.
{ config, lib, pkgs, osConfig ? null, ... }:
let
  cfg = config.services.codex-sessions-archive;
  hostName = lib.attrByPath [ "networking" "hostName" ] "host" (if osConfig != null then osConfig else { });

  archiveScript = pkgs.writeShellApplication {
    name = "codex-sessions-archive";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnutar
      pkgs.jq
      pkgs.rclone
      pkgs.zstd
    ];
    text = ''
      set -euo pipefail

      dry_run=0
      min_age_days="${toString cfg.minAgeDays}"
      remote="${cfg.remote}"
      sessions_dir="''${CODEX_HOME:-$HOME/.codex}/sessions"
      host_tag="${hostName}"

      while [ $# -gt 0 ]; do
        case "$1" in
          --dry-run) dry_run=1 ;;
          --min-age-days) min_age_days="$2"; shift ;;
          --remote) remote="$2"; shift ;;
          -h|--help)
            echo "Usage: codex-sessions-archive [--dry-run] [--min-age-days N] [--remote REMOTE:PATH]"
            exit 0
            ;;
          *)
            echo "codex-sessions-archive: unknown argument: $1" >&2
            exit 2
            ;;
        esac
        shift
      done

      if [ ! -d "$sessions_dir" ]; then
        echo "codex-sessions-archive: $sessions_dir does not exist; nothing to do."
        exit 0
      fi

      remote_name="''${remote%%:*}"
      if ! rclone listremotes 2>/dev/null | grep -qx "''${remote_name}:"; then
        echo "codex-sessions-archive: rclone remote '$remote_name:' is not configured yet." >&2
        echo "Run: rclone config create $remote_name drive" >&2
        exit 1
      fi

      current_ym="$(date +%Y/%m)"
      cutoff_epoch="$(( $(date +%s) - min_age_days * 86400 ))"
      stage_dir="$(mktemp -d "''${TMPDIR:-/tmp}/codex-archive.XXXXXX")"
      trap 'rm -rf "$stage_dir"' EXIT

      archived=0
      skipped=0

      # Iterate over YYYY/MM directories in chronological order
      while IFS= read -r -d "" month_dir; do
        rel="''${month_dir#"$sessions_dir"/}"
        if [ "$rel" = "$current_ym" ]; then
          skipped=$((skipped + 1))
          continue
        fi

        # Check newest file mtime inside this month directory
        newest_mtime="$(find "$month_dir" -type f -printf '%T@\n' 2>/dev/null | sort -nr | head -n1 | cut -d. -f1 || true)"
        if [ -z "$newest_mtime" ]; then
          # Empty directory
          if [ "$dry_run" -eq 1 ]; then
            echo "[dry-run] would remove empty dir $month_dir"
          else
            rmdir "$month_dir" 2>/dev/null || true
          fi
          continue
        fi

        if [ "$newest_mtime" -ge "$cutoff_epoch" ]; then
          echo "Skipping $rel (newest file is newer than ''${min_age_days}d)"
          skipped=$((skipped + 1))
          continue
        fi

        ym_slug="''${rel//\//-}"
        raw_size="$(du -sh "$month_dir" | cut -f1)"
        archive_name="codex-sessions-''${host_tag}-''${ym_slug}.tar.zst"

        # Avoid overwriting an existing remote archive if a month was partially archived before
        if rclone lsjson "$remote/$archive_name" >/dev/null 2>&1; then
          stamp="$(date +%Y%m%d-%H%M%S)"
          archive_name="codex-sessions-''${host_tag}-''${ym_slug}-''${stamp}.tar.zst"
        fi

        if [ "$dry_run" -eq 1 ]; then
          echo "[dry-run] would archive $rel ($raw_size) -> $remote/$archive_name"
          archived=$((archived + 1))
          continue
        fi

        local_archive="$stage_dir/$archive_name"
        local_sha="$stage_dir/''${archive_name}.sha256"

        echo "Compressing $rel ($raw_size) -> $archive_name ..."
        tar -C "$sessions_dir" -I "zstd -T2 -6" -cf "$local_archive" "$rel"
        (cd "$stage_dir" && sha256sum "$archive_name" > "$local_sha")

        local_bytes="$(stat -c%s "$local_archive")"
        comp_human="$(du -sh "$local_archive" | cut -f1)"
        echo "Uploading $archive_name ($comp_human) -> $remote/ ..."
        rclone copyto "$local_archive" "$remote/$archive_name" --stats=15s --stats-one-line
        rclone copyto "$local_sha" "$remote/''${archive_name}.sha256"

        # Verify remote file size matches before deleting local files
        remote_bytes="$(rclone lsjson "$remote/$archive_name" | jq -r '.[0].Size // 0')"
        if [ "$remote_bytes" != "$local_bytes" ]; then
          echo "ERROR: size mismatch for $archive_name (local=$local_bytes remote=$remote_bytes); keeping local files!" >&2
          exit 1
        fi

        echo "Verified $remote/$archive_name ($remote_bytes bytes); removing local $month_dir"
        rm -rf "$month_dir"
        rm -f "$local_archive" "$local_sha"

        # Remove parent YYYY directory if now empty
        year_dir="$(dirname "$month_dir")"
        rmdir "$year_dir" 2>/dev/null || true

        archived=$((archived + 1))
      done < <(find "$sessions_dir" -mindepth 2 -maxdepth 2 -type d -print0 | sort -z)

      echo "Done: archived=$archived skipped=$skipped remote=$remote"
    '';
  };
in
{
  options.services.codex-sessions-archive = {
    enable = lib.mkEnableOption "Monthly archival of old Codex CLI sessions to cloud storage via rclone";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "gdrive:Archives/codex-sessions/${hostName}";
      description = "rclone remote and destination path for compressed monthly archives.";
    };

    minAgeDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Only archive completed YYYY/MM directories whose newest file is older than this many days.";
    };

    calendar = lib.mkOption {
      type = lib.types.str;
      default = "monthly";
      description = "systemd OnCalendar schedule for automatic archival.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.rclone
      archiveScript
    ];

    systemd.user.services.codex-sessions-archive = {
      Unit.Description = "Archive old Codex CLI sessions to ${cfg.remote}";
      Service = {
        Type = "oneshot";
        ExecStart = "${archiveScript}/bin/codex-sessions-archive";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUQuota = "50%";
      };
    };

    systemd.user.timers.codex-sessions-archive = {
      Unit.Description = "Periodically archive old Codex CLI sessions";
      Timer = {
        OnCalendar = cfg.calendar;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
