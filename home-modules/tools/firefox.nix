{ config, pkgs, lib, ... }:

{
  # Firefox browser configuration - simplified without extensions
  # Extensions can be installed manually from the browser
  programs.firefox = {
    enable = true;
    package = pkgs.firefox;
    policies = {
      Extensions = {
        Install = [
          "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
        ];
      };
      PasswordManagerEnabled = false;
    };
    
    profiles = {
      default = {
        id = 0;
        name = "Default";
        isDefault = true;
        
        # Search engines configuration
        search = {
          default = "DuckDuckGo";
          force = true;
          engines = {
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
          # Enable native messaging for 1Password
          "signon.rememberSignons" = false;
          
          # Enable native messaging for 1Password
          "extensions.1Password.native-messaging-hosts" = true;
          "dom.event.clipboardevents.enabled" = true; # Required for 1Password
          
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
          "browser.uidensity" = 0;
          
          # Display scaling for HiDPI Retina display (180 DPI)
          "layout.css.devPixelsPerPx" = "-1.0";  # Let Firefox auto-detect from system DPI
          "layout.css.dpi" = 0;  # Disable automatic DPI detection
          "browser.zoom.full" = true;  # Zoom text and images together
          "browser.zoom.updateBackgroundTabs" = false;
          
          # Performance
          "gfx.webrender.all" = true;
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
        bookmarks = [
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
}
