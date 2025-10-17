{ lib, config, ... }:

# Auto-generated PWA Window Rules
#
# This module automatically generates KWin window rules for all PWAs defined in data.nix.
# Rules are generated based on PWA activity assignments:
# - null activity → all activities (00000000-0000-0000-0000-000000000000)
# - specific activity → that activity's UUID
#
# This ensures PWAs automatically open in their designated activities.

let
  # Import PWA definitions (source of truth for PWA → Activity mappings)
  pwaData = import ./data.nix { inherit lib config; };

  # Import activity definitions (source of truth for activity UUIDs)
  activityData = import ../project-activities/data.nix { inherit lib config; pkgs = null; };

  # All activities UUID (special value meaning "available on all activities")
  allActivitiesUuid = "00000000-0000-0000-0000-000000000000";

  # Generate a window rule for a single PWA
  mkPWARule = pwaId: pwa:
    let
      # Determine activity UUID
      activityUuid =
        if pwa.activity == null
        then allActivitiesUuid
        else activityData.activities.${pwa.activity}.uuid;

      # Generate rule name (use pwaId as rule identifier)
      ruleName = "pwa-${pwaId}";

    in {
      ${ruleName} = {
        Description = "${pwa.name} - ${if pwa.activity == null then "All Activities" else activityData.activities.${pwa.activity}.name}";
        activity = activityUuid;
        activityrule = 2;  # Force
        clientmachine = "localhost";
        title = pwa.name;
        titlematch = 1;  # Substring match
        types = 1;  # Normal windows
        # PWAs use either "firefoxpwa" or "FFPWA" as wmclass
        # The actual format is "FFPWA-{ID}" but we use substring matching
        wmclass = "FFPWA";
        wmclasscomplete = false;
        wmclassmatch = 1;  # Substring match
      };
    };

  # Generate rules for all PWAs
  allPWARules = lib.concatMapAttrs mkPWARule pwaData.pwas;

in {
  kwinrulesrc = allPWARules;

  # Debug info
  debug = {
    pwaCount = builtins.length (lib.attrNames pwaData.pwas);
    ruleNames = lib.attrNames allPWARules;
  };
}
