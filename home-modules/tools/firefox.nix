{ config, pkgs, lib, osConfig, ... }:

let
  isM1 = osConfig.networking.hostName or "" == "nixos-m1";
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
      pkgs.kdePackages.plasma-browser-integration  # KDE Plasma 6 browser integration
    ];
    policies = {
      Extensions = {
        Install = [
          "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/pwas-for-firefox/latest.xpi"
          "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi"
        ];
      };
      PasswordManagerEnabled = false;
      # Grant permissions to the Plasma Browser Integration extension
      ExtensionSettings = {
        "plasma-browser-integration@kde.org" = {
          installation_mode = "allowed";
          allowed_types = ["extension"];
        };
      };
      # Allow native messaging host for Plasma integration
      EnableNativeMessagingHosts = true;
    };

    profiles = {
      default = {
        id = 0;
        name = "Default";
        isDefault = true;

        # Search engines configuration
        search = {
          default = "google";  # Use Google as default search engine (use lowercase id)
          force = true;
          engines = {
            "Google" = {
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

          # Enable native messaging for Plasma Browser Integration
          "extensions.plasma-browser-integration.native-messaging-hosts" = true;

          # Grant history access permissions for Plasma Integration
          "privacy.history.enabled" = true;
          "places.history.enabled" = true;

          # Allow Plasma extension to access browsing data
          "extensions.webextensions.ExtensionStorageIDB.migrated.plasma-browser-integration@kde.org" = true;

          # Auto-accept extension permissions
          "extensions.autoDisableScopes" = 0;  # Don't disable any scopes
          "extensions.enabledScopes" = 15;  # Enable all scopes (1+2+4+8)

          # Ensure extensions are active immediately
          "extensions.webextensions.restrictedDomains" = "";  # Allow on all domains

          # Show extension buttons on toolbar (not unified menu)
          "extensions.unifiedExtensions.enabled" = false;

          # Force extensions to be visible on toolbar
          "browser.compactmode.show" = false;  # Don't show compact mode option
          "extensions.pocket.enabled" = false;  # Disable Pocket to save space

          # Auto-pin PWAsForFirefox extension to toolbar
          # This ensures the extension button is visible immediately after installation
          "browser.uiCustomization.state" = builtins.toJSON {
            placements = {
              widget-overflow-fixed-list = [];
              unified-extensions-area = [];
              nav-bar = [
                "back-button"
                "forward-button"
                "stop-reload-button"
                "customizableui-special-spring1"
                "urlbar-container"
                "customizableui-special-spring2"
                "firefoxpwa_filips_si-browser-action"  # PWAsForFirefox extension - visible
                "_b9db16a4-6edc-47ec-a1f4-b86292ed211d_-browser-action"  # 1Password extension - visible
                "plasma-browser-integration_kde_org-browser-action"  # Plasma Integration - visible
                "downloads-button"
                "fxa-toolbar-menu-button"
              ];
              toolbar-menubar = [ "menubar-items" ];
              TabsToolbar = [ "tabbrowser-tabs" "new-tab-button" "alltabs-button" ];
              PersonalToolbar = [ "import-button" "personal-bookmarks" ];
            };
            seen = [ "firefoxpwa_filips_si-browser-action" "_b9db16a4-6edc-47ec-a1f4-b86292ed211d_-browser-action" "plasma-browser-integration_kde_org-browser-action" "developer-button" ];
            dirtyAreaCache = [ "nav-bar" "toolbar-menubar" "TabsToolbar" "PersonalToolbar" ];
            currentVersion = 20;
            newElementCount = 5;
          };

          # WebAuthn/Passkeys
          "security.webauth.webauthn" = true;
          "security.webauth.u2f" = true;

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

          # Enhanced Tracking Protection - use Standard mode for OAuth compatibility
          "privacy.trackingprotection.enabled" = true;
          "privacy.trackingprotection.socialtracking.enabled" = false;  # Disable social tracking blocking
          "browser.contentblocking.category" = "standard";  # Use standard instead of strict

          # UI settings
          "browser.toolbars.bookmarks.visibility" = "always";
          "browser.tabs.inTitlebar" = 1;
          "browser.uidensity" = 0;  # Normal UI density (0=normal, 1=compact, 2=touch)

          # Display settings - let Wayland/KDE handle scaling
          "layout.css.devPixelsPerPx" = "-1.0";  # Auto-detect from system (KDE is at 2x)

          # Performance and Wayland support
          "gfx.webrender.all" = true;
          "widget.use-xdg-desktop-portal.file-picker" = 1;  # Use native file picker on Wayland
          "widget.use-xdg-desktop-portal.mime-handler" = 1;  # Use XDG portal for mime handling
          "media.ffmpeg.vaapi.enabled" = true;
          "media.hardware-video-decoding.force-enabled" = true;

          # Theme and color settings
          # Force Firefox to use system theme detection
          "ui.systemUsesDarkTheme" = -1;  # -1 = auto-detect, 0 = light, 1 = dark
          "browser.theme.content-theme" = 0;  # 0 = auto/system, 1 = light, 2 = dark
          "browser.theme.toolbar-theme" = 0;  # 0 = auto/system, 1 = light, 2 = dark

          # Improve form field visibility
          "browser.display.use_system_colors" = false;  # Don't use system colors for form controls
          "browser.display.document_color_use" = 2;  # 0=always use page colors, 1=never, 2=only with high contrast themes
          "browser.display.background_color" = "#ffffff";  # White background for better contrast
          "browser.display.foreground_color" = "#000000";  # Black text for better contrast

          # Disable forced colors that might interfere with websites
          "layout.css.prefers-color-scheme.content-override" = 2;  # 0=dark, 1=light, 2=follow system
          "layout.css.forced-colors.enabled" = false;  # Don't force high contrast colors

          # Developer settings
          "devtools.theme" = "dark";
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

  # Force Firefox to use our user.js settings by cleaning prefs.js
  home.activation.firefoxPrefs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    FIREFOX_PROFILE="$HOME/.mozilla/firefox/default"
    if [ -d "$FIREFOX_PROFILE" ]; then
      # Remove any cached scaling preference
      ${pkgs.gnused}/bin/sed -i '/devPixelsPerPx/d' "$FIREFOX_PROFILE/prefs.js" 2>/dev/null || true

      # Ensure user.js exists and has correct permissions
      if [ -e "$FIREFOX_PROFILE/user.js" ]; then
        chmod 644 "$FIREFOX_PROFILE/user.js" 2>/dev/null || true
      fi
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

    # Ensure KDE respects our MIME associations
    if [ -d "$HOME/.config" ]; then
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kdeglobals --group General --key BrowserApplication "firefox.desktop" 2>/dev/null || true
    fi

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
  xdg.mimeApps = {
    enable = true;  # Single source of truth for MIME associations
    # Home Manager manages MIME associations with logging of any overwrites
    # Check ~/.local/share/home-manager/mime-logs/ for any user changes that were overwritten
    defaultApplications = {
      # Web browsers
      "text/html" = [ "firefox.desktop" ];
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/about" = [ "firefox.desktop" ];
      "x-scheme-handler/unknown" = [ "firefox.desktop" ];
      "x-scheme-handler/ftp" = [ "firefox.desktop" ];
      "x-scheme-handler/chrome" = [ "firefox.desktop" ];
      "application/x-extension-htm" = [ "firefox.desktop" ];
      "application/x-extension-html" = [ "firefox.desktop" ];
      "application/x-extension-shtml" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
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

  # Create symlink for firefoxpwa native messaging host
  # This ensures the extension can find the native component
  home.file.".mozilla/native-messaging-hosts/firefoxpwa.json".source =
    "${pkgs.firefoxpwa}/lib/mozilla/native-messaging-hosts/firefoxpwa.json";
}