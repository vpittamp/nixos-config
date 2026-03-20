# 1Password home-manager configuration
# Manages user-specific 1Password settings
{ config, lib, pkgs, ... }:

let
  onePasswordPwaAudit = pkgs.writeShellScriptBin "1password-pwa-audit" ''
    #!/usr/bin/env bash
    set -euo pipefail

    OP="$(command -v op || true)"
    if [[ -z "$OP" ]]; then
      OP="${pkgs._1password-cli}/bin/op"
    fi
    JQ="${pkgs.jq}/bin/jq"
    REGISTRY="$HOME/.config/i3/application-registry.json"
    JSON_OUTPUT=0

    if [[ "''${1:-}" == "--json" ]]; then
      JSON_OUTPUT=1
      shift
    fi

    if [[ ! -f "$REGISTRY" ]]; then
      echo "Missing application registry: $REGISTRY" >&2
      exit 1
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    pwa_json="$tmp_dir/pwas.json"

    "$JQ" '
      [
        .applications[]
        | select(.name | endswith("-pwa"))
        | select((.pwa_match_domains // []) | length > 1)
        | {
            app_name: .name,
            display_name: .display_name,
            preferred_workspace: .preferred_workspace,
            login_domains: (
              (.pwa_match_domains // [])
              | map(ascii_downcase | sub("^www\\."; ""))
              | unique
            )
          }
      ]
    ' "$REGISTRY" > "$pwa_json"

    if ! "$OP" whoami --format json >/dev/null 2>&1; then
      if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        "$JQ" '{ signed_in: false, pwas: . }' "$pwa_json"
      else
        echo "1Password CLI is not signed in. Static PWA login-domain audit:"
        "$JQ" -r '
          .[]
          | "\(.display_name) [WS \(.preferred_workspace)]\n  domains: \(.login_domains | join(", "))\n"
        ' "$pwa_json"
        echo "Sign in with: op signin"
        echo "Then rerun: 1password-pwa-audit"
      fi
      exit 0
    fi

    items_json="$tmp_dir/items.json"
    "$OP" item list --categories Login --format json | "$OP" item get - --format json > "$items_json"

    "$JQ" -n \
      --slurpfile pwas "$pwa_json" \
      --slurpfile items "$items_json" '
      def norm_domain:
        sub("^https?://"; "")
        | sub("^www\\."; "")
        | split("/")[0]
        | split("?")[0]
        | split("#")[0]
        | split(":")[0]
        | ascii_downcase;

      def item_domains($item):
        (
          (($item.urls // []) | map(.href // empty))
          + [($item.url // empty)]
        )
        | map(select(type == "string" and length > 0) | norm_domain)
        | unique;

      def title_matches($item; $pwa):
        (($item.title // "") | ascii_downcase) == (($pwa.display_name // "") | ascii_downcase);

      {
        signed_in: true,
        pwas: (
          $pwas[0]
          | map(
              . as $pwa
              | (
                  $items[0]
                  | map(
                      . as $item
                      | {
                          id: $item.id,
                          title: $item.title,
                          vault: ($item.vault.name // $item.vault.id // ""),
                          domains: item_domains($item)
                        }
                    )
                  | map(
                      select(
                        title_matches(.; $pwa)
                        or ([ .domains[] | select($pwa.login_domains | index(.)) ] | length > 0)
                      )
                    )
                ) as $matches
              | . + {
                  matching_items: $matches,
                  covered_domains: ($matches | map(.domains[]) | unique | sort),
                  missing_domains: (
                    [.login_domains[] | select((($matches | map(.domains[]) | unique) | index(.)) | not)]
                    | unique
                    | sort
                  )
                }
            )
        )
      }' > "$tmp_dir/report.json"

    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
      cat "$tmp_dir/report.json"
    else
      "$JQ" -r '
        .pwas[]
        | "\(.display_name) [WS \(.preferred_workspace)]\n"
          + "  expected domains: \(.login_domains | join(", "))\n"
          + (
              if (.matching_items | length) == 0 then
                "  matching items: none\n"
              else
                "  matching items:\n"
                + (
                    .matching_items
                    | map("    - \(.title) [\(.id)] in \(.vault) :: \(.domains | join(", "))")
                    | join("\n")
                  ) + "\n"
              end
            )
          + "  missing domains: "
          + (
              if (.missing_domains | length) == 0
              then "none"
              else (.missing_domains | join(", "))
              end
            ) + "\n"
      ' "$tmp_dir/report.json"
      echo "To add missing domains to a Login item:"
      echo "  1password-pwa-fix <app-name> <item-id> [--vault <vault>]"
    fi
  '';

  pwa1passwordInit = pkgs.writeShellScriptBin "pwa-1password-init" ''
    #!/usr/bin/env bash
    set -euo pipefail

    cat <<'EOF'
Current Chrome PWA launches use the main Chrome profile.

No per-PWA 1Password bootstrap is required anymore.

If browser unlock/fill is broken, check:
  1. 1password-chrome-status
  2. systemctl --user status onepassword-gui.service
  3. journalctl --user -u onepassword-gui.service -n 100 --no-pager

Legacy isolated profiles may still exist under ~/.local/share/webapps, but they
are no longer the active 1Password path for launch-pwa-by-name.
EOF
  '';

  onePasswordPwaFix = pkgs.writeShellScriptBin "1password-pwa-fix" ''
    #!/usr/bin/env bash
    set -euo pipefail

    OP="$(command -v op || true)"
    if [[ -z "$OP" ]]; then
      OP="${pkgs._1password-cli}/bin/op"
    fi
    JQ="${pkgs.jq}/bin/jq"
    REGISTRY="$HOME/.config/i3/application-registry.json"

    if [[ $# -lt 2 ]]; then
      echo "Usage: 1password-pwa-fix <app-name> <item-id-or-name> [--vault <vault>] [--dry-run]" >&2
      exit 1
    fi

    APP_NAME="$1"
    ITEM_REF="$2"
    shift 2

    VAULT_ARGS=()
    DRY_RUN=0

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --vault)
          VAULT_ARGS+=(--vault "$2")
          shift 2
          ;;
        --dry-run)
          DRY_RUN=1
          shift
          ;;
        *)
          echo "Unknown argument: $1" >&2
          exit 1
          ;;
      esac
    done

    if [[ ! -f "$REGISTRY" ]]; then
      echo "Missing application registry: $REGISTRY" >&2
      exit 1
    fi

    if ! "$OP" whoami --format json >/dev/null 2>&1; then
      echo "1Password CLI is not signed in. Run: op signin" >&2
      exit 1
    fi

    app_json="$("$JQ" -c --arg app "$APP_NAME" '
      .applications[]
      | select(.name == $app)
      | {
          app_name: .name,
          display_name: .display_name,
          login_domains: (
            (.pwa_match_domains // [])
            | map(ascii_downcase | sub("^www\\."; ""))
            | unique
          )
        }
    ' "$REGISTRY")"

    if [[ -z "$app_json" ]]; then
      echo "PWA not found in application registry: $APP_NAME" >&2
      exit 1
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    item_json="$tmp_dir/item.json"

    "$OP" item get "$ITEM_REF" "''${VAULT_ARGS[@]}" --format json > "$item_json"

    if ! "$JQ" empty "$item_json" >/dev/null 2>&1; then
      echo "Failed to parse item JSON for $ITEM_REF" >&2
      exit 1
    fi

    updated_json="$tmp_dir/item-updated.json"
    "$JQ" --argjson app "$app_json" '
      def norm_domain:
        sub("^https?://"; "")
        | sub("^www\\."; "")
        | split("/")[0]
        | split("?")[0]
        | split("#")[0]
        | split(":")[0]
        | ascii_downcase;

      def current_urls:
        (
          ((.urls // []) | map(.href // empty))
          + [(.url // empty)]
        )
        | map(select(type == "string" and length > 0));

      def current_domains:
        current_urls | map(norm_domain) | unique;

      . as $item
      | (current_domains) as $existing_domains
      | ($app.login_domains | map(select(($existing_domains | index(.)) | not))) as $missing_domains
      | .urls = (
          ($item.urls // [])
          + (
              $missing_domains
              | map({
                  label: ("PWA auth: " + .),
                  primary: false,
                  href: ("https://" + . + "/")
                })
            )
        )
      | . + { _pwa_missing_domains: $missing_domains }
    ' "$item_json" > "$updated_json"

    missing_count="$("$JQ" '._pwa_missing_domains | length' "$updated_json")"
    if [[ "$missing_count" -eq 0 ]]; then
      echo "No missing domains for $ITEM_REF"
      exit 0
    fi

    echo "Adding domains to $ITEM_REF:"
    "$JQ" -r '._pwa_missing_domains[] | "  - \(.)"' "$updated_json"

    clean_json="$tmp_dir/item-clean.json"
    "$JQ" 'del(._pwa_missing_domains)' "$updated_json" > "$clean_json"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "Dry run only. Updated item template:"
      cat "$clean_json"
      exit 0
    fi

    cat "$clean_json" | "$OP" item edit "$ITEM_REF" "''${VAULT_ARGS[@]}" >/dev/null
    echo "Updated $ITEM_REF"
  '';
in
{
  home.packages = [
    onePasswordPwaAudit
    onePasswordPwaFix
    pwa1passwordInit
  ];

  # Create 1Password settings directory structure
  # Note: 1Password uses authenticated settings with HMAC tags that cannot be set declaratively
  # These settings must be configured through the 1Password GUI and will persist across rebuilds
  # The settings are stored in ~/.config/1Password/settings/settings.json
  home.activation.onePasswordSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Create 1Password config directories
    mkdir -p $HOME/.config/1Password/settings
    mkdir -p $HOME/.config/1Password/Data
    
    # Important settings that need to be enabled manually in 1Password GUI:
    # 1. Settings → Developer → "Integrate with 1Password CLI" (enables CLI integration)
    # 2. Settings → Security → "Unlock using system authentication service" (enables biometric/system auth)
    # 3. Settings → Developer → "Use SSH agent" (enables SSH key management)
    # 4. Settings → Security → Adjust auto-lock timeout to preference for the desktop app
    # 5. Settings → Appearance/General → Keep in system tray / minimize to tray if desired
    # 
    # These settings will persist across NixOS rebuilds as they're stored in the user's home directory
    
    # Check if settings exist and provide guidance
    if [ ! -f $HOME/.config/1Password/settings/settings.json ]; then
      echo "=================================================================================="
      echo "1Password First-Time Setup Required:"
      echo ""
      echo "Please open 1Password and configure the following settings:"
      echo "1. Settings → Developer → Enable 'Integrate with 1Password CLI'"
      echo "2. Settings → Security → Enable 'Unlock using system authentication service'"
      echo "3. Settings → Developer → Enable 'Use SSH agent' (for Git authentication)"
      echo "4. Settings → Security → Set your preferred auto-lock timeout for the app"
      echo "5. Optional: enable tray/minimize-to-tray behavior in the app"
      echo "6. Optional: run '1password-pwa-audit' after CLI integration is enabled"
      echo ""
      echo "These settings will persist across system rebuilds."
      echo "=================================================================================="
    elif ! grep -q '"developers.cliSharedLockState.enabled": true' $HOME/.config/1Password/settings/settings.json 2>/dev/null; then
      echo "Note: 1Password CLI integration may not be enabled. Check Settings → Developer"
    fi
  '';

  # Note: SSH_AUTH_SOCK is set in onepassword-env.nix with platform-aware paths
}
