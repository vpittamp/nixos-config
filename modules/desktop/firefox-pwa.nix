# Firefox PWA (Progressive Web Apps) Support Module
# Enables creating standalone web apps using Firefox
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.firefox-pwa;

  # PWA installation script - declaratively creates PWAs on first run
  # PWA manager script with better UX
  pwaManager = pkgs.writeShellScriptBin "pwa-manager" (builtins.readFile ../../scripts/pwa-manager.sh);

  pwaInstaller = pkgs.writeShellScriptBin "install-firefox-pwas" ''
    #!/usr/bin/env bash
    set -e

    # Ensure firefoxpwa is available
    if ! command -v firefoxpwa &> /dev/null; then
      echo "Error: firefoxpwa command not found"
      exit 1
    fi

    # Note: firefoxpwa site install command opens Firefox for interactive installation
    echo "Preparing to install PWAs..."
    echo ""
    echo "YouTube PWA..."
    firefoxpwa site install \
      --name "YouTube" \
      --url "https://youtube.com" || echo "Installation initiated in Firefox"

    echo ""
    echo "Google AI Studio PWA..."
    firefoxpwa site install \
      --name "Google AI Studio" \
      --url "https://aistudio.google.com" || echo "Installation initiated in Firefox"

    echo ""
    echo "Gemini PWA..."
    firefoxpwa site install \
      --name "Gemini" \
      --url "https://gemini.google.com" || echo "Installation initiated in Firefox"

    echo ""
    echo "PWA installation process initiated."
    echo "Complete the installation in Firefox when it opens."
    echo "Use 'firefoxpwa profile list' to see installed profiles."
  '';

in
{
  options.services.firefox-pwa = {
    enable = mkEnableOption "Firefox PWA support";

    autoInstallPWAs = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically install predefined PWAs on system activation";
    };
  };

  config = mkIf cfg.enable {
    # Install the native component for PWAsForFirefox
    environment.systemPackages = with pkgs; [
      firefoxpwa  # Native component for PWAsForFirefox
      pwaInstaller  # Our PWA installation script
      pwaManager  # User-friendly PWA management tool
    ];

    # Enable Firefox with native messaging hosts at system level
    programs.firefox = {
      enable = lib.mkDefault true;
      package = lib.mkDefault pkgs.firefox;
      nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
    };

    # System activation script to install PWAs
    system.activationScripts.firefox-pwas = mkIf cfg.autoInstallPWAs ''
      # Run as the user, not root
      if [ -n "''${SUDO_USER:-}" ]; then
        echo "Setting up Firefox PWAs for user $SUDO_USER..."

        # Check if firefoxpwa is installed and user is available
        if command -v firefoxpwa &> /dev/null && id "$SUDO_USER" &> /dev/null; then
          # Install PWAs as the user
          sudo -u "$SUDO_USER" ${pwaInstaller}/bin/install-firefox-pwas || true
        fi
      fi
    '';

    # Create desktop entries for manual PWA management
    environment.etc."xdg/autostart/firefox-pwa-setup.desktop" = mkIf cfg.autoInstallPWAs {
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Firefox PWA Setup
        Comment=Set up Firefox Progressive Web Apps
        Exec=${pwaInstaller}/bin/install-firefox-pwas
        Icon=firefox
        Terminal=false
        Categories=Network;WebBrowser;
        StartupNotify=true
        Hidden=false
        X-GNOME-Autostart-enabled=true
        X-KDE-autostart-after=panel
      '';
      mode = "0644";
    };

    # Add PWA management commands to user environment
    environment.shellAliases = {
      "pwa" = "${pwaManager}/bin/pwa-manager";
      "pwa-list" = "${pwaManager}/bin/pwa-manager list";
      "pwa-install" = "${pwaManager}/bin/pwa-manager install";
      "pwa-uninstall" = "${pwaManager}/bin/pwa-manager uninstall";
      "pwa-update" = "${pwaManager}/bin/pwa-manager update";
      "pwa-launch" = "${pwaManager}/bin/pwa-manager launch";
      "pwa-setup" = "${pwaManager}/bin/pwa-manager install-defaults";
    };
  };
}