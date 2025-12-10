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
    LOCK_DIR="$LOG_DIR/pwa-router-locks"

    # Ensure directories exist
    mkdir -p "$LOG_DIR" "$LOCK_DIR"

    log() {
      echo "[$(date -Iseconds)] $*" >> "$LOG_FILE"
    }

    # Rotate log if too large (>1MB)
    if [ -f "$LOG_FILE" ] && [ "$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)" -gt 1048576 ]; then
      mv "$LOG_FILE" "$LOG_FILE.old"
    fi

    # ============================================================================
    # GLOBAL RATE LIMITER - Prevent URL cascade/flood
    # ============================================================================
    # AGGRESSIVE: Only allow 2 URLs per 60 seconds, then DROP everything.
    # This is intentionally restrictive to prevent cascade storms.
    RATE_LIMIT_FILE="$LOCK_DIR/.rate_limit"
    RATE_LIMIT_MAX=2
    RATE_LIMIT_WINDOW=60

    # Count recent URL opens
    NOW=$(date +%s)
    if [ -f "$RATE_LIMIT_FILE" ]; then
      # Filter to only lines within the time window and count
      RECENT_COUNT=$(awk -v now="$NOW" -v window="$RATE_LIMIT_WINDOW" '$1 > (now - window)' "$RATE_LIMIT_FILE" 2>/dev/null | wc -l)
      if [ "$RECENT_COUNT" -ge "$RATE_LIMIT_MAX" ]; then
        log "RATE LIMITED: $RECENT_COUNT URLs in last ''${RATE_LIMIT_WINDOW}s (max $RATE_LIMIT_MAX) - DROPPING URL: $URL"
        exit 0  # Drop the URL entirely, don't open anything
      fi
    fi
    # Record this URL open
    echo "$NOW" >> "$RATE_LIMIT_FILE"
    # Prune old entries (keep only last 60 seconds)
    if [ -f "$RATE_LIMIT_FILE" ]; then
      awk -v now="$NOW" '$1 > (now - 60)' "$RATE_LIMIT_FILE" > "$RATE_LIMIT_FILE.tmp" 2>/dev/null && mv "$RATE_LIMIT_FILE.tmp" "$RATE_LIMIT_FILE"
    fi

    # ============================================================================
    # INFINITE LOOP PREVENTION
    # ============================================================================
    # Detect if we're being called in a loop to prevent:
    # PWA → xdg-open → pwa-url-router → PWA → xdg-open → ... (infinite!)
    #
    # Detection methods:
    # 1. Check if we're already in a PWA launch context (I3PM_PWA_URL set)
    # 2. Check lock file for SAME URL routed recently (unconditional check)
    # 3. Check if parent process is firefoxpwa (PWA opened external link)

    # Method 1: Already in PWA URL launch context - go directly to Firefox
    if [ -n "''${I3PM_PWA_URL:-}" ]; then
      log "LOOP PREVENTION: I3PM_PWA_URL already set, bypassing to Firefox"
      exec ${pkgs.firefox}/bin/firefox "$URL"
    fi

    # Method 2: ATOMIC domain-based lock using mkdir (race-condition safe)
    # This is the primary loop prevention mechanism
    # Use DOMAIN-based hashing (not full URL) because URLs may have different query params
    # (e.g., GitHub auth URLs have different requestId each time, causing loop)
    if [ -n "$URL" ]; then
      # Extract domain for lock file (ignore path and query params)
      LOCK_DOMAIN=$(echo "$URL" | ${pkgs.gnused}/bin/sed -E 's|^https?://||' | ${pkgs.gnused}/bin/sed -E 's|/.*||' | ${pkgs.gnused}/bin/sed -E 's|:.*||')
      DOMAIN_HASH=$(echo -n "$LOCK_DOMAIN" | md5sum | cut -d' ' -f1)
      LOCK_DIR_ATOMIC="$LOCK_DIR/$DOMAIN_HASH.lock"

      # Try to atomically acquire lock using mkdir (atomic on POSIX)
      if mkdir "$LOCK_DIR_ATOMIC" 2>/dev/null; then
        # We got the lock - record timestamp for cleanup
        echo "$$" > "$LOCK_DIR_ATOMIC/pid"
        log "LOCK ACQUIRED: Domain $LOCK_DOMAIN (hash: $DOMAIN_HASH)"
      else
        # Lock exists - check if it's stale (older than 120 seconds)
        # 120 seconds is long enough for PWA to load and complete auth flows
        if [ -d "$LOCK_DIR_ATOMIC" ]; then
          LOCK_AGE=$(($(date +%s) - $(stat -c%Y "$LOCK_DIR_ATOMIC" 2>/dev/null || echo 0)))
          if [ "$LOCK_AGE" -lt 120 ]; then
            log "LOOP PREVENTION: Domain $LOCK_DOMAIN locked $LOCK_AGE seconds ago, bypassing to Firefox"
            exec ${pkgs.firefox}/bin/firefox "$URL"
          else
            # Stale lock - remove and retry
            rm -rf "$LOCK_DIR_ATOMIC" 2>/dev/null
            if mkdir "$LOCK_DIR_ATOMIC" 2>/dev/null; then
              echo "$$" > "$LOCK_DIR_ATOMIC/pid"
              log "LOCK ACQUIRED (stale removed): Domain $LOCK_DOMAIN"
            else
              # Another process beat us to it
              log "LOOP PREVENTION: Domain $LOCK_DOMAIN locked by another process, bypassing to Firefox"
              exec ${pkgs.firefox}/bin/firefox "$URL"
            fi
          fi
        fi
      fi
    fi

    # Method 3: Check if parent process chain includes firefox
    # Additional safety: if called from firefox/PWA, always bypass to Firefox
    if [ -n "$URL" ]; then
      PARENT_CHAIN=$(ps -o comm= -p $PPID 2>/dev/null || echo "")
      GRANDPARENT_CHAIN=$(ps -o comm= -p $(ps -o ppid= -p $PPID 2>/dev/null) 2>/dev/null || echo "")
      if [[ "$PARENT_CHAIN" == *"firefox"* ]] || [[ "$GRANDPARENT_CHAIN" == *"firefox"* ]]; then
        log "LOOP PREVENTION: Called from firefox process chain, bypassing to Firefox"
        exec ${pkgs.firefox}/bin/firefox "$URL"
      fi
    fi

    # Clean up old lock directories (older than 3 minutes)
    find "$LOCK_DIR" -maxdepth 1 -type d -name "*.lock" -mmin +3 -exec rm -rf {} \; 2>/dev/null || true

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
    # AUTHENTICATION DOMAIN BYPASS
    # ============================================================================
    # These domains are used for SSO/OAuth flows and should ALWAYS open in Firefox
    # to prevent authentication loops and ensure proper session handling.
    AUTH_DOMAINS="accounts.google.com accounts.youtube.com login.microsoftonline.com login.live.com github.com/login github.com/session github.com/auth auth0.com login.tailscale.com"

    for auth_domain in $AUTH_DOMAINS; do
      if [[ "$DOMAIN" == "$auth_domain" ]] || [[ "$URL" == *"$auth_domain"* ]]; then
        log "AUTH BYPASS: $DOMAIN is an authentication domain, opening in Firefox"
        exec ${pkgs.firefox}/bin/firefox "$URL"
      fi
    done

    # Look up domain in registry
    if [ -f "$DOMAIN_REGISTRY" ]; then
      PWA_INFO=$(${pkgs.jq}/bin/jq -r --arg d "$DOMAIN" '.[$d] // empty' "$DOMAIN_REGISTRY" 2>/dev/null || echo "")

      if [ -n "$PWA_INFO" ] && [ "$PWA_INFO" != "null" ]; then
        PWA_DISPLAY=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.name')
        PWA_APP_NAME=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.pwa')
        PWA_ULID=$(echo "$PWA_INFO" | ${pkgs.jq}/bin/jq -r '.ulid')
        log "Match found: $DOMAIN → $PWA_APP_NAME ($PWA_DISPLAY, ULID: $PWA_ULID)"

        # ============================================================================
        # CRITICAL: Check if PWA is ALREADY RUNNING
        # ============================================================================
        # If the PWA is already running, DO NOT launch another instance.
        # This prevents infinite loops when PWAs trigger auth flows or external URLs.
        # Route to Firefox instead so the existing PWA can handle it via session cookies.
        #
        # ONLY use process detection - lock files are unreliable (persist after crashes)
        # Check for Firefox process with this PWA's ULID in command line
        if ${pkgs.procps}/bin/pgrep -f "firefox.*--pwa.*$PWA_ULID" >/dev/null 2>&1; then
          log "PWA ALREADY RUNNING: $PWA_DISPLAY (ULID: $PWA_ULID) - routing to Firefox"
          exec ${pkgs.firefox}/bin/firefox "$URL"
        fi

        # Lock already acquired atomically at the start (Method 2)
        # Launch PWA with URL for deep linking
        # Use launch-pwa-by-name directly with URL argument
        # (app-launcher-wrapper uses swaymsg exec which loses I3PM_PWA_URL env var)
        if command -v launch-pwa-by-name >/dev/null 2>&1; then
          log "Launching: launch-pwa-by-name \"$PWA_DISPLAY\" \"$URL\""
          exec launch-pwa-by-name "$PWA_DISPLAY" "$URL"
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
