{ lib, config, ... }:
# KWin Window Rules Transformer
#
# This module transforms the machine-specific window rules exported by plasma-rc2nix
# to use canonical activity UUIDs and paths defined in project-activities/data.nix.
#
# Problem: plasma-rc2nix exports window rules with system-generated activity UUIDs
# that differ between machines (e.g., 6ed332bc-fa61-5381-511d-4d5ba44a293b).
#
# Solution: This transformer:
# 1. Imports canonical activity definitions from data.nix (single source of truth)
# 2. Imports raw rules from generated/plasma-rc2nix.nix (unchanged by exports)
# 3. Builds UUID and path mappings
# 4. Transforms each rule to use canonical UUIDs and expanded paths
# 5. For PWA rules: Replaces title-based matching with WM class matching
#
# Workflow:
# 1. Edit KDE window rules via GUI
# 2. Run: scripts/plasma-rc2nix.sh > home-modules/desktop/generated/plasma-rc2nix.nix
# 3. Rebuild: sudo nixos-rebuild switch --flake .#<target>
# 4. Rules automatically use canonical UUIDs from data.nix
#
let
  # Import activity definitions (source of truth for UUIDs and paths)
  activityData = import ./project-activities/data.nix { inherit lib config; pkgs = null; };

  # Import PWA definitions (source of truth for PWA → Activity mappings)
  pwaData = import ./pwas/data.nix { inherit lib config; };

  # Import raw generated window rules from plasma-rc2nix
  generatedConfig = import ./generated/plasma-rc2nix.nix;
  rawRules = generatedConfig.programs.plasma.configFile.kwinrulesrc;

  # Build mapping from activity names to their canonical UUIDs
  activityNameToUuid = lib.mapAttrs (name: activity: activity.uuid) activityData.activities;

  # Build mapping from activity UUIDs to their directory paths
  # This handles path expansion (~ to absolute paths)
  activityUuidToPath = lib.mapAttrs'
    (name: activity: lib.nameValuePair activity.uuid activity.directory)
    activityData.activities;

  # Reverse mapping: from directory path to activity UUID
  # Handles both short names (e.g., "nixos") and full paths
  pathToActivityUuid =
    (lib.mapAttrs'
      (name: activity: lib.nameValuePair name activity.uuid)
      activityData.activities)
    // activityUuidToPath;

  # Helper: Extract activity name from window title
  # Looks for patterns like "coordination", "nixos", "stacks", etc.
  extractActivityFromTitle = title:
    let
      lowerTitle = lib.toLower title;
      activityNames = lib.attrNames activityData.activities;
      # Find first matching activity name in title
      matches = builtins.filter
        (name: lib.hasInfix name lowerTitle)
        activityNames;
    in
      if builtins.length matches > 0
      then builtins.head matches
      else null;

  # Helper: Normalize path for comparison
  normalizePath = path:
    let
      homeDir = config.home.homeDirectory;
      # Replace home directory references
      withoutHome = lib.replaceStrings ["/home/vpittamp" homeDir] ["~" "~"] path;
      # Extract base directory name (e.g., "coordination" from "/home/user/coordination")
      baseName = builtins.baseNameOf withoutHome;
    in {
      normalized = withoutHome;
      base = baseName;
    };

  # Helper: Load PWA WM class mappings from runtime file (if exists)
  # This file is generated at activation time by pwas/generator.nix
  pwaRuntimeMappingPath = "${config.home.homeDirectory}/.config/plasma-pwas/pwa-classes.json";

  # Helper: Check if rule appears to be for a PWA
  # PWAs can have wmclass="firefoxpwa" or wmclass="FFPWA" (GUI export) and a title matching a PWA name
  isPWARule = rule:
    let wmclass = rule.wmclass or "";
    in (wmclass == "firefoxpwa" || wmclass == "FFPWA") &&
       (rule.title or "") != "";

  # Helper: Find PWA config by title
  findPWAByTitle = title:
    let
      matchingPWAs = lib.filterAttrs (id: pwa: pwa.name == title) pwaData.pwas;
    in
      if builtins.length (lib.attrNames matchingPWAs) > 0
      then builtins.head (lib.attrValues matchingPWAs)
      else null;

  # Transform a single window rule to use canonical activity UUIDs
  transformRule = ruleName: rule:
    let
      # Check if this is a PWA rule
      isPWA = isPWARule rule;
      pwaConfig = if isPWA then findPWAByTitle (rule.title or "") else null;

      # For PWA rules, get activity from PWA config
      # For other rules, try to determine from title/description
      activityFromTitle = extractActivityFromTitle (rule.title or "");
      activityFromDesc = extractActivityFromTitle (rule.Description or "");
      # Handle PWA config: null activity means "all activities", otherwise use the specified activity
      activityFromPWA = if pwaConfig != null then
                          (if pwaConfig.activity == null then "all-activities"
                           else if activityNameToUuid ? ${pwaConfig.activity} then pwaConfig.activity
                           else null)
                        else null;

      # Check if existing activity is "all activities" (zeros UUID)
      isAllActivities = act: act == "00000000-0000-0000-0000-000000000000";
      existingActivity = rule.activity or rule.activities or null;

      # Get canonical UUID based on activity name
      # Priority: PWA config > title > description > existing (if not "all activities")
      canonicalUuid =
        if activityFromPWA == "all-activities" then
          "00000000-0000-0000-0000-000000000000"
        else if activityFromPWA != null then
          activityNameToUuid.${activityFromPWA}
        else if activityFromTitle != null then
          activityNameToUuid.${activityFromTitle}
        else if activityFromDesc != null then
          activityNameToUuid.${activityFromDesc}
        else if existingActivity != null && !(isAllActivities existingActivity) then
          existingActivity
        else
          null;

      # Transform path in title if it references a home directory
      transformedTitle =
        if rule ? title then
          let
            normalized = normalizePath rule.title;
            # Check if base name matches an activity
            matchingActivity =
              if pathToActivityUuid ? ${normalized.base}
              then activityData.activities.${normalized.base}
              else null;
          in
            if matchingActivity != null
            then matchingActivity.directory
            else rule.title
        else
          rule.title or "";

      # For PWA rules, add note about WM class matching
      pwaNote = if isPWA && pwaConfig != null
                then "\n# NOTE: At runtime, WM class matching will use: FFPWA-{ID}\n# The actual ID is dynamically discovered from desktop files"
                else "";

      baseRule = rule // lib.optionalAttrs (canonicalUuid != null) {
        # Update activity UUID to canonical value
        activity = canonicalUuid;
      } // lib.optionalAttrs (rule ? activities && canonicalUuid != null) {
        # Also update activities field if present
        activities = canonicalUuid;
      } // lib.optionalAttrs (!isPWA) {
        # For non-PWA rules, update title with transformed path
        title = transformedTitle;
      };

      # For PWA rules, remove title matching and use only WM class matching
      pwaRule = if isPWA then
        (builtins.removeAttrs baseRule ["title" "titlematch"]) // {
          # The wmclass will be dynamically updated at activation time
          # Format: FFPWA-{ID} where ID is machine-specific
          wmclass = "FFPWA-PLACEHOLDER-${rule.title or "unknown"}";
          wmclassmatch = 1;  # Exact match
          wmclasscomplete = false;  # Substring match
        }
      else
        baseRule;
    in
      pwaRule;

  # Transform all rules in the General section
  transformedGeneral = rawRules.General or {};

  # Transform all numbered rule sections
  transformedRules = lib.mapAttrs transformRule
    (lib.filterAttrs (name: _: name != "General") rawRules);

in {
  # Export transformed kwinrulesrc configuration
  kwinrulesrc = {
    General = transformedGeneral;
  } // transformedRules;

  # Also export the mappings for debugging/inspection
  debug = {
    inherit activityNameToUuid activityUuidToPath pathToActivityUuid;
    originalRuleCount = builtins.length (lib.attrNames rawRules) - 1;
    transformedRuleCount = builtins.length (lib.attrNames transformedRules);
    pwaCount = builtins.length (lib.attrNames pwaData.pwas);
    pwaNames = lib.attrNames pwaData.pwas;
  };

  # Export PWA data for other modules to use
  inherit pwaData;
}

