{ config, pkgs, lib, osConfig, ... }:

let
  # Import centralized PWA site definitions
  # Feature 125: Pass hostName for host-specific parameterization
  hostName = if osConfig ? networking && osConfig.networking ? hostName then osConfig.networking.hostName else "";
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib hostName; };

  # Generate Firefox policy exception patterns from PWA sites
  trackingExceptions = pwaSitesConfig.helpers.getDomainPatterns
    pwaSitesConfig.pwaSites
    pwaSitesConfig.additionalTrustedDomains;

  # Cluster CA certificate for *.cnoe.localtest.me
  # This is the CA certificate (with CA:TRUE) that signs the server certificates
  # Firefox uses Certificates.Install policy + security.enterprise_roots.enabled
  clusterCaCertFile = pkgs.writeText "cnoe-ca.pem" ''
    -----BEGIN CERTIFICATE-----
    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
    CBn6
    -----END CERTIFICATE-----
  '';
in
{
  # Firefox browser configuration - simplified without extensions
  # Extensions can be installed manually from the browser
  # Firefox is the PRIMARY/DEFAULT system browser
  # Chromium is installed separately for MCP server and development use
  programs.firefox = {
    enable = true;
    package = pkgs.firefox;
    nativeMessagingHosts = [
      pkgs.firefoxpwa  # PWA native messaging host
    ];
    policies = {
      # Install cluster CA certificate for HTTPS trust to *.cnoe.localtest.me
      # This works alongside security.enterprise_roots.enabled in profile settings
      Certificates = {
        Install = [ "${clusterCaCertFile}" ];
      };
      Extensions = {
        Install = [
          "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/pwas-for-firefox/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/gitingest/latest.xpi"
        ];
      };
      PasswordManagerEnabled = false;
      # Grant permissions to extensions - 1Password with full access
      # See: https://mozilla.github.io/policy-templates/#extensionsettings
      ExtensionSettings = {
        # 1Password extension - force install with maximum permissions
        "{d634138d-c276-4fc8-924b-40a0ea21d284}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi";
          default_area = "navbar";
          # Allow in private browsing (Firefox 136+, ESR 128.8+)
          private_browsing = true;
          # Note: updates_disabled is NOT set, allowing automatic updates (default behavior)
        };
        # Default settings for all extensions
        "*" = {
          # Clear restricted domains for 1Password to work everywhere
          # By default, extensions can't run on addons.mozilla.org and certain Mozilla sites
          restricted_domains = [];
        };
      };
      # Allow native messaging hosts for PWAsForFirefox and 1Password
      EnableNativeMessagingHosts = true;

      # Disable Enhanced Tracking Protection for development/PWA domains
      # This is a policy-level setting that cannot be overridden by user
      # Prevents tracking protection from blocking OAuth flows and PWA functionality
      # Exceptions are automatically generated from pwa-sites.nix
      WebsiteFilter = {
        Block = [];  # No blocked sites
        Exceptions = trackingExceptions;
      };

      PopupBlocking = {
        Allow = [
          "https://my.1password.com"
          "https://*.my.1password.com"
        ];
      };

      # Disable tracking protection globally via policy (cannot be overridden)
      # This ensures PWAs and OAuth flows work without user intervention
      Cookies = {
        AcceptThirdParty = "always";  # Allow third-party cookies for OAuth
        RejectTracker = false;  # Don't block tracking cookies (needed for some OAuth)
      };
    };

    profiles = {
      default = {
        id = 0;
        name = "Default";
        isDefault = true;

        # Search engines configuration
        search = {
          default = "google";  # Default search engine ID
          force = true;
          engines = {
            "google" = {  # Use ID instead of name (lowercase)
              urls = [{
                template = "https://www.google.com/search";
                params = [
                  { name = "q"; value = "{searchTerms}"; }
                ];
              }];
              icon = "https://www.google.com/favicon.ico";
              definedAliases = [ "@g" ];
            };

            "Nix Packages" = {
              urls = [{
                template = "https://search.nixos.org/packages";
                params = [
                  { name = "type"; value = "packages"; }
                  { name = "query"; value = "{searchTerms}"; }
                ];
              }];
              definedAliases = [ "@np" ];
            };

            "NixOS Wiki" = {
              urls = [{ template = "https://nixos.wiki/index.php?search={searchTerms}"; }];
              definedAliases = [ "@nw" ];
            };
          };
        };

        # Firefox settings with 1Password support
        settings = {
          # Homepage and startup settings
          "browser.startup.homepage" = "https://www.google.com";
          "browser.startup.page" = 1;  # 0=blank, 1=home, 2=last visited, 3=resume previous session
          "browser.newtabpage.enabled" = true;
          "browser.newtabpage.activity-stream.showSearch" = true;
          "browser.newtabpage.activity-stream.default.sites" = "";  # Clear default sites

          # Enable native messaging for 1Password
          "signon.rememberSignons" = false;

          # Enable native messaging for 1Password
          "extensions.1Password.native-messaging-hosts" = true;
          "dom.event.clipboardevents.enabled" = true; # Required for 1Password

          # Enable native messaging for PWAsForFirefox
          "extensions.firefoxpwa.native-messaging-hosts" = true;

          # Privacy and history settings
          "privacy.history.enabled" = true;
          "places.history.enabled" = true;

          # Enable reading CA certificates from NSS database
          # This allows dynamically imported certs (via certutil) to be trusted
          # Used for CNOE/Kind cluster self-signed certificates
          "security.enterprise_roots.enabled" = true;
        }
        // {

          # Auto-accept extension permissions
          "extensions.autoDisableScopes" = 0;  # Don't disable any scopes
          "extensions.enabledScopes" = 15;  # Enable all scopes (1+2+4+8)

          # Ensure extensions are active immediately
          "extensions.webextensions.restrictedDomains" = "";  # Allow on all domains

          # Show extension buttons on toolbar (not unified menu)
          # Extension configuration
          "extensions.pocket.enabled" = false;  # Disable Pocket

          # WebAuthn/Passkeys
          "security.webauth.webauthn" = true;
          "security.webauth.u2f" = true;

          # Clipboard API - Enable for Codespaces and web apps
          "dom.events.asyncClipboard.read" = true;  # Allow websites to read clipboard
          "dom.events.asyncClipboard.clipboardItem" = true;  # Enable ClipboardItem API
          "dom.events.testing.asyncClipboard" = false;  # Disable test mode

          # Auto-grant clipboard permissions to trusted domains
          # This prevents the "grant access" prompt for GitHub Codespaces and development tools
          "permissions.default.clipboard-read" = 1;  # 1=allow, 2=deny, 0=always ask

          # Privacy settings optimized for OAuth compatibility
          "browser.send_pings" = false;
          "browser.urlbar.speculativeConnect.enabled" = false;
          "media.eme.enabled" = true;
          "media.gmp-widevinecdm.enabled" = true;
          "media.navigator.enabled" = false;

          # Cookie and tracking protection settings optimized for OAuth compatibility
          # Standard mode (1) instead of Strict to prevent OAuth issues
          "network.cookie.cookieBehavior" = 1;  # 1=Standard, 4=Strict, 5=ETP Strict
          "network.cookie.sameSite.laxByDefault" = false;  # Allow cross-site cookies for OAuth
          "network.cookie.sameSite.noneRequiresSecure" = true;  # Require secure for SameSite=None

          # Referer settings - less strict to avoid OAuth issues
          "network.http.referer.XOriginPolicy" = 1;  # 0=always, 1=same-origin, 2=cross-origin
          "network.http.referer.XOriginTrimmingPolicy" = 1;  # 0=full, 1=scheme+host+port, 2=scheme+host

          # Disable first party isolation as it breaks OAuth flows
          "privacy.firstparty.isolate" = false;

          # Enhanced Tracking Protection - DISABLED for OAuth compatibility (VSCode, Claude, etc.)
          # Custom URL schemes like vscode:// are blocked by tracking protection
          "privacy.trackingprotection.enabled" = false;  # Disable to allow vscode:// redirects
          "privacy.trackingprotection.pbmode.enabled" = false;  # Also disable in private browsing
          "privacy.trackingprotection.socialtracking.enabled" = false;  # Disable social tracking blocking
          "browser.contentblocking.category" = "custom";  # Use custom mode with tracking protection disabled

          # Performance and Wayland support
          "gfx.webrender.all" = true;
          "widget.use-xdg-desktop-portal.file-picker" = 1;  # Use native file picker on Wayland
          "widget.use-xdg-desktop-portal.mime-handler" = 1;  # Use XDG portal for mime handling
          "media.ffmpeg.vaapi.enabled" = true;
          "media.hardware-video-decoding.force-enabled" = true;
        }
        // {
          # Developer settings
          "devtools.debugger.remote-enabled" = true;
          "devtools.chrome.enabled" = true;

          # Disable telemetry
          "browser.newtabpage.activity-stream.telemetry" = false;
          "browser.ping-centre.telemetry" = false;
          "toolkit.telemetry.archive.enabled" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.unified" = false;
        };

        # Bookmarks
        bookmarks = {
          force = true;  # Required for declarative bookmarks
          settings = [
            {
              name = "Nix Sites";
              toolbar = true;
              bookmarks = [
                {
                  name = "1Password";
                  url = "https://my.1password.com";
                }
                {
                  name = "NixOS Search";
                  url = "https://search.nixos.org";
                }
                {
                  name = "Home Manager Options";
                  url = "https://nix-community.github.io/home-manager/options.html";
                }
              ];
            }
          ];
        };
      };
    };
  };

  # Clean Firefox prefs.js to remove cached preferences that might override user.js
  # This is needed because Firefox caches preferences in prefs.js that can override user.js
  # Home-manager manages user.js as a symlink, but prefs.js is Firefox's runtime state
  home.activation.firefoxPrefs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    FIREFOX_PROFILE="$HOME/.mozilla/firefox/default"
    if [ -d "$FIREFOX_PROFILE" ] && [ -f "$FIREFOX_PROFILE/prefs.js" ]; then
      # Drop legacy UI and appearance overrides so Firefox falls back to defaults
      ${pkgs.gnused}/bin/sed -i \
        -e '/devPixelsPerPx/d' \
        -e '/browser\.toolbars\.bookmarks\.visibility/d' \
        -e '/browser\.tabs\.inTitlebar/d' \
        -e '/browser\.uidensity/d' \
        -e '/devtools\.theme/d' \
        -e '/ui\.systemUsesDarkTheme/d' \
        -e '/browser\.theme\.content-theme/d' \
        -e '/browser\.theme\.toolbar-theme/d' \
        -e '/browser\.display\.use_system_colors/d' \
        -e '/browser\.display\.document_color_use/d' \
        -e '/browser\.display\.background_color/d' \
        -e '/browser\.display\.foreground_color/d' \
        -e '/layout\.css\.prefers-color-scheme\.content-override/d' \
        -e '/layout\.css\.forced-colors\.enabled/d' \
        "$FIREFOX_PROFILE/prefs.js" 2>/dev/null || true
    fi
  '';

  # Ensure mimeapps.list files are managed by home-manager while preserving PWA registrations
  home.activation.manageMimeApps = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Create a log directory for tracking MIME association changes
    MIME_LOG_DIR="$HOME/.local/share/home-manager/mime-logs"
    mkdir -p "$MIME_LOG_DIR"

    # File to track PWA-related MIME associations
    PWA_MIME_FILE="$MIME_LOG_DIR/pwa-associations.conf"

    # Function to extract PWA associations from desktop files
    extract_pwa_associations() {
      local associations=""
      for desktop_file in $HOME/.local/share/applications/FFPWA-*.desktop; do
        if [ -f "$desktop_file" ]; then
          local pwa_id=$(basename "$desktop_file" .desktop)
          local pwa_name=$(grep "^Name=" "$desktop_file" | cut -d= -f2)
          # PWAs typically don't need special MIME associations beyond what Firefox handles
          # But we log them for reference
          echo "# PWA: $pwa_name ($pwa_id)" >> "$PWA_MIME_FILE.tmp"
        fi
      done
    }

    # Function to compare and log differences
    check_mime_differences() {
      local current_file="$1"
      local managed_file="$2"
      local log_file="$3"

      if [ -f "$current_file" ] && [ ! -L "$current_file" ]; then
        # File exists and is not a symlink - check for differences
        if ! diff -q "$current_file" "$managed_file" > /dev/null 2>&1; then
          echo "$(date): Differences detected in $current_file" >> "$log_file"
          echo "User-specific associations that would be overwritten:" >> "$log_file"
          diff --unified=0 "$managed_file" "$current_file" 2>/dev/null | grep "^+" | grep -v "^+++" >> "$log_file" || true

          # Check if any PWA-related entries are being overwritten
          if grep -q "FFPWA" "$current_file" 2>/dev/null; then
            echo "Note: PWA associations detected - these are handled separately" >> "$log_file"
          fi
          echo "---" >> "$log_file"

          # Save a copy of user's modifications for reference
          cp "$current_file" "$MIME_LOG_DIR/$(basename $current_file).user-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        fi
      fi
    }

    # Check both MIME association files before home-manager overwrites them
    MANAGED_CONFIG="${pkgs.writeText "managed-mimeapps" ""}"
    LOG_FILE="$MIME_LOG_DIR/changes.log"

    check_mime_differences "$HOME/.config/mimeapps.list" "$MANAGED_CONFIG" "$LOG_FILE"
    check_mime_differences "$HOME/.local/share/applications/mimeapps.list" "$MANAGED_CONFIG" "$LOG_FILE"

    # Clean up old backup files to prevent conflicts
    find "$HOME/.config" "$HOME/.local/share/applications" -maxdepth 1 \
      -name "mimeapps.list.backup*" -o -name "mimeapps.list.hm-backup*" \
      -mtime +7 -delete 2>/dev/null || true

    # Print a message if there were recent changes
    if [ -f "$LOG_FILE" ]; then
      recent_changes=$(find "$LOG_FILE" -mmin -5 2>/dev/null)
      if [ -n "$recent_changes" ]; then
        echo "ℹ️  MIME associations updated. User changes logged to: $MIME_LOG_DIR"
        tail -n 20 "$LOG_FILE" 2>/dev/null | grep "^User-specific" || true
      fi
    fi
  '';

  # Set Firefox as the default browser for all browser-based activities
  # Using both defaultApplications (enforced) and associations.added (preferences)
  # This ensures OAuth flows work while allowing PWAs to register themselves
  #
  # Feature 113: URL scheme handlers (http/https) now route through pwa-url-router
  # which opens PWAs for matching domains and falls back to Firefox for others.
  # HTML files opened directly still use Firefox.
  xdg.mimeApps = {
    enable = true;

    # Enforced defaults
    defaultApplications = {
      "text/html" = "firefox.desktop";
      "application/xhtml+xml" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };

    # Additional associations - preferences, not enforced defaults
    associations.added = {
      # Web browsers - additional file types
      "x-scheme-handler/ftp" = [ "firefox.desktop" ];
      "x-scheme-handler/chrome" = [ "firefox.desktop" ];
      "application/x-extension-htm" = [ "firefox.desktop" ];
      "application/x-extension-html" = [ "firefox.desktop" ];
      "application/x-extension-shtml" = [ "firefox.desktop" ];
      "application/x-extension-xhtml" = [ "firefox.desktop" ];
      "application/x-extension-xht" = [ "firefox.desktop" ];
      "application/pdf" = [ "firefox.desktop" "okularApplication_pdf.desktop" ];  # Firefox first, Okular as fallback

      # Web content
      "x-scheme-handler/webcal" = [ "firefox.desktop" ];
      "x-scheme-handler/mailto" = [ "firefox.desktop" ];
    };
  };

  # Set environment variables for default browser
  home.sessionVariables = {
    DEFAULT_BROWSER = "${pkgs.firefox}/bin/firefox";
    BROWSER = "${pkgs.firefox}/bin/firefox";
  };

}
