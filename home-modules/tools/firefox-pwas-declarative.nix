# Fully Declarative Firefox PWA Configuration
# This module manages Progressive Web Apps completely declaratively
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefox-pwas;

  # Generate deterministic ULID-like IDs based on PWA name
  generateId = name: seed:
    let
      # Create a proper hash from the name and seed
      hash = builtins.hashString "sha256" "${name}-${seed}";
      # Take first 24 characters of the hex hash and pad with 0s if needed
      hexChars = lib.stringToCharacters hash;
      idPart = lib.concatStrings (lib.take 24 hexChars);
    in "01" + lib.toUpper idPart;

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
      icon = "https://www.youtube.com/yts/img/favicon_144-vfliLAfaB.png";
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

    # CNOE Developer Tools
    argocd = {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443/";
      icon = "https://argocd.cnoe.localtest.me:8443/assets/images/argo.png";
      categories = ["Development" "Deployment" "CNOE"];
      description = "Declarative GitOps CD for Kubernetes";
      display = "standalone";
    };
    gitea = {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443/";
      icon = "https://gitea.cnoe.localtest.me:8443/assets/img/logo.svg";
      categories = ["Development" "VersionControl" "CNOE"];
      description = "Self-hosted Git service";
      display = "standalone";
    };
    backstage = {
      name = "Backstage";
      url = "https://backstage.cnoe.localtest.me:8443/";
      icon = "https://backstage.cnoe.localtest.me:8443/favicon.ico";
      categories = ["Development" "Documentation" "CNOE"];
      description = "Open platform for building developer portals";
      display = "standalone";
    };
    headlamp = {
      name = "Headlamp";
      url = "https://headlamp.cnoe.localtest.me:8443/";
      icon = "https://headlamp.cnoe.localtest.me:8443/favicon.ico";
      categories = ["Development" "Monitoring" "CNOE"];
      description = "Kubernetes web UI";
      display = "standalone";
    };
    kargo = {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443/";
      icon = "https://kargo.cnoe.localtest.me:8443/favicon.ico";
      categories = ["Development" "Deployment" "CNOE"];
      description = "Progressive delivery for Kubernetes";
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

    // 1Password Extension Support
    user_pref("extensions.autoDisableScopes", 0);
    user_pref("extensions.enabledScopes", 15);
    user_pref("extensions.update.autoUpdateDefault", true);
    user_pref("extensions.1Password.native-messaging-hosts", true);
    user_pref("dom.event.clipboardevents.enabled", true);
    user_pref("signon.rememberSignons", false);

    // Certificate handling for self-signed certs
    user_pref("security.tls.insecure_fallback_hosts", "argocd.cnoe.localtest.me,gitea.cnoe.localtest.me,backstage.cnoe.localtest.me,headlamp.cnoe.localtest.me,kargo.cnoe.localtest.me");
    user_pref("network.stricttransportsecurity.preloadlist", false);
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
    # Install firefoxpwa package and 1Password extension
    home.packages = [
      pkgs.firefoxpwa
    ];

    # Create all necessary files and directories
    home.file = lib.listToAttrs (
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

    # Create icon files and install PWAs in activation
    home.activation.firefoxPwaSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Create necessary directories
      mkdir -p $HOME/.local/share/firefoxpwa/profiles
      mkdir -p $HOME/.local/share/firefoxpwa/sites
      mkdir -p $HOME/.local/share/icons/hicolor/512x512/apps
      mkdir -p $HOME/.cache/firefoxpwa

      # Install each PWA
      ${lib.concatMapStringsSep "\n" (name:
        let
          pwa = pwaDefinitions.${name};
          siteId = generateId name "site";
          profileId = generateId name "profile";
        in ''
          # Create profile directory structure
          mkdir -p "$HOME/.local/share/firefoxpwa/profiles/${profileId}"

          # Create site JSON file for firefoxpwa
          SITE_DIR="$HOME/.local/share/firefoxpwa/sites/${siteId}"
          mkdir -p "$SITE_DIR"

          cat > "$SITE_DIR/site.json" << 'EOF'
          {
            "id": "${siteId}",
            "name": "${pwa.name}",
            "description": "${pwa.description or pwa.name}",
            "start_url": "${pwa.url}",
            "manifest_url": "${pwa.manifestUrl or (pwa.url + "/manifest.json")}",
            "document_url": "${pwa.url}",
            "icon": {
              "src": "${pwa.icon}",
              "type": "image/png"
            },
            "profile_id": "${profileId}",
            "categories": ["Network", "WebBrowser"],
            "keywords": [],
            "enabled": true
          }
          EOF

          # Download and convert icon
          ICON_FILE="$HOME/.local/share/icons/hicolor/512x512/apps/FFPWA-${siteId}.png"
          if [ ! -f "$ICON_FILE" ]; then
            echo "Installing PWA: ${pwa.name}..."
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

          # Copy icon to site directory
          if [ -f "$ICON_FILE" ]; then
            cp "$ICON_FILE" "$SITE_DIR/icon.png"
          fi

          # Create extensions directory and install 1Password extension
          EXTENSIONS_DIR="$HOME/.local/share/firefoxpwa/profiles/${profileId}/extensions"
          mkdir -p "$EXTENSIONS_DIR"

          # Download and install 1Password extension XPI
          ONEPASS_URL="https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
          echo "Installing 1Password extension for ${pwa.name} PWA..."
          ${pkgs.curl}/bin/curl -sL "$ONEPASS_URL" -o "$EXTENSIONS_DIR/{d634138d-c276-4fc8-924b-40a0ea21d284}.xpi" 2>/dev/null || true

          # Add extensions.json for auto-loading
          cat > "$HOME/.local/share/firefoxpwa/profiles/${profileId}/extensions.json" << 'EOF'
          {
            "addons": [
              {
                "id": "{d634138d-c276-4fc8-924b-40a0ea21d284}",
                "location": "app-profile",
                "path": "{d634138d-c276-4fc8-924b-40a0ea21d284}.xpi",
                "active": true,
                "visible": true,
                "userDisabled": false
              }
            ]
          }
          EOF

          # Create user.js for additional extension preferences (doesn't modify symlinked prefs.js)
          cat > "$HOME/.local/share/firefoxpwa/profiles/${profileId}/user-overrides.js" << 'EOF'
          user_pref("extensions.autoDisableScopes", 0);
          user_pref("extensions.enabledScopes", 15);
          user_pref("browser.tabs.warnOnClose", false);
          user_pref("extensions.webextensions.ExtensionStorageIDB.migrated.{d634138d-c276-4fc8-924b-40a0ea21d284}", true);
          EOF
        ''
      ) cfg.pwas}

      # Update icon cache
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t $HOME/.local/share/icons/hicolor || true

      # Create writable config.json (not a symlink)
      cat > "$HOME/.local/share/firefoxpwa/config.json" << 'EOF'
      ${builtins.toJSON (generatePWAConfig cfg.pwas)}
      EOF

      # Update firefoxpwa runtime config
      cat > "$HOME/.local/share/firefoxpwa/runtime.json" << 'EOF'
      {
        "runtime_path": "${pkgs.firefox}/bin/firefox",
        "profile_template": "",
        "browser": "firefox",
        "sites": [
          ${lib.concatMapStringsSep ",\n    " (name:
            let siteId = generateId name "site";
            in ''"${siteId}"''
          ) cfg.pwas}
        ]
      }
      EOF
    '';

    # Configure KDE Plasma taskbar if enabled
    home.activation.kdePlasmaTaskbar = mkIf cfg.pinToTaskbar (
      lib.hm.dag.entryAfter ["firefoxPwaSetup"] ''
        PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
        if [ -f "$PLASMA_CONFIG" ] && [ ! -L "$PLASMA_CONFIG" ]; then
          # Backup
          cp "$PLASMA_CONFIG" "$PLASMA_CONFIG.backup-pwas" 2>/dev/null || true

          # Build launcher list with PWA shortcuts
          PWA_LAUNCHERS=""
          ${lib.concatMapStringsSep "\n" (name:
            let siteId = generateId name "site";
            in ''
              if [ -f "$HOME/.local/share/applications/FFPWA-${siteId}.desktop" ]; then
                PWA_LAUNCHERS="$PWA_LAUNCHERS,file://$HOME/.local/share/applications/FFPWA-${siteId}.desktop"
              fi
            ''
          ) cfg.pwas}

          # Find and update all icontasks applets
          echo "Looking for Icon-only Task Manager widgets..."

          # First, find all containments with icontasks applets
          ${pkgs.gawk}/bin/awk '
            /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {
              containment = $0
              gsub(/.*\[Containments\]\[/, "", containment)
              gsub(/\].*/, "", containment)
              applet = $0
              gsub(/.*\[Applets\]\[/, "", applet)
              gsub(/\]$/, "", applet)
            }
            /^plugin=org\.kde\.plasma\.icontasks$/ && containment {
              print containment, applet
            }
          ' "$PLASMA_CONFIG" | while read CONT_ID APP_ID; do
            echo "Found icontasks widget: Containment[$CONT_ID] Applet[$APP_ID]"

            # Check if this applet already has launchers configured
            if ${pkgs.gnugrep}/bin/grep -q "^\[Containments\]\[$CONT_ID\]\[Applets\]\[$APP_ID\]\[Configuration\]\[General\]" "$PLASMA_CONFIG"; then
              # Extract existing launchers if any
              EXISTING_LAUNCHERS=$(${pkgs.gawk}/bin/awk '
                /^\[Containments\]\['$CONT_ID'\]\[Applets\]\['$APP_ID'\]\[Configuration\]\[General\]/ { in_section=1 }
                in_section && /^launchers=/ {
                  sub(/^launchers=/, "")
                  print
                  exit
                }
                in_section && /^\[/ { exit }
              ' "$PLASMA_CONFIG")

              # Merge with PWA launchers (avoid duplicates)
              if [ -n "$EXISTING_LAUNCHERS" ]; then
                # Keep existing launchers and append PWAs if not already present
                for pwa in $(echo "$PWA_LAUNCHERS" | tr ',' ' '); do
                  if [ -n "$pwa" ] && ! echo "$EXISTING_LAUNCHERS" | ${pkgs.gnugrep}/bin/grep -q "$pwa"; then
                    EXISTING_LAUNCHERS="$EXISTING_LAUNCHERS,$pwa"
                  fi
                done
                NEW_LAUNCHERS="$EXISTING_LAUNCHERS"
              else
                # No existing launchers, add default + PWAs
                NEW_LAUNCHERS="applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop$PWA_LAUNCHERS"
              fi

              # Update the launchers
              ${pkgs.gnused}/bin/sed -i '
                /^\[Containments\]\['$CONT_ID'\]\[Applets\]\['$APP_ID'\]\[Configuration\]\[General\]/,/^\[/ {
                  /^launchers=/d
                  /showOnlyCurrentActivity=/s/=.*/=false/
                  /^\[Configuration\]\[General\]/a launchers='"$NEW_LAUNCHERS"'
                }
              ' "$PLASMA_CONFIG"
            else
              # No [Configuration][General] section exists, create it
              echo "" >> "$PLASMA_CONFIG"
              echo "[Containments][$CONT_ID][Applets][$APP_ID][Configuration][General]" >> "$PLASMA_CONFIG"
              echo "launchers=applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop$PWA_LAUNCHERS" >> "$PLASMA_CONFIG"
              echo "showOnlyCurrentActivity=false" >> "$PLASMA_CONFIG"
            fi
          done

          echo "KDE taskbar updated with PWAs"
        fi
      ''
    );
  };
}