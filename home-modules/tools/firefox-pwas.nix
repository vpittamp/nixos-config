# Declarative Firefox PWA Configuration
# This module manages Progressive Web Apps declaratively
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefox-pwas;

  # Generate ULID-like IDs (simplified version for deterministic generation)
  generateId = name:
    let
      hash = builtins.hashString "sha256" name;
      # Take first 26 chars and make them uppercase alphanumeric
      id = lib.toUpper (lib.substring 0 26 (builtins.replaceStrings
        ["-" "_" "." "/"]
        ["0" "1" "2" "3"]
        hash));
    in "01" + id;

  # PWA definitions
  pwaDefinitions = {
    google = {
      name = "Google";
      url = "https://www.google.com";
      icon = "https://www.gstatic.com/images/branding/searchlogo/ico/favicon.ico";
      categories = ["Network" "WebBrowser"];
      description = "Google Search";
    };
    youtube = {
      name = "YouTube";
      url = "https://www.youtube.com";
      icon = "https://www.youtube.com/s/desktop/ef159f37/img/favicon_144x144.png";
      categories = ["AudioVideo" "Video"];
      description = "YouTube Video Platform";
    };
    gemini = {
      name = "Gemini";
      url = "https://gemini.google.com";
      icon = "https://www.gstatic.com/lamda/images/gemini_favicon.png";
      categories = ["Utility" "Science"];
      description = "Google Gemini AI";
    };
    chatgpt = {
      name = "ChatGPT";
      url = "https://chat.openai.com";
      icon = "https://chat.openai.com/favicon.ico";
      categories = ["Utility" "Science"];
      description = "OpenAI ChatGPT";
    };
    "google-ai-studio" = {
      name = "Google AI Studio";
      url = "https://aistudio.google.com";
      icon = "https://www.gstatic.com/aistudio/ai_studio_favicon.svg";
      categories = ["Development" "Science"];
      description = "Google AI Studio";
    };
  };

  # Generate manifest JSON for a PWA
  generateManifest = pwa: builtins.toJSON {
    start_url = pwa.url;
    scope = pwa.url + "/";
    name = pwa.name;
    display = "browser";
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

  # Generate base64 encoded manifest
  encodeManifest = pwa:
    let
      manifest = generateManifest pwa;
      # We'll use a helper script since Nix doesn't have base64 encoding built-in
    in "data:application/manifest+json;base64," +
       builtins.readFile (pkgs.runCommand "manifest-base64" {} ''
         echo -n '${manifest}' | ${pkgs.coreutils}/bin/base64 -w0 > $out
       '');

  # Generate PWA config JSON
  generatePWAConfig = enabledPwas:
    let
      profiles = {
        "00000000000000000000000000" = {
          ulid = "00000000000000000000000000";
          name = "Default";
          description = "Default profile for all web apps";
          sites = [];
        };
      } // lib.mapAttrs' (name: pwa:
        let profileId = generateId "${name}-profile";
        in lib.nameValuePair profileId {
          ulid = profileId;
          name = pwa.name;
          description = pwa.description or null;
          sites = [ (generateId "${name}-site") ];
        }
      ) enabledPwas;

      sites = lib.mapAttrs' (name: pwa:
        let
          siteId = generateId "${name}-site";
          profileId = generateId "${name}-profile";
        in lib.nameValuePair siteId {
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
          manifest = builtins.fromJSON (generateManifest pwa);
        }
      ) enabledPwas;
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

  # Generate desktop file for a PWA
  generateDesktopFile = name: pwa:
    let
      siteId = generateId "${name}-site";
      desktopFileName = "FFPWA-${siteId}.desktop";
    in {
      name = ".local/share/applications/${desktopFileName}";
      value = {
        text = ''
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
      };
    };

in
{
  options.programs.firefox-pwas = {
    enable = mkEnableOption "Firefox PWAs declarative configuration";

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
    # Ensure firefoxpwa is installed
    home.packages = [ pkgs.firefoxpwa ];

    # Create PWA configuration file and desktop files
    home.file = {
      ".local/share/firefoxpwa/config.json" = {
        text = builtins.toJSON (generatePWAConfig
          (lib.filterAttrs (n: v: elem n cfg.pwas) pwaDefinitions));
        force = true;  # Overwrite existing config
      };
    } // lib.listToAttrs (map (name:
      generateDesktopFile name pwaDefinitions.${name}
    ) cfg.pwas);

    # Create icon files (using downloaded icons)
    home.activation.firefoxPwaIcons = lib.hm.dag.entryAfter ["writeBoundary"] (
      lib.concatMapStringsSep "\n" (name:
        let
          pwa = pwaDefinitions.${name};
          siteId = generateId "${name}-site";
          iconDir = "$HOME/.local/share/icons/hicolor/512x512/apps";
        in ''
          mkdir -p ${iconDir}
          if [ ! -f "${iconDir}/FFPWA-${siteId}.png" ]; then
            ${pkgs.curl}/bin/curl -sL "${pwa.icon}" -o "/tmp/icon-${siteId}" || true
            if [ -f "/tmp/icon-${siteId}" ]; then
              ${pkgs.imagemagick}/bin/convert "/tmp/icon-${siteId}" -resize 512x512 "${iconDir}/FFPWA-${siteId}.png" || \
              cp "/tmp/icon-${siteId}" "${iconDir}/FFPWA-${siteId}.png" || true
              rm -f "/tmp/icon-${siteId}"
            fi
          fi
        ''
      ) cfg.pwas
    );

    # Configure KDE Plasma taskbar if enabled
    home.activation.kdePlasmaTaskbar = mkIf cfg.pinToTaskbar (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
        if [ -f "$PLASMA_CONFIG" ]; then
          # Backup current config
          cp "$PLASMA_CONFIG" "$PLASMA_CONFIG.backup-pwa" || true

          # Generate launcher list
          LAUNCHERS="applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop"
          ${lib.concatMapStringsSep "\n" (name:
            let siteId = generateId "${name}-site";
            in ''LAUNCHERS="$LAUNCHERS,file://$HOME/.local/share/applications/FFPWA-${siteId}.desktop"''
          ) cfg.pwas}

          # Update taskbar configuration
          ${pkgs.gnused}/bin/sed -i '/\[Containments\]\[410\]\[Applets\]\[412\]\[Configuration\]\[General\]/,/^$/ {
            /launchers=/d
            /showOnlyCurrentActivity=/s/=.*/=false/
            /\[Configuration\]\[General\]/a launchers='"$LAUNCHERS"'
          }' "$PLASMA_CONFIG" || true
        fi
      ''
    );
  };
}