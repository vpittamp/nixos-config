{ config, lib, pkgs, ... }:

{
  # Konsole profiles configuration
  xdg.dataFile = {
    # Supervisor profile for tmux dashboard with smaller font
    "konsole/Supervisor.profile".text = ''
      [Appearance]
      ColorScheme=WhiteOnBlack
      Font=FiraCode Nerd Font,8

      [General]
      Command=${pkgs.bash}/bin/bash -l -c '${pkgs.tmux}/bin/tmux attach -t supervisor-dashboard || /etc/nixos/scripts/tmux-supervisor/tmux-supervisor-enhanced.sh'
      Name=Supervisor
      Parent=FALLBACK/

      [Scrolling]
      ScrollBarPosition=2
      HistoryMode=2
      HistorySize=10000
    '';

    # You can add more profiles here if needed
    # For example, a monitoring-specific profile:
    "konsole/Monitoring.profile".text = ''
      [Appearance]
      ColorScheme=Breeze
      Font=FiraCode Nerd Font,9

      [General]
      Command=${pkgs.bash}/bin/bash -l
      Name=Monitoring
      Parent=FALLBACK/

      [Scrolling]
      ScrollBarPosition=2
      HistoryMode=2
      HistorySize=5000
    '';
  };
}