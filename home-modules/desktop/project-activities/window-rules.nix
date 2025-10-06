{ lib, config, activities, ... }:

# Improved Window Rules Generator
#
# Problem: VS Code and other apps show folder basename in title (e.g., "nixos")
# not full path (e.g., "/etc/nixos"), causing window rules to fail.
#
# Solution: Generate rules based on folder basename that apps actually show
# in their window titles, not the full directory path.

let
  # Extract folder basename for matching
  getFolderBasename = path:
    builtins.baseNameOf (lib.removeSuffix "/" path);

  # Get directory for an activity with expanded paths
  getActivityDirectory = activity:
    let
      dir = activity.directory;
      homeDir = config.home.homeDirectory;
    in
      if lib.hasPrefix "~/" dir
      then lib.replaceStrings ["~/"] ["${homeDir}/"] dir
      else dir;

  # Generate window rules for VS Code
  mkVSCodeRules = activityId: activity:
    let
      basename = getFolderBasename (getActivityDirectory activity);
      fullPath = getActivityDirectory activity;
    in {
      "vscode-${activityId}" = {
        Description = "VS Code - ${activity.name}";
        wmclass = "code";
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        # Match either the basename OR the full path in title
        title = basename;
        titlematch = 1;  # Substring match
        activity = activity.uuid;
        activityrule = 2;  # Force
        types = 1;  # Normal windows
        clientmachine = "localhost";
      };
    };

  # Generate window rules for Konsole
  mkKonsoleRules = activityId: activity:
    let
      basename = getFolderBasename (getActivityDirectory activity);
      fullPath = getActivityDirectory activity;
    in {
      "konsole-${activityId}" = {
        Description = "Konsole - ${activity.name}";
        wmclass = "konsole";
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        # Konsole shows path in title, match basename
        title = basename;
        titlematch = 1;  # Substring match
        activity = activity.uuid;
        activityrule = 2;  # Force
        types = 1;  # Normal windows
        clientmachine = "localhost";
      };
    };

  # Generate window rules for Dolphin
  mkDolphinRules = activityId: activity:
    let
      basename = getFolderBasename (getActivityDirectory activity);
      fullPath = getActivityDirectory activity;
    in {
      "dolphin-${activityId}" = {
        Description = "Dolphin - ${activity.name}";
        wmclass = "dolphin";
        wmclassmatch = 1;  # Substring match
        wmclasscomplete = false;
        # Dolphin shows full path, but also match basename for safety
        title = basename;
        titlematch = 1;  # Substring match
        activity = activity.uuid;
        activityrule = 2;  # Force
        types = 1;  # Normal windows
        clientmachine = "localhost";
      };
    };

  # Generate all rules for all activities
  allActivityRules = lib.concatMapAttrs
    (activityId: activity:
      (mkVSCodeRules activityId activity) //
      (mkKonsoleRules activityId activity) //
      (mkDolphinRules activityId activity)
    )
    activities;

  # Count rules for General section
  ruleNames = lib.attrNames allActivityRules;
  ruleCount = builtins.length ruleNames;

in {
  # Export kwinrulesrc configuration
  kwinrulesrc = {
    General = {
      count = ruleCount;
      rules = lib.concatStringsSep "," ruleNames;
    };
  } // allActivityRules;

  # Debug info
  debug = {
    inherit ruleCount ruleNames;
    activityBasenames = lib.mapAttrs
      (id: activity: getFolderBasename (getActivityDirectory activity))
      activities;
  };
}
