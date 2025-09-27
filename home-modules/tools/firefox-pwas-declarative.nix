# Declarative PWA Installation and Management Module
{ config, lib, pkgs, ... }:

with lib;

let
  # Define PWAs to be installed
  pwas = [
    {
      name = "Google";
      url = "https://www.google.com";
      icon = "https://www.google.com/favicon.ico";
      description = "Google Search";
    }
    {
      name = "YouTube";
      url = "https://www.youtube.com";
      icon = "https://www.youtube.com/favicon.ico";
      description = "YouTube Video Platform";
    }
    {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443";
      icon = "https://gitea.cnoe.localtest.me:8443/assets/img/favicon.png";
      description = "Git Repository Management";
    }
    {
      name = "Backstage";
      url = "https://backstage.cnoe.localtest.me:8443";
      icon = "https://backstage.cnoe.localtest.me:8443/favicon.ico";
      description = "Developer Portal";
    }
    {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443";
      icon = "https://kargo.cnoe.localtest.me:8443/favicon.ico";
      description = "GitOps Promotion";
    }
    {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443";
      icon = "https://argocd.cnoe.localtest.me:8443/assets/favicon.ico";
      description = "GitOps Continuous Delivery";
    }
    {
      name = "Headlamp";
      url = "https://headlamp.cnoe.localtest.me:8443";
      icon = "https://headlamp.cnoe.localtest.me:8443/favicon.ico";
      description = "Kubernetes Dashboard";
    }
  ];

  # Script to install and manage PWAs
  managePWAsScript = pkgs.writeShellScript "manage-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.findutils}/bin:${pkgs.jq}/bin:$PATH"
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
        fi
      fi

    '') pwas}

    # Update desktop database
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi

    echo "PWA management completed"
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

        # Try to install using local manifest
        if $FFPWA site install "http://localhost:$PORT/$(basename $MANIFEST_FILE)" \
             --document-url "${pwa.url}" \
             --name "${pwa.name}" \
             --description "${pwa.description}" \
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

  # Provide installation helper script
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
  ];
}