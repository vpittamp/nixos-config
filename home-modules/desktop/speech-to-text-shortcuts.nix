# KDE Global Shortcuts for Speech-to-Text
# Provides keyboard shortcuts for nerd-dictation toggle
{ config, lib, pkgs, ... }:

{
  programs.plasma.configFile."kglobalshortcutsrc" = {
    # Custom shortcuts for speech-to-text
    "speech-to-text" = {
      "_k_friendly_name" = "Speech to Text";
      "toggle-dictation" = "Ctrl+Space,none,Toggle Speech Dictation";
    };
  };

  # Custom KDE hotkey configuration for the actual command
  programs.plasma.hotkeys.commands."toggle-dictation" = {
    name = "Toggle Speech Dictation";
    key = "Ctrl+Space";
    comment = "Start/stop speech-to-text keyboard dictation";
    command = "${pkgs.bash}/bin/bash -c 'export PYTHONPATH=/var/lib/vosk-python:$PYTHONPATH; export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH; /run/current-system/sw/bin/nerd-dictation-toggle'";
  };
}
