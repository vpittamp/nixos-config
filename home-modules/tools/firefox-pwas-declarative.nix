# Declarative PWA Installation Module (Feature 056)
# TDD-driven implementation with ULID-based cross-machine portability
{ config, lib, pkgs, ... }:

with lib;

let
  # Import centralized PWA site definitions
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib; };
  pwas = pwaSitesConfig.pwaSites;

  #
  # Core Functions (Phase 2: Foundational)
  #

  # validateULID: Validates ULID format (T010)
  # ULID spec: 26 characters from alphabet [0-9A-HJKMNP-TV-Z]
  # Excludes: I, L, O, U (to avoid confusion with 1, 1, 0, V)
  #
  # Test coverage: T007-T009 in tests/pwa-installation/unit/test-validate-ulid.nix
  # Returns: true if valid, false otherwise
  validateULID = ulid:
    let
      # Check length is exactly 26 characters
      len = builtins.stringLength ulid;

      # ULID alphabet: 0-9, A-Z excluding I, L, O, U
      # Regex pattern: ^[0-9A-HJKMNP-TV-Z]{26}$
      #
      # We use builtins.match which returns null if no match, or a list if match
      isValidFormat = builtins.match "[0-9A-HJKMNP-TV-Z]{26}" ulid != null;
    in
    len == 26 && isValidFormat;

  # generateManifest: Generate Web App Manifest JSON from PWA definition (T015)
  # Generates a standards-compliant Web App Manifest
  #
  # Test coverage: T012-T014 in tests/pwa-installation/unit/test-generate-manifest.nix
  # Spec: https://www.w3.org/TR/appmanifest/
  # Returns: attrset representing manifest JSON
  generateManifest = pwa: {
    name = pwa.name;
    short_name = pwa.name;  # Use same as name for simplicity
    start_url = pwa.url;
    scope = pwa.scope or "https://${pwa.domain}/";  # Default to domain root
    display = "standalone";  # Always standalone for PWAs
    description = pwa.description;
    icons = [
      {
        src = pwa.icon;
        sizes = "512x512";
        type = "image/png";
      }
    ];
  };

  # generateFirefoxPWAConfig: Generate firefoxpwa config.json (T021)
  # Creates the config.json structure for firefoxpwa runtime
  #
  # Test coverage: T017-T020
  # Returns: attrset representing config.json
  generateFirefoxPWAConfig = pwaList:
    let
      # Check for duplicate ULIDs
      ulids = builtins.map (pwa: pwa.ulid) pwaList;
      uniqueULIDs = lib.lists.unique ulids;
      hasDuplicates = builtins.length ulids != builtins.length uniqueULIDs;

      # Convert PWA list to sites attrset keyed by ULID
      sitesAttrset = builtins.listToAttrs (builtins.map (pwa: {
        name = pwa.ulid;
        value = {
          name = pwa.name;
          description = pwa.description;
          start_url = pwa.url;
          scope = pwa.scope or "https://${pwa.domain}/";
          # manifest_url and icon_path will be set during installation
          manifest_url = "file:///tmp/placeholder-${pwa.ulid}.json";
          icon_path = pwa.icon;
        };
      }) pwaList);
    in
    if hasDuplicates
    then throw "Duplicate ULIDs detected in PWA configuration"
    else {
      version = 5;
      runtime_version = "2.12.3";  # firefoxpwa version
      profiles = {
        "00000000000000000000000000" = {  # Default profile ULID
          name = "Default";
          description = "Default Firefox PWA Profile";
          config = {};
          sites = sitesAttrset;
        };
      };
    };

in
{
  #
  # Module Configuration (T023-T024)
  #

  # Module options (T024)
  options.programs.firefoxpwa-declarative = {
    enable = mkEnableOption "Declarative Firefox PWA management";
  };

  config = mkIf config.programs.firefoxpwa-declarative.enable {
    # Validate all ULIDs in pwa-sites.nix on module load
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

    #
    # Phase 3: User Story 1 - Zero-Touch PWA Deployment (T033-T041)
    #

    # Ensure firefoxpwa is installed (T033)
    home.packages = [
      pkgs.firefoxpwa

      # T052: Cross-machine PWA launcher
      (pkgs.writeShellScriptBin "launch-pwa-by-name" (builtins.readFile ./launch-pwa-by-name.sh))
    ];

    # T034: Generate manifest files for all PWAs
    xdg.dataFile = builtins.listToAttrs (builtins.map (pwa:
      {
        name = "pwa-manifests/${pwa.ulid}.json";
        value = {
          text = builtins.toJSON (generateManifest pwa);
        };
      }
    ) pwas);

    # T035-T036: Generate firefoxpwa config.json
    xdg.configFile."firefoxpwa/config.json" = {
      text = builtins.toJSON (generateFirefoxPWAConfig pwas);
    };

    # T037-T040: Installation script with idempotency and error handling
    home.activation.managePWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Managing declarative PWAs..."

      FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"
      MANIFEST_DIR="$HOME/.local/share/pwa-manifests"

      # Check if firefoxpwa is available
      if [ ! -x "$FFPWA" ]; then
        echo "Warning: firefoxpwa not found, skipping PWA installation"
        exit 0
      fi

      # Get currently installed PWAs (T038: Idempotency check)
      INSTALLED_NAMES=$($FFPWA profile list 2>/dev/null | grep "^- " | sed 's/^- \([^:]*\):.*/\1/' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' || echo "")

      # Install each PWA (T037: installPWAScript)
      ${lib.concatMapStrings (pwa: ''
        # T038: Check if already installed (idempotency)
        if echo "$INSTALLED_NAMES" | grep -qxF "${pwa.name}"; then
          $VERBOSE_ECHO "PWA already installed: ${pwa.name}"
        else
          $VERBOSE_ECHO "Installing PWA: ${pwa.name}..."

          # Use manifest from xdg.dataFile
          MANIFEST_PATH="$MANIFEST_DIR/${pwa.ulid}.json"

          # T040: Error handling - log errors but continue
          if $FFPWA site install "$MANIFEST_PATH" \
               --name "${pwa.name}" \
               --description "${pwa.description}" \
               --start-url "${pwa.url}" \
               ${if (pwa ? categories) then "--categories \"${pwa.categories}\"" else ""} \
               ${if (pwa ? keywords) then "--keywords \"${pwa.keywords}\"" else ""} \
               2>&1 | grep -q "installed"; then
            $VERBOSE_ECHO "  ✓ ${pwa.name} installed successfully"
          else
            echo "  Warning: Failed to install ${pwa.name}" >&2
          fi
        fi
      '') pwas}

      # T041: Create desktop entry symlinks
      PWA_DIR="$HOME/.local/share/firefox-pwas"
      APPS_DIR="$HOME/.local/share/applications"

      if [ -d "$PWA_DIR" ]; then
        mkdir -p "$APPS_DIR"
        for desktop_file in "$PWA_DIR"/*.desktop; do
          if [ -f "$desktop_file" ]; then
            basename=$(basename "$desktop_file")
            $DRY_RUN_CMD ln -sf "$desktop_file" "$APPS_DIR/$basename"
          fi
        done
      fi

      $VERBOSE_ECHO "PWA management completed"
    '';
  };
}
