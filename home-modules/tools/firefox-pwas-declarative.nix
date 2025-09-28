# Declarative PWA Installation and Management Module
{ config, lib, pkgs, ... }:

with lib;

let
  # Custom icons can be placed in /etc/nixos/assets/pwa-icons/
  # Use format: "file:///etc/nixos/assets/pwa-icons/name.png" for local icons
  # Or use URLs for remote icons

  # Define PWAs to be installed
  pwas = [
    {
      name = "Google AI";
      url = "https://www.google.com/search?udm=50";  # AI mode enabled
      icon = "file:///etc/nixos/assets/pwa-icons/google.png";  # Custom high-res icon
      description = "Google AI Search";
      categories = "Network;WebBrowser;";
      keywords = "search;web;ai;";
    }
    {
      name = "YouTube";
      url = "https://www.youtube.com";
      icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";  # Custom high-res icon
      description = "YouTube Video Platform";
      categories = "AudioVideo;Video;";
      keywords = "video;streaming;";
    }
    {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443";
      icon = "file:///etc/nixos/assets/pwa-icons/gitea.png";  # Official Gitea logo
      description = "Git Repository Management";
      categories = "Development;";
      keywords = "git;code;repository;";
    }
    {
      name = "Backstage";
      url = "https://backstage-dev.cnoe.localtest.me:8443";
      icon = "file:///etc/nixos/assets/pwa-icons/backstage.png";  # Official Backstage logo
      description = "Developer Portal";
      categories = "Development;";
      keywords = "portal;platform;developer;";
    }
    {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443";
      icon = "file:///etc/nixos/assets/pwa-icons/kargo.png";  # Official Akuity Kargo logo
      description = "GitOps Promotion";
      categories = "Development;";
      keywords = "gitops;deployment;kubernetes;";
    }
    {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443";
      icon = "file:///etc/nixos/assets/pwa-icons/argocd.png";  # Official CNCF ArgoCD logo
      description = "GitOps Continuous Delivery";
      categories = "Development;";
      keywords = "gitops;cd;kubernetes;deployment;";
    }
    {
      name = "Headlamp";
      url = "https://headlamp.cnoe.localtest.me:8443";
      icon = "file:///etc/nixos/assets/pwa-icons/headlamp.png";  # Official Headlamp logo (updated)
      description = "Kubernetes Dashboard";
      categories = "Development;System;";
      keywords = "kubernetes;k8s;dashboard;monitoring;";
    }
    {
      name = "Home Assistant";
      url = "http://localhost:8123";
      icon = "file:///etc/nixos/assets/pwa-icons/home-assistant.png";  # Official Home Assistant logo
      description = "Home Automation Platform";
      categories = "Network;RemoteAccess;";
      keywords = "home;automation;smart;iot;assistant;";
    }
    {
      name = "Uber Eats";
      url = "https://www.ubereats.com";
      icon = "file:///etc/nixos/assets/pwa-icons/uber-eats.png";  # Official Uber Eats logo
      description = "Food Delivery Service";
      categories = "Network;Office;";
      keywords = "food;delivery;restaurant;uber;";
    }
  ];

  # Script to install and manage PWAs
  managePWAsScript = pkgs.writeShellScript "manage-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.findutils}/bin:${pkgs.jq}/bin:${pkgs.imagemagick}/bin:$PATH"
    FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"
    DESKTOP_DIR="$HOME/.local/share/applications"
    STATE_FILE="$HOME/.config/firefoxpwa/installed-pwas.json"

    # Ensure directories exist
    mkdir -p "$DESKTOP_DIR"
    mkdir -p "$(dirname "$STATE_FILE")"

    # Initialize state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
      echo '{}' > "$STATE_FILE"
    fi

    # Check if firefoxpwa is available
    if [ ! -x "$FFPWA" ]; then
      echo "firefoxpwa not found, cannot manage PWAs" >&2
      exit 1
    fi

    echo "Managing declarative PWAs..."

    # Get currently installed PWAs
    INSTALLED_IDS=$($FFPWA profile list 2>/dev/null | grep "^- " | awk -F'[()]' '{print $2}' | xargs)

    # Process each declared PWA
    ${lib.concatMapStrings (pwa: ''
      echo "Checking PWA: ${pwa.name}"

      # Check if this PWA is already installed
      PWA_INSTALLED=false
      for id in $INSTALLED_IDS; do
        # Get the name of the installed PWA
        INSTALLED_NAME=$($FFPWA profile list 2>/dev/null | grep "$id" | sed 's/^- \([^:]*\):.*/\1/' | xargs)
        if [ "$INSTALLED_NAME" = "${pwa.name}" ]; then
          PWA_INSTALLED=true
          PWA_ID="$id"
          echo "  Already installed with ID: $id"
          break
        fi
      done

      # Install if not present
      if [ "$PWA_INSTALLED" = false ]; then
        echo "  Installing ${pwa.name}..."

        # Create a simple manifest URL (most sites have one)
        MANIFEST_URL="${pwa.url}/manifest.json"

        # Try to install the PWA
        # Use the site URL as both manifest and document URL for simplicity
        $FFPWA site install "${pwa.url}" \
          --document-url "${pwa.url}" \
          --start-url "${pwa.url}" \
          --name "${pwa.name}" \
          --description "${pwa.description}" \
          --icon-url "${pwa.icon}" \
          --no-system-integration \
          2>&1 | grep -E "(installed|error|failed)" || true

        # Note: This will likely fail for sites without manifests
        # In that case, we provide manual instructions
        if [ $? -ne 0 ]; then
          echo "  Auto-install failed for ${pwa.name}"
          echo "  Manual installation required: firefoxpwa site install '${pwa.url}'"
        fi
      else
        # Create/update desktop file for existing PWA
        if [ ! -z "$PWA_ID" ]; then
          cat > "$DESKTOP_DIR/FFPWA-$PWA_ID.desktop" << DESKTOP
    [Desktop Entry]
    Type=Application
    Version=1.4
    Name=${pwa.name}
    Comment=Firefox Progressive Web App - ${pwa.url}
    Icon=FFPWA-$PWA_ID
    Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch $PWA_ID --protocol %u
    Terminal=false
    StartupNotify=true
    StartupWMClass=FFPWA-$PWA_ID
    Categories=Network;
    MimeType=x-scheme-handler/https;x-scheme-handler/http;
    DESKTOP
          chmod 644 "$DESKTOP_DIR/FFPWA-$PWA_ID.desktop"

          # Process icon for proper KRunner display
          ICON_PATH="${pwa.icon}"
          if [[ "$ICON_PATH" == file://* ]]; then
            ICON_FILE="''${ICON_PATH#file://}"
            if [ -f "$ICON_FILE" ]; then
              echo "  Processing custom icon for ${pwa.name}"

              # Create all required icon sizes for KDE integration
              for size in 16 22 24 32 48 64 128 256 512; do
                icon_dir="$HOME/.local/share/icons/hicolor/''${size}x''${size}/apps"
                mkdir -p "$icon_dir"

                # Check if icon is square and resize appropriately
                dimensions=$(identify "$ICON_FILE" 2>/dev/null | awk '{print $3}' || echo "")
                if [ ! -z "$dimensions" ]; then
                  width=$(echo $dimensions | cut -dx -f1)
                  height=$(echo $dimensions | cut -dx -f2)

                  if [ "$width" != "$height" ]; then
                    # Convert to square format
                    magick "$ICON_FILE" \
                      -resize ''${size}x''${size} \
                      -gravity center \
                      -background transparent \
                      -extent ''${size}x''${size} \
                      "$icon_dir/FFPWA-$PWA_ID.png" 2>/dev/null || \
                    convert "$ICON_FILE" \
                      -resize ''${size}x''${size} \
                      -gravity center \
                      -background transparent \
                      -extent ''${size}x''${size} \
                      "$icon_dir/FFPWA-$PWA_ID.png"
                  else
                    # Just resize
                    magick "$ICON_FILE" -resize ''${size}x''${size} "$icon_dir/FFPWA-$PWA_ID.png" 2>/dev/null || \
                    convert "$ICON_FILE" -resize ''${size}x''${size} "$icon_dir/FFPWA-$PWA_ID.png"
                  fi
                else
                  # Fallback if identify fails
                  magick "$ICON_FILE" -resize ''${size}x''${size} "$icon_dir/FFPWA-$PWA_ID.png" 2>/dev/null || \
                  convert "$ICON_FILE" -resize ''${size}x''${size} "$icon_dir/FFPWA-$PWA_ID.png"
                fi
              done
            fi
          fi
        fi
      fi

    '') pwas}

    # Update desktop database
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi

    # Clear old icon cache for KRunner
    rm -rf ~/.cache/icon-cache.kcache 2>/dev/null || true

    # Update XDG menu
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
      xdg-desktop-menu forceupdate 2>/dev/null || true
    fi

    # Rebuild KDE cache for KRunner icon visibility
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
      kbuildsycoca6 --noincremental 2>/dev/null || true
      echo "KDE cache rebuilt for icon visibility"
    fi

    echo "PWA management completed"

    # Apply dialog fixes for Wayland compatibility
    if [ -x /etc/nixos/scripts/fix-pwa-dialogs.sh ]; then
      echo "Applying dialog fixes..."
      /etc/nixos/scripts/fix-pwa-dialogs.sh >/dev/null 2>&1 || echo "Dialog fixes not available"
    fi

    # Optional: Pin to taskbar if the script exists
    if command -v pwa-pin-taskbar >/dev/null 2>&1; then
      echo "Updating taskbar pins..."
      pwa-pin-taskbar 2>/dev/null || echo "Taskbar pinning not configured"
    elif [ -x /etc/nixos/scripts/pwa-taskbar-pin.sh ]; then
      echo "Updating taskbar pins..."
      /etc/nixos/scripts/pwa-taskbar-pin.sh 2>/dev/null || echo "Taskbar pinning not configured"
    fi
  '';

  # Script to auto-install PWAs (idempotent)
  autoInstallScript = pkgs.writeShellScript "auto-install-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.curl}/bin:${pkgs.lsof}/bin:$PATH"
    FFPWA="${pkgs.firefoxpwa}/bin/firefoxpwa"

    echo "Checking configured PWAs (idempotent operation)..."
    echo ""

    # Debug: Show currently installed PWAs
    echo "Currently installed PWAs:"
    $FFPWA profile list 2>/dev/null | grep "^- " | sed 's/^- /  - /' || echo "  None"
    echo ""

    # Get currently installed PWAs (names only, one per line)
    # This extracts just the name part before the colon
    INSTALLED_NAMES=$($FFPWA profile list 2>/dev/null | grep "^- " | cut -d: -f1 | sed 's/^- //' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # Track what we install
    INSTALLED_COUNT=0
    SKIPPED_COUNT=0
    FAILED_COUNT=0

    # Install each PWA from configuration
    ${lib.concatMapStrings (pwa: ''
      # Check if already installed (exact match)
      if echo "$INSTALLED_NAMES" | grep -qx "${pwa.name}"; then
        echo "✓ ${pwa.name} - already installed"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      else
        echo "Installing ${pwa.name}..."

        # Create a temporary manifest file
        MANIFEST_FILE=$(mktemp /tmp/pwa-manifest-XXXXXX.json)
        echo '{
          "name": "${pwa.name}",
          "short_name": "${pwa.name}",
          "start_url": "${pwa.url}",
          "display": "standalone",
          "description": "${pwa.description}",
          "icons": [{
            "src": "${pwa.icon}",
            "sizes": "512x512",
            "type": "image/png"
          }]
        }' > "$MANIFEST_FILE"

        # Find an available port for the HTTP server
        PORT=8899
        while lsof -i:$PORT >/dev/null 2>&1; do
          PORT=$((PORT + 1))
        done

        # Start a simple HTTP server to serve the manifest
        (cd /tmp && ${pkgs.python3}/bin/python3 -m http.server $PORT >/dev/null 2>&1) &
        SERVER_PID=$!
        sleep 1

        # Try to install using local manifest with proper icon
        ICON_ARG=""
        if [ ! -z "${pwa.icon}" ]; then
          ICON_ARG="--icon-url ${pwa.icon}"
        fi

        if $FFPWA site install "http://localhost:$PORT/$(basename $MANIFEST_FILE)" \
             --document-url "${pwa.url}" \
             --name "${pwa.name}" \
             --description "${pwa.description}" \
             $ICON_ARG \
             ${if (pwa.categories or null) != null then "--categories \"${pwa.categories}\"" else ""} \
             ${if (pwa.keywords or null) != null then "--keywords \"${pwa.keywords}\"" else ""} \
             2>&1 | tee /tmp/pwa-install.log | grep -q "Web app installed"; then
          echo "✓ ${pwa.name} - successfully installed"
          INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        else
          echo "✗ ${pwa.name} - installation failed"
          echo "  Error output:"
          cat /tmp/pwa-install.log | grep -E "(ERROR|error)" | head -3
          echo "  Manual installation may be required"
          FAILED_COUNT=$((FAILED_COUNT + 1))
        fi

        # Clean up
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
        rm -f "$MANIFEST_FILE"
      fi
      echo ""
    '') pwas}

    # Summary
    echo "Installation complete:"
    echo "  - Installed: $INSTALLED_COUNT"
    echo "  - Skipped (already installed): $SKIPPED_COUNT"
    echo "  - Failed: $FAILED_COUNT"

    if [ $INSTALLED_COUNT -gt 0 ]; then
      echo ""
      echo "Updating desktop files..."
      systemctl --user restart manage-pwas.service
    fi

    # Clean up
    rm -f /tmp/pwa-install.log
  '';

in {
  # Run the management script on activation
  home.activation.managePWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Managing declarative PWAs..."
    ${managePWAsScript}
  '';

  # Service to manage PWAs
  systemd.user.services.manage-pwas = {
    Unit = {
      Description = "Manage declarative Firefox PWAs";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${managePWAsScript}";
      StandardOutput = "journal";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Timer to check PWAs daily
  systemd.user.timers.manage-pwas = {
    Unit = {
      Description = "Check declarative PWAs daily";
    };
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # Provide installation helper scripts
  home.packages = [
    pkgs.firefoxpwa
    (pkgs.writeShellScriptBin "pwa-install-all" ''
      ${autoInstallScript}
    '')
    (pkgs.writeShellScriptBin "pwa-list" ''
      echo "Configured PWAs:"
      ${lib.concatMapStrings (pwa: ''
        echo "  - ${pwa.name}: ${pwa.url}"
      '') pwas}
      echo ""
      echo "Installed PWAs:"
      ${pkgs.firefoxpwa}/bin/firefoxpwa profile list 2>/dev/null | grep "^- " || echo "  None"
    '')
    (pkgs.writeShellScriptBin "pwa-update-panels" ''
      # Check PWA panel status (safe version that doesn't modify panels)
      if [ -f /etc/nixos/scripts/pwa-update-panels-fixed.sh ]; then
        /etc/nixos/scripts/pwa-update-panels-fixed.sh
      elif [ -f /etc/nixos/scripts/pwa-update-panels.sh ]; then
        echo "Warning: Using old panel update script. This may cause issues."
        echo "Showing status only..."
        echo ""
        # Just show PWA status, don't modify anything
        firefoxpwa profile list 2>/dev/null | grep "^- " || echo "No PWAs installed"
        echo ""
        echo "To update panels, edit panels.nix with the IDs above and rebuild."
      else
        echo "Error: Panel update script not found"
        echo "Please run from within /etc/nixos"
        exit 1
      fi
    '')
    (pkgs.writeShellScriptBin "pwa-get-ids" ''
      # Get current PWA IDs for updating panels.nix
      echo "Current PWA IDs (for panels.nix):"
      echo ""
      firefoxpwa profile list 2>/dev/null | grep "^- " | while IFS=: read -r name_part rest; do
        name=$(echo "$name_part" | sed 's/^- //' | xargs)
        id=$(echo "$rest" | awk -F'[()]' '{print $2}' | xargs)
        if [ ! -z "$id" ]; then
          varname=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
          echo "      ''${varname}Id = \"$id\";  # $name"
        fi
      done
      echo ""
      echo "Copy these IDs to panels.nix and rebuild to make permanent."
    '')
  ];
}