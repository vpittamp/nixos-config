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
      {
        cid: 0xc3;
        action = {
          type: "Gestures";
          gestures: (
            {
              direction: "None";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" ];
              };
            },
            {
              direction: "Up";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_Q" ];
              };
            },
            {
              direction: "Down";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_TAB" ];
              };
            },
            {
              direction: "Left";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_LEFTCTRL" "KEY_LEFT" ];
              };
            },
            {
              direction: "Right";
              mode: "OnRelease";
              action = {
                type: "Keypress";
                keys: [ "KEY_LEFTMETA" "KEY_LEFTCTRL" "KEY_RIGHT" ];
              };
            }
          );
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
