{ lib, config, activities, ... }:

let
  # Create a desktop folder widget for each activity
  # These widgets show the activity's directory on the desktop with its wallpaper
  mkActivityDesktopWidget = activityId: activity: {
    name = "org.kde.plasma.folder";
    config = {
      General = {
        url = "file://${activity.directory}";
        # Configure folder widget appearance
        arrangement = 0;  # Rows
        alignToGrid = true;
        locked = true;
        sortMode = 0;  # Sort by name
        sortDesc = false;
        sortDirsFirst = true;
        iconSize = 2;  # Medium icons
        labelWidth = 2;
        positions = "{}";  # Auto-arrange
        popups = true;  # Show folder preview popups
      };
    };
  };

  # Generate desktop widgets for all activities
  activityDesktopWidgets = lib.mapAttrsToList mkActivityDesktopWidget activities;

in
  # Return the list of desktop folder widgets for plasma-manager's desktop.widgets API
  activityDesktopWidgets
