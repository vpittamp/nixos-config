{ pkgs, lib }:

let
  auditScript = ./audit.py;

  nixBloatAudit = pkgs.writeShellApplication {
    name = "nix-bloat-audit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.nix
      pkgs.python3
      pkgs.systemd
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${auditScript} "$@"
    '';
  };

  nixUsageLogShell = pkgs.writeShellApplication {
    name = "nix-usage-log-shell";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      shell_name=""
      cwd_path=""
      command_text=""

      while [ $# -gt 0 ]; do
        case "$1" in
          --shell)
            shell_name="$2"
            shift 2
            ;;
          --cwd)
            cwd_path="$2"
            shift 2
            ;;
          --command)
            command_text="$2"
            shift 2
            ;;
          *)
            echo "nix-usage-log-shell: unknown argument: $1" >&2
            exit 2
            ;;
        esac
      done

      if [ -z "$command_text" ]; then
        exit 0
      fi

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-usage-audit"
      mkdir -p "$state_dir"

      sanitize() {
        printf '%s' "$1" | tr '\t\r\n' '   '
      }

      printf '%s\t%s\t%s\t%s\n' \
        "$(${pkgs.coreutils}/bin/date +%s)" \
        "$(sanitize "$shell_name")" \
        "$(sanitize "$cwd_path")" \
        "$(sanitize "$command_text")" \
        >> "$state_dir/shell-commands.tsv"
    '';
  };

  nixUsageLogLaunch = pkgs.writeShellApplication {
    name = "nix-usage-log-launch";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      source_name="desktop-entry"
      app_name=""
      package_name=""
      record_only=0

      while [ $# -gt 0 ]; do
        case "$1" in
          --source)
            source_name="$2"
            shift 2
            ;;
          --app)
            app_name="$2"
            shift 2
            ;;
          --package)
            package_name="$2"
            shift 2
            ;;
          --record-only)
            record_only=1
            shift
            ;;
          --)
            shift
            break
            ;;
          *)
            echo "nix-usage-log-launch: unknown argument: $1" >&2
            exit 2
            ;;
        esac
      done

      if [ -n "$app_name" ] || [ -n "$package_name" ]; then
        state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nix-usage-audit"
        mkdir -p "$state_dir"

        sanitize() {
          printf '%s' "$1" | tr '\t\r\n' '   '
        }

        printf '%s\t%s\t%s\t%s\n' \
          "$(${pkgs.coreutils}/bin/date +%s)" \
          "$(sanitize "$source_name")" \
          "$(sanitize "$app_name")" \
          "$(sanitize "$package_name")" \
          >> "$state_dir/desktop-launches.tsv"
      fi

      if [ "$record_only" -eq 1 ] || [ $# -eq 0 ]; then
        exit 0
      fi

      exec "$@"
    '';
  };
in
pkgs.symlinkJoin {
  name = "nix-bloat-audit-tools";
  paths = [
    nixBloatAudit
    nixUsageLogShell
    nixUsageLogLaunch
  ];

  meta = with lib; {
    description = "Host-aware NixOS package bloat audit and lightweight usage telemetry helpers";
    platforms = platforms.linux;
  };
}
