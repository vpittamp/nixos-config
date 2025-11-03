# Declarative PWA Installation Module (Feature 056)
# Fully declarative PWA management with controlled ULIDs
{ config, lib, pkgs, ... }:

with lib;

let
  # Import centralized PWA site definitions
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
  pwas = pwaSitesConfig.pwaSites;

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
  generateManifest = pwa: {
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
        src = pwa.icon;
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
      sitesAttrset = builtins.listToAttrs (builtins.map (pwa: {
        name = pwa.ulid;
        value = {
          ulid = pwa.ulid;
          profile = pwa.ulid;  # Each site uses its own profile
          config = {
            name = pwa.name;
            description = pwa.description;
            start_url = "${pwa.url}/";  # Must match document_url with trailing slash
            icon_url = pwa.icon;
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
        runtime_use_portals = false;
        runtime_use_xinput2 = false;
        use_linked_runtime = true;      # Use immutable runtime from Nix package
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

      # Fix dialog rendering issues on Wayland (Feature 056)
      (pkgs.writeShellScriptBin "pwa-fix-dialogs" ''
        # Fix thin sliver dialog rendering on Wayland with fractional scaling
        # Applies user.js fixes to all PWA profiles

        PROFILES_DIR="$HOME/.local/share/firefoxpwa/profiles"

        if [ ! -d "$PROFILES_DIR" ]; then
          echo "Error: PWA profiles directory not found: $PROFILES_DIR"
          exit 1
        fi

        count=0
        for profile in "$PROFILES_DIR"/*; do
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
EOF
            echo "Updated: $profile/user.js"
            ((count++))
          fi
        done

        echo ""
        echo "✓ Updated $count PWA profiles with Wayland dialog fixes"
        echo ""
        echo "Restart your PWAs for changes to take effect:"
        echo "  1. Close all PWA windows"
        echo "  2. Relaunch PWAs from Walker (Meta+D)"
      '')

    ];

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
          Exec=launch-pwa-by-name ${pwa.ulid}
          Icon=FFPWA-${pwa.ulid}
          Terminal=false
          Categories=${categoriesStr}
          MimeType=x-scheme-handler/http;x-scheme-handler/https;
          StartupNotify=true
        '';
      }) pwas);
  };
}
