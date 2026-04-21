{ config, pkgs, lib, ... }:

let
  shared = import ./browser-mcp-shared.nix { inherit config lib pkgs; };
  enableBrowserMcpServices = shared.enableBrowserMcpServers;

  managedBrowserServiceName = "mcp-chrome-devtools-browser.service";
  reaperServiceName = "mcp-browser-orphan-reaper.service";
  reaperTimerName = "mcp-browser-orphan-reaper.timer";

  mcpBrowserLifecycleScript = pkgs.writeText "mcp-browser-lifecycle.py" ''
    import json
    import os
    import re
    import signal
    import subprocess
    import sys
    import time

    ASSISTANT_NAMES = {"claude", "codex", "codex-raw", "gemini"}
    MANAGED_BROWSER_SERVICE = "${managedBrowserServiceName}"
    REAPER_TIMER = "${reaperTimerName}"
    HOST = "${shared.chromeDevtoolsBrowserHost}"
    PORT = ${toString shared.chromeDevtoolsBrowserPort}
    ENDPOINT_URL = "${shared.chromeDevtoolsBrowserUrl}"
    MANAGED_PROFILE_DIR = "${shared.chromeDevtoolsProfileDir}"
    PROFILE_DIRS = ${builtins.toJSON shared.assistantBrowserProfileDirs}
    LEGACY_PROFILE_DIRS = ${builtins.toJSON shared.legacyBrowserProfileDirs}
    MIN_STALE_AGE_SECONDS = 180
    LISTENER_RE = re.compile(r"pid=(\d+)")


    def service_is_active(name: str) -> bool:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return result.returncode == 0


    def list_processes():
        processes = {}
        clk_tck = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        with open("/proc/uptime", "r", encoding="utf-8") as handle:
            uptime_seconds = float(handle.read().split()[0])

        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            pid = int(entry)
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as handle:
                    raw_cmdline = handle.read().replace(b"\x00", b" ").decode("utf-8").strip()
                if not raw_cmdline:
                    continue

                with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as handle:
                    stat_payload = handle.read().strip()
                rparen = stat_payload.rfind(")")
                if rparen == -1:
                    continue
                fields = stat_payload[rparen + 2 :].split()
                ppid = int(fields[1])
                start_ticks = int(fields[19])
                age_seconds = max(0, int(uptime_seconds - (start_ticks / clk_tck)))

                token0 = raw_cmdline.split()[0]
                processes[pid] = {
                    "pid": pid,
                    "ppid": ppid,
                    "cmdline": raw_cmdline,
                    "age_seconds": age_seconds,
                    "exe_name": os.path.basename(token0),
                }
            except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError, ValueError):
                continue
        return processes


    def is_assistant_process(proc) -> bool:
        if proc["exe_name"] in ASSISTANT_NAMES:
            return True
        cmdline = proc["cmdline"]
        return any(f"/{name} " in cmdline or cmdline.endswith(f"/{name}") for name in ASSISTANT_NAMES)


    def has_assistant_ancestor(pid: int, processes) -> bool:
        seen = set()
        current = processes.get(pid)
        while current:
            parent_pid = current["ppid"]
            if parent_pid <= 1 or parent_pid in seen:
                return False
            seen.add(parent_pid)
            parent = processes.get(parent_pid)
            if not parent:
                return False
            if is_assistant_process(parent):
                return True
            current = parent
        return False


    def is_candidate_process(proc) -> bool:
        cmdline = proc["cmdline"]
        if any(marker in cmdline for marker in ("chrome-devtools-mcp", "@playwright/mcp", "playwright-mcp")):
            return True
        if any(profile_dir in cmdline for profile_dir in PROFILE_DIRS):
            return True
        return any(legacy_dir in cmdline for legacy_dir in LEGACY_PROFILE_DIRS)


    def is_managed_browser(proc) -> bool:
        return MANAGED_PROFILE_DIR in proc["cmdline"]


    def collect_candidates(
        *,
        processes,
        include_live_ancestors: bool,
        include_managed_browser: bool,
        min_age_seconds: int,
    ):
        managed_service_active = service_is_active(MANAGED_BROWSER_SERVICE)
        stale = []
        for proc in processes.values():
            if not is_candidate_process(proc):
                continue
            if proc["age_seconds"] < min_age_seconds:
                continue
            if not include_live_ancestors and has_assistant_ancestor(proc["pid"], processes):
                continue
            if (
                not include_managed_browser
                and managed_service_active
                and is_managed_browser(proc)
            ):
                continue
            stale.append(
                {
                    "pid": proc["pid"],
                    "ppid": proc["ppid"],
                    "age_seconds": proc["age_seconds"],
                    "cmdline": proc["cmdline"],
                }
            )
        stale.sort(key=lambda item: (item["age_seconds"], item["pid"]), reverse=True)
        return stale


    def terminate_processes(candidates):
        for sig in (signal.SIGTERM, signal.SIGKILL):
            for proc in candidates:
                try:
                    os.kill(proc["pid"], sig)
                except ProcessLookupError:
                    continue
                except PermissionError:
                    continue
            if sig == signal.SIGTERM:
                time.sleep(1)


    def detect_listener(processes):
        try:
            result = subprocess.run(
                ["ss", "-ltnpH"],
                capture_output=True,
                text=True,
                check=False,
            )
            lines = result.stdout.splitlines()
        except FileNotFoundError:
            lines = []

        listener_line = ""
        for line in lines:
            if f"{HOST}:{PORT}" in line:
                listener_line = line.strip()
                break

        pid = None
        cmdline = ""
        matches_expected_profile = False
        if listener_line:
            match = LISTENER_RE.search(listener_line)
            if match:
                pid = int(match.group(1))
                proc = processes.get(pid)
                if proc:
                    cmdline = proc["cmdline"]
                    matches_expected_profile = MANAGED_PROFILE_DIR in cmdline

        return {
            "line": listener_line,
            "pid": pid,
            "cmdline": cmdline,
            "matches_expected_profile": matches_expected_profile,
        }


    def health_payload():
        processes = list_processes()
        stale_candidates = collect_candidates(
            processes=processes,
            include_live_ancestors=False,
            include_managed_browser=False,
            min_age_seconds=MIN_STALE_AGE_SECONDS,
        )
        listener = detect_listener(processes)
        browser_service_active = service_is_active(MANAGED_BROWSER_SERVICE)
        reaper_timer_active = service_is_active(REAPER_TIMER)

        issues = []
        if not browser_service_active:
            issues.append(f"{MANAGED_BROWSER_SERVICE} is not active")
        if not reaper_timer_active:
            issues.append(f"{REAPER_TIMER} is not active")
        if listener["pid"] is None:
            issues.append(f"no listener found on {ENDPOINT_URL}")
        elif not listener["matches_expected_profile"]:
            issues.append(f"{ENDPOINT_URL} is owned by an unexpected process")
        if stale_candidates:
            issues.append(f"{len(stale_candidates)} stale MCP/browser processes detected")

        return {
            "healthy": not issues,
            "issues": issues,
            "endpoint_url": ENDPOINT_URL,
            "managed_browser_service": {
                "name": MANAGED_BROWSER_SERVICE,
                "active": browser_service_active,
                "profile_dir": MANAGED_PROFILE_DIR,
                "port": PORT,
            },
            "reaper_timer": {
                "name": REAPER_TIMER,
                "active": reaper_timer_active,
            },
            "listener": listener,
            "stale_candidates": stale_candidates,
        }


    def main():
        command = sys.argv[1] if len(sys.argv) > 1 else "health"

        if command == "health":
            print(json.dumps(health_payload()))
            return 0

        processes = list_processes()
        if command == "reap":
            candidates = collect_candidates(
                processes=processes,
                include_live_ancestors=False,
                include_managed_browser=False,
                min_age_seconds=MIN_STALE_AGE_SECONDS,
            )
        elif command == "cleanup-session":
            candidates = collect_candidates(
                processes=processes,
                include_live_ancestors=True,
                include_managed_browser=True,
                min_age_seconds=0,
            )
        else:
            print(f"unknown command: {command}", file=sys.stderr)
            return 1

        terminate_processes(candidates)
        print(
            json.dumps(
                {
                    "command": command,
                    "killed": len(candidates),
                    "candidates": candidates,
                }
            )
        )
        return 0


    if __name__ == "__main__":
        raise SystemExit(main())
  '';

  mcpBrowserLifecycle = pkgs.writeShellScriptBin "mcp-browser-lifecycle" ''
    exec ${pkgs.python3}/bin/python3 ${mcpBrowserLifecycleScript} "$@"
  '';

  chromeDevtoolsBrowserLauncher = pkgs.writeShellScriptBin "mcp-chrome-devtools-browser" ''
    set -euo pipefail

    mkdir -p "${shared.chromeDevtoolsProfileDir}"
    chmod 700 "${shared.chromeDevtoolsProfileDir}"

    exec ${pkgs.google-chrome}/bin/google-chrome-stable \
      --remote-debugging-address=${shared.chromeDevtoolsBrowserHost} \
      --remote-debugging-port=${toString shared.chromeDevtoolsBrowserPort} \
      --user-data-dir="${shared.chromeDevtoolsProfileDir}" \
      --no-first-run \
      --disable-background-networking \
      --disable-component-update \
      --disable-features=MediaRouter,OptimizationHints,Translate \
      --password-store=basic \
      about:blank
  '';
in
{
  config = lib.mkIf enableBrowserMcpServices {
    home.packages = [
      mcpBrowserLifecycle
      chromeDevtoolsBrowserLauncher
    ];

    home.activation.setupSharedBrowserMcpRuntimeDirs =
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        set -euo pipefail

        for dir in \
          "${shared.chromeDevtoolsProfileDir}"
        do
          $DRY_RUN_CMD mkdir -p "$dir"
          $DRY_RUN_CMD chmod 700 "$dir"
        done
      '';

    systemd.user.services.mcp-chrome-devtools-browser = {
      Unit = {
        Description = "Managed Chrome DevTools browser for assistant MCP servers";
        After = [ "sway-session.target" ];
        BindsTo = [ "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${chromeDevtoolsBrowserLauncher}/bin/mcp-chrome-devtools-browser";
        Restart = "on-failure";
        RestartSec = "5s";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    systemd.user.services.mcp-browser-orphan-reaper = {
      Unit = {
        Description = "Reap stale assistant MCP browser processes";
        After = [ "sway-session.target" ];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${mcpBrowserLifecycle}/bin/mcp-browser-lifecycle reap";
      };
    };

    systemd.user.timers.mcp-browser-orphan-reaper = {
      Unit = {
        Description = "Periodic stale assistant MCP browser cleanup";
        After = [ "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };

      Timer = {
        OnBootSec = "5m";
        OnUnitActiveSec = "15m";
        Unit = reaperServiceName;
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    systemd.user.services.mcp-browser-session-cleanup = {
      Unit = {
        Description = "Cleanup assistant MCP browser state on sway session stop";
        After = [ "sway-session.target" ];
        BindsTo = [ "sway-session.target" ];
        PartOf = [ "sway-session.target" ];
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = "${mcpBrowserLifecycle}/bin/mcp-browser-lifecycle cleanup-session";
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
