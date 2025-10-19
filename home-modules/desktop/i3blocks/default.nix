# i3blocks Status Command Configuration
# Feature 013: Migrated from polybar to i3bar with i3blocks
{ config, lib, pkgs, ... }:

{
  # Enable i3blocks using home-manager module
  programs.i3blocks = {
    enable = true;

    bars = {
      top = {
        # US2: System information blocks
        cpu = {
          command = "${pkgs.bash}/bin/bash ${./scripts/cpu.sh}";
          interval = 5;
        };

        memory = {
          command = "${pkgs.bash}/bin/bash ${./scripts/memory.sh}";
          interval = 5;
        };

        network = {
          command = "${pkgs.bash}/bin/bash ${./scripts/network.sh}";
          interval = 10;
        };

        # US3: Project indicator (signal-based)
        project = {
          command = "${pkgs.bash}/bin/bash ${./scripts/project.sh}";
          interval = "once";
          signal = 10;
        };

        # DateTime
        datetime = {
          command = "${pkgs.bash}/bin/bash ${./scripts/datetime.sh}";
          interval = 60;
        };
      };
    };
  };
}
