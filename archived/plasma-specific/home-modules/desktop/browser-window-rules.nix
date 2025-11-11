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

    # GitKraken - All activities
    "gitkraken" = {
      Description = "GitKraken - All Activities";
      activity = allActivitiesUuid;
      activityrule = 2;  # Force
      types = 1;  # Normal windows
      wmclass = "gitkraken";
      wmclasscomplete = false;
      wmclassmatch = 1;  # Substring match
    };

    # K9s - All activities
    # K9s launches via custom desktop file with title "K9s"
    # Match on Konsole + title to group as standalone app
    # Force custom icon to show in taskbar
    "k9s" = {
      Description = "K9s - All Activities";
      activity = allActivitiesUuid;
      activityrule = 2;  # Force
      types = 1;  # Normal windows
      wmclass = "konsole";
      wmclasscomplete = false;
      wmclassmatch = 1;  # Substring match
      title = "K9s";
      titlematch = 2;  # Exact match
      icon = "/etc/nixos/assets/icons/k9s.png";
      iconrule = 2;  # Force
    };

    # Headlamp - All activities
    "headlamp" = {
      Description = "Headlamp - All Activities";
      activity = allActivitiesUuid;
      activityrule = 2;  # Force
      types = 1;  # Normal windows
      wmclass = "Headlamp";  # Note: Capitalized window class
      wmclasscomplete = false;
      wmclassmatch = 1;  # Substring match
    };
  };
}
