{ config, pkgs, lib, ... }:

let
  cfgText = ''
devices: (
  {
    name: "MX Master 3";
    smartshift: {
      on: true;
      threshold: 10;
      default: 0;
    };
    hiresscroll: {
      hires: true;
      invert: false;
      target: false;
    };
    dpi: 1200;
    buttons: (
      # Thumb button (gesture button)
      {
        cid: 0xc3;
        action = {
          type: "Gestures";
          gestures: (
            {
              # No movement - show Overview
              direction: "None";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_W" ];  # Overview
              };
            },
            {
              # Swipe up - Activity Switcher
              direction: "Up";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_Q" ];  # Activity Switcher
              };
            },
            {
              # Swipe down - Show all windows (Present Windows)
              direction: "Down";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_TAB" ];  # Window switcher
              };
            },
            {
              # Swipe left - Previous desktop
              direction: "Left";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_LEFTCTRL" "KEY_LEFT" ];
              };
            },
            {
              # Swipe right - Next desktop
              direction: "Right";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_LEFTCTRL" "KEY_RIGHT" ];
              };
            }
          );
        };
      },
      # Back button
      {
        cid: 0x53;
        action = {
          type: "Keypress";
          keys: [ "KEY_LEFTALT" "KEY_LEFT" ];  # Browser back
        };
      },
      # Forward button
      {
        cid: 0x56;
        action = {
          type: "Keypress";
          keys: [ "KEY_LEFTALT" "KEY_RIGHT" ];  # Browser forward
        };
      }
    );
  }
);
'';

in {
  environment.systemPackages = lib.mkAfter [ pkgs.logiops ];

  environment.etc."logid.cfg" = {
    text = cfgText;
    mode = "0644";
  };

  systemd.services.logiops = {
    description = "Logitech HID++ daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.logiops}/bin/logid";
      ExecReload = "/bin/kill -HUP $MAINPID";
      Restart = "on-failure";
    };
  };
}
