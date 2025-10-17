{ lib, config, activities, mkUUID, ... }:

let
  # Create a desktop folder containment for each activity
  # These are full-screen desktop folder views (not floating widgets)
  # Must be generated as INI config, not via plasma-manager widgets API
  mkActivityContainment = entry:
    let
      activity = activities.${entry.id};
      containmentId = toString (600 + entry.idx);
    in ''
[Containments][${containmentId}]
activityId=${mkUUID entry.id}
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][${containmentId}][General]
url=file://${activity.directory}

'' + lib.optionalString (activity.wallpaper != null) ''
[Containments][${containmentId}][Wallpaper][org.kde.image][General]
Image=${activity.wallpaper}
PreviewImage=${activity.wallpaper}

'';

  activityContainmentsIni =
    lib.concatMapStrings
      mkActivityContainment
      (lib.imap0 (idx: id: { inherit idx id; }) (lib.attrNames activities));

in {
  # Return INI text for desktop folder containments
  iniText = activityContainmentsIni;
}
