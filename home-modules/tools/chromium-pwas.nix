# Chromium-based PWA Management (Proof of Concept)
# Dramatically simpler than Firefox PWA approach
{ config, lib, pkgs, ... }:

with lib;

let
  # Simple PWA definitions - just URL and optional overrides
  pwas = [
    {
      url = "https://www.google.com/search?udm=50";
      name = "Google AI";  # Optional: auto-detected from site
    }
    {
      url = "https://www.youtube.com";
      name = "YouTube";
    }
    {
      url = "https://gitea.cnoe.localtest.me:8443";
      name = "Gitea";
    }
    {
      url = "https://cnoe.localtest.me:8443";
      name = "Backstage";
    }
    {
      url = "https://kargo.cnoe.localtest.me:8443";
      name = "Kargo";
    }
    {
      url = "https://argocd.cnoe.localtest.me:8443";
      name = "ArgoCD";
    }
    {
      url = "http://localhost:8123";
      name = "Home Assistant";
    }
    {
      url = "https://www.ubereats.com";
      name = "Uber Eats";
    }
  ];

  # Simple installation script - Chromium does all the heavy lifting
  installPWAsScript = pkgs.writeShellScript "install-chromium-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.chromium}/bin:$PATH"

    echo "Installing Chromium PWAs..."
    echo ""

    # Chromium PWA data directory
    PWA_DIR="$HOME/.config/chromium/Default/Web Applications"
    mkdir -p "$PWA_DIR"

    ${lib.concatMapStrings (pwa: ''
      echo "Installing ${pwa.name}..."

      # Chromium's native PWA installation
      # --install-url installs the PWA and exits
      # --no-startup-window prevents browser window from opening
      chromium \
        --install-url="${pwa.url}" \
        --no-startup-window \
        2>/dev/null &

      # Give Chromium time to install
      sleep 2

      # Kill the background Chromium process
      pkill -f "chromium.*${pwa.url}" 2>/dev/null || true

      echo "✓ ${pwa.name} installed"
      echo ""
    '') pwas}

    echo "PWA installation complete!"
    echo ""
    echo "Installed PWAs can be found in:"
    echo "  - Application menu: Search for app names"
    echo "  - Desktop files: ~/.local/share/applications/chrome-*"
    echo ""
    echo "To launch: Click app icon or run 'chromium --app=<url>'"
  '';

  # List installed PWAs
  listPWAsScript = pkgs.writeShellScript "list-chromium-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"

    echo "Configured PWAs:"
    ${lib.concatMapStrings (pwa: ''
      echo "  - ${pwa.name}: ${pwa.url}"
    '') pwas}
    echo ""

    echo "Installed PWA desktop files:"
    if [ -d "$HOME/.local/share/applications" ]; then
      ls -1 "$HOME/.local/share/applications"/chrome-*.desktop 2>/dev/null | while read -r file; do
        name=$(grep "^Name=" "$file" | cut -d= -f2)
        echo "  - $name ($(basename "$file"))"
      done
    else
      echo "  None found"
    fi
  '';

  # Clean up PWAs
  uninstallPWAsScript = pkgs.writeShellScript "uninstall-chromium-pwas" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"

    echo "Removing Chromium PWAs..."

    # Remove PWA desktop files
    rm -f "$HOME/.local/share/applications"/chrome-*.desktop

    # Remove PWA data
    rm -rf "$HOME/.config/chromium/Default/Web Applications"

    echo "✓ All Chromium PWAs removed"
  '';

in {
  # Install Chromium
  programs.chromium = {
    enable = true;

    # Enable PWA support via command line flags
    commandLineArgs = [
      # Enable PWA features
      "--enable-features=WebAppInstallation"
      # Optional: Disable GPU for remote desktop compatibility
      # "--disable-gpu"
    ];
  };

  # Activation script to install PWAs
  home.activation.installChromiumPWAs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d "$HOME/.config/chromium/Default/Web Applications" ]; then
      echo "Installing Chromium PWAs for first time..."
      ${installPWAsScript}
    else
      echo "Chromium PWAs already installed (run 'chromium-pwa-install' to reinstall)"
    fi
  '';

  # Provide helper commands
  home.packages = [
    (pkgs.writeShellScriptBin "chromium-pwa-install" ''
      ${installPWAsScript}
    '')
    (pkgs.writeShellScriptBin "chromium-pwa-list" ''
      ${listPWAsScript}
    '')
    (pkgs.writeShellScriptBin "chromium-pwa-uninstall" ''
      ${uninstallPWAsScript}
    '')
  ];
}
