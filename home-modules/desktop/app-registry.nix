{ config, lib, pkgs, assetsPackage, osConfig, ... }:

# Feature 034: Unified Application Launcher - Application Registry
# Feature 106: Portable icon paths via assetsPackage
#
# This module defines all launchable applications with project context support.
# Applications are defined declaratively and generate:
# - Base JSON registry at ~/.local/share/i3pm/registry/base.json
# - Effective runtime JSON registry at ~/.config/i3/application-registry.json
# - Desktop files at ~/.local/share/applications/
# - Window rules at ~/.config/i3/window-rules-generated.json

let
  # Feature 125: Pass hostName for host-specific parameterization
  hostName = if osConfig ? networking && osConfig.networking ? hostName then osConfig.networking.hostName else "";
  appRegistrySyncTool = import ./app-registry-sync-tool.nix { inherit pkgs lib; };

  # Import validated application definitions from shared data file
  # Feature 106: Pass assetsPackage for portable icon paths
  registryData = import ./app-registry-data.nix { inherit lib assetsPackage hostName; };

  # Import PWA sites configuration
  # Feature 106: Pass assetsPackage for portable icon paths
  pwaSitesConfig = import ../../shared/pwa-sites.nix { inherit lib assetsPackage hostName; };

  appRegistryOverlayPath = ../../shared/app-registry-overrides.json;
  editableOverlayFields = [
    "aliases"
    "description"
    "display_name"
    "fallback_behavior"
    "floating"
    "floating_size"
    "icon"
    "multi_instance"
    "preferred_monitor_role"
    "preferred_workspace"
  ];
  rawAppRegistryOverlay = builtins.fromJSON (builtins.readFile appRegistryOverlayPath);
  appRegistryOverlayApplications =
    if rawAppRegistryOverlay ? applications
    then rawAppRegistryOverlay.applications
    else { };
  filteredOverlayFor = app:
    let
      rawOverride =
        if builtins.hasAttr app.name appRegistryOverlayApplications
        then builtins.getAttr app.name appRegistryOverlayApplications
        else { };
    in
    lib.filterAttrs (name: _value: builtins.elem name editableOverlayFields) rawOverride;
  declarativeApplications = map (app: app // filteredOverlayFor app) registryData.applications;

  # Transform PWA sites to simplified PWA registry format
  # Only include fields needed by sway-test framework and workspace panel
  pwaDefinitions = map (pwa: {
    name = lib.toLower pwa.name;  # Normalize to lowercase for consistency
    url = pwa.url;
    domain = pwa.domain; # Feature 056: Chrome dynamic ID fallback mapping
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
      Version=1.4
      Type=Application
      Name=${app.display_name}
      Comment=${comment}
      Exec=${config.home.profileDirectory}/bin/i3pm launch open ${app.name}
      Icon=${if app ? icon then app.icon else "application-x-executable"}
      Terminal=false
      NoDisplay=false
      Categories=${categories}
      ${lib.optionalString (app ? expected_class) "StartupWMClass=${app.expected_class}"}
      X-Project-Scope=${app.scope}
      ${lib.optionalString (app ? preferred_workspace && app.preferred_workspace != null) "X-Preferred-Workspace=${toString app.preferred_workspace}"}
      X-Multi-Instance=${if app.multi_instance then "true" else "false"}
      X-Fallback-Behavior=${app.fallback_behavior}
      ${lib.optionalString (app ? nix_package) "X-Nix-Package=${app.nix_package}"}
    '';

  # Generate home.file entries for each .desktop file
  # Use completely separate directory outside standard XDG paths
  # so Walker/Elephant only shows our apps (Feature 034)
  desktopFileEntries = builtins.listToAttrs (map (app: {
    name = ".local/share/i3pm-applications/applications/${app.name}.desktop";
    value.text = mkDesktopFile app;
  }) declarativeApplications);

in
{
  home.packages = [ appRegistrySyncTool ];

  # Generate JSON registry from validated application definitions
  home.file = {
    ".local/share/i3pm/registry/base.json".text = builtins.toJSON {
      version = "1.0.0";
      applications = registryData.applications;
    };

    ".local/share/i3pm/registry/declarative-overrides.json".text = builtins.toJSON rawAppRegistryOverlay;

    # Generate PWA registry for sway-test framework (Feature 070)
    ".config/i3/pwa-registry.json".text = builtins.toJSON {
      version = "1.0.0";
      pwas = pwaDefinitions;
    };
  } // desktopFileEntries;  # T040: Generate .desktop files manually

  home.activation.ensureMutableAppRegistry = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    set -euo pipefail

    EFFECTIVE_PATH="$HOME/.config/i3/application-registry.json"
    WORKING_COPY_PATH="$HOME/.config/i3/app-registry-working-copy.json"
    BASE_PATH="$HOME/.local/share/i3pm/registry/base.json"
    DECLARATIVE_OVERLAY_PATH="$HOME/.local/share/i3pm/registry/declarative-overrides.json"
    APP_REGISTRY_SYNC_BIN="${appRegistrySyncTool}/bin/i3pm-app-registry-sync"

    ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/i3" "$HOME/.local/share/i3pm/registry"

    for path in "$EFFECTIVE_PATH" "$WORKING_COPY_PATH"; do
      if [ -L "$path" ]; then
        target="$(${pkgs.coreutils}/bin/readlink -f "$path" || true)"
        case "$target" in
          /nix/store/*)
            ${pkgs.coreutils}/bin/rm -f "$path"
            ;;
        esac
      fi
    done

    if [ ! -e "$WORKING_COPY_PATH" ]; then
      ${pkgs.coreutils}/bin/cp "$DECLARATIVE_OVERLAY_PATH" "$WORKING_COPY_PATH"
    fi

    "$APP_REGISTRY_SYNC_BIN" render-live >/dev/null 2>&1 || true

    if [ ! -e "$EFFECTIVE_PATH" ]; then
      ${pkgs.coreutils}/bin/cp "$BASE_PATH" "$EFFECTIVE_PATH"
    fi

    if [ -e "$WORKING_COPY_PATH" ]; then
      ${pkgs.coreutils}/bin/chmod u+rw "$WORKING_COPY_PATH"
    fi

    if [ -e "$EFFECTIVE_PATH" ]; then
      ${pkgs.coreutils}/bin/chmod u+rw "$EFFECTIVE_PATH"
    fi
  '';
}
