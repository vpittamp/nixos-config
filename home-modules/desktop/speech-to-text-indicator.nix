# KDE Plasma Widget for Speech-to-Text Status Indicator
# Shows visual indicator in system tray when dictation is active
{ config, lib, pkgs, ... }:

let
  # Package the plasmoid widget
  speechIndicatorWidget = pkgs.stdenv.mkDerivation {
    pname = "plasma-speech-to-text-indicator";
    version = "1.0";

    src = ../../assets/plasma-widgets/speech-to-text-indicator;

    installPhase = ''
      mkdir -p $out/share/plasma/plasmoids/org.nixos.speechToTextIndicator
      cp -r $src/* $out/share/plasma/plasmoids/org.nixos.speechToTextIndicator/
    '';

    meta = {
      description = "KDE Plasma widget showing speech-to-text dictation status";
    };
  };
in
{
  # Install the widget package
  home.packages = [ speechIndicatorWidget ];

  # Configure KDE Plasma to add widget to system tray
  programs.plasma = {
    # Add widget to panel
    panels = [
      {
        location = "top";
        widgets = [
          # Existing widgets...
          {
            name = "org.nixos.speechToTextIndicator";
            config = {
              General = {
                showBackground = false;
              };
            };
          }
        ];
      }
    ];
  };
}
