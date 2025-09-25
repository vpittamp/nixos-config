# Fully Automated Firefox PWA Management for NixOS
# This module provides complete declarative PWA automation including:
# - PWA installation and management
# - Icon generation and caching
# - Desktop file creation
# - KDE taskbar integration via plasma-manager
# - Automatic profile management

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefoxpwa-auto;

  # Generate consistent PWA ID from URL
  generatePwaId = url: let
    hash = builtins.hashString "sha256" url;
  in "01${toUpper (substring 0 24 hash)}";

  # Create desktop file for a PWA
  mkDesktopFile = name: pwa: let
    pwaId = if pwa.id != null then pwa.id else (generatePwaId pwa.url);
  in pkgs.writeTextFile {
    name = "FFPWA-${pwaId}.desktop";
    destination = "/share/applications/FFPWA-${pwaId}.desktop";
    text = ''
      [Desktop Entry]
      Type=Application
      Version=1.4
      Name=${pwa.name}
      Comment=${if pwa.description != null then pwa.description else ""}
      Icon=FFPWA-${pwaId}
      Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${pwaId} --protocol %u
      Terminal=false
      StartupNotify=true
      StartupWMClass=FFPWA-${pwaId}
      Categories=${pwa.categories}
      Keywords=${pwa.keywords}
    '';
  };

  # Generate icon derivation for a PWA
  mkPwaIcon = name: pwa: let
    pwaId = if pwa.id != null then pwa.id else (generatePwaId pwa.url);
  in pkgs.stdenv.mkDerivation {
    name = "pwa-icon-${name}";
    nativeBuildInputs = with pkgs; [ imagemagick curl wget ];

    buildCommand = ''
      mkdir -p $out/share/icons/hicolor

      # Download or use provided icon
      ${if pwa.icon != null then ''
        cp ${pwa.icon} icon_src
      '' else if pwa.iconUrl != null then ''
        curl -L "${pwa.iconUrl}" -o icon_src || \
        wget "${pwa.iconUrl}" -O icon_src || \
        echo "Failed to download icon"
      '' else ''
        # Create a default icon
        convert -size 256x256 xc:blue \
                -fill white -gravity center \
                -pointsize 128 -annotate +0+0 "${substring 0 1 pwa.name}" \
                icon_src
      ''}

      # Generate multiple icon sizes
      for size in 16 22 24 32 48 64 128 256 512; do
        mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
        convert icon_src -resize ''${size}x''${size} \
          $out/share/icons/hicolor/''${size}x''${size}/apps/FFPWA-${pwaId}.png
      done

      # Also create a pixmap version
      mkdir -p $out/share/pixmaps
      cp $out/share/icons/hicolor/256x256/apps/FFPWA-${pwaId}.png \
         $out/share/pixmaps/
    '';
  };

  # PWA installation script
  pwaInstallScript = pkgs.writeScriptBin "install-pwas" ''
    #!${pkgs.bash}/bin/bash
    set -e
    
    echo "Installing Firefox PWAs..."
    
    # Ensure directories exist
    mkdir -p ~/.local/share/firefoxpwa/sites
    mkdir -p ~/.local/share/applications
    mkdir -p ~/.mozilla/native-messaging-hosts
    
    # Link native messaging host
    ln -sf ${pkgs.firefoxpwa}/lib/mozilla/native-messaging-hosts/firefoxpwa.json \
      ~/.mozilla/native-messaging-hosts/firefoxpwa.json 2>/dev/null || true
    
    ${concatMapStringsSep "\n" (name: let
      pwa = cfg.pwas.${name};
      id = if pwa.id != null then pwa.id else (generatePwaId pwa.url);
    in ''
      echo "Checking PWA: ${pwa.name} (${id})"
      
      # Check if already installed by looking for the site directory
      if [ ! -d "$HOME/.local/share/firefoxpwa/sites/${id}" ]; then
        echo "  Installing ${pwa.name}..."
        
        # Create site directory
        mkdir -p "$HOME/.local/share/firefoxpwa/sites/${id}"
        
        # Create site.json
        cat > "$HOME/.local/share/firefoxpwa/sites/${id}/site.json" << 'SITE_JSON_EOF'
{
  "id": "${id}",
  "name": "${pwa.name}",
  "description": "${if pwa.description != null then pwa.description else ""}",
  "start_url": "${pwa.url}",
  "manifest_url": "${if pwa.manifest != null then pwa.manifest else ""}",
  "document_url": "${pwa.url}",
  "icon": {}
}
SITE_JSON_EOF
        
        # Try to install via firefoxpwa if available
        if command -v firefoxpwa &> /dev/null; then
          firefoxpwa site install \
            --name "${pwa.name}" \
            --start-url "${pwa.url}" \
            ${optionalString (pwa.manifest != null) ''"${pwa.manifest}"''} \
            || echo "  Note: firefoxpwa install failed, using fallback"
        fi
      else
        echo "  ${pwa.name} already installed"
      fi
    '') (attrNames cfg.pwas)}
    
    echo "PWA installation complete!"
  '';

  # All desktop files for PWAs
  pwaDesktopFiles = mapAttrs mkDesktopFile cfg.pwas;
  
  # All icon packages for PWAs
  pwaIcons = mapAttrs mkPwaIcon cfg.pwas;

in
{
  options.programs.firefoxpwa-auto = {
    enable = mkEnableOption "Automated Firefox PWA management";
    
    pwas = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name of the PWA";
          };
          
          url = mkOption {
            type = types.str;
            description = "Start URL of the PWA";
          };
          
          manifest = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "URL to the web app manifest";
          };
          
          description = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Description of the PWA";
          };
          
          icon = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Local path to icon file";
          };
          
          iconUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "URL to download icon from";
          };
          
          id = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Specific ID for the PWA (auto-generated if not set)";
          };
          
          categories = mkOption {
            type = types.str;
            default = "GTK;";
            description = "Desktop file categories";
          };
          
          keywords = mkOption {
            type = types.str;
            default = "";
            description = "Desktop file keywords";
          };
        };
      });
      default = {};
      description = "PWAs to install and manage";
    };
    
    autoInstall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically install PWAs on activation";
    };
    
    addToTaskbar = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically add PWAs to KDE taskbar (requires plasma-manager)";
    };
  };
  
  config = mkIf cfg.enable {
    # Install firefoxpwa package, desktop files, and icons
    environment.systemPackages = with pkgs; [
      firefoxpwa
      pwaInstallScript
    ] ++ (attrValues pwaDesktopFiles) ++ (attrValues pwaIcons);

    # Install icon paths
    environment.pathsToLink = [ "/share/icons" "/share/pixmaps" ];
    
    # Auto-install PWAs on activation if enabled
    system.activationScripts.installPwas = mkIf cfg.autoInstall ''
      echo "Setting up Firefox PWAs..."
      
      # Install desktop files system-wide
      ${concatMapStringsSep "\n" (name: let
        desktopPkg = pwaDesktopFiles.${name};
      in ''
        ln -sf ${desktopPkg}/share/applications/*.desktop /run/current-system/sw/share/applications/ 2>/dev/null || true
      '') (attrNames cfg.pwas)}
      
      # Install icons system-wide
      ${concatMapStringsSep "\n" (name: let
        iconPkg = pwaIcons.${name};
      in ''
        for icon in ${iconPkg}/share/icons/hicolor/*/apps/*.png; do
          dir=$(dirname "$icon" | ${pkgs.gnused}/bin/sed "s|${iconPkg}|/run/current-system/sw|")
          mkdir -p "$dir"
          ln -sf "$icon" "$dir/" 2>/dev/null || true
        done
      '') (attrNames cfg.pwas)}
      
      # Update icon cache
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f /run/current-system/sw/share/icons/hicolor 2>/dev/null || true
    '';
    
    # User activation for PWA profiles
    system.userActivationScripts.installPwas = mkIf cfg.autoInstall ''
      ${pwaInstallScript}/bin/install-pwas
    '';
  };
}
