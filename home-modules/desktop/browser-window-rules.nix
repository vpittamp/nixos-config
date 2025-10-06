{ lib, config, ... }:

# Browser Window Rules
#
# This module defines window rules for browsers and other applications
# that should be available on all activities.
#
# To add a new browser or application rule:
# 1. Add a new rule section below
# 2. Run: sudo nixos-rebuild switch --flake .#<target>

let
  # All activities UUID (special value meaning "available on all activities")
  allActivitiesUuid = "00000000-0000-0000-0000-000000000000";

in {
  kwinrulesrc = {
    # Firefox - All activities
    # Note: Firefox may create multiple rule entries, hence UUID-based names
    "firefox-1" = {
      Description = "Firefox - All Activities";
      activity = allActivitiesUuid;
      activityrule = 2;  # Force
      clientmachine = "localhost";
      types = 1;  # Normal windows
      wmclass = "firefox";
      wmclassmatch = 1;  # Substring match
    };

    # Chromium - All activities
    "chromium" = {
      Description = "Chromium - All Activities";
      activities = "";  # Empty string also means all activities
      activitiesrule = 2;  # Force
      types = 1;  # Normal windows
      wmclass = "chromium-browser";
      wmclasscomplete = false;
      wmclassmatch = 1;  # Substring match
    };

    # Add more browser/application rules here as needed
    # Example:
    # "brave" = {
    #   Description = "Brave Browser - All Activities";
    #   activity = allActivitiesUuid;
    #   activityrule = 2;
    #   types = 1;
    #   wmclass = "brave-browser";
    #   wmclassmatch = 1;
    # };
  };
}
