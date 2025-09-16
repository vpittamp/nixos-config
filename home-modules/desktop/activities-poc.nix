{ config, lib, pkgs, ... }:

let
  activities = {
    nixos = {
      name = "NixOS";
      path = "/etc/nixos";
      wallpaper = null;
    };
    stacks = {
      name = "Stacks";
      path = "~/stacks";
      wallpaper = null;
    };
  };

  mkUUID = name: let
    hash = builtins.hashString "sha256" name;
  in "${builtins.substring 0 8 hash}-${builtins.substring 8 4 hash}-${builtins.substring 12 4 hash}-${builtins.substring 16 4 hash}-${builtins.substring 20 12 hash}";

  primaryPanelIni = ''
[Containments][410]
activityId=
formfactor=2
immutability=1
lastScreen[$i]=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][410][Applets][411]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][410][Applets][411][Configuration][General]
favoritesPortedToKAstats=true

[Containments][410][Applets][412]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][410][Applets][412][Configuration][General]
showOnlyCurrentActivity=true
showOnlyCurrentDesktop=false
showOnlyCurrentScreen=true

[Containments][410][Applets][413]
immutability=1
plugin=org.kde.plasma.marginsseparator

[Containments][410][Applets][414]
activityId=
formfactor=0
immutability=1
lastScreen=-1
location=0
plugin=org.kde.plasma.systemtray
wallpaperplugin=org.kde.image

[Containments][410][Applets][414][Applets][415]
immutability=1
plugin=org.kde.plasma.notifications

[Containments][410][Applets][414][Applets][416]
immutability=1
plugin=org.kde.plasma.manage-inputmethod

[Containments][410][Applets][414][Applets][417]
immutability=1
plugin=org.kde.plasma.devicenotifier

[Containments][410][Applets][414][Applets][418]
immutability=1
plugin=org.kde.plasma.clipboard

[Containments][410][Applets][414][Applets][419]
immutability=1
plugin=org.kde.plasma.cameraindicator

[Containments][410][Applets][414][Applets][420]
immutability=1
plugin=org.kde.plasma.printmanager

[Containments][410][Applets][414][Applets][421]
immutability=1
plugin=org.kde.plasma.keyboardindicator

[Containments][410][Applets][414][Applets][422]
immutability=1
plugin=org.kde.plasma.keyboardlayout

[Containments][410][Applets][414][Applets][423]
immutability=1
plugin=org.kde.plasma.weather

[Containments][410][Applets][414][Applets][424]
immutability=1
plugin=org.kde.kdeconnect

[Containments][410][Applets][414][Applets][425]
immutability=1
plugin=org.kde.plasma.volume

[Containments][410][Applets][414][Applets][425][Configuration][General]
migrated=true

[Containments][410][Applets][414][Applets][426]
immutability=1
plugin=org.kde.kscreen

[Containments][410][Applets][414][Applets][433]
immutability=1
plugin=org.kde.plasma.mediacontroller

[Containments][410][Applets][414][Applets][434]
immutability=1
plugin=org.kde.plasma.battery

[Containments][410][Applets][414][Applets][435]
immutability=1
plugin=org.kde.plasma.brightness

[Containments][410][Applets][414][General]
extraItems=org.kde.plasma.notifications,org.kde.plasma.manage-inputmethod,org.kde.plasma.devicenotifier,org.kde.plasma.clipboard,org.kde.plasma.cameraindicator,org.kde.plasma.printmanager,org.kde.plasma.battery,org.kde.plasma.keyboardindicator,org.kde.plasma.brightness,org.kde.plasma.keyboardlayout,org.kde.plasma.weather,org.kde.kdeconnect,org.kde.plasma.bluetooth,org.kde.plasma.mediacontroller,org.kde.plasma.volume,org.kde.kscreen
knownItems=org.kde.plasma.notifications,org.kde.plasma.manage-inputmethod,org.kde.plasma.devicenotifier,org.kde.plasma.clipboard,org.kde.plasma.cameraindicator,org.kde.plasma.printmanager,org.kde.plasma.battery,org.kde.plasma.keyboardindicator,org.kde.plasma.brightness,org.kde.plasma.keyboardlayout,org.kde.plasma.weather,org.kde.kdeconnect,org.kde.plasma.bluetooth,org.kde.plasma.mediacontroller,org.kde.plasma.volume,org.kde.kscreen

[Containments][410][Applets][427]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][410][Applets][427][Configuration][Appearance]
fontWeight=400

[Containments][410][Applets][428]
immutability=1
plugin=org.kde.plasma.showdesktop

[Containments][410][General]
AppletOrder=411;412;413;414;427;428

'';

  secondaryPanelsIni = ''
[Containments][429]
activityId=
formfactor=2
immutability=1
lastScreen[$i]=1
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][429][Applets][430]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][429][Applets][430][Configuration][General]
launchers=
showOnlyCurrentActivity=true
showOnlyCurrentDesktop=false
showOnlyCurrentScreen=true

[Containments][429][General]
AppletOrder=430

[Containments][431]
activityId=
formfactor=2
immutability=1
lastScreen[$i]=2
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][431][Applets][430]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][431][Applets][430][Configuration][General]
launchers=
showOnlyCurrentActivity=true
showOnlyCurrentDesktop=false
showOnlyCurrentScreen=true

[Containments][431][General]
AppletOrder=430

'';

  mkActivityContainment = entry:
    let
      activity = activities.${entry.id};
      containmentId = toString (600 + entry.idx);
      uuid = mkUUID entry.id;
    in ''
[Containments][${containmentId}]
activityId=${uuid}
formfactor=0
immutability=1
lastScreen=0
location=0
plugin=org.kde.plasma.folder
wallpaperplugin=org.kde.image

[Containments][${containmentId}][General]
url=file://${activity.path}

'' + lib.optionalString (activity.wallpaper != null) ''
[Containments][${containmentId}][Wallpaper][org.kde.image][General]
Image=${activity.wallpaper}
PreviewImage=${activity.wallpaper}

'';

  activityContainmentsIni =
    lib.concatMapStrings
      mkActivityContainment
      (lib.imap0 (idx: id: { inherit idx id; }) (lib.attrNames activities));

  screenMappingIni = ''
[ScreenMapping]
itemsOnDisabledScreens=
screenMapping=desktop:/chrome-agimnkijcaahngcdmfeangaknmldooml-Default.desktop,0,${mkUUID "nixos"},desktop:/chrome-ejjefgjnimbklpdgenehmplpccdknekl-Default.desktop,0,${mkUUID "nixos"}

'';

  panelIniText = primaryPanelIni + secondaryPanelsIni + activityContainmentsIni + screenMappingIni;

  ensureActivities = pkgs.writeShellScript "ensure-activities" ''
    #!/usr/bin/env bash

    while ! ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.ActivityManager &>/dev/null; do
      sleep 1
    done

    ${lib.concatStringsSep "
" (lib.mapAttrsToList (id: activity: ''
      uuid="${mkUUID id}"
      name="${activity.name}"

      if ! ${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.ActivityManager /ActivityManager/Activities ActivityName "$uuid" &>/dev/null; then
        echo "Creating activity: $name ($uuid)"
        mkdir -p ~/.config
        cat >> ~/.config/kactivitymanagerdrc <<EOF

[$uuid]
Name=$name
EOF
      fi
    '') activities)}

    ${pkgs.kdePackages.kactivitymanagerd}/bin/kactivitymanagerd --replace &
  '';

in {
  programs.plasma.configFile."kactivitymanagerdrc" = {
    activities = lib.mapAttrs' (id: activity: lib.nameValuePair (mkUUID id) activity.name) activities;
    main.currentActivity = lib.mkForce (mkUUID "nixos");
  };

  programs.plasma.resetFilesExclude = lib.mkBefore [ "plasma-org.kde.plasma.desktop-appletsrc" ];

  home.file.".config/plasma-org.kde.plasma.desktop-appletsrc" = {
    force = true;
    text = panelIniText;
  };

  programs.bash.shellAliases = lib.mapAttrs (id: _: "${pkgs.libsForQt5.qttools}/bin/qdbus org.kde.ActivityManager /ActivityManager/Activities SetCurrentActivity ${mkUUID id}") activities;
}
