{ lib, activities, mkUUID }:

let
  # Generate PWA launcher paths
  pwaLaunchers =
    let
      # These are the actual stable IDs from firefoxpwa profile list
      # Retrieved via: firefoxpwa profile list | grep "^- " | awk -F'[()]' '{print $2}'
      claudeId = "01K63FXC9HKD0AS81V3P07NBC1";
      chatgptId = "01K63FXEJ8B7AV6A3CJB7W9DN2";
      geminiId = "01K63FXAWFH80XQX260RP8FPGE";
      githubId = "01K63FX9NK39YJS6DXX4WKBD32";
      gmailId = "01K63FXMC4X923P036TRXDPFJ2";
      argoCDId = "01K63FX8DD5YH7V19VZQ6PNR5F";
      backstageId = "01K63FXHP54ADP56PFRTBHB1VV";
      youtubeId = "01K63FXJYHTC0FYYQ80364P1TE";
    in
      ",applications:FFPWA-${claudeId}.desktop" +
      ",applications:FFPWA-${chatgptId}.desktop" +
      ",applications:FFPWA-${geminiId}.desktop" +
      ",applications:FFPWA-${githubId}.desktop" +
      ",applications:FFPWA-${gmailId}.desktop" +
      ",applications:FFPWA-${argoCDId}.desktop" +
      ",applications:FFPWA-${backstageId}.desktop" +
      ",applications:FFPWA-${youtubeId}.desktop";

  primaryPanelIni = ''
[Containments][410]
activityId=
formfactor=2
immutability=1
lastScreen=0
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
launchers=applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop${pwaLaunchers}
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

  # Monitoring activity panel with system monitoring widgets
  monitoringPanelIni = ''
[Containments][500]
activityId=645bcfb7-e769-4000-93be-ad31eb77ea2e
formfactor=2
immutability=1
lastScreen=0
location=3
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][500][Applets][501]
immutability=1
plugin=org.kde.plasma.systemmonitor.cpu

[Containments][500][Applets][501][Configuration][Appearance]
title=CPU Usage
chartFace=org.kde.ksysguard.barchart

[Containments][500][Applets][501][Configuration][SensorColors]
cpu/all/usage=61,174,233

[Containments][500][Applets][501][Configuration][Sensors]
highPrioritySensorIds=["cpu/all/usage"]
totalSensors=["cpu/all/usage"]

[Containments][500][Applets][502]
immutability=1
plugin=org.kde.plasma.systemmonitor.memory

[Containments][500][Applets][502][Configuration][Appearance]
title=Memory
chartFace=org.kde.ksysguard.piechart

[Containments][500][Applets][502][Configuration][SensorColors]
memory/physical/used=233,120,61
memory/physical/free=61,233,140

[Containments][500][Applets][502][Configuration][Sensors]
highPrioritySensorIds=["memory/physical/used","memory/physical/free"]
totalSensors=["memory/physical/used","memory/physical/free"]

[Containments][500][Applets][503]
immutability=1
plugin=org.kde.plasma.systemmonitor.net

[Containments][500][Applets][503][Configuration][Appearance]
title=Network
chartFace=org.kde.ksysguard.linechart

[Containments][500][Applets][503][Configuration][SensorColors]
network/all/download=61,233,61
network/all/upload=233,61,61

[Containments][500][Applets][503][Configuration][Sensors]
highPrioritySensorIds=["network/all/download","network/all/upload"]

[Containments][500][Applets][504]
immutability=1
plugin=org.kde.plasma.systemmonitor.diskactivity

[Containments][500][Applets][504][Configuration][Appearance]
title=Disk I/O
chartFace=org.kde.ksysguard.linechart

[Containments][500][Applets][504][Configuration][SensorColors]
disk/all/read=61,120,233
disk/all/write=233,174,61

[Containments][500][Applets][504][Configuration][Sensors]
highPrioritySensorIds=["disk/all/read","disk/all/write"]

[Containments][500][Applets][505]
immutability=1
plugin=org.kde.plasma.systemmonitor

[Containments][500][Applets][505][Configuration][Appearance]
title=System Load
chartFace=org.kde.ksysguard.linechart

[Containments][500][Applets][505][Configuration][SensorColors]
cpu/system/loadAverage1=174,61,233
cpu/system/loadAverage5=120,61,233
cpu/system/loadAverage15=61,61,233

[Containments][500][Applets][505][Configuration][Sensors]
highPrioritySensorIds=["cpu/system/loadAverage1","cpu/system/loadAverage5","cpu/system/loadAverage15"]

[Containments][500][Applets][506]
immutability=1
plugin=org.kde.plasma.panelspacer

[Containments][500][Applets][506][Configuration][General]
expanding=false
length=20

[Containments][500][Applets][507]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][500][Applets][507][Configuration][Appearance]
showDate=true

[Containments][500][General]
AppletOrder=501;502;503;504;505;506;507

'';

  secondaryPanelsIni = ''
[Containments][429]
activityId=
formfactor=2
immutability=1
lastScreen=1
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
lastScreen=2
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
