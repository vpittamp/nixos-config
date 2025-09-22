{ config, pkgs, lib, osConfig, ... }:

let
  isM1 = osConfig.networking.hostName or "" == "nixos-m1";
in
{
  # Firefox browser configuration - simplified without extensions
  # Extensions can be installed manually from the browser
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
          
          # Privacy settings
          "browser.send_pings" = false;
          "browser.urlbar.speculativeConnect.enabled" = false;
          "media.eme.enabled" = true;
          "media.gmp-widevinecdm.enabled" = true;
          "media.navigator.enabled" = false;
          "network.cookie.cookieBehavior" = 1;
          "network.http.referer.XOriginPolicy" = 2;
          "network.http.referer.XOriginTrimmingPolicy" = 2;
          "privacy.firstparty.isolate" = true;
          "privacy.trackingprotection.enabled" = true;
          
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

  # Set Firefox as the default browser for all browser-based activities
  xdg.mimeApps = {
    enable = true;
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
      "application/pdf" = [ "firefox.desktop" ];  # Open PDFs in Firefox

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
