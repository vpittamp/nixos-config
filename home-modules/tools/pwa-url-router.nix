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

    # Feature 115: Parse arguments
    VERBOSE=false
    URL=""
    for arg in "$@"; do
      case "$arg" in
        --verbose|-v)
          VERBOSE=true
          ;;
        --help|-h)
          echo "Usage: pwa-url-router [--verbose|-v] <url>"
          echo ""
          echo "Routes URLs to PWAs or Firefox based on domain."
          echo ""
          echo "Options:"
          echo "  --verbose, -v  Print routing decisions to stderr"
          echo "  --help, -h     Show this help message"
          exit 0
          ;;
        *)
          URL="$arg"
          ;;
      esac
    done

    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"
    LOG_DIR="$HOME/.local/state"
    LOG_FILE="$LOG_DIR/pwa-url-router.log"
    LOCK_DIR="$LOG_DIR/pwa-router-locks"

    # Ensure directories exist
    mkdir -p "$LOG_DIR" "$LOCK_DIR"

    log() {
      echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
      if [ "$VERBOSE" = true ]; then
        echo "[pwa-url-router] $*" >&2
      fi
    }

    # Rotate log if too large (>1MB)
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)" -gt 1048576 ]; then
      mv "$LOG_FILE" "$LOG_FILE.old"
    fi

    # ============================================================================
    # INFINITE LOOP PREVENTION
    # ============================================================================
    # Detect if we're being called repeatedly to prevent loops:
    # PWA → xdg-open → pwa-url-router → PWA → xdg-open → ... (infinite!)
    #
    # Detection methods:
    # 1. Check if we're already in a PWA launch context (I3PM_PWA_URL set)
    # 2. UNCONDITIONAL lock file check - if URL was routed recently, bypass to Firefox
    #    This prevents loops regardless of how the router was invoked

    # Method 1: Already in PWA URL launch context - go directly to Firefox
    if [ -n "''${I3PM_PWA_URL:-}" ]; then
      log "LOOP PREVENTION: I3PM_PWA_URL already set, bypassing to Firefox"
      exec ${pkgs.firefox}/bin/firefox "$URL"
    fi

    # Method 2: UNCONDITIONAL lock file check
    # If this exact URL was routed within the last 30 seconds, bypass to Firefox
    # This prevents loops regardless of the parent process
    if [ -n "$URL" ]; then
      URL_HASH=$(echo -n "$URL" | md5sum | cut -d' ' -f1)
      LOCK_FILE="$LOCK_DIR/$URL_HASH"

      if [ -f "$LOCK_FILE" ]; then
        LOCK_AGE=$(($(date +%s) - $(stat -c%Y "$LOCK_FILE" 2>/dev/null || echo 0)))
        if [ "$LOCK_AGE" -lt 30 ]; then
          log "LOOP PREVENTION: URL was routed $LOCK_AGE seconds ago, bypassing to Firefox"
          exec ${pkgs.firefox}/bin/firefox "$URL"
        fi
      fi
    fi

    # Clean up old lock files (older than 2 minutes)
    find "$LOCK_DIR" -type f -mmin +2 -delete 2>/dev/null || true

    if [ -z "$URL" ]; then
      log "ERROR: No URL provided"
      # Still open Firefox with no URL (new window)
      exec ${pkgs.firefox}/bin/firefox
    fi

    log "Routing URL: $URL"

    # Extract domain from URL (handles http://, https://, and URLs with ports/paths)
    DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|/.*||' | ${pkgs.gnused}/bin/sed -E 's|:.*||')

    log "Extracted domain: $DOMAIN"

    # ============================================================================
    # AUTHENTICATION DOMAIN BYPASS (Feature 115)
    # ============================================================================
    # These domains and patterns are used for SSO/OAuth flows and should ALWAYS
    # open in Firefox to prevent authentication loops and ensure proper session handling.
    #
    # Three-layer auth bypass:
    # 1. AUTH_DOMAINS: Exact domain match or subdomain (e.g., *.auth0.com)
    # 2. AUTH_PATHS: URL path patterns (e.g., github.com/login)
    # 3. OAUTH_PARAMS: OAuth callback detection via URL parameters

    # Layer 1: Domain-level auth providers (exact match or subdomain)
    AUTH_DOMAINS=(
      "accounts.google.com"
      "accounts.youtube.com"
      "login.microsoftonline.com"
      "login.live.com"
      "auth0.com"
      "login.tailscale.com"
      "appleid.apple.com"
      "id.atlassian.com"
      "login.okta.com"
      "sso.google.com"
    )

    # Layer 2: Path-based auth patterns (checked against full URL)
    AUTH_PATHS=(
      "github.com/login"
      "github.com/session"
      "github.com/oauth"
      "/oauth/authorize"
      "/oauth/callback"
      "/auth/callback"
      "/signin"
      "/sso/"
    )

    # Layer 3: OAuth callback detection (URL parameter patterns)
    # These indicate OAuth in-flight - URL contains auth callback params
    OAUTH_PARAMS=(
      "oauth_token="
      "code=.*state="
      "access_token="
      "id_token="
    )

    # Function: Check if URL should bypass PWA routing for authentication
    is_auth_bypass() {
      local url="$1"
      local domain="$2"

      # Layer 1: Check domain-level auth providers
      for auth_domain in "''${AUTH_DOMAINS[@]}"; do
        # Exact match
        if [[ "$domain" == "$auth_domain" ]]; then
          log "AUTH BYPASS (domain): $domain matches auth provider $auth_domain"
          return 0
        fi
        # Subdomain match (e.g., foo.auth0.com matches auth0.com)
        if [[ "$domain" == *".$auth_domain" ]]; then
          log "AUTH BYPASS (subdomain): $domain is subdomain of $auth_domain"
          return 0
        fi
      done

      # Layer 2: Check path-based auth patterns
      for auth_path in "''${AUTH_PATHS[@]}"; do
        if [[ "$url" == *"$auth_path"* ]]; then
          log "AUTH BYPASS (path): URL matches auth path pattern $auth_path"
          return 0
        fi
      done

      # Layer 3: Check OAuth callback parameters
      for oauth_param in "''${OAUTH_PARAMS[@]}"; do
        if [[ "$url" =~ $oauth_param ]]; then
          log "AUTH BYPASS (oauth): URL contains OAuth parameter pattern $oauth_param"
          return 0
        fi
      done

      return 1
    }

    # Run auth bypass check
    if is_auth_bypass "$URL" "$DOMAIN"; then
      exec ${pkgs.firefox}/bin/firefox "$URL"
    fi

    # Look up domain in registry
    if [ -f "$DOMAIN_REGISTRY" ]; then
      PWA_INFO=$(${pkgs.jq}/bin/jq -r --arg d "$DOMAIN" '.[$d] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")

      if [ -n "$PWA_INFO" ] && [ "$PWA_INFO" != "null" ]; then
        PWA_DISPLAY=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.name')
        PWA_APP_NAME=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.pwa')
        PWA_ULID=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.ulid')
        log "Match found: $DOMAIN → $PWA_APP_NAME ($PWA_DISPLAY, ULID: $PWA_ULID)"

        # Create lock file BEFORE launching to prevent loops
        # This marks that we're actively routing this URL
        URL_HASH=$(echo -n "$URL" | md5sum | cut -d' ' -f1)
        touch "$LOCK_DIR/$URL_HASH"

        # Launch PWA directly with URL for deep linking
        # We call launch-pwa-by-name directly (not through app-launcher-wrapper)
        # because swaymsg exec doesn't preserve environment variables
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
    log "No PWA match for $DOMAIN, opening in Firefox"
    exec ${pkgs.firefox}/bin/firefox "$URL"
  '';

  # Diagnostic tool for testing routing (Feature 115: Enhanced with auth bypass and loop prevention status)
  routeTestScript = pkgs.writeShellScriptBin "pwa-route-test" ''
    #!/usr/bin/env bash
    # Feature 113/115: Test PWA URL routing without actually opening anything
    # Shows complete routing decision: auth bypass, loop prevention, PWA match

    URL="''${1:-}"
    DOMAIN_REGISTRY="$HOME/.config/i3/pwa-domains.json"
    LOCK_DIR="$HOME/.local/state/pwa-router-locks"

    if [ -z "$URL" ]; then
      echo "Usage: pwa-route-test <url>"
      echo "Example: pwa-route-test https://github.com/user/repo"
      echo ""
      echo "Shows routing decision including:"
      echo "  - Auth bypass status (OAuth/SSO domains)"
      echo "  - Loop prevention status (recent routing)"
      echo "  - PWA match and metadata"
      exit 1
    fi

    # Extract domain from URL
    DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|/.*||' | ${pkgs.gnused}/bin/sed -E 's|:.*||')

    echo "URL: $URL"
    echo "Domain: $DOMAIN"
    echo ""

    # ============================================================================
    # STEP 1: Check Loop Prevention Status
    # ============================================================================
    echo "=== Loop Prevention ==="

    # Check environment variable
    if [ -n "''${I3PM_PWA_URL:-}" ]; then
      echo "⚠ I3PM_PWA_URL is set - would bypass to Firefox (PWA context detected)"
    else
      echo "✓ I3PM_PWA_URL not set"
    fi

    # Check lock file
    if [ -n "$URL" ]; then
      URL_HASH=$(echo -n "$URL" | md5sum | cut -d' ' -f1)
      LOCK_FILE="$LOCK_DIR/$URL_HASH"

      if [ -f "$LOCK_FILE" ]; then
        LOCK_AGE=$(($(date +%s) - $(stat -c%Y "$LOCK_FILE" 2>/dev/null || echo 0)))
        if [ "$LOCK_AGE" -lt 30 ]; then
          echo "⚠ LOOP PREVENTION: URL was routed $LOCK_AGE seconds ago - would bypass to Firefox"
        else
          echo "✓ Lock file exists but expired ($LOCK_AGE seconds old)"
        fi
      else
        echo "✓ No recent lock file"
      fi
    fi
    echo ""

    # ============================================================================
    # STEP 2: Check Auth Bypass Status (Feature 115)
    # ============================================================================
    echo "=== Auth Bypass Check ==="

    # Layer 1: Domain-level auth providers
    AUTH_DOMAINS=(
      "accounts.google.com"
      "accounts.youtube.com"
      "login.microsoftonline.com"
      "login.live.com"
      "auth0.com"
      "login.tailscale.com"
      "appleid.apple.com"
      "id.atlassian.com"
      "login.okta.com"
      "sso.google.com"
    )

    # Layer 2: Path-based auth patterns
    AUTH_PATHS=(
      "github.com/login"
      "github.com/session"
      "github.com/oauth"
      "/oauth/authorize"
      "/oauth/callback"
      "/auth/callback"
      "/signin"
      "/sso/"
    )

    # Layer 3: OAuth callback detection
    OAUTH_PARAMS=(
      "oauth_token="
      "code=.*state="
      "access_token="
      "id_token="
    )

    AUTH_BYPASS_REASON=""

    # Check domain-level
    for auth_domain in "''${AUTH_DOMAINS[@]}"; do
      if [[ "$DOMAIN" == "$auth_domain" ]]; then
        AUTH_BYPASS_REASON="domain match: $auth_domain"
        break
      fi
      if [[ "$DOMAIN" == *".$auth_domain" ]]; then
        AUTH_BYPASS_REASON="subdomain of $auth_domain"
        break
      fi
    done

    # Check path-level
    if [ -z "$AUTH_BYPASS_REASON" ]; then
      for auth_path in "''${AUTH_PATHS[@]}"; do
        if [[ "$URL" == *"$auth_path"* ]]; then
          AUTH_BYPASS_REASON="path match: $auth_path"
          break
        fi
      done
    fi

    # Check OAuth params
    if [ -z "$AUTH_BYPASS_REASON" ]; then
      for oauth_param in "''${OAUTH_PARAMS[@]}"; do
        if [[ "$URL" =~ $oauth_param ]]; then
          AUTH_BYPASS_REASON="OAuth param: $oauth_param"
          break
        fi
      done
    fi

    if [ -n "$AUTH_BYPASS_REASON" ]; then
      echo "⚠ AUTH BYPASS: Would open in Firefox"
      echo "  Reason: $AUTH_BYPASS_REASON"
      echo ""
      echo "=== Final Decision ==="
      echo "✗ Firefox (auth bypass)"
      exit 0
    else
      echo "✓ Not an auth domain/path"
    fi
    echo ""

    # ============================================================================
    # STEP 3: Check PWA Match
    # ============================================================================
    echo "=== PWA Lookup ==="

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
      echo "✓ Match found in domain registry"
      echo "  PWA: $PWA_NAME"
      echo "  Display name: $PWA_DISPLAY"
      echo "  ULID: $PWA_ULID"
      echo ""
      echo "=== Final Decision ==="
      echo "✓ Would route to: $PWA_NAME ($PWA_DISPLAY)"
    else
      echo "✗ No match in domain registry"
      echo ""
      echo "=== Final Decision ==="
      echo "✗ Firefox (no PWA match)"
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
