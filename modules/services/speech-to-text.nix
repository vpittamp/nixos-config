# Speech-to-Text Module
# Provides OpenAI Whisper and Nerd Dictation for system-wide speech recognition
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.speech-to-text;

  # Nerd Dictation wrapper script
  nerdDictationWrapper = pkgs.writeScriptBin "nerd-dictation-toggle" ''
    #!${pkgs.bash}/bin/bash

    # Check if nerd-dictation is running
    if pgrep -f "nerd-dictation begin" > /dev/null; then
      # Stop dictation
      nerd-dictation end
      notify-send "Speech to Text" "Dictation stopped" -i microphone-sensitivity-muted
    else
      # Start dictation with Whisper
      nerd-dictation begin \
        --model base.en \
        --continuous \
        --output SIMULATE_INPUT &
      notify-send "Speech to Text" "Dictation started - Speak now!" -i audio-input-microphone
    fi
  '';

  # Setup script for Whisper models
  whisperSetup = pkgs.writeScriptBin "whisper-setup" ''
    #!${pkgs.bash}/bin/bash

    MODEL_DIR="$HOME/.cache/whisper"
    mkdir -p "$MODEL_DIR"

    echo "Setting up Whisper models..."
    echo "Models will be downloaded on first use to: $MODEL_DIR"
    echo ""
    echo "Available models (from smallest to largest):"
    echo "  tiny.en    (39 MB, English-only, fastest)"
    echo "  base.en    (74 MB, English-only, good balance)"
    echo "  small.en   (244 MB, English-only, better accuracy)"
    echo "  medium.en  (769 MB, English-only, high accuracy)"
    echo "  large      (1550 MB, multilingual, best accuracy)"
    echo ""
    echo "To test Whisper:"
    echo "  whisper --model base.en --language en <audio_file>"
    echo ""
    echo "To use with microphone (via nerd-dictation):"
    echo "  Press Super+Alt+D to toggle dictation"
  '';

in
{
  options.services.speech-to-text = {
    enable = mkEnableOption "speech-to-text services with Whisper";

    model = mkOption {
      type = types.str;
      default = "base.en";
      description = "Default Whisper model to use";
    };

    language = mkOption {
      type = types.str;
      default = "en";
      description = "Default language for speech recognition";
    };

    enableGlobalShortcut = mkOption {
      type = types.bool;
      default = true;
      description = "Enable KDE global shortcut for dictation toggle";
    };
  };

  config = mkIf cfg.enable {
    # Install required packages
    environment.systemPackages = with pkgs; [
      # Core STT packages
      openai-whisper
      ffmpeg-full  # Required by Whisper for audio processing

      # Nerd Dictation and dependencies
      (python3.withPackages (ps: with ps; [
        evdev        # For keyboard simulation
        pyxdg        # For XDG compliance
        pulsectl     # For audio control
      ]))
      xdotool      # For input simulation
      wtype        # Wayland input simulation (for KDE Plasma 6)

      # Helper scripts
      nerdDictationWrapper
      whisperSetup

      # Optional GUI tools
      sox          # Sound processing
      pavucontrol  # PulseAudio control for microphone setup
    ];

    # Install nerd-dictation from GitHub (not in nixpkgs yet)
    system.activationScripts.nerdDictation = ''
      NERD_DIR="/opt/nerd-dictation"
      if [ ! -d "$NERD_DIR" ]; then
        echo "Installing nerd-dictation..."
        ${pkgs.git}/bin/git clone https://github.com/ideasman42/nerd-dictation.git "$NERD_DIR" || true
      else
        echo "Updating nerd-dictation..."
        cd "$NERD_DIR" && ${pkgs.git}/bin/git pull || true
      fi

      # Create symlink to system PATH
      ln -sf "$NERD_DIR/nerd-dictation" /usr/local/bin/nerd-dictation 2>/dev/null || true
    '';

    # Create systemd user service for nerd-dictation
    systemd.user.services.nerd-dictation = {
      description = "Nerd Dictation Speech-to-Text Service";
      after = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];

      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo Service ready for activation via shortcut'";
        ExecStop = "/usr/local/bin/nerd-dictation end";
        Restart = "no";
        RemainAfterExit = false;
      };
    };

    # Environment variables
    environment.sessionVariables = {
      WHISPER_MODEL = cfg.model;
      WHISPER_LANGUAGE = cfg.language;
    };
  };
}