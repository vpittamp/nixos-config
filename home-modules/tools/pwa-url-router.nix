# Feature 113: PWA URL Router
# Routes HTTP/HTTPS URLs to appropriate PWAs based on domain matching
# Falls back to Firefox for non-matching URLs
{ config, lib, pkgs, ... }:

with lib;

let
  # Import centralized PWA site definitions
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
  pwas = pwaSitesConfig.pwaSites;

  # Generate PWA app name from display name (e.g., "GitHub" → "github-pwa")
  mkPwaAppName = name: "${toLower (replaceStrings [" "] ["-"] name)}-pwa";

  # Build domain → PWA mapping from routing_domains
  # Only include PWAs that have non-empty routing_domains
  domainMapping = let
    # For each PWA with routing_domains, create entries for each domain
    pwaEntries = builtins.concatMap (pwa:
      let
        domains = if pwa ? routing_domains then pwa.routing_domains else [ pwa.domain ];
        appName = mkPwaAppName pwa.name;
      in
      if domains == [] then []
      else builtins.map (domain: {
        inherit domain;
        pwa = appName;
        ulid = pwa.ulid;
        name = pwa.name;
      }) domains
    ) pwas;
  in
  builtins.listToAttrs (builtins.map (entry: {
    name = entry.domain;
    value = {
      pwa = entry.pwa;
      ulid = entry.ulid;
      name = entry.name;
    };
  }) pwaEntries);

  # Generate JSON registry file
  domainRegistryJson = builtins.toJSON domainMapping;

  # URL Router shell script
  urlRouterScript = pkgs.writeShellScriptBin "pwa-url-router" ''
    #!/usr/bin/env bash
    # Feature 113: URL Router - Open URLs in PWAs when domain matches
    # Only handles external app links; Firefox internal links stay in Firefox

    set -euo pipefail

    URL="''${1:-}"
    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"
    LOG_DIR="$HOME/.local/state"
    LOG_FILE="$LOG_DIR/pwa-url-router.log"

    # Ensure log directory exists
    mkdir -p "$LOG_DIR"

    log() {
      echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
    }

    # Rotate log if too large (>1MB)
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)" -gt 1048576 ]; then
      mv "$LOG_FILE" "$LOG_FILE.old"
    fi

    if [ -z "$URL" ]; then
      log "ERROR: No URL provided"
      # Still open Firefox with no URL (new window)
      exec ${pkgs.firefox}/bin/firefox
    fi

    log "Routing URL: $URL"

    # Extract domain from URL (handles http://, https://, and URLs with ports/paths)
    DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|/.*||' | ${pkgs.gnused}/bin/sed -E 's|:.*||')

    log "Extracted domain: $DOMAIN"

    # Look up domain in registry
    if [ -f "$DOMAIN_REGISTRY" ]; then
      PWA_INFO=$(${pkgs.jq}/bin/jq -r --arg d "$DOMAIN" '.[$d] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")

      if [ -n "$PWA_INFO" ] && [ "$PWA_INFO" != "null" ]; then
        PWA_DISPLAY=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.name')
        PWA_APP_NAME=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.pwa')
        PWA_ULID=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.ulid')
        log "Match found: $DOMAIN → $PWA_APP_NAME ($PWA_DISPLAY, ULID: $PWA_ULID)"

        # Launch PWA through app-launcher-wrapper for proper i3pm tracking
        # Set I3PM_PWA_URL for deep linking - launch-pwa-by-name will pick this up
        if command -v app-launcher-wrapper.sh >/dev/null 2>&1; then
          log "Launching via wrapper: I3PM_PWA_URL=\"$URL\" app-launcher-wrapper.sh \"$PWA_APP_NAME\""
          export I3PM_PWA_URL="$URL"
          exec app-launcher-wrapper.sh "$PWA_APP_NAME"
        elif command -v launch-pwa-by-name >/dev/null 2>&1; then
          # Fallback: direct launch (won't have proper i3pm tracking)
          log "WARNING: app-launcher-wrapper.sh not found, using direct launch (no i3pm tracking)"
          log "Launching: launch-pwa-by-name \"$PWA_DISPLAY\" \"$URL\""
          exec launch-pwa-by-name "$PWA_DISPLAY" "$URL"
        else
          log "ERROR: No launcher found, falling back to Firefox"
          exec ${pkgs.firefox}/bin/firefox "$URL"
        fi
      fi
    else
      log "WARNING: Domain registry not found at $DOMAIN_REGISTRY"
    fi

    # No match - fallback to Firefox
    log "No PWA match for $DOMAIN, opening in Firefox"
    exec ${pkgs.firefox}/bin/firefox "$URL"
  '';

  # Diagnostic tool for testing routing
  routeTestScript = pkgs.writeShellScriptBin "pwa-route-test" ''
    #!/usr/bin/env bash
    # Feature 113: Test PWA URL routing without actually opening anything

    URL="''${1:-}"
    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"

    if [ -z "$URL" ]; then
      echo "Usage: pwa-route-test <url>"
      echo "Example: pwa-route-test https://github.com/user/repo"
      exit 1
    fi

    # Extract domain from URL
    DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|/.*||' | ${pkgs.gnused}/bin/sed -E 's|:.*||')

    echo "URL: $URL"
    echo "Domain: $DOMAIN"
    echo ""

    if [ ! -f "$DOMAIN_REGISTRY" ]; then
      echo "ERROR: Domain registry not found at $DOMAIN_REGISTRY"
      echo "Run: nixos-rebuild switch to generate it"
      exit 1
    fi

    PWA_INFO=$(${pkgs.jq}/bin/jq -r --arg d "$DOMAIN" '.[$d] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")

    if [ -n "$PWA_INFO" ] && [ "$PWA_INFO" != "null" ]; then
      PWA_NAME=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.pwa')
      PWA_DISPLAY=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.name')
      PWA_ULID=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.ulid')
      echo "✓ Would route to: $PWA_NAME"
      echo "  Display name: $PWA_DISPLAY"
      echo "  ULID: $PWA_ULID"
    else
      echo "✗ No PWA match - would open in Firefox"
    fi
  '';

in
{
  options.programs.pwa-url-router = {
    enable = mkEnableOption "PWA URL routing for external links";
  };

  config = mkIf config.programs.pwa-url-router.enable {
    # Install router scripts
    home.packages = [
      urlRouterScript
      routeTestScript
    ];

    # Generate domain registry JSON
    xdg.configFile."i3/pwa-domains.json" = {
      text = domainRegistryJson;
    };

    # Generate desktop entry for URL handler
    home.file.".local/share/applications/pwa-url-router.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=PWA URL Router
      Comment=Routes URLs to PWAs or Firefox based on domain (Feature 113)
      Exec=${urlRouterScript}/bin/pwa-url-router %u
      Terminal=false
      NoDisplay=true
      MimeType=x-scheme-handler/http;x-scheme-handler/https;
      StartupNotify=false
      Categories=Network;WebBrowser;
    '';
  };
}
