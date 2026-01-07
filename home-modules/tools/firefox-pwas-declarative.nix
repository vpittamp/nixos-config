# Declarative PWA Installation Module (Feature 056)
# Fully declarative PWA management with controlled ULIDs
{ config, lib, pkgs, osConfig, ... }:

with lib;

let
  # Import centralized PWA site definitions
  # Feature 125: Pass hostName for host-specific parameterization
  hostName = if osConfig ? networking && osConfig.networking ? hostName then osConfig.networking.hostName else "";
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib hostName; };
  pwas = pwaSitesConfig.pwaSites;

  # Cluster CA certificate for *.cnoe.localtest.me
  # This is the CA certificate (with CA:TRUE) that signs the server certificates
  # PWA profiles need this certificate for HTTPS trust to cluster services
  clusterCaCertFile = pkgs.writeText "cnoe-ca.pem" ''
    -----BEGIN CERTIFICATE-----
    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
    CBn6
    -----END CERTIFICATE-----
  '';
  ensureFileUrl = path:
    if lib.hasPrefix "file://" path then path
    else if lib.hasPrefix "/" path then "file://${path}"
    else throw "PWA icon path must be absolute or file:// URL: ${path}";

  inherit (lib.hm.dag) entryAfter;

  pwaDialogFixScript = pkgs.writeShellScriptBin "pwa-fix-dialogs" ''
    # Fix thin sliver dialog rendering on Wayland with fractional scaling
    # Applies user.js fixes to all PWA profiles

    PROFILES_DIR="$HOME/.local/share/firefoxpwa/profiles"

    usage() {
      cat <<'EOF'
Usage: pwa-fix-dialogs [--profile ULID]

Apply Wayland/PWA preferences (including 1Password pinning) to all profiles or a single profile.
EOF
    }

    TARGET=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --profile)
          TARGET="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "Unknown argument: $1" >&2
          usage >&2
          exit 1
          ;;
      esac
    done

    if [ ! -d "$PROFILES_DIR" ]; then
      echo "Error: PWA profiles directory not found: $PROFILES_DIR"
      exit 1
    fi

    if [ -n "$TARGET" ]; then
      set -- "$PROFILES_DIR/$TARGET"
    else
      set -- "$PROFILES_DIR"/*
    fi

    count=0
    for profile in "$@"; do
      if [ -d "$profile" ]; then
        cat > "$profile/user.js" << 'EOF'
// Wayland Dialog/Popup Fixes (Feature 056)
// Fix thin sliver dialog rendering on Wayland with fractional scaling

// CRITICAL: Disable fractional scaling - causes dialog sizing bugs
// Bug 1849109: Context menus and popups broken with this enabled
user_pref("widget.wayland.fractional-scale.enabled", false);

// Use system DPI scaling (-1 = automatic)
// Bug 1634404: Popups broken when this is not -1 or 1
user_pref("layout.css.devPixelsPerPx", -1);

// Disable fingerprinting resistance which can interfere with window sizing
user_pref("privacy.resistFingerprinting", false);

// Force use of XDG desktop portals for better Wayland integration
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);
// DISABLED for PWAs: mime-handler = 1 causes system handler dialogs during auth
// The portal mime handler shows an app chooser when PWAs navigate to auth URLs
user_pref("widget.use-xdg-desktop-portal.mime-handler", 0);

// Ensure native Wayland backend
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);

// === WebGL and GPU Rendering ===
// Enable WebGL2 for apps that require it (e.g., RAG WebUI with visualization libraries)
// Note: The Mesa/Asahi GPU crash workaround was removed as it's only needed on Apple Silicon

// Enable WebGL (required by visualization libraries like Three.js, TensorFlow.js, etc.)
user_pref("webgl.disabled", false);
user_pref("webgl.enable-webgl2", true);

// Enable hardware-accelerated canvas for better performance
user_pref("gfx.canvas.accelerated", true);

// Enable GPU process for hardware acceleration
user_pref("layers.gpu-process.enabled", true);
user_pref("media.hardware-video-decoding.enabled", true);

// Enable WebRender compositor for smoother rendering
user_pref("gfx.webrender.compositor", true);

// === 1Password Integration (Feature 056) ===
// Enable 1Password extension and native messaging

// Install and enable 1Password extension
user_pref("extensions.autoDisableScopes", 0);
user_pref("extensions.enabledScopes", 15);

// Disable Firefox password manager - use 1Password instead
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("signon.generation.enabled", false);
user_pref("signon.management.page.breach-alerts.enabled", false);

// Enable extensions in private browsing
user_pref("extensions.allowPrivateBrowsingByDefault", true);

// Native messaging for 1Password desktop integration
user_pref("privacy.resistFingerprinting.block_mozAddonManager", true);

// Allow signed extensions
user_pref("xpinstall.signatures.required", true);

// Enable web extensions
user_pref("extensions.webextensions.remote", true);

// Pin 1Password button on toolbar by default
user_pref("browser.uiCustomization.state", "{\"placements\":{\"widget-overflow-fixed-list\":[],\"nav-bar\":[\"back-button\",\"forward-button\",\"urlbar-container\",\"_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action\",\"unified-extensions-button\"],\"toolbar-menubar\":[\"menubar-items\"],\"TabsToolbar\":[\"tabbrowser-tabs\",\"new-tab-button\",\"alltabs-button\"],\"PersonalToolbar\":[\"personal-bookmarks\"],\"unified-extensions-area\":[]},\"seen\":[\"_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action\",\"unified-extensions-button\"],\"dirtyAreaCache\":[\"nav-bar\",\"TabsToolbar\",\"PersonalToolbar\"],\"currentVersion\":23,\"newElementCount\":2}");

// === Feature 118: PWA External Link Handling ===
// DISABLED: openOutOfScopeInDefaultBrowser causes system handler dialogs
// even with allowedDomains set. Keep all navigation within PWA instead.
// Auth flows (OAuth/SSO) will complete within the PWA window.
user_pref("firefoxpwa.openOutOfScopeInDefaultBrowser", false);

// === Enterprise Certificate Trust ===
// Enable reading CA certificates from NSS database
// This allows dynamically imported certs (via certutil) to be trusted
// Used for CNOE/Kind cluster self-signed certificates at *.cnoe.localtest.me:8443
user_pref("security.enterprise_roots.enabled", true);
EOF
        echo "Updated: $profile/user.js"
        ((count++))

        # Ensure 1Password toolbar button is pinned inside each profile
        if [ -f "$profile/prefs.js" ]; then
          ${pkgs.python3}/bin/python3 - <<'PY' "$profile/prefs.js"
import json
import re
import sys
from pathlib import Path

prefs_path = Path(sys.argv[1])
text = prefs_path.read_text()

pattern = re.compile(r'user_pref\("browser.uiCustomization.state", "(.*?)"\);')
match = pattern.search(text)
placement = "_d634138d-c276-4fc8-924b-40a0ea21d284_-browser-action"

def dump_state(state):
    return json.dumps(state, separators=(",", ":")).replace('"', '\\"')

if not match:
    state = {
        "placements": {
            "nav-bar": ["back-button", "forward-button", "urlbar-container", placement, "unified-extensions-button"],
            "toolbar-menubar": ["menubar-items"],
            "TabsToolbar": ["tabbrowser-tabs", "new-tab-button", "alltabs-button"],
            "PersonalToolbar": ["personal-bookmarks"],
            "unified-extensions-area": [],
        },
        "seen": [placement, "unified-extensions-button"],
        "dirtyAreaCache": ["nav-bar", "TabsToolbar", "PersonalToolbar"],
        "currentVersion": 23,
        "newElementCount": 2,
    }
    line = f'user_pref("browser.uiCustomization.state", "{dump_state(state)}");\n'
    if not text.endswith("\n"):
        text += "\n"
    prefs_path.write_text(text + line)
    raise SystemExit

decoded = bytes(match.group(1), "utf-8").decode("unicode_escape")
state = json.loads(decoded)
placements = state.setdefault("placements", {})
nav = placements.setdefault("nav-bar", [])
changed = False

nav = [item for item in nav if item != placement]

if placement not in nav:
    insert_idx = len(nav)
    for anchor in ("unified-extensions-button", "urlbar-container", "vertical-spacer"):
        if anchor in nav:
            insert_idx = nav.index(anchor)
            if anchor == "urlbar-container":
                insert_idx += 1
            break
    nav.insert(insert_idx, placement)
    changed = True

seen = state.setdefault("seen", [])
if placement not in seen:
    seen.append(placement)
    changed = True

if "unified-extensions-button" not in nav:
    nav.append("unified-extensions-button")
    changed = True

if "unified-extensions-button" not in seen:
    seen.append("unified-extensions-button")
    changed = True

if changed:
    new_json = dump_state(state)
    replacement = f'user_pref("browser.uiCustomization.state", "{new_json}");'
    text = pattern.sub(replacement, text, count=1)
    if not text.endswith("\n"):
        text += "\n"
    prefs_path.write_text(text)
PY
        fi
      fi
    done

    echo ""
    echo "✓ Updated $count PWA profiles with Wayland dialog fixes"
    echo ""
    echo "To apply changes:"
    echo "  1. Reload Sway: swaymsg reload"
    echo "  2. Restart PWAs (close and relaunch from Walker)"
  '';

  #
  # Core Functions
  #

  # validateULID: Validates ULID format
  # ULID spec: 26 characters from alphabet [0-9A-HJKMNP-TV-Z]
  # Excludes: I, L, O, U (to avoid confusion with 1, 1, 0, V)
  validateULID = ulid:
    let
      len = builtins.stringLength ulid;
      isValidFormat = builtins.match "[0-9A-HJKMNP-TV-Z]{26}" ulid != null;
    in
    len == 26 && isValidFormat;

  # generateManifest: Generate Web App Manifest JSON from PWA definition
  # Spec: https://www.w3.org/TR/appmanifest/
  generateManifest = pwa:
    let
      iconUrl = ensureFileUrl pwa.icon;
    in {
    name = pwa.name;
    short_name = pwa.name;
    start_url = "${pwa.url}/";  # Trailing slash
    scope = pwa.scope or "${pwa.url}/";
    display = "standalone";
    description = pwa.description;
    dir = "auto";
    orientation = "any";
    prefer_related_applications = false;
    related_applications = [];
    protocol_handlers = [];
    shortcuts = [];
    icons = [
      {
        src = iconUrl;
        sizes = "512x512";
        type = "image/png";
        purpose = "any";
      }
    ];
    screenshots = [];
  };

  # generateFirefoxPWAConfig: Generate complete firefoxpwa config.json
  # This is the ACTUAL database firefoxpwa uses
  # Location: ~/.local/share/firefoxpwa/config.json
  generateFirefoxPWAConfig = pwaList:
    let
      # Check for duplicate ULIDs
      ulids = builtins.map (pwa: pwa.ulid) pwaList;
      uniqueULIDs = lib.lists.unique ulids;
      hasDuplicates = builtins.length ulids != builtins.length uniqueULIDs;

      # Create separate profiles for each PWA (recommended due to issue #322)
      # Each PWA gets its own profile with ULID derived from site ULID
      profilesAttrset = builtins.listToAttrs (builtins.map (pwa: {
        name = pwa.ulid;  # Use site ULID as profile ULID
        value = {
          ulid = pwa.ulid;
          name = "${pwa.name} Profile";
          description = "Dedicated profile for ${pwa.name}";
          sites = [ pwa.ulid ];
        };
      }) pwaList);

      # Convert PWA list to sites attrset keyed by ULID
      sitesAttrset = builtins.listToAttrs (builtins.map (pwa:
        let
          iconUrl = ensureFileUrl pwa.icon;
        in {
          name = pwa.ulid;
          value = {
            ulid = pwa.ulid;
            profile = pwa.ulid;  # Each site uses its own profile
            config = {
            name = pwa.name;
            description = pwa.description;
            start_url = "${pwa.url}/";  # Must match document_url with trailing slash
            icon_url = iconUrl;
            document_url = "${pwa.url}/";  # Trailing slash is important!
            manifest_url = "${pwa.url}/";  # Point to document_url
            categories = if (pwa ? categories)
              then builtins.filter (x: x != "") (lib.splitString ";" pwa.categories)
              else [];
            keywords = if (pwa ? keywords)
              then builtins.filter (x: x != "") (lib.splitString ";" pwa.keywords)
              else [];
            enabled_url_handlers = [];
            enabled_protocol_handlers = [];
            custom_protocol_handlers = [];
            launch_on_login = false;
            # Feature 113: DISABLED - causes infinite loops with URL routing
            # When enabled, PWAs auto-launch when visiting matching domains,
            # which conflicts with pwa-url-router and causes cascading opens.
            # PWAs are launched explicitly via tmux-url-open or app launcher.
            launch_on_browser = false;
            # Note: allowed_domains is NOT used here - firefoxpwa reads it from
            # user.js preference firefoxpwa.allowedDomains (set in pwa-update-profiles)
          };
          manifest = generateManifest pwa;
        };
      }) pwaList);

      # Generate list of site ULIDs for profile
      siteUlids = builtins.map (pwa: pwa.ulid) pwaList;

    in
    if hasDuplicates
    then throw "Duplicate ULIDs detected in PWA configuration"
    else {
      # Top-level configuration
      arguments = [];
      config = {
        always_patch = false;
        runtime_enable_wayland = true;   # Enable native Wayland for Sway
        runtime_use_portals = true;      # Use XDG desktop portals for dialogs
        runtime_use_xinput2 = false;
        use_linked_runtime = false;     # Prefer system Firefox for latest Wayland fixes
      };

      # Profiles section - separate profile for each PWA
      profiles = profilesAttrset;

      # Sites section
      sites = sitesAttrset;
    };

in
{
  #
  # Module Configuration
  #

  options.programs.firefoxpwa-declarative = {
    enable = mkEnableOption "Declarative Firefox PWA management";
  };

  config = mkIf config.programs.firefoxpwa-declarative.enable {
    # Validate all ULIDs on module load
    assertions = [
      {
        assertion = builtins.all (pwa: validateULID pwa.ulid) pwas;
        message = ''
          Invalid ULID detected in pwa-sites.nix
          All ULIDs must be exactly 26 characters from alphabet [0-9A-HJKMNP-TV-Z]
          (excludes I, L, O, U to avoid confusion)
        '';
      }
    ];

    # Ensure firefoxpwa is installed
    home.packages = [
      pkgs.firefoxpwa
      pwaDialogFixScript
    ];

    home.activation.firefoxpwaWaylandPrefs = entryAfter [ "writeBoundary" ] ''
      if [ -x "${pwaDialogFixScript}/bin/pwa-fix-dialogs" ]; then
        "${pwaDialogFixScript}/bin/pwa-fix-dialogs" || true
      fi
    '';

    home.activation.firefoxpwaEnsure1Password = entryAfter [ "firefoxpwaWaylandPrefs" ] ''
      if command -v pwa-enable-1password >/dev/null 2>&1; then
        pwa-enable-1password >/dev/null 2>&1 || true
      fi
    '';

    # Add cluster CA certificate to all PWA profile NSS databases
    # This enables PWAs to trust *.cnoe.localtest.me HTTPS connections
    home.activation.firefoxpwaTrustClusterCert = entryAfter [ "firefoxpwaWaylandPrefs" ] ''
      PROFILES_DIR="$HOME/.local/share/firefoxpwa/profiles"
      CERT_NICKNAME="CNOE-Local-Dev-CA"

      if [ -d "$PROFILES_DIR" ]; then
        for profile in "$PROFILES_DIR"/*; do
          if [ -d "$profile" ]; then
            # Initialize NSS database if it doesn't exist (cert9.db is the SQLite format)
            if [ ! -f "$profile/cert9.db" ]; then
              ${pkgs.nssTools}/bin/certutil -d sql:"$profile" -N --empty-password 2>/dev/null || true
            fi

            # Remove existing cert if present (to update it)
            ${pkgs.nssTools}/bin/certutil -d sql:"$profile" -D -n "$CERT_NICKNAME" 2>/dev/null || true

            # Add the cluster CA certificate (CT,C,C = trusted for SSL/email/code)
            ${pkgs.nssTools}/bin/certutil -d sql:"$profile" -A -n "$CERT_NICKNAME" -t "CT,C,C" -i "${clusterCaCertFile}" 2>/dev/null || true
          fi
        done
      fi
    '';

    #
    # BREAKTHROUGH: Write config to CORRECT location!
    # firefoxpwa reads from ~/.local/share/firefoxpwa/config.json
    # NOT from ~/.config/firefoxpwa/config.json
    #
    xdg.dataFile."firefoxpwa/config.json" = {
      text = builtins.toJSON (generateFirefoxPWAConfig pwas);
      force = true;  # Always override without backup
    };

    #
    # Generate desktop entries for all PWAs
    # Desktop files use ULID in filename: FFPWA-<ULID>.desktop
    # This makes window class matching predictable: FFPWA-<ULID>
    # Using home.file instead of xdg.desktopEntries due to schema issues with newer home-manager
    #
    home.file = builtins.listToAttrs (builtins.map (pwa:
      let
        categoriesStr = if (pwa ? categories)
          then pwa.categories  # Already has semicolons from pwa-sites.nix
          else "Network;";
        # Keywords for application search (used by Walker, rofi, etc.)
        keywordsStr = if (pwa ? keywords)
          then pwa.keywords  # Already has semicolons from pwa-sites.nix
          else "";
        # PWA app name in app registry (e.g., "youtube-pwa")
        appName = "${lib.toLower (lib.replaceStrings [" "] ["-"] pwa.name)}-pwa";
      in {
        name = ".local/share/applications/FFPWA-${pwa.ulid}.desktop";
        value.text = ''
          [Desktop Entry]
          Type=Application
          Name=${pwa.name}
          Comment=${pwa.description}
          Exec=${config.home.homeDirectory}/.local/bin/app-launcher-wrapper.sh ${lib.toLower (lib.replaceStrings [" "] ["-"] pwa.name)}-pwa
          Icon=${pwa.icon}
          Terminal=false
          Categories=${categoriesStr}
          ${if keywordsStr != "" then "Keywords=${keywordsStr}" else ""}
          StartupNotify=true
        '';
      }) pwas);
  };
}
