# Fully Declarative PWA Management System
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefox-pwas-declarative;

  # Define PWAs declaratively by name, not by generated ID
  pwaDefinitions = {
    google-ai = {
      name = "Google AI";
      url = "https://www.google.com/search?udm=50";
      icon = ./../../assets/icons/pwas/google-ai.png;  # Using PNG for now
      categories = ["Network" "WebBrowser"];
      keywords = ["search" "ai" "google"];
    };

    youtube = {
      name = "YouTube";
      url = "https://www.youtube.com";
      icon = ./../../assets/icons/pwas/youtube.png;  # Will download/create
      categories = ["AudioVideo" "Video"];
      keywords = ["video" "streaming"];
    };

    argocd = {
      name = "ArgoCD";
      url = "https://argocd.cnoe.localtest.me:8443";
      icon = ./../../assets/icons/pwas/ArgoCD.png;  # Note: capital letters in filename
      categories = ["Development" "Utility"];
      keywords = ["kubernetes" "gitops" "deployment"];
    };

    gitea = {
      name = "Gitea";
      url = "https://gitea.cnoe.localtest.me:8443";
      icon = ./../../assets/icons/pwas/Gitea.png;
      categories = ["Development"];
      keywords = ["git" "repository" "code"];
    };

    backstage = {
      name = "Backstage";
      url = "https://backstage.cnoe.localtest.me:8443";
      icon = ./../../assets/icons/pwas/Backstage.png;
      categories = ["Development"];
      keywords = ["platform" "developer" "portal"];
    };

    headlamp = {
      name = "Headlamp";
      url = "https://headlamp.cnoe.localtest.me:8443";
      icon = ./../../assets/icons/pwas/Headlamp.png;
      categories = ["Development" "System"];
      keywords = ["kubernetes" "dashboard"];
    };

    kargo = {
      name = "Kargo";
      url = "https://kargo.cnoe.localtest.me:8443";
      icon = ./../../assets/icons/pwas/Kargo.png;
      categories = ["Development"];
      keywords = ["deployment" "promotion" "gitops"];
    };
  };

  # Generate deterministic desktop files at build time
  mkPwaDesktopFile = name: pwa: pkgs.writeTextDir "share/applications/pwa-${name}.desktop" ''
    [Desktop Entry]
    Version=1.4
    Type=Application
    Name=${pwa.name}
    Comment=Progressive Web App
    Icon=pwa-${name}
    Exec=${pkgs.firefox}/bin/firefox --new-window --name="${pwa.name}" --class="firefox-pwa-${name}" "${pwa.url}"
    Terminal=false
    StartupNotify=true
    StartupWMClass=firefox-pwa-${name}
    Categories=${concatStringsSep ";" pwa.categories};
    Keywords=${concatStringsSep ";" pwa.keywords};
    Actions=open-normal;open-private;

    [Desktop Action open-normal]
    Name=Open in Normal Firefox
    Exec=${pkgs.firefox}/bin/firefox "${pwa.url}"

    [Desktop Action open-private]
    Name=Open in Private Window
    Exec=${pkgs.firefox}/bin/firefox --private-window "${pwa.url}"
  '';

  # Process icon: convert SVG to PNG at build time if needed
  mkPwaIcon = name: pwa:
    let
      iconName = "pwa-${name}";
      iconFile = pwa.icon;
    in pkgs.runCommand "${iconName}-icon" {
      buildInputs = [ pkgs.imagemagick ];
    } ''
      mkdir -p $out/share/icons/hicolor/scalable/apps

      # If it's an SVG, copy it directly
      if [[ "${iconFile}" == *.svg ]]; then
        cp ${iconFile} $out/share/icons/hicolor/scalable/apps/${iconName}.svg

        # Also generate PNG versions at build time
        for size in 16 32 48 64 96 128 192 256 512; do
          mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
          ${pkgs.imagemagick}/bin/magick ${iconFile} \
            -background none -resize ''${size}x''${size} \
            $out/share/icons/hicolor/''${size}x''${size}/apps/${iconName}.png
        done
      else
        # If it's a PNG, generate all sizes
        for size in 16 32 48 64 96 128 192 256 512; do
          mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
          ${pkgs.imagemagick}/bin/magick ${iconFile} \
            -background none -resize ''${size}x''${size} \
            $out/share/icons/hicolor/''${size}x''${size}/apps/${iconName}.png
        done
      fi
    '';

  # Combine all PWA packages
  pwaPackages = mapAttrsToList (name: pwa:
    pkgs.symlinkJoin {
      name = "pwa-${name}";
      paths = [
        (mkPwaDesktopFile name pwa)
        (mkPwaIcon name pwa)
      ];
    }
  ) cfg.pwas;

in
{
  options.programs.firefox-pwas-declarative = {
    enable = mkEnableOption "Fully declarative Firefox PWA management";

    pwas = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the PWA";
          };
          url = mkOption {
            type = types.str;
            description = "URL to open";
          };
          icon = mkOption {
            type = types.path;
            description = "Path to icon file (SVG preferred)";
          };
          categories = mkOption {
            type = types.listOf types.str;
            default = ["Network"];
            description = "Desktop categories";
          };
          keywords = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Search keywords";
          };
        };
      });
      default = pwaDefinitions;
      description = "Progressive Web App definitions";
    };

    useFirefoxPwa = mkOption {
      type = types.bool;
      default = false;
      description = "Use firefoxpwa tool instead of native Firefox (less declarative)";
    };
  };

  config = mkIf cfg.enable {
    # Install all PWA desktop files and icons
    environment.systemPackages = pwaPackages ++ (with pkgs; [
      firefox
    ]);

    # Create activation script to ensure PWAs are in app menu
    system.activationScripts.declarative-pwas = ''
      # Update desktop database
      if [ -x /run/current-system/sw/bin/update-desktop-database ]; then
        /run/current-system/sw/bin/update-desktop-database -q /run/current-system/sw/share/applications || true
      fi

      # Update icon cache
      if [ -x /run/current-system/sw/bin/gtk-update-icon-cache ]; then
        /run/current-system/sw/bin/gtk-update-icon-cache -qf /run/current-system/sw/share/icons/hicolor || true
      fi
    '';
  };
}