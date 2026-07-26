{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.slab-reboot;

  # Graceful drain-and-reboot for the NVIDIA explicit-sync kmalloc-64 slab
  # leak (see configurations/ryzen.nix). Leaked SUnreclaim slab is unreachable
  # from every teardown path — only a reboot recovers it — so the safe move is
  # draining herdr-managed AI agent sessions first, then rebooting. herdr's
  # resume_agents_on_restore = true brings the sessions back after boot, so no
  # explicit checkpoint step is needed beyond stopping the server cleanly.
  slabReboot = pkgs.writeShellScriptBin "slab-reboot" ''
    set -u

    jq=${pkgs.jq}/bin/jq
    timeout_mins=${toString cfg.drainTimeoutMins}
    check=0 yes=0 force=0

    usage() {
      cat <<'USAGE'
    slab-reboot — drain herdr AI agents, then reboot (NVIDIA slab-leak recovery)

    Usage: slab-reboot [--check] [--yes] [--force] [--timeout-mins N]

      --check           Show slab/agent status and exit without rebooting
      --yes             Skip the confirmation prompt
      --force           Skip waiting for working agents to drain
      --timeout-mins N  Per-agent drain timeout in minutes (default from config)

    Waits for every herdr agent with status "working" to reach idle/done/
    blocked, stops the herdr server cleanly (sessions auto-resume after boot),
    then reboots. Caveats: (1) if you ask an AI agent to run this, its own
    pane counts as "working" and the drain will wait on it — run from a plain
    shell or pass --force in that case; (2) when run from a herdr-managed
    terminal, your pane disappears as the server stops — that is expected,
    the reboot still follows within seconds.
    USAGE
    }

    while [ $# -gt 0 ]; do
      case "$1" in
        --check) check=1 ;;
        --yes) yes=1 ;;
        --force) force=1 ;;
        --timeout-mins) shift; timeout_mins="''${1:?--timeout-mins needs a value}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "slab-reboot: unknown option: $1" >&2; usage >&2; exit 2 ;;
      esac
      shift
    done

    kb() { ${pkgs.gawk}/bin/awk -v k="$1:" '$1==k{print $2}' /proc/meminfo; }
    echo "SUnreclaim $(( $(kb SUnreclaim) / 1024 )) MiB unreclaimable slab, MemAvailable $(( $(kb MemAvailable) / 1024 )) MiB"

    agents_json=""
    if command -v herdr >/dev/null 2>&1; then
      agents_json=$(herdr agent list 2>/dev/null || true)
    else
      echo "herdr not found on PATH; skipping agent drain" >&2
    fi

    if [ -n "$agents_json" ]; then
      echo "herdr agents:"
      printf '%s' "$agents_json" \
        | "$jq" -r '.result.agents[]? | "  \(.pane_id)\t\(.agent)\t\(.agent_status)\t\(.terminal_title_stripped // "")"' \
        || echo "  (could not parse agent list)"
    fi

    if [ "$check" = 1 ]; then
      exit 0
    fi

    working=$(printf '%s' "$agents_json" \
      | "$jq" -r '.result.agents[]? | select(.agent_status=="working") | "\(.pane_id)\t\(.agent)\t\(.terminal_title_stripped // "")"' \
      2>/dev/null || true)

    if [ -n "$working" ] && [ "$force" != 1 ]; then
      echo "Draining working agents (timeout ''${timeout_mins}m each; --force to skip)..."
      while IFS="$(printf '\t')" read -r pane agent title; do
        [ -n "$pane" ] || continue
        echo "  waiting for $agent [$pane] $title"
        if ! herdr agent wait "$pane" --timeout $(( timeout_mins * 60000 )) >/dev/null 2>&1; then
          # Nonzero also means the pane vanished (user closed it) — that IS
          # drained. Only abort if the agent is still listed as working.
          still_working=$(herdr agent list 2>/dev/null \
            | "$jq" -r --arg p "$pane" \
              '.result.agents[]? | select(.pane_id==$p and .agent_status=="working") | .pane_id' \
            2>/dev/null || true)
          if [ -n "$still_working" ]; then
            echo "slab-reboot: agent $agent [$pane] did not drain within ''${timeout_mins}m — aborting." >&2
            echo "Re-run with --force to reboot anyway, or wait for it to finish." >&2
            exit 1
          fi
          echo "  ($agent [$pane] pane is gone — treating as drained)"
        fi
      done <<EOF
    $working
    EOF
      echo "All agents drained."
    fi

    if [ "$yes" != 1 ]; then
      printf 'Reboot now? Sessions resume after boot via herdr. [y/N] '
      read -r answer </dev/tty || answer=""
      case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
      esac
    fi

    # Final phase must survive its own terminal: when run from a herdr pane
    # (the default on this host), stopping the server closes our PTY and HUPs
    # this very script. Ignore the teardown signals and detach stdio BEFORE
    # stopping the server so control reaches the reboot; polkit-wise we stay
    # inside the login session, so systemctl reboot needs no auth (with a
    # sudo -n fallback just in case).
    echo "Stopping herdr server, then rebooting. If this terminal is a herdr"
    echo "pane it will disappear now — the reboot still follows."
    trap "" HUP TERM PIPE
    exec </dev/null >/dev/null 2>&1
    if command -v herdr >/dev/null 2>&1; then
      herdr server stop || true
      sleep 1
    fi
    ${pkgs.systemd}/bin/systemctl reboot \
      || ${pkgs.sudo}/bin/sudo -n ${pkgs.systemd}/bin/systemctl reboot
  '';
in
{
  options.programs.slab-reboot = {
    enable = mkEnableOption "graceful drain-and-reboot helper for the NVIDIA kmalloc-64 slab leak";

    drainTimeoutMins = mkOption {
      type = types.ints.positive;
      default = 30;
      description = "Default per-agent drain timeout in minutes before slab-reboot aborts.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ slabReboot ];
  };
}
