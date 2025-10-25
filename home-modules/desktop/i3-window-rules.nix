{ config, lib, pkgs, ... }:

# Feature 035: Auto-generate i3 window rules from app-registry.nix
#
# This module generates for_window rules for GLOBAL-scoped applications that have
# preferred_workspace assignments. SCOPED applications are managed dynamically
# via the daemon's environment-based filtering.
#
# Rule format: for_window [class="ClassName"] move to workspace number N
#
# Only GLOBAL apps need static rules because:
# - SCOPED apps are managed by daemon via /proc reading
# - GLOBAL apps should land on preferred workspace regardless of active project
# - Removes need for hardcoded window rules in i3 config

let
  # Load registry
  registry = import ./app-registry.nix { inherit config lib pkgs; };

  # Filter for global apps with preferred_workspace
  globalAppsWithWorkspace = lib.filter
    (app: app.scope == "global" && app ? preferred_workspace)
    registry.applications;

  # Generate for_window rule for each app
  generateWindowRule = app:
    ''for_window [class="${app.expected_class}"] move to workspace number ${toString app.preferred_workspace}'';

  # Generate all rules
  windowRules = lib.concatStringsSep "\n" (
    map generateWindowRule globalAppsWithWorkspace
  );

  # Count for debugging
  ruleCount = builtins.length globalAppsWithWorkspace;
in
{
  # Write auto-generated window rules to config file
  home.file.".config/i3/window-rules-generated.conf" = {
    text = ''
      # Auto-generated from app-registry.nix (Feature 035)
      # Generated: ${builtins.toString builtins.currentTime}
      # Rules: ${toString ruleCount} global applications with preferred workspaces
      #
      # DO NOT EDIT - Changes will be overwritten on next rebuild
      # To modify: Edit app-registry.nix and rebuild

      ${windowRules}
    '';

    # Set permissions
    onChange = ''
      echo "i3-window-rules: Generated ${toString ruleCount} window rules for global applications"
    '';
  };

  # Import into i3 config via extraConfig
  # This will be imported by i3wm.nix module
  xsession.windowManager.i3.config.startup = [
    {
      command = "echo 'i3-window-rules: Loaded ${toString ruleCount} auto-generated rules'";
      always = false;
      notification = false;
    }
  ];
}
