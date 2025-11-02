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
    start_url = pwa.url;
    scope = pwa.scope or "https://${pwa.domain}/";
    display = "standalone";
    description = pwa.description;
    icons = [
      {
        src = pwa.icon;
        sizes = "512x512";
        type = "image/png";
      }
    ];
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

      # Default profile ULID (firefoxpwa convention)
      defaultProfileUlid = "00000000000000000000000000";

      # Convert PWA list to sites attrset keyed by ULID
      sitesAttrset = builtins.listToAttrs (builtins.map (pwa: {
        name = pwa.ulid;
        value = {
          ulid = pwa.ulid;
          profile = defaultProfileUlid;
          config = {
            name = pwa.name;
            description = pwa.description;
            start_url = pwa.url;
            icon_url = null;  # firefoxpwa will populate this
            document_url = pwa.url;  # CRITICAL: Provides security context
            manifest_url = "https://${pwa.domain}/manifest.json";  # Standard location
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
        runtime_enable_wayland = false;
        runtime_use_portals = false;
        runtime_use_xinput2 = false;
        use_linked_runtime = false;
      };

      # Profiles section
      profiles = {
        "${defaultProfileUlid}" = {
          ulid = defaultProfileUlid;
          name = "Default";
          description = "Default profile for all web apps";
          sites = siteUlids;
        };
      };

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
    #
    xdg.desktopEntries = builtins.listToAttrs (builtins.map (pwa: {
      name = "FFPWA-${pwa.ulid}";
      value = {
        name = pwa.name;
        comment = pwa.description;
        exec = "firefoxpwa site launch ${pwa.ulid} --protocol %u";
        icon = "FFPWA-${pwa.ulid}";  # firefoxpwa manages icon cache
        terminal = false;
        type = "Application";
        categories = if (pwa ? categories)
          then builtins.filter (x: x != "") (lib.splitString ";" pwa.categories)
          else [ "Network" ];
        startupNotify = true;
        # Note: Window class will be FFPWA-<ULID> set by firefoxpwa itself
        mimeType = [ "x-scheme-handler/http" "x-scheme-handler/https" ];
      };
    }) pwas);
  };
}
