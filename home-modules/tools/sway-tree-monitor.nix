{ config, lib, pkgs, ... }:

let
  # Build sway-tree-monitor Python package from local source
  sway-tree-monitor = pkgs.python3Packages.buildPythonPackage {
    pname = "sway-tree-monitor";
    version = "1.1.5";  # Fixed ActionType enum mismatch - simplified semantic relevance scoring to work with actual BINDING/KEYPRESS/MOUSE_CLICK/IPC_COMMAND values

    src = ./sway-tree-monitor;

    format = "other";

    propagatedBuildInputs = with pkgs.python3Packages; [
      i3ipc
      orjson
      psutil
      pydantic
      xxhash
      textual
      rich
    ];

    installPhase = ''
      mkdir -p $out/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_tree_monitor
      cp -r * $out/lib/python${pkgs.python3.pythonVersion}/site-packages/sway_tree_monitor/
    '';

    meta = with lib; {
      description = "Sway tree diff monitor daemon - real-time window state monitoring";
      license = licenses.mit;
    };
  };

  # Python environment with all dependencies
  python-env = pkgs.python3.withPackages (ps: [
    sway-tree-monitor
  ]);

  # Wrapper script for the daemon
  sway-tree-monitor-daemon = pkgs.writeShellScriptBin "sway-tree-monitor-daemon" ''
    # Find user runtime directory
    USER_ID=$(${pkgs.coreutils}/bin/id -u)
    USER_RUNTIME_DIR="/run/user/$USER_ID"

    # Find Sway IPC socket (matches pattern: sway-ipc.*.sock)
    SWAY_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)

    if [ -n "$SWAY_SOCK" ]; then
      export SWAYSOCK="$SWAY_SOCK"
      export I3SOCK="$SWAY_SOCK"  # i3ipc library checks both
      echo "Found Sway IPC socket: $SWAY_SOCK" >&2
    else
      echo "ERROR: No Sway IPC socket found in $USER_RUNTIME_DIR" >&2
      exit 1
    fi

    # Set WAYLAND_DISPLAY
    WAYLAND_SOCK=$(${pkgs.findutils}/bin/find "$USER_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -type s 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)
    if [ -n "$WAYLAND_SOCK" ]; then
      WAYLAND_DISPLAY=$(${pkgs.coreutils}/bin/basename "$WAYLAND_SOCK")
      export WAYLAND_DISPLAY
      export XDG_RUNTIME_DIR="$USER_RUNTIME_DIR"
    fi

    # Set Python environment
    export PYTHONUNBUFFERED=1
    export LOG_LEVEL="INFO"
    export BUFFER_SIZE="500"

    exec ${python-env}/bin/python -m sway_tree_monitor.daemon
  '';

in
{
  # Install the package and daemon wrapper
  home.packages = [ sway-tree-monitor-daemon ];

  # Systemd service for the daemon
  systemd.user.services.sway-tree-monitor = {
    Unit = {
      Description = "Sway Tree Diff Monitor - Real-time window state monitoring";
      Documentation = "file:///etc/nixos/specs/064-sway-tree-diff-monitor/quickstart.md";
      After = [ "sway-session.target" ];
      Requires = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${sway-tree-monitor-daemon}/bin/sway-tree-monitor-daemon";
      Restart = "on-failure";
      RestartSec = "2";

      # Resource limits (from Feature 064 spec)
      MemoryHigh = "40M";
      MemoryMax = "50M";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
    };

    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}
