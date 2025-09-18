{
  config,
  pkgs,
  lib,
  ...
}: let
  snapshotRelative = "home-modules/desktop/generated/plasma-rc2nix.nix";
  defaultFlake = "/etc/nixos#vpittamp";
  plasmaSyncScript = pkgs.writeShellApplication {
    name = "plasma-sync";
    runtimeInputs = [
      pkgs.nix
      pkgs.git
      pkgs.diffutils
      pkgs.findutils
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.gum
      pkgs.nixpkgs-fmt
      pkgs.alejandra
      pkgs.less
      pkgs.bat
      pkgs.home-manager
    ];
    text = ''
            #!/usr/bin/env bash
            set -euo pipefail

            USE_GUM=''${USE_GUM:-1}
            DEFAULT_REPO=''${PLASMA_REPO_ROOT:-/etc/nixos}
            SNAPSHOT_RELATIVE=''${SNAPSHOT_RELATIVE:-${snapshotRelative}}
            FLAKE_REF=''${FLAKE_REF:-${defaultFlake}}

            GUM_BIN="$(command -v gum || true)"

            # Parse global options
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --no-gum)
                  USE_GUM=0
                  shift
                  ;;
                --gum)
                  USE_GUM=1
                  shift
                  ;;
                --flake)
                  if [[ $# -lt 2 ]]; then
                    echo "--flake requires an argument" >&2
                    exit 1
                  fi
                  FLAKE_REF="$2"
                  shift 2
                  ;;
                --snapshot-file)
                  if [[ $# -lt 2 ]]; then
                    echo "--snapshot-file requires an argument" >&2
                    exit 1
                  fi
                  SNAPSHOT_RELATIVE="$2"
                  shift 2
                  ;;
                --repo)
                  if [[ $# -lt 2 ]]; then
                    echo "--repo requires an argument" >&2
                    exit 1
                  fi
                  DEFAULT_REPO="$2"
                  shift 2
                  ;;
                --)
                  shift
                  break
                  ;;
                *)
                  break
                  ;;
              esac
            done

            CMD=''${1:-interactive}
            if [[ $# -gt 0 ]]; then
              shift
            fi

            if [[ "$CMD" == "help" || "$CMD" == "-h" || "$CMD" == "--help" ]]; then
              cat <<'USAGE'
      Usage: plasma-sync [options] [command] [-- command-args]

      Commands:
        snapshot | export   Capture a new Plasma snapshot and rewrite the tracked file
        diff                Show git diff for the tracked snapshot
        activate            Run home-manager switch for the Plasma profile
        full                Snapshot and then activate (use --hm to split Home Manager args)
        interactive | menu  Launch gum-driven workflow (default)
        help                Show this message

      Common options:
        --no-gum            Disable gum UI even for interactive commands
        --gum               Force gum UI (default if available)
        --repo PATH         Override repo root (defaults to /etc/nixos or git toplevel)
        --snapshot-file REL Path to snapshot file relative to repo (default: ${snapshotRelative})
        --flake FLAKE       Flake ref to activate (default: ${defaultFlake})
        --                  Treat remaining args as passthrough to the command (rc2nix or home-manager)

      Examples:
        plasma-sync snapshot
        plasma-sync --no-gum full --hm --show-trace
        plasma-sync activate -- --impure
      USAGE
              exit 0
            fi

            # Determine whether we can use gum UI
            use_gum() {
              [[ "$USE_GUM" -eq 1 && -n "$GUM_BIN" ]]
            }

            run_with_spinner() {
              local title="$1"; shift
              if use_gum; then
                "$GUM_BIN" spin --spinner dot --title "$title" -- "$@"
              else
                "$@"
              fi
            }

            style_msg() {
              local color="$1"; shift
              if use_gum; then
                "$GUM_BIN" style --foreground "$color" "$@"
              else
                printf '%s\n' "$*"
              fi
            }

            style_block() {
              local title="$1"; shift
              local body="$1"; shift
              if use_gum; then
                "$GUM_BIN" style --border double --padding "1 2" --border-foreground 213 --foreground 252 "''${title}" "''${body}"
              else
                printf '*** %s ***\n%s\n' "$title" "$body"
              fi
            }

            repo_root() {
              if git rev-parse --show-toplevel >/dev/null 2>&1; then
                git rev-parse --show-toplevel
              elif [[ -d "$DEFAULT_REPO/.git" ]]; then
                printf '%s\n' "$DEFAULT_REPO"
              elif [[ -d "$DEFAULT_REPO" ]]; then
                printf '%s\n' "$DEFAULT_REPO"
              else
                pwd
              fi
            }

            format_snapshot() {
              local path="$1"
              if command -v alejandra >/dev/null 2>&1; then
                alejandra "$path" >/dev/null 2>&1 || true
              elif command -v nixpkgs-fmt >/dev/null 2>&1; then
                nixpkgs-fmt "$path" >/dev/null 2>&1 || true
              fi
            }

            show_snapshot_diff() {
              local old="$1" new="$2"
              if cmp -s "$old" "$new"; then
                style_msg 82 "No snapshot changes detected."
                return 0
              fi
              local diff_file
              diff_file="$(mktemp)"
              diff -u "$old" "$new" > "$diff_file" || true
              if use_gum; then
                style_block "📊 Snapshot Diff" "$SNAPSHOT_RELATIVE"
                if command -v bat >/dev/null 2>&1; then
                  bat --style=changes --language=diff "$diff_file"
                else
                  "$GUM_BIN" pager < "$diff_file"
                fi
              else
                printf '--- %s (old)\n+++ %s (new)\n' "$old" "$new"
                cat "$diff_file"
              fi
              rm -f "$diff_file"
            }

            git_snapshot_diff() {
              local repo="$1"
              local rel="$2"
              if git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
                if use_gum; then
                  style_block "📈 Git Diff" "$rel"
                  git -C "$repo" --no-pager diff --stat "$rel"
                  git -C "$repo" --no-pager diff "$rel"
                else
                  git -C "$repo" --no-pager diff "$rel"
                fi
              else
                style_msg 226 "Git repository not initialized; skipping git diff."
              fi
            }

            snapshot_action() {
              local repo="$1"; shift || true
              local rel="$SNAPSHOT_RELATIVE"
              local snapshot="$repo/$rel"
              local workdir
              workdir="$(mktemp -d)"
              trap 'rm -rf "${workdir:-}"' EXIT

              local raw="$workdir/raw.nix"
              local old="$workdir/old.nix"
              local newfile="$workdir/new.nix"

              if [[ -f "$snapshot" ]]; then
                cp "$snapshot" "$old"
              else
                touch "$old"
              fi

              style_msg 117 "📥 Exporting Plasma configuration..."
              # shellcheck disable=SC2016
              run_with_spinner "Running plasma-manager rc2nix" \
                bash -c '
                  set -euo pipefail
                  dest="$1"; shift
                  nix run github:nix-community/plasma-manager -- rc2nix "$@" > "$dest"
                ' rc2nix "$raw" "$@"

              local generated
              generated="$(nix eval --impure --expr 'let pkgs = import <nixpkgs> {}; snapshot = import "'"$raw"'"; in pkgs.lib.generators.toPretty { multiline = true; } (builtins.removeAttrs snapshot.programs.plasma ["enable"])' --raw)"

              cat <<'EOF_HEADER' > "$newfile"
      { lib, ... }:
      let
        generated =
      EOF_HEADER

              printf '%s\n' "$generated" >> "$newfile"

              cat <<'EOF_FOOTER' >> "$newfile"
      ;
      in
      {
        programs.plasma = {
          enable = lib.mkDefault true;
        } // generated;
      }
      EOF_FOOTER

              mv "$newfile" "$snapshot"
              format_snapshot "$snapshot"

              style_msg 45 "📄 Snapshot written to $rel"
              show_snapshot_diff "$old" "$snapshot"
              git_snapshot_diff "$repo" "$rel"

              rm -rf "$workdir"
              workdir=""
              trap - EXIT
            }

            activate_action() {
              local repo="$1"; shift || true
              local flake_ref="$FLAKE_REF"
              style_msg 81 "🚀 Running home-manager switch ($flake_ref)..."
              # shellcheck disable=SC2016
              run_with_spinner "home-manager switch" \
                bash -c '
                  set -euo pipefail
                  flake="$1"; shift
                  home-manager switch --flake "$flake" "$@"
                ' hm "$flake_ref" "$@"
            }

            interactive_menu() {
              if ! use_gum; then
                echo "Interactive mode requires gum; re-run with gum installed or use --no-gum snapshot" >&2
                exit 1
              fi
              local repo="$1"; shift || true
              while true; do
                local choice
                choice=$("$GUM_BIN" choose \
                  --header "Plasma snapshot actions" \
                  "Run full pipeline" \
                  "Take snapshot" \
                  "Show current diff" \
                  "Activate configuration" \
                  "Quit")
                case "$choice" in
                  "Run full pipeline")
                    snapshot_action "$repo" "$@"
                    activate_action "$repo" "$@"
                    ;;
                  "Take snapshot")
                    snapshot_action "$repo" "$@"
                    ;;
                  "Show current diff")
                    git_snapshot_diff "$repo" "$SNAPSHOT_RELATIVE"
                    ;;
                  "Activate configuration")
                    activate_action "$repo" "$@"
                    ;;
                  "Quit")
                    break
                    ;;
                esac
              done
            }

            main() {
              local repo
              repo="$(repo_root)"
              case "$CMD" in
                snapshot|export)
                  snapshot_action "$repo" "$@"
                  ;;
                diff)
                  git_snapshot_diff "$repo" "$SNAPSHOT_RELATIVE"
                  ;;
                activate)
                  activate_action "$repo" "$@"
                  ;;
                full)
                  local rc_args=()
                  local hm_args=()
                  local split=0
                  for arg in "$@"; do
                    if [[ "$arg" == "--hm" ]]; then
                      split=1
                      continue
                    fi
                    if [[ $split -eq 0 ]]; then
                      rc_args+=("$arg")
                    else
                      hm_args+=("$arg")
                    fi
                  done
                  snapshot_action "$repo" "''${rc_args[@]}"
                  activate_action "$repo" "''${hm_args[@]}"
                  ;;
                interactive|menu)
                  interactive_menu "$repo" "$@"
                  ;;
                *)
                  echo "Unknown command: $CMD" >&2
                  exit 2
                  ;;
              esac
            }

            main "$@"
    '';
  };

  bashHelpers = ''
    plasma-sync() {
      "${plasmaSyncScript}/bin/plasma-sync" "$@"
    }
    plasma-sync-full() {
      "${plasmaSyncScript}/bin/plasma-sync" full "$@"
    }
    plasma-sync-snapshot() {
      "${plasmaSyncScript}/bin/plasma-sync" snapshot "$@"
    }
    plasma-sync-activate() {
      "${plasmaSyncScript}/bin/plasma-sync" activate "$@"
    }
  '';
in {
  home.packages = [plasmaSyncScript];

  programs.bash.initExtra = lib.mkAfter ''
    # Plasma Manager helpers
    ${bashHelpers}
  '';

  programs.bash.shellAliases = {
    psync = "plasma-sync";
    psync-full = "plasma-sync full";
    psync-activate = "plasma-sync activate";
    psync-snapshot = "plasma-sync snapshot";
  };
}
