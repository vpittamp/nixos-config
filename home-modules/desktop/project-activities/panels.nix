{ lib, activities, mkUUID }:

let
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

[Containments][410][Applets][437]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][410][Applets][437][Configuration][General]
expanding=true

[Containments][410][Applets][436]
immutability=1
plugin=org.kde.plasma.showActivityManager

[Containments][410][Applets][438]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][410][Applets][438][Configuration][General]
expanding=true

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
AppletOrder=411;412;437;436;438;413;414;427;428

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

[Containments][429][Applets][442]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][429][Applets][442][Configuration][General]
expanding=true

[Containments][429][Applets][440]
immutability=1
plugin=org.kde.plasma.showActivityManager

[Containments][429][Applets][443]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][429][Applets][443][Configuration][General]
expanding=true

[Containments][429][General]
AppletOrder=430;442;440;443

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

[Containments][431][Applets][444]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][431][Applets][444][Configuration][General]
expanding=true

[Containments][431][Applets][441]
immutability=1
plugin=org.kde.plasma.showActivityManager

[Containments][431][General]
AppletOrder=430;444;441;445

[Containments][431][Applets][445]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][431][Applets][445][Configuration][General]
expanding=true

'';

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

  screenMappingIni = ''
[ScreenMapping]
itemsOnDisabledScreens=
screenMapping=

'';

in {
  panelIniText = primaryPanelIni + secondaryPanelsIni + activityContainmentsIni + screenMappingIni;
}
