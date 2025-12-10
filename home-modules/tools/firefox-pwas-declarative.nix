# Declarative PWA Installation Module (Feature 056)
# Fully declarative PWA management with controlled ULIDs
{ config, lib, pkgs, ... }:

with lib;

let
  # Import centralized PWA site definitions
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
  pwas = pwaSitesConfig.pwaSites;
  ensureFileUrl = path:
    if lib.hasPrefix "file://" path then path
    else if lib.hasPrefix "/" path then "file://${path}"
    else throw "PWA icon path must be absolute or file:// URL: ${path}";

  inherit (lib.hm.dag) entryAfter;

  # Feature 113: Google redirect URL interceptor extension for PWAs
  # This extension extracts the real URL from Google tracking/redirect links
  # and opens them externally, allowing PWA URL routing to work correctly
  googleRedirectInterceptorExtension = pkgs.runCommand "pwa-google-redirect-interceptor" {} ''
    mkdir -p $out

    # manifest.json - Extension manifest
    cat > $out/manifest.json << 'MANIFEST'
    {
      "manifest_version": 2,
      "name": "PWA Link Interceptor",
      "version": "1.0.0",
      "description": "Intercepts Google/tracking redirect URLs and opens the real destination externally (Feature 113)",
      "permissions": [
        "activeTab",
        "<all_urls>"
      ],
      "content_scripts": [
        {
          "matches": ["*://*.google.com/*", "*://*.youtube.com/*", "*://*.bing.com/*"],
          "js": ["content.js"],
          "run_at": "document_start",
          "all_frames": true
        }
      ],
      "browser_specific_settings": {
        "gecko": {
          "id": "pwa-link-interceptor@nixos-config"
        }
      }
    }
    MANIFEST

    # content.js - Content script that intercepts redirect links
    cat > $out/content.js << 'CONTENTJS'
    // Feature 113: PWA Link Interceptor
    // Intercepts Google/tracking redirect URLs and opens them externally

    (function() {
      'use strict';

      // Patterns for redirect URLs that contain the real destination
      const REDIRECT_PATTERNS = [
        // Google redirect: google.com/url?...&url=<real_url>
        { pattern: /[?&]url=([^&]+)/i, decode: true },
        // Google redirect: google.com/url?...&q=<real_url>
        { pattern: /[?&]q=([^&]+)/i, decode: true },
        // YouTube redirect
        { pattern: /[?&]redir_token=[^&]+.*[?&]q=([^&]+)/i, decode: true },
      ];

      // Domains that should be opened externally (not same-origin)
      // These are domains we have PWAs for
      const PWA_DOMAINS = [
        'github.com', 'www.github.com',
        'claude.ai', 'www.claude.ai',
        'youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be',
        'chatgpt.com', 'www.chatgpt.com', 'chat.openai.com',
        'mail.google.com',
        'calendar.google.com',
        'outlook.office.com', 'outlook.live.com',
        'perplexity.ai', 'www.perplexity.ai',
        'github.dev',
        'vscode.dev', 'insiders.vscode.dev'
      ];

      function extractRealUrl(href) {
        for (const {pattern, decode} of REDIRECT_PATTERNS) {
          const match = href.match(pattern);
          if (match && match[1]) {
            try {
              const url = decode ? decodeURIComponent(match[1]) : match[1];
              // Validate it's actually a URL
              if (url.startsWith('http://') || url.startsWith('https://')) {
                return url;
              }
            } catch (e) {
              // Decoding failed, continue to next pattern
            }
          }
        }
        return null;
      }

      function getDomain(url) {
        try {
          const parsed = new URL(url);
          return parsed.hostname.toLowerCase();
        } catch (e) {
          return null;
        }
      }

      function shouldOpenExternally(realUrl) {
        const domain = getDomain(realUrl);
        if (!domain) return false;

        // Check if the real URL's domain is different from current page
        const currentDomain = window.location.hostname.toLowerCase();

        // If same domain, don't intercept
        if (domain === currentDomain) return false;

        // If real URL points to a PWA domain, open externally
        if (PWA_DOMAINS.some(d => domain === d || domain.endsWith('.' + d))) {
          return true;
        }

        // For any cross-domain link from a Google property, open externally
        // This allows pwa-url-router to handle it
        if (currentDomain.includes('google.com') || currentDomain.includes('youtube.com')) {
          return true;
        }

        return false;
      }

      function handleClick(event) {
        // Find the clicked link (may be nested in other elements)
        let target = event.target;
        while (target && target.tagName !== 'A') {
          target = target.parentElement;
        }

        if (!target || !target.href) return;

        const href = target.href;

        // Check if this is a redirect URL
        const realUrl = extractRealUrl(href);

        if (realUrl && shouldOpenExternally(realUrl)) {
          // Prevent default navigation
          event.preventDefault();
          event.stopPropagation();

          // Open the real URL externally (will trigger xdg-open → pwa-url-router)
          console.log('[PWA Link Interceptor] Redirecting:', href, '→', realUrl);
          window.open(realUrl, '_blank');
        }
      }

      // Intercept clicks on document
      document.addEventListener('click', handleClick, true);

      // Also handle mousedown for middle-click
      document.addEventListener('mousedown', function(event) {
        if (event.button === 1) { // Middle click
          handleClick(event);
        }
      }, true);

      console.log('[PWA Link Interceptor] Feature 113 active');
    })();
    CONTENTJS
  '';

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
user_pref("widget.use-xdg-desktop-portal.mime-handler", 1);

// Ensure native Wayland backend
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);

// === Mesa/Asahi GPU Crash Workarounds ===
// Fixes SIGSEGV crashes in libgallium on Apple Silicon
// Bug: Use-after-free in Mesa GPU driver triggered by WebGL content

// Disable WebGL to prevent GPU driver crashes
user_pref("webgl.disabled", true);
user_pref("webgl.enable-webgl2", false);

// Use software rendering for canvas operations
user_pref("gfx.canvas.accelerated", false);

// Disable GPU process to reduce driver complexity
user_pref("layers.gpu-process.enabled", false);
user_pref("media.hardware-video-decoding.enabled", false);

// Keep basic GPU compositing but avoid problematic features
user_pref("gfx.webrender.compositor", false);

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

// === Feature 113: PWA External Link Handling ===
// Open out-of-scope URLs in the default system browser
// This allows pwa-url-router to intercept and route them appropriately
user_pref("firefoxpwa.openOutOfScopeInDefaultBrowser", true);

// IMPORTANT: Do NOT set firefoxpwa.allowedDomains here!
// Per https://github.com/filips123/PWAsForFirefox/discussions/197
// Setting allowedDomains breaks openOutOfScopeInDefaultBrowser functionality.
// SSO flows will open in the default browser, but pwa-url-router will
// route them back to the appropriate PWA if the domain matches.
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

  # Feature 113: Script to install link interceptor extension into PWA profiles
  pwaInstallLinkInterceptorScript = pkgs.writeShellScriptBin "pwa-install-link-interceptor" ''
    #!/usr/bin/env bash
    # Feature 113: Install PWA Link Interceptor extension
    # This extension intercepts Google/tracking redirect URLs and opens them externally

    set -euo pipefail

    PROFILES_DIR="$HOME/.local/share/firefoxpwa/profiles"
    EXTENSION_SRC="${googleRedirectInterceptorExtension}"
    EXTENSION_ID="pwa-link-interceptor@nixos-config"

    echo "Installing PWA Link Interceptor extension (Feature 113)..."
    echo "Source: $EXTENSION_SRC"

    if [ ! -d "$PROFILES_DIR" ]; then
      echo "No PWA profiles found at $PROFILES_DIR"
      echo "Install some PWAs first, then run this script."
      exit 0
    fi

    count=0
    for profile in "$PROFILES_DIR"/*/; do
      if [ -d "$profile" ]; then
        profile_name=$(basename "$profile")
        ext_dir="$profile/extensions/$EXTENSION_ID"

        echo "  Installing to profile: $profile_name"

        # Create extensions directory
        mkdir -p "$profile/extensions"

        # Remove old installation if exists
        rm -rf "$ext_dir"

        # Copy extension files
        mkdir -p "$ext_dir"
        cp "$EXTENSION_SRC/manifest.json" "$ext_dir/"
        cp "$EXTENSION_SRC/content.js" "$ext_dir/"

        ((count++))
      fi
    done

    echo ""
    echo "✓ Installed link interceptor to $count PWA profiles"
    echo ""
    echo "The extension will intercept Google/tracking redirect URLs"
    echo "and open the real destination externally (via pwa-url-router)."
    echo ""
    echo "Restart your PWAs to activate the extension."
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
      pwaInstallLinkInterceptorScript  # Feature 113: Google redirect interceptor
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

    # Feature 113: Install link interceptor extension to all PWA profiles
    home.activation.firefoxpwaInstallLinkInterceptor = entryAfter [ "firefoxpwaEnsure1Password" ] ''
      if [ -x "${pwaInstallLinkInterceptorScript}/bin/pwa-install-link-interceptor" ]; then
        "${pwaInstallLinkInterceptorScript}/bin/pwa-install-link-interceptor" || true
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
          MimeType=x-scheme-handler/http;x-scheme-handler/https;
          StartupNotify=true
        '';
      }) pwas);
  };
}
