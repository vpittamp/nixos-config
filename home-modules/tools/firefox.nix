{ config, pkgs, lib, ... }:

let
  # Firefox is primarily for Linux, on macOS users typically use the native app
  isDarwin = pkgs.stdenv.isDarwin or false;
in
{
  # Firefox browser configuration (Linux only for now)
  programs.firefox = lib.mkIf (!isDarwin) {
    enable = true;
    
    # Package selection (use ESR for stability or regular for latest)
    package = pkgs.firefox;
    
    # Firefox profiles
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
              icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@np" ];
            };
            
            "NixOS Wiki" = {
              urls = [{ template = "https://nixos.wiki/index.php?search={searchTerms}"; }];
              iconUpdateURL = "https://nixos.wiki/favicon.png";
              updateInterval = 24 * 60 * 60 * 1000; # every day
              definedAliases = [ "@nw" ];
            };
          };
        };
        
        # Firefox settings
        settings = {
          # Privacy settings
          "browser.send_pings" = false;
          "browser.urlbar.speculativeConnect.enabled" = false;
          "dom.event.clipboardevents.enabled" = false;
          "media.eme.enabled" = true;
          "media.gmp-widevinecdm.enabled" = true;
          "media.navigator.enabled" = false;
          "network.cookie.cookieBehavior" = 1;
          "network.http.referer.XOriginPolicy" = 2;
          "network.http.referer.XOriginTrimmingPolicy" = 2;
          "privacy.firstparty.isolate" = true;
          "privacy.trackingprotection.enabled" = true;
          "services.sync.prefs.sync.browser.newtabpage.activity-stream.showSponsoredTopSite" = false;
          
          # UI settings
          "browser.toolbars.bookmarks.visibility" = "always";
          "browser.tabs.inTitlebar" = 1;
          "browser.uidensity" = 0;  # 0=normal, 1=compact, 2=touch
          
          # Performance
          "gfx.webrender.all" = true;
          "media.ffmpeg.vaapi.enabled" = true;
          "media.hardware-video-decoding.force-enabled" = true;
          
          # Developer settings
          "devtools.theme" = "dark";
          "devtools.debugger.remote-enabled" = true;
          "devtools.chrome.enabled" = true;
          
          # New tab page
          "browser.newtabpage.activity-stream.showSponsored" = false;
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.newtabpage.activity-stream.feeds.snippets" = false;
          "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
          "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
          "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = false;
          "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = false;
          "browser.newtabpage.activity-stream.section.highlights.includeVisited" = false;
          
          # Disable telemetry
          "browser.newtabpage.activity-stream.telemetry" = false;
          "browser.ping-centre.telemetry" = false;
          "toolkit.telemetry.archive.enabled" = false;
          "toolkit.telemetry.bhrPing.enabled" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.firstShutdownPing.enabled" = false;
          "toolkit.telemetry.hybridContent.enabled" = false;
          "toolkit.telemetry.newProfilePing.enabled" = false;
          "toolkit.telemetry.reportingpolicy.firstRun" = false;
          "toolkit.telemetry.shutdownPingSender.enabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.updatePing.enabled" = false;
        };
        
        # Bookmarks - you can add your frequently used sites
        bookmarks = [
          {
            name = "Nix Sites";
            toolbar = true;
            bookmarks = [
              {
                name = "NixOS Search";
                url = "https://search.nixos.org";
              }
              {
                name = "Home Manager Options";
                url = "https://nix-community.github.io/home-manager/options.html";
              }
              {
                name = "Nix Pills";
                url = "https://nixos.org/guides/nix-pills/";
              }
            ];
          }
        ];
        
        # Extensions can be added later with NUR
        # extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        #   ublock-origin
        #   bitwarden
        #   vimium
        #   darkreader
        #   privacy-badger
        # ];
      };
    };
    
    # Enable Firefox accounts sync
    # policies = {
    #   DisableFirefoxAccounts = false;
    #   PasswordManagerEnabled = true;
    # };
  };
}