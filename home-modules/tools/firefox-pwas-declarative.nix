# Fully Declarative Firefox PWA Configuration
# This module manages Progressive Web Apps completely declaratively
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefox-pwas;

  # Generate deterministic ULID-like IDs
  generateId = name: seed:
    let
      hash = builtins.hashString "sha256" "${name}-${seed}";
      # Convert to ULID-like format (26 chars, alphanumeric uppercase)
      chars = lib.stringToCharacters "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
      hashChars = lib.stringToCharacters hash;
      mapChar = c:
        let
          code = builtins.fromJSON (builtins.toJSON c);
        in lib.elemAt chars (lib.mod (lib.stringLength code) 32);
      id = lib.concatStrings (lib.take 24 (map mapChar hashChars));
    in "01" + lib.toUpper id;

  # PWA definitions with all required metadata
  pwaDefinitions = {
    google = {
      name = "Google";
      url = "https://www.google.com/";
      icon = "https://www.gstatic.com/images/branding/searchlogo/ico/favicon.ico";
      categories = ["Network" "WebBrowser"];
      description = "Google Search";
      display = "standalone";
    };
    youtube = {
      name = "YouTube";
      url = "https://www.youtube.com/";
      icon = "https://www.youtube.com/s/desktop/ef159f37/img/favicon_144x144.png";
      categories = ["AudioVideo" "Video"];
      description = "YouTube Video Platform";
      display = "standalone";
    };
    gemini = {
      name = "Gemini";
      url = "https://gemini.google.com/";
      icon = "https://www.gstatic.com/lamda/images/gemini_favicon.png";
      categories = ["Utility" "Science"];
      description = "Google Gemini AI";
      display = "standalone";
    };
    chatgpt = {
      name = "ChatGPT";
      url = "https://chat.openai.com/";
      icon = "https://chat.openai.com/favicon.ico";
      categories = ["Utility" "Science"];
      description = "OpenAI ChatGPT";
      display = "standalone";
    };
    "google-ai-studio" = {
      name = "Google AI Studio";
      url = "https://aistudio.google.com/";
      icon = "https://www.gstatic.com/aistudio/ai_studio_favicon.svg";
      categories = ["Development" "Science"];
      description = "Google AI Studio";
      display = "standalone";
    };
  };

  # Base Firefox preferences for PWA profiles
  basePrefs = ''
    // PWA Base Preferences
    user_pref("browser.cache.disk.enable", false);
    user_pref("browser.cache.disk.capacity", 0);
    user_pref("browser.cache.disk.smart_size.enabled", false);
    user_pref("browser.cache.disk_cache_ssl", false);
    user_pref("browser.cache.memory.enable", true);
    user_pref("browser.cache.offline.enable", false);
    user_pref("browser.chrome.site_icons", true);
    user_pref("browser.display.use_document_fonts", 1);
    user_pref("browser.dom.window.dump.enabled", false);
    user_pref("browser.privatebrowsing.autostart", false);
    user_pref("browser.sessionstore.resume_from_crash", false);
    user_pref("browser.shell.checkDefaultBrowser", false);
    user_pref("browser.startup.homepage_override.mstone", "ignore");
    user_pref("browser.tabs.warnOnClose", false);
    user_pref("browser.uitour.enabled", false);
    user_pref("datareporting.healthreport.uploadEnabled", false);
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("toolkit.telemetry.enabled", false);
    user_pref("toolkit.telemetry.unified", false);
    user_pref("toolkit.telemetry.archive.enabled", false);
  '';

  # Generate manifest JSON
  generateManifest = pwa: {
    start_url = pwa.url;
    scope = pwa.url;
    name = pwa.name;
    display = pwa.display or "standalone";
    orientation = "any";
    icons = [{
      src = pwa.icon;
      sizes = "";
      purpose = "any";
    }];
    categories = [];
    keywords = [];
    dir = "auto";
    prefer_related_applications = false;
    related_applications = [];
    protocol_handlers = [];
    shortcuts = [];
    screenshots = [];
  };

  # Encode manifest as base64
  encodeManifest = pwa:
    let manifest = builtins.toJSON (generateManifest pwa);
    in "data:application/manifest+json;base64,${builtins.readFile (
      pkgs.runCommand "manifest-base64" {} ''
        echo -n '${manifest}' | ${pkgs.coreutils}/bin/base64 -w0 > $out
      ''
    )}";

  # Generate complete PWA configuration
  generatePWAConfig = enabledPwas:
    let
      # Default profile
      defaultProfile = {
        "00000000000000000000000000" = {
          ulid = "00000000000000000000000000";
          name = "Default";
          description = "Default profile for all web apps";
          sites = [];
        };
      };

      # Generate profiles for each PWA
      profiles = defaultProfile // lib.listToAttrs (map (name:
        let
          pwa = pwaDefinitions.${name};
          profileId = generateId name "profile";
          siteId = generateId name "site";
        in {
          name = profileId;
          value = {
            ulid = profileId;
            name = pwa.name;
            description = pwa.description or null;
            sites = [ siteId ];
          };
        }
      ) enabledPwas);

      # Generate sites for each PWA
      sites = lib.listToAttrs (map (name:
        let
          pwa = pwaDefinitions.${name};
          profileId = generateId name "profile";
          siteId = generateId name "site";
        in {
          name = siteId;
          value = {
            ulid = siteId;
            profile = profileId;
            config = {
              name = null;
              description = null;
              start_url = null;
              icon_url = null;
              document_url = pwa.url;
              manifest_url = encodeManifest pwa;
              categories = null;
              keywords = null;
              enabled_url_handlers = [];
              enabled_protocol_handlers = [];
              custom_protocol_handlers = [];
              launch_on_login = false;
              launch_on_browser = false;
            };
            manifest = generateManifest pwa;
          };
        }
      ) enabledPwas);
    in {
      inherit profiles sites;
      arguments = [];
      variables = {};
      config = {
        always_patch = false;
        runtime_enable_wayland = false;
        runtime_use_xinput2 = false;
        runtime_use_portals = false;
        use_linked_runtime = false;
      };
    };

  # Generate desktop file content
  generateDesktopFile = name:
    let
      pwa = pwaDefinitions.${name};
      siteId = generateId name "site";
    in ''
      [Desktop Entry]
      Type=Application
      Version=1.4
      Name=${pwa.name}
      Comment=${pwa.description or ""}
      Keywords=${lib.concatStringsSep ";" (pwa.keywords or [])}
      Categories=${lib.concatStringsSep ";" pwa.categories};
      Icon=FFPWA-${siteId}
      Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${siteId} --protocol %u
      Actions=
      MimeType=
      Terminal=false
      StartupNotify=true
      StartupWMClass=FFPWA-${siteId}
    '';

in {
  options.programs.firefox-pwas = {
    enable = mkEnableOption "Firefox PWAs fully declarative configuration";

    pwas = mkOption {
      type = types.listOf (types.enum (builtins.attrNames pwaDefinitions));
      default = [];
      example = ["google" "youtube" "chatgpt"];
      description = "List of PWAs to install declaratively";
    };

    pinToTaskbar = mkOption {
      type = types.bool;
      default = true;
      description = "Pin PWAs to KDE taskbar";
    };
  };

  config = mkIf cfg.enable {
    # Install firefoxpwa package
    home.packages = [ pkgs.firefoxpwa ];

    # Create all necessary files and directories
    home.file = {
      # Main configuration file
      ".local/share/firefoxpwa/config.json" = {
        text = builtins.toJSON (generatePWAConfig cfg.pwas);
        force = true;
      };
    } // lib.listToAttrs (
      # Desktop files for each PWA
      map (name:
        let siteId = generateId name "site";
        in {
          name = ".local/share/applications/FFPWA-${siteId}.desktop";
          value = { text = generateDesktopFile name; };
        }
      ) cfg.pwas
    ) // lib.listToAttrs (
      # Profile directories with prefs.js for each PWA
      lib.flatten (map (name:
        let
          profileId = generateId name "profile";
          pwa = pwaDefinitions.${name};
        in [
          # Create prefs.js for the profile
          {
            name = ".local/share/firefoxpwa/profiles/${profileId}/prefs.js";
            value = {
              text = ''
                ${basePrefs}
                user_pref("browser.startup.homepage", "${pwa.url}");
                user_pref("firefoxpwa.id", "${generateId name "site"}");
                user_pref("firefoxpwa.name", "${pwa.name}");
                user_pref("firefoxpwa.start_url", "${pwa.url}");
              '';
            };
          }
          # Create user.js as well (Firefox reads both)
          {
            name = ".local/share/firefoxpwa/profiles/${profileId}/user.js";
            value = {
              text = ''
                ${basePrefs}
                user_pref("browser.startup.homepage", "${pwa.url}");
              '';
            };
          }
        ]
      ) cfg.pwas)
    );

    # Create icon files in activation
    home.activation.firefoxPwaSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Create necessary directories
      mkdir -p $HOME/.local/share/firefoxpwa/profiles
      mkdir -p $HOME/.local/share/icons/hicolor/512x512/apps
      mkdir -p $HOME/.cache/firefoxpwa

      # Download and convert icons
      ${lib.concatMapStringsSep "\n" (name:
        let
          pwa = pwaDefinitions.${name};
          siteId = generateId name "site";
          profileId = generateId name "profile";
        in ''
          # Create profile directory structure
          mkdir -p "$HOME/.local/share/firefoxpwa/profiles/${profileId}"

          # Download and convert icon
          ICON_FILE="$HOME/.local/share/icons/hicolor/512x512/apps/FFPWA-${siteId}.png"
          if [ ! -f "$ICON_FILE" ]; then
            echo "Downloading icon for ${pwa.name}..."
            ${pkgs.curl}/bin/curl -sL "${pwa.icon}" -o "/tmp/icon-${siteId}" 2>/dev/null || true
            if [ -f "/tmp/icon-${siteId}" ]; then
              ${pkgs.imagemagick}/bin/convert "/tmp/icon-${siteId}" \
                -resize 512x512 \
                -background transparent \
                -gravity center \
                -extent 512x512 \
                "$ICON_FILE" 2>/dev/null || \
              cp "/tmp/icon-${siteId}" "$ICON_FILE" || true
              rm -f "/tmp/icon-${siteId}"
            fi
          fi
        ''
      ) cfg.pwas}

      # Update icon cache
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t $HOME/.local/share/icons/hicolor || true
    '';

    # Configure KDE Plasma taskbar if enabled
    home.activation.kdePlasmaTaskbar = mkIf cfg.pinToTaskbar (
      lib.hm.dag.entryAfter ["firefoxPwaSetup"] ''
        PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
        if [ -f "$PLASMA_CONFIG" ] && [ ! -L "$PLASMA_CONFIG" ]; then
          # Backup
          cp "$PLASMA_CONFIG" "$PLASMA_CONFIG.backup-pwas" 2>/dev/null || true

          # Build launcher list
          LAUNCHERS="applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop"
          ${lib.concatMapStringsSep "\n" (name:
            let siteId = generateId name "site";
            in ''
              LAUNCHERS="$LAUNCHERS,file://$HOME/.local/share/applications/FFPWA-${siteId}.desktop"
            ''
          ) cfg.pwas}

          # Update configuration
          ${pkgs.gnused}/bin/sed -i '
            /\[Containments\]\[410\]\[Applets\]\[412\]\[Configuration\]\[General\]/,/^$/ {
              /^launchers=/d
              /showOnlyCurrentActivity=/s/=.*/=false/
              /\[General\]/a launchers='"$LAUNCHERS"'
            }
          ' "$PLASMA_CONFIG" 2>/dev/null || true

          echo "KDE taskbar updated with PWAs"
        fi
      ''
    );
  };
}