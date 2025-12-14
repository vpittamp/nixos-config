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

  # Build domain/path → PWA mapping from routing_domains and routing_paths
  # Feature 118: Added path-based routing support
  domainMapping = let
    # For each PWA, create entries for:
    # 1. Each domain in routing_domains (domain-only key)
    # 2. Each path in routing_paths combined with domain (domain/path key)
    pwaEntries = builtins.concatMap (pwa:
      let
        domains = if pwa ? routing_domains then pwa.routing_domains else [ pwa.domain ];
        paths = if pwa ? routing_paths then pwa.routing_paths else [];
        appName = mkPwaAppName pwa.name;

        # Domain-only entries (from routing_domains)
        domainEntries = if domains == [] then []
          else builtins.map (domain: {
            key = domain;
            pwa = appName;
            ulid = pwa.ulid;
            name = pwa.name;
          }) domains;

        # Path-based entries (from routing_paths, combined with primary domain)
        # Format: "google.com/ai" for routing_paths = [ "/ai" ]
        # Also generates www variant if domain doesn't start with www
        pathEntries = builtins.concatMap (path:
          let
            # Normalize path: ensure it starts with / and remove trailing /
            normalizedPath = if builtins.substring 0 1 path == "/"
              then path
              else "/${path}";
            cleanPath = builtins.replaceStrings ["//"] ["/"] normalizedPath;
            baseEntry = {
              key = "${pwa.domain}${cleanPath}";
              pwa = appName;
              ulid = pwa.ulid;
              name = pwa.name;
            };
            # Add www variant if domain doesn't already have www prefix
            wwwEntry = if !(lib.hasPrefix "www." pwa.domain)
              then [{
                key = "www.${pwa.domain}${cleanPath}";
                pwa = appName;
                ulid = pwa.ulid;
                name = pwa.name;
              }]
              else [];
          in
          [ baseEntry ] ++ wwwEntry
        ) paths;
      in
      domainEntries ++ pathEntries
    ) pwas;
  in
  builtins.listToAttrs (builtins.map (entry: {
    name = entry.key;
    value = {
      pwa = entry.pwa;
      ulid = entry.ulid;
      name = entry.name;
    };
  }) pwaEntries);

  # Generate JSON registry file
  domainRegistryJson = builtins.toJSON domainMapping;

  # URL Router shell script
  # Feature 118: Simplified URL routing with path-based matching, no lock files
  urlRouterScript = pkgs.writeShellScriptBin "pwa-url-router" ''
    #!/usr/bin/env bash
    # Feature 118: URL Router - Open URLs in PWAs based on domain/path matching
    # Simplified from Feature 113: removed lock files, auth bypass (PWAs handle auth internally)

    set -euo pipefail

    # Parse arguments
    VERBOSE=false
    URL=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -v|--verbose) VERBOSE=true; shift ;;
        *) URL="$1"; shift ;;
      esac
    done

    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"
    LOG_DIR="$HOME/.local/state"
    LOG_FILE="$LOG_DIR/pwa-url-router.log"

    # Ensure log directory exists
    mkdir -p "$LOG_DIR"

    log() {
      echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
      if $VERBOSE; then
        echo "[pwa-url-router] $*" >&2
      fi
    }

    # Rotate log if too large (>1MB)
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)" -gt 1048576 ]; then
      mv "$LOG_FILE" "$LOG_FILE.old"
    fi

    # ============================================================================
    # LOOP PREVENTION (Simplified - Feature 118)
    # ============================================================================
    # Single check: if I3PM_PWA_URL is set, we're already in a PWA launch context
    if [ -n "''${I3PM_PWA_URL:-}" ]; then
      log "LOOP PREVENTION: I3PM_PWA_URL already set, bypassing to Firefox"
      exec ${pkgs.firefox}/bin/firefox "$URL"
    fi

    if [ -z "$URL" ]; then
      log "No URL provided, opening Firefox"
      exec ${pkgs.firefox}/bin/firefox
    fi

    log "Routing URL: $URL"

    # Extract domain and path from URL
    # Domain: everything between :// and first / or : (port)
    DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|[/:?#].*||')
    # Path: everything after domain, before query string
    PATH_PART=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://[^/]*||' | ${pkgs.gnused}/bin/sed -E 's|\?.*||')

    log "Extracted domain: $DOMAIN, path: $PATH_PART"

    # Look up in registry with path-based matching
    if [ -f "$DOMAIN_REGISTRY" ]; then
      # Try longest prefix match: domain/path1/path2, then domain/path1, then domain
      MATCH_KEY=""
      PWA_INFO=""

      # Build list of keys to try (longest to shortest)
      # Start with domain + full path, progressively shorten
      CURRENT_PATH="$PATH_PART"
      while true; do
        if [ -n "$CURRENT_PATH" ] && [ "$CURRENT_PATH" != "/" ]; then
          TRY_KEY="$DOMAIN$CURRENT_PATH"
          RESULT=$(${pkgs.jq}/bin/jq -r --arg k "$TRY_KEY" '.[$k] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")
          if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
            MATCH_KEY="$TRY_KEY"
            PWA_INFO="$RESULT"
            break
          fi
          # Remove last path segment
          CURRENT_PATH=$(echo "$CURRENT_PATH" | ${pkgs.gnused}/bin/sed -E 's|/[^/]*$||')
        else
          # Try domain-only match
          TRY_KEY="$DOMAIN"
          RESULT=$(${pkgs.jq}/bin/jq -r --arg k "$TRY_KEY" '.[$k] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")
          if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
            MATCH_KEY="$TRY_KEY"
            PWA_INFO="$RESULT"
          fi
          break
        fi
      done

      if [ -n "$PWA_INFO" ]; then
        PWA_DISPLAY=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.name')
        PWA_APP_NAME=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.pwa')
        PWA_ULID=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.ulid')
        log "Match found: $MATCH_KEY → $PWA_APP_NAME ($PWA_DISPLAY, ULID: $PWA_ULID)"

        # Launch PWA with URL for deep linking
        if command -v launch-pwa-by-name >/dev/null 2>&1; then
          log "Launching via launch-pwa-by-name: $PWA_ULID with URL: $URL"
          export I3PM_PWA_URL="$URL"
          exec launch-pwa-by-name "$PWA_ULID"
        else
          log "ERROR: launch-pwa-by-name not found, falling back to Firefox"
          exec ${pkgs.firefox}/bin/firefox "$URL"
        fi
      fi
    else
      log "WARNING: Domain registry not found at $DOMAIN_REGISTRY"
    fi

    # No match - fallback to Firefox
    log "No PWA match for $DOMAIN$PATH_PART, opening in Firefox"
    exec ${pkgs.firefox}/bin/firefox "$URL"
  '';

  # Diagnostic tool for testing routing
  # Feature 118: Updated to show path-based matching
  routeTestScript = pkgs.writeShellScriptBin "pwa-route-test" ''
    #!/usr/bin/env bash
    # Feature 118: Test PWA URL routing without actually opening anything
    # Shows domain, path, and matched registry key

    URL="''${1:-}"
    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"

    if [ -z "$URL" ]; then
      echo "Usage: pwa-route-test <url>"
      echo "Example: pwa-route-test https://github.com/user/repo"
      echo "         pwa-route-test https://google.com/ai/chat"
      exit 1
    fi

    # Extract domain and path from URL
    DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|[/:?#].*||')
    PATH_PART=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://[^/]*||' | ${pkgs.gnused}/bin/sed -E 's|\?.*||')

    echo "URL: $URL"
    echo "Domain: $DOMAIN"
    echo "Path: $PATH_PART"
    echo ""

    if [ ! -f "$DOMAIN_REGISTRY" ]; then
      echo "ERROR: Domain registry not found at $DOMAIN_REGISTRY"
      echo "Run: nixos-rebuild switch to generate it"
      exit 1
    fi

    # Try longest prefix match: domain/path1/path2, then domain/path1, then domain
    MATCH_KEY=""
    PWA_INFO=""
    MATCH_TYPE=""

    CURRENT_PATH="$PATH_PART"
    while true; do
      if [ -n "$CURRENT_PATH" ] && [ "$CURRENT_PATH" != "/" ]; then
        TRY_KEY="$DOMAIN$CURRENT_PATH"
        RESULT=$(${pkgs.jq}/bin/jq -r --arg k "$TRY_KEY" '.[$k] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")
        if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
          MATCH_KEY="$TRY_KEY"
          PWA_INFO="$RESULT"
          MATCH_TYPE="path match"
          break
        fi
        # Remove last path segment
        CURRENT_PATH=$(echo "$CURRENT_PATH" | ${pkgs.gnused}/bin/sed -E 's|/[^/]*$||')
      else
        # Try domain-only match
        TRY_KEY="$DOMAIN"
        RESULT=$(${pkgs.jq}/bin/jq -r --arg k "$TRY_KEY" '.[$k] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")
        if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
          MATCH_KEY="$TRY_KEY"
          PWA_INFO="$RESULT"
          MATCH_TYPE="domain match"
        fi
        break
      fi
    done

    if [ -n "$PWA_INFO" ]; then
      PWA_NAME=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.pwa')
      PWA_DISPLAY=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.name')
      PWA_ULID=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.ulid')
      echo "✓ Would route to: $PWA_NAME"
      echo "  Display name: $PWA_DISPLAY"
      echo "  ULID: $PWA_ULID"
      echo "  Match: $MATCH_KEY ($MATCH_TYPE)"
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
