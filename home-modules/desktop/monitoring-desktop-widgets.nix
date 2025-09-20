{ config, lib, pkgs, ... }:

let
  # Script to add monitoring widgets to the Monitoring activity desktop
  setupMonitoringWidgets = pkgs.writeScriptBin "setup-monitoring-widgets" ''
    #!/usr/bin/env bash
    set -euo pipefail

    ACTIVITY_ID="645bcfb7-e769-4000-93be-ad31eb77ea2e"

    echo "Setting up monitoring widgets for activity: Monitoring"

    # Use qdbus to add widgets programmatically when possible
    # This is a placeholder - actual widget placement needs to be done through
    # the KDE UI or by manipulating plasma config files

    cat << 'EOF' > ~/.local/share/kactivitymanagerd/resources/monitoring-widgets.txt
    Monitoring Activity Widget Setup
    =================================

    Please manually add the following widgets to your desktop:

    1. System Monitor - CPU Usage
    2. System Monitor - Memory
    3. System Monitor - Network
    4. System Monitor - Disk Activity
    5. System Monitor - System Load

    Right-click on the desktop and choose "Add Widgets" to add these monitors.

    Arrange them as a dashboard for system monitoring.
    EOF

    echo "Widget setup instructions created in ~/.local/share/kactivitymanagerd/resources/monitoring-widgets.txt"
  '';

in {
  # Add the setup script to user packages
  home.packages = with pkgs; [
    setupMonitoringWidgets
    kdePackages.plasma-systemmonitor
    kdePackages.libksysguard
    kdePackages.ksystemstats
  ];

  # Create a desktop entry for easy access
  xdg.desktopEntries.monitoring-dashboard = {
    name = "Monitoring Dashboard";
    comment = "System resource monitoring dashboard";
    exec = "${pkgs.kdePackages.plasma-systemmonitor}/bin/plasma-systemmonitor";
    icon = "utilities-system-monitor";
    terminal = false;
    categories = [ "System" "Monitor" ];
  };

  # Add plasma-systemmonitor to autostart for the monitoring activity
  # This will open the system monitor app when switching to the activity
  home.file.".config/autostart/monitoring-dashboard.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=System Monitor
      Exec=${pkgs.kdePackages.plasma-systemmonitor}/bin/plasma-systemmonitor
      Icon=utilities-system-monitor
      X-KDE-autostart-condition=kactivitymanagerdrc:main:currentActivity:645bcfb7-e769-4000-93be-ad31eb77ea2e
    '';
  };
}