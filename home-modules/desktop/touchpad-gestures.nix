{ config, pkgs, lib, ... }:

{
  # Copy touchegg configuration to user directory
  # Using the correct qttools.bin output that contains the qdbus binary
  home.file.".config/touchegg/touchegg.conf".text = ''
    <touchégg>
      <settings>
        <property name="animation_delay">150</property>
        <property name="action_execute_threshold">20</property>
        <property name="color">auto</property>
        <property name="borderColor">auto</property>
      </settings>
      
      <application name="All">
        <!-- 3 finger swipe up: Overview -->
        <gesture type="SWIPE" fingers="3" direction="UP">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut Overview'</command>
          </action>
        </gesture>
        
        <!-- 3 finger swipe down: Show Desktop -->
        <gesture type="SWIPE" fingers="3" direction="DOWN">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut ShowDesktop'</command>
          </action>
        </gesture>
        
        <!-- 3 finger swipe left: Next Desktop -->
        <gesture type="SWIPE" fingers="3" direction="LEFT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.KWin /KWin nextDesktop'</command>
          </action>
        </gesture>
        
        <!-- 3 finger swipe right: Previous Desktop -->
        <gesture type="SWIPE" fingers="3" direction="RIGHT">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.KWin /KWin previousDesktop'</command>
          </action>
        </gesture>
        
        <!-- 4 finger swipe up: Present Windows (All) -->
        <gesture type="SWIPE" fingers="4" direction="UP">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut ExposeAll'</command>
          </action>
        </gesture>
        
        <!-- 4 finger swipe down: Present Windows (Current Desktop) -->
        <gesture type="SWIPE" fingers="4" direction="DOWN">
          <action type="RUN_COMMAND">
            <command>sh -c 'export DISPLAY=:0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; ${pkgs.libsForQt5.qttools.bin}/bin/qdbus org.kde.kglobalaccel /component/kwin invokeShortcut Expose'</command>
          </action>
        </gesture>
        
        <!-- Pinch in/out: Zoom -->
        <gesture type="PINCH" fingers="2" direction="IN">
          <action type="SEND_KEYS">
            <keys>Control+minus</keys>
          </action>
        </gesture>
        
        <gesture type="PINCH" fingers="2" direction="OUT">
          <action type="SEND_KEYS">
            <keys>Control+plus</keys>
          </action>
        </gesture>
      </application>
    </touchégg>
  '';

  # Robust touchegg client service with proper KDE integration
  systemd.user.services.touchegg-client = {
    Unit = {
      Description = "Touchegg gesture client for KDE";
      Documentation = "https://github.com/JoseExposito/touchegg";
      
      # Ensure proper startup order
      After = [ 
        "graphical-session.target" 
        "plasma-kwin_x11.service"  # Wait for KWin to be ready
      ];
      Wants = [ "touchegg.service" ];  # Requires the system daemon
      PartOf = [ "graphical-session.target" ];
      
      # No socket file check needed - touchegg uses abstract socket
    };
    
    Service = {
      Type = "simple";
      
      # Add a delay and check if daemon is ready before starting
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'sleep 2 && until systemctl is-active touchegg.service; do sleep 1; done'";
      ExecStart = "${pkgs.touchegg}/bin/touchegg --client";
      
      # Robust restart policy
      Restart = "always";
      RestartSec = 5;
      StartLimitBurst = 5;
      StartLimitInterval = 30;
      
      # Environment setup
      Environment = [
        "DISPLAY=:0"
        "XDG_RUNTIME_DIR=/run/user/%U"
      ];
      
      # Process management
      KillMode = "process";
      KillSignal = "SIGTERM";
      TimeoutStopSec = 10;
    };
    
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
  
  # Also create XDG autostart entry as a fallback
  # This ensures touchegg starts even if systemd user service fails
  home.file.".config/autostart/touchegg-client.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Touchegg Client
      Comment=Multi-touch gesture client
      Exec=${pkgs.touchegg}/bin/touchegg --client
      Hidden=false
      NoDisplay=true
      X-GNOME-Autostart-enabled=true
      X-KDE-autostart-after=panel
      X-KDE-autostart-phase=2
      StartupNotify=false
      Terminal=false
      Categories=Utility;
    '';
  };
}