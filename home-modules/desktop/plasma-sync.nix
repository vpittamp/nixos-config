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

            CACHE_DIR=''${PLASMA_SYNC_CACHE:-"$HOME/.cache/plasma-sync"}
            mkdir -p "$CACHE_DIR" 2>/dev/null || true
            LAST_SNAPSHOT_DIFF_FILE="$CACHE_DIR/last-diff.patch"
            LAST_SNAPSHOT_RAW_FILE="$CACHE_DIR/last-raw.nix"
            LAST_SNAPSHOT_MODULE_FILE="$CACHE_DIR/last-generated.nix"
            LAST_SNAPSHOT_TIMESTAMP=""
            LAST_SNAPSHOT_HAS_DIFF=0
            SNAPSHOT_FOLLOWUP_MODE="auto"

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

      🔍 PLASMA CONFIGURATION ANALYSIS & SYNC TOOL
      Note: System uses declarative plasma-manager configuration, not rc2nix output

      Commands:
        snapshot | export   Capture a new Plasma snapshot for analysis
        diff                Show the cached rc2nix diff
        git-diff            Compare the tracked snapshot against git HEAD
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
        plasma-sync snapshot           # Analyze current plasma config
        plasma-sync diff               # View differences
        plasma-sync activate           # Apply configuration (if using rc2nix)
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

            view_with_pager() {
              local title="$1"; shift
              local path="$1"; shift
              local lang=''${1:-}
              if [[ ! -f "$path" ]]; then
                style_msg 226 "No data available for ''${title}."
                return 1
              fi
              if [[ ! -s "$path" ]]; then
                style_msg 82 "''${title} – no changes detected."
                return 0
              fi
              if use_gum; then
                style_block "$title" "$path"
                if command -v bat >/dev/null 2>&1; then
                  if [[ -n "$lang" ]]; then
                    bat --style=changes --language="$lang" "$path"
                  else
                    bat "$path"
                  fi
                else
                  "$GUM_BIN" pager < "$path"
                fi
              else
                printf -- '--- %s ---\n' "$title"
                cat "$path"
              fi
            }

            choose_option() {
              local header="$1"; shift
              local options=("$@")
              local choice=""
              if use_gum && [[ -t 0 && -t 1 ]]; then
                if ! choice=$("$GUM_BIN" choose --header "$header" "''${options[@]}" 2>/dev/null); then
                  echo "Quit"
                  return 0
                fi
              else
                printf '%s\n' "$header"
                local idx=1
                for opt in "''${options[@]}"; do
                  printf '  %d) %s\n' "$idx" "$opt"
                  idx=$((idx + 1))
                done
                local selection
                while true; do
                  read -rp "Select option [1-''${#options[@]}] (q to quit): " selection || { echo "Quit"; return 0; }
                  if [[ "$selection" =~ ^[Qq]$ ]]; then
                    echo "Quit"
                    return 0
                  fi
                  if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ''${#options[@]} )); then
                    choice="''${options[$((selection - 1))]}"
                    break
                  fi
                  echo "Invalid selection." >&2
                done
              fi
              echo "$choice"
            }

            write_diff_cache() {
              local old="$1" new="$2"
              if [[ -z "$LAST_SNAPSHOT_DIFF_FILE" ]]; then
                return
              fi
              if diff -u "$old" "$new" > "$LAST_SNAPSHOT_DIFF_FILE"; then
                LAST_SNAPSHOT_HAS_DIFF=0
              else
                LAST_SNAPSHOT_HAS_DIFF=1
              fi
            }

            record_snapshot_artifacts() {
              local raw="$1"
              local generated="$2"
              cp "$raw" "$LAST_SNAPSHOT_RAW_FILE" 2>/dev/null || true
              cp "$generated" "$LAST_SNAPSHOT_MODULE_FILE" 2>/dev/null || true
              LAST_SNAPSHOT_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
            }

            display_snapshot_diff() {
              if [[ ''${LAST_SNAPSHOT_HAS_DIFF:-0} -eq 0 ]]; then
                style_msg 82 "No snapshot differences recorded yet."
                return 0
              fi
              view_with_pager "📊 Snapshot Diff" "$LAST_SNAPSHOT_DIFF_FILE" diff
            }

            display_raw_snapshot() {
              view_with_pager "🧾 Raw rc2nix Export" "$LAST_SNAPSHOT_RAW_FILE" nix
            }

            display_generated_snapshot() {
              view_with_pager "🧩 Generated Module" "$LAST_SNAPSHOT_MODULE_FILE" nix
            }

            display_git_diff() {
              local repo="$1"
              local rel="$2"
              if ! git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
                style_msg 226 "Git repository not initialized; skipping git diff."
                return 1
              fi

              local mode="Full diff"
              if use_gum; then
                mode=$("$GUM_BIN" choose --header "Select git diff view" "Summary" "Full diff" "Both" 2>/dev/null)
                mode=''${mode:-Full diff}
              fi

              local show_summary=0
              local show_full=0
              case "$mode" in
                "Summary") show_summary=1 ;;
                "Both") show_summary=1; show_full=1 ;;
                *) show_full=1 ;;
              esac

              if [[ $show_summary -eq 1 ]]; then
                local summary
                summary=$(git -C "$repo" --no-pager diff --stat HEAD -- "$rel" || true)
                if [[ -z "$summary" ]]; then
                  style_msg 82 "No pending git changes for $rel."
                else
                  if use_gum; then
                    style_block "📈 Git Diff (Summary)" "$rel"
                  fi
                  printf '%s\n' "$summary"
                fi
              fi

              if [[ $show_full -eq 1 ]]; then
                local diff_file="$CACHE_DIR/git-diff.patch"
                git -C "$repo" --no-pager diff HEAD -- "$rel" > "$diff_file"
                view_with_pager "📈 Git Diff" "$diff_file" diff
              fi
            }

            display_git_status() {
              local repo="$1"
              if ! git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then
                style_msg 226 "Git repository not initialized; skipping status."
                return 1
              fi
              if use_gum; then
                style_block "📋 Git Status" "$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
                git -C "$repo" status --short --branch | "$GUM_BIN" pager
              else
                git -C "$repo" status --short --branch
              fi
            }

            view_docs() {
              local repo="$1"
              local doc_path="$repo/docs/PLASMA_MANAGER.md"
              if [[ ! -f "$doc_path" ]]; then
                style_msg 226 "Documentation not found at $doc_path"
                return 1
              fi
              view_with_pager "📚 Plasma Manager Docs" "$doc_path"
            }

            snapshot_followup_menu() {
              local repo="$1"
              local header="Snapshot captured ''${LAST_SNAPSHOT_TIMESTAMP:-} – select next action"
              while true; do
                local choice
                choice=$(choose_option "$header" \
                  "View snapshot diff" \
                  "View raw rc2nix export" \
                  "View generated module" \
                  "View git diff" \
                  "Show git status" \
                  "Activate configuration" \
                  "Back to main menu")
                case "$choice" in
                  "View snapshot diff")
                    display_snapshot_diff
                    ;;
                  "View raw rc2nix export")
                    display_raw_snapshot
                    ;;
                  "View generated module")
                    display_generated_snapshot
                    ;;
                  "View git diff")
                    display_git_diff "$repo" "$SNAPSHOT_RELATIVE"
                    ;;
                  "Show git status")
                    display_git_status "$repo"
                    ;;
                  "Activate configuration")
                    activate_action "$repo"
                    ;;
                  "Back to main menu"|"Quit"|*)
                    break
                    ;;
                esac
              done
            }

            snapshot_followup() {
              local repo="$1"
              case "''${SNAPSHOT_FOLLOWUP_MODE:-auto}" in
                skip)
                  ;;
                menu)
                  snapshot_followup_menu "$repo"
                  ;;
                *)
                  if use_gum && [[ -t 1 ]]; then
                    snapshot_followup_menu "$repo"
                  fi
                  ;;
              esac
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

            git_snapshot_diff() {
              local repo="$1"
              display_git_diff "$repo" "$SNAPSHOT_RELATIVE"
            }

            snapshot_action() {
              local repo="$1"; shift || true
              local rel="$SNAPSHOT_RELATIVE"
              local snapshot="$repo/$rel"
              mkdir -p "$(dirname "$snapshot")"
              local workdir
              workdir="$(mktemp -d)"
              trap 'rm -rf "''${workdir:-}"' EXIT

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

              write_diff_cache "$old" "$snapshot"
              record_snapshot_artifacts "$raw" "$snapshot"

              if [[ ''${LAST_SNAPSHOT_HAS_DIFF:-0} -eq 1 ]]; then
                style_msg 45 "📄 Snapshot updated at $rel (diff cached)."
              else
                style_msg 82 "📄 Snapshot matches existing state; no changes detected."
              fi

              snapshot_followup "$repo"

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
              # Check if we have a TTY for interactive mode first
              if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
                echo "Error: Interactive mode requires a TTY. You can:" >&2
                echo "  1. Run specific commands directly: plasma-sync snapshot, plasma-sync activate, etc." >&2
                echo "  2. Use --no-gum flag: plasma-sync --no-gum snapshot" >&2
                echo "  3. Run in a proper terminal (Konsole, Yakuake, etc.)" >&2
                exit 1
              fi

              # Check if gum is available
              if ! command -v "$GUM_BIN" >/dev/null 2>&1; then
                echo "Interactive mode requires gum to be installed" >&2
                echo "Run: nix-shell -p gum" >&2
                exit 1
              fi

              local repo="$1"; shift || true

              # Get current status for display
              local snapshot_status="Unknown"
              if [[ -f "$LAST_SNAPSHOT_TIMESTAMP" ]]; then
                snapshot_status="Last: $LAST_SNAPSHOT_TIMESTAMP"
              elif [[ -f "$repo/$SNAPSHOT_RELATIVE" ]]; then
                snapshot_status="Config exists"
              else
                snapshot_status="Not initialized"
              fi

              while true; do
                local choice
                choice=$("$GUM_BIN" choose \
                  --header "🌀 Plasma Analysis Tool | Status: $snapshot_status" \
                  "📸 Take snapshot (rc2nix)" \
                  "🚀 Run full workflow (snapshot + activate)" \
                  "✨ Activate configuration" \
                  "📊 View snapshot diff" \
                  "📄 View raw rc2nix export" \
                  "🧩 View generated module" \
                  "📈 View git diff" \
                  "📋 Show git status" \
                  "📚 Open docs" \
                  "❌ Exit")

                case "$choice" in
                  "📸 Take snapshot (rc2nix)")
                    style_msg 117 "📸 Taking Plasma configuration snapshot..."
                    SNAPSHOT_FOLLOWUP_MODE="skip"
                    snapshot_action "$repo" "$@"
                    SNAPSHOT_FOLLOWUP_MODE="auto"
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "🚀 Run full workflow"*)
                    if "$GUM_BIN" confirm "This will snapshot and then activate. Continue?"; then
                      style_msg 117 "🚀 Running full workflow..."
                      SNAPSHOT_FOLLOWUP_MODE="skip"
                      snapshot_action "$repo" "$@"
                      SNAPSHOT_FOLLOWUP_MODE="auto"
                      echo ""
                      activate_action "$repo" "$@"
                      echo ""
                      "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                      read -r
                    fi
                    ;;
                  "✨ Activate configuration")
                    if "$GUM_BIN" confirm "Apply Plasma configuration with home-manager?"; then
                      activate_action "$repo" "$@"
                      echo ""
                      "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                      read -r
                    fi
                    ;;
                  "📊 View snapshot diff")
                    display_snapshot_diff
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "📄 View raw rc2nix export")
                    display_raw_snapshot
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "🧩 View generated module")
                    display_generated_snapshot
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "📈 View git diff")
                    display_git_diff "$repo" "$SNAPSHOT_RELATIVE"
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "📋 Show git status")
                    display_git_status "$repo"
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "📚 Open docs")
                    view_docs "$repo"
                    echo ""
                    "$GUM_BIN" style --foreground 82 "Press Enter to continue..."
                    read -r
                    ;;
                  "❌ Exit"|*)
                    break
                    ;;
                esac

                # Update status after each action
                if [[ -f "$LAST_SNAPSHOT_TIMESTAMP" ]]; then
                  snapshot_status="Last: $LAST_SNAPSHOT_TIMESTAMP"
                elif [[ -f "$repo/$SNAPSHOT_RELATIVE" ]]; then
                  snapshot_status="Config exists"
                else
                  snapshot_status="Not initialized"
                fi
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
                  display_snapshot_diff
                  ;;
                git-diff)
                  display_git_diff "$repo" "$SNAPSHOT_RELATIVE"
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
