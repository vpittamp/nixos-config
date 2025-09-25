# Home-Manager Module for KDE Plasma PWA Taskbar Integration
# This module works with plasma-manager to automatically add PWAs to the taskbar

{ config, lib, pkgs, osConfig, ... }:

with lib;

let
  cfg = config.programs.plasma-pwa-taskbar;
  
  # Get PWA configuration from system config if available
  systemPwas = if (osConfig != null && osConfig ? programs && osConfig.programs ? firefoxpwa-auto && osConfig.programs.firefoxpwa-auto ? pwas)
                then osConfig.programs.firefoxpwa-auto.pwas
                else {};
  
  # Generate PWA ID from URL (must match system module)
  generatePwaId = url: let
    hash = builtins.hashString "sha256" url;
  in "01${toUpper (substring 0 24 hash)}";
  
  # Build launcher entry for a PWA
  mkPwaLauncher = name: pwa:
    if pwa != null && pwa ? url then let
      id = if pwa ? id && pwa.id != null then pwa.id else (generatePwaId pwa.url);
    in "file://$HOME/.local/share/applications/FFPWA-${id}.desktop"
    else "";
  
  # Build complete launcher list
  buildLauncherList = pwas: let
    # Default applications
    baseApps = [
      "applications:firefox.desktop"
      "applications:org.kde.dolphin.desktop"
      "applications:org.kde.konsole.desktop"
    ];

    # PWA launchers (filter out empty entries)
    pwaLaunchers = filter (x: x != "") (mapAttrsToList mkPwaLauncher pwas);
  in
    concatStringsSep "," (baseApps ++ pwaLaunchers);

in
{
  options.programs.plasma-pwa-taskbar = {
    enable = mkEnableOption "Automatic PWA taskbar integration for KDE Plasma";
    
    pwas = mkOption {
      type = types.attrs;
      default = systemPwas;
      description = "PWAs to add to taskbar (defaults to system PWAs)";
    };
    
    primaryScreen = mkOption {
      type = types.bool;
      default = true;
      description = "Add PWAs to primary screen panel";
    };
    
    additionalScreens = mkOption {
      type = types.listOf types.int;
      default = [];
      description = "Additional screen numbers to add PWAs to";
    };
  };
  
  config = mkIf (cfg.enable && config.programs.plasma.enable) {
    # Configure plasma panel using plasma-manager
    programs.plasma.configFile = {
      "plasma-org.kde.plasma.desktop-appletsrc" = {
        # Configure Icon Tasks widget for primary panel
        "Containments.410.Applets.412.Configuration.General" = mkIf cfg.primaryScreen {
          "launchers" = buildLauncherList cfg.pwas;
          "showOnlyCurrentActivity" = true;
          "showOnlyCurrentDesktop" = false;
          "showOnlyCurrentScreen" = true;
        };
        
        # Configure additional panels if specified
      } // (listToAttrs (map (screenNum: {
        name = "Containments.${toString (429 + screenNum)}.Applets.430.Configuration.General";
        value = {
          "launchers" = buildLauncherList cfg.pwas;
          "showOnlyCurrentActivity" = true;
          "showOnlyCurrentDesktop" = false;
          "showOnlyCurrentScreen" = true;
        };
      }) cfg.additionalScreens));
    };
    
    # Ensure PWA desktop files are installed for the user
    home.activation.ensurePwaDesktopFiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Ensuring PWA desktop files are available..."
      
      # Create applications directory
      mkdir -p "$HOME/.local/share/applications"
      
      # Link or copy desktop files
      ${concatMapStringsSep "\n" (name: let
        pwa = cfg.pwas.${name};
        id = if pwa ? id && pwa.id != null then pwa.id else if pwa ? url then (generatePwaId pwa.url) else "unknown";
      in ''
        desktop_file="$HOME/.local/share/applications/FFPWA-${id}.desktop"
        
        if [ ! -f "$desktop_file" ]; then
          # Try to find system desktop file
          system_desktop="/run/current-system/sw/share/applications/FFPWA-${id}.desktop"
          
          if [ -f "$system_desktop" ]; then
            ln -sf "$system_desktop" "$desktop_file"
          else
            # Create desktop file if not found
            cat > "$desktop_file" << 'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Version=1.4
Name=${pwa.name}
Comment=${if pwa ? description && pwa.description != null then pwa.description else ""}
Icon=FFPWA-${id}
Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${id} --protocol %u
Terminal=false
StartupNotify=true
StartupWMClass=FFPWA-${id}
Categories=${if pwa ? categories then pwa.categories else "GTK;"}
Keywords=${if pwa ? keywords then pwa.keywords else ""}
DESKTOP_EOF
          fi
        fi
      '') (attrNames cfg.pwas)}
      
      # Update desktop database
      ${pkgs.desktop-file-utils}/bin/update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
      
      # Update KDE cache
      ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental 2>/dev/null || \
      ${pkgs.kdePackages.kservice}/bin/kbuildsycoca5 --noincremental 2>/dev/null || true
    '';
  };
}
