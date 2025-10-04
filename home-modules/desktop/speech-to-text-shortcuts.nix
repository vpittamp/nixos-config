# KDE Global Shortcuts for Speech-to-Text
# Provides keyboard shortcuts for nerd-dictation toggle
{ config, lib, pkgs, ... }:

let
  # Wrapper script that sets up environment and calls nerd-dictation-toggle
  toggleWrapper = pkgs.writeScriptBin "nerd-dictation-toggle-kde" ''
    #!${pkgs.bash}/bin/bash
    export PYTHONPATH=/var/lib/vosk-python:$PYTHONPATH
    export LD_LIBRARY_PATH=${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH
    exec /run/current-system/sw/bin/nerd-dictation-toggle
  '';
in
{
  # Add wrapper to user packages
  home.packages = [ toggleWrapper ];

  programs.plasma.configFile."kglobalshortcutsrc" = {
    # Custom shortcuts for speech-to-text
    "speech-to-text" = {
      "_k_friendly_name" = "Speech to Text";
      "toggle-dictation" = "Meta+Shift+Space,none,Toggle Speech Dictation";
    };
  };

  # Custom KDE hotkey commands (visible in KRunner)
  programs.plasma.hotkeys.commands = {
    "toggle-speech-dictation" = {
      name = "Toggle Speech Dictation";
      key = "Meta+Shift+Space";
      comment = "Start/stop speech-to-text keyboard dictation with VOSK";
      command = "${toggleWrapper}/bin/nerd-dictation-toggle-kde";
    };
    "speech-to-clipboard" = {
      name = "Speech to Clipboard";
      key = "Meta+Alt+C";
      comment = "Record 10 seconds of audio and transcribe to clipboard with Whisper";
      command = "${pkgs.writeShellScript "whisper-clipboard" ''
        AUDIO_FILE="/tmp/whisper-recording.wav"
        # Record 10 seconds of audio
        ${pkgs.sox}/bin/rec -c 1 -r 16000 "$AUDIO_FILE" trim 0 10
        # Transcribe with Whisper
        TEXT=$(${pkgs.openai-whisper}/bin/whisper "$AUDIO_FILE" --model base.en --output_format txt --output_dir /tmp 2>/dev/null | tail -1)
        # Copy to clipboard
        echo "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
        ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Text copied to clipboard" -i edit-copy
        rm -f "$AUDIO_FILE"
      ''}";
    };
  };

  # Create visible desktop entries for KRunner
  xdg.desktopEntries = {
    "toggle-speech-dictation" = {
      name = "Toggle Speech Dictation";
      comment = "Start/stop speech-to-text keyboard dictation";
      icon = "audio-input-microphone";
      exec = "${toggleWrapper}/bin/nerd-dictation-toggle-kde";
      categories = [ "Utility" "Accessibility" ];
      terminal = false;
    };
    "speech-to-clipboard" = {
      name = "Speech to Clipboard";
      comment = "Record audio and transcribe to clipboard";
      icon = "edit-copy";
      exec = "${pkgs.writeShellScript "whisper-clipboard" ''
        AUDIO_FILE="/tmp/whisper-recording.wav"
        ${pkgs.sox}/bin/rec -c 1 -r 16000 "$AUDIO_FILE" trim 0 10
        TEXT=$(${pkgs.openai-whisper}/bin/whisper "$AUDIO_FILE" --model base.en --output_format txt --output_dir /tmp 2>/dev/null | tail -1)
        echo "$TEXT" | ${pkgs.wl-clipboard}/bin/wl-copy
        ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Text copied to clipboard" -i edit-copy
        rm -f "$AUDIO_FILE"
      ''}";
      categories = [ "Utility" "Accessibility" ];
      terminal = false;
    };
  };
}
