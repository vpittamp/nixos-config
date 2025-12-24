{ config, lib, pkgs, assetsPackage, osConfig, ... }:

# Feature 034: Unified Application Launcher - Application Registry
# Feature 106: Portable icon paths via assetsPackage
#
# This module defines all launchable applications with project context support.
# Applications are defined declaratively and generate:
# - JSON registry at ~/.config/i3/application-registry.json
# - Desktop files at ~/.local/share/applications/
# - Window rules at ~/.config/i3/window-rules-generated.json

let
  # Feature 125: Pass hostName for host-specific parameterization
  hostName = if osConfig ? networking && osConfig.networking ? hostName then osConfig.networking.hostName else "";

  # Import validated application definitions from shared data file
  # Feature 106: Pass assetsPackage for portable icon paths
  validated = import ./app-registry-data.nix { inherit lib assetsPackage hostName; };

  # Import PWA sites configuration
  # Feature 106: Pass assetsPackage for portable icon paths
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib assetsPackage hostName; };

  # Transform PWA sites to simplified PWA registry format
  # Only include fields needed by sway-test framework and workspace panel
  pwaDefinitions = map (pwa: {
    name = lib.toLower pwa.name;  # Normalize to lowercase for consistency
    url = pwa.url;
    ulid = pwa.ulid;
    icon = pwa.icon;  # Include icon for workspace panel
    preferred_workspace = if pwa ? preferred_workspace then pwa.preferred_workspace else null;
    preferred_monitor_role = if pwa ? preferred_monitor_role then pwa.preferred_monitor_role else null;
  }) pwaSitesConfig.pwaSites;

  # Helper to generate .desktop file content manually
  # This avoids xdg.desktopEntries schema issues with newer home-manager
  mkDesktopFile = app:
    let
      comment = if app ? description then app.description else "Launch ${app.display_name}";
      categories = if app.scope == "scoped" then "Development;ProjectScoped;" else "Application;Global;";
    in
    ''
      [Desktop Entry]
      Type=Application
      Name=${app.display_name}
      Comment=${comment}
      Exec=${config.home.homeDirectory}/.local/bin/app-launcher-wrapper.sh ${app.name}
      Icon=${if app ? icon then app.icon else "application-x-executable"}
      Terminal=false
      NoDisplay=false
      Categories=${categories}
      ${lib.optionalString (app ? expected_class) "StartupWMClass=${app.expected_class}"}
      X-Project-Scope=${app.scope}
      X-Preferred-Workspace=${toString app.preferred_workspace}
      X-Multi-Instance=${if app.multi_instance then "true" else "false"}
      X-Fallback-Behavior=${app.fallback_behavior}
      ${lib.optionalString (app ? nix_package) "X-Nix-Package=${app.nix_package}"}
    '';

  # Generate home.file entries for each .desktop file
  # Use completely separate directory outside standard XDG paths
  # so Walker/Elephant only shows our apps (Feature 034)
  # EXCLUDE PWA apps - they have desktop files from firefox-pwas-declarative.nix
  desktopFileEntries = builtins.listToAttrs (map (app: {
    name = ".local/share/i3pm-applications/applications/${app.name}.desktop";
    value.text = mkDesktopFile app;
  }) (builtins.filter (app: !lib.hasSuffix "-pwa" app.name) validated));

in
{
  # Generate JSON registry from validated application definitions
  home.file = {
    ".config/i3/application-registry.json".text = builtins.toJSON {
      version = "1.0.0";
      applications = validated;
    };

    # Generate PWA registry for sway-test framework (Feature 070)
    ".config/i3/pwa-registry.json".text = builtins.toJSON {
      version = "1.0.0";
      pwas = pwaDefinitions;
    };
  } // desktopFileEntries;  # T040: Generate .desktop files manually
}
