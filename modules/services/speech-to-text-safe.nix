# Speech-to-Text Module (Safe Version)
# Provides OpenAI Whisper and tools for speech recognition
# Removed problematic network operations and flatpak dependencies
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.speech-to-text;

  # VOSK model path (to be downloaded manually)
  voskModelPath = "/var/cache/vosk/model";

  # Note: nerd-dictation will be installed manually after build
  # to avoid network dependencies during build

  # Toggle script for nerd-dictation
  nerdDictationToggle = pkgs.writeScriptBin "nerd-dictation-toggle" ''
    #!${pkgs.bash}/bin/bash

    # Check if VOSK model is installed
    if [ ! -d "${voskModelPath}" ]; then
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "VOSK model not found! Run: speech-model-setup" -i dialog-error
      echo "Error: VOSK model not found at ${voskModelPath}"
      echo "Please run: speech-model-setup"
      exit 1
    fi

    # Check if nerd-dictation is installed
    if ! command -v nerd-dictation &> /dev/null; then
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "nerd-dictation not found! Run: speech-model-setup for instructions" -i dialog-error
      echo "Error: nerd-dictation not found"
      echo "Please install it manually after running: speech-model-setup"
      exit 1
    fi

    # Check if nerd-dictation is running
    if pgrep -f "nerd-dictation begin" > /dev/null; then
      # Stop dictation
      nerd-dictation end
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Dictation stopped" -i microphone-sensitivity-muted
    else
      # Start dictation with VOSK model
      nerd-dictation begin \
        --vosk-model-dir "${voskModelPath}" \
        --continuous \
        --output SIMULATE_INPUT &
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Dictation started - Speak now!" -i audio-input-microphone
    fi
  '';

  # Model setup script for manual downloads
  modelSetup = pkgs.writeScriptBin "speech-model-setup" ''
    #!${pkgs.bash}/bin/bash

    echo "Speech Recognition Model Setup"
    echo "=============================="
    echo ""
    echo "This script helps you download speech recognition models."
    echo ""

    # VOSK model setup
    echo "1. VOSK Model (for offline dictation)"
    echo "   Download location: ${voskModelPath}"
    echo ""

    if [ ! -d "${voskModelPath}" ]; then
      echo "   Status: NOT INSTALLED"
      echo ""
      echo "   To install VOSK model (40MB):"
      echo "   sudo mkdir -p /var/cache/vosk"
      echo "   cd /var/cache/vosk"
      echo "   sudo wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
      echo "   sudo unzip vosk-model-small-en-us-0.15.zip"
      echo "   sudo mv vosk-model-small-en-us-0.15 model"
      echo "   sudo rm vosk-model-small-en-us-0.15.zip"
    else
      echo "   Status: INSTALLED ✓"
    fi

    echo ""
    echo "2. Whisper Models (for file transcription)"
    echo "   Download location: ~/.cache/whisper/"
    echo ""
    echo "   Whisper models are downloaded automatically on first use."
    echo "   Available models:"
    echo "     - tiny.en    (39 MB)  - whisper audio.mp3 --model tiny.en"
    echo "     - base.en    (74 MB)  - whisper audio.mp3 --model base.en"
    echo "     - small.en   (244 MB) - whisper audio.mp3 --model small.en"
    echo "     - medium.en  (769 MB) - whisper audio.mp3 --model medium.en"
    echo "     - large      (1.5 GB) - whisper audio.mp3 --model large"
    echo ""
    echo "   To pre-download a model, run:"
    echo "   whisper --model base.en --language en /dev/null 2>/dev/null"
    echo ""
    echo "3. Nerd Dictation (for keyboard input)"
    echo ""
    if ! command -v nerd-dictation &> /dev/null; then
      echo "   Status: NOT INSTALLED"
      echo ""
      echo "   To install nerd-dictation:"
      echo "   git clone https://github.com/ideasman42/nerd-dictation.git"
      echo "   cd nerd-dictation"
      echo "   sudo cp nerd-dictation /usr/local/bin/"
      echo "   sudo chmod +x /usr/local/bin/nerd-dictation"
    else
      echo "   Status: INSTALLED ✓"
    fi
    echo ""

    # Check if user wants to download VOSK now
    if [ ! -d "${voskModelPath}" ]; then
      read -p "Download VOSK model now? (y/n) " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Downloading VOSK model..."
        sudo mkdir -p /var/cache/vosk
        cd /var/cache/vosk
        sudo wget https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
        sudo unzip vosk-model-small-en-us-0.15.zip
        sudo mv vosk-model-small-en-us-0.15 model
        sudo rm vosk-model-small-en-us-0.15.zip
        echo "VOSK model installed successfully!"
      fi
    fi
  '';

  # Whisper helper script
  whisperHelper = pkgs.writeScriptBin "whisper-helper" ''
    #!${pkgs.bash}/bin/bash

    MODEL_DIR="$HOME/.cache/whisper"
    mkdir -p "$MODEL_DIR"

    echo "OpenAI Whisper Speech Recognition"
    echo "================================="
    echo ""
    echo "Models will be downloaded automatically to: $MODEL_DIR"
    echo ""
    echo "Available models:"
    echo "  tiny.en    (39 MB)  - Fastest, English-only"
    echo "  base.en    (74 MB)  - Good balance"
    echo "  small.en   (244 MB) - Better accuracy"
    echo "  medium.en  (769 MB) - High accuracy"
    echo "  large      (1.5 GB) - Best accuracy, multilingual"
    echo ""
    echo "Usage examples:"
    echo "  whisper audio.mp3 --model base.en --language en"
    echo "  whisper recording.wav --model small.en --output_format txt"
    echo ""
    echo "To use with microphone:"
    echo "  Press Super+Alt+D to toggle dictation (using nerd-dictation)"
  '';

  # Simple speech recognition script using whisper
  whisperLive = pkgs.writeScriptBin "whisper-live" ''
    #!${pkgs.bash}/bin/bash

    # Record audio from microphone and transcribe with Whisper
    TEMP_FILE=$(mktemp --suffix=.wav)

    echo "Recording... Press Ctrl+C to stop"
    ${pkgs.sox}/bin/rec -c 1 -r 16000 "$TEMP_FILE" 2>/dev/null

    echo "Transcribing..."
    ${pkgs.openai-whisper}/bin/whisper "$TEMP_FILE" \
      --model ${cfg.model} \
      --language ${cfg.language} \
      --output_format txt

    # Display result
    cat "$(basename "$TEMP_FILE" .wav).txt" 2>/dev/null

    # Cleanup
    rm -f "$TEMP_FILE" "$(basename "$TEMP_FILE" .wav)".*
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
      ffmpeg-full  # Required by Whisper

      # Python packages for speech processing
      (python3.withPackages (ps: with ps; [
        # vosk  # Not in nixpkgs - will be installed manually
        pyaudio
        soundfile
        numpy
        # torch and torchaudio are large - install manually if needed
        # torch
        # torchaudio
      ]))

      # Input simulation
      xdotool      # X11 input simulation
      wtype        # Wayland input simulation

      # Audio tools
      sox          # Recording and playback
      pavucontrol  # Audio control GUI
      pulseaudioFull

      # Notifications
      libnotify

      # Helper scripts
      nerdDictationToggle
      whisperHelper
      whisperLive
      modelSetup  # Manual model download helper
    ];

    # Create directory for models
    systemd.tmpfiles.rules = [
      "d /var/cache/whisper 0755 root root -"
      "d /var/cache/vosk 0755 root root -"
    ];

    # No systemd services - everything is manual to avoid activation issues
    # The nerd-dictation-toggle script handles starting/stopping

    # Environment variables
    environment.sessionVariables = {
      WHISPER_MODEL = cfg.model;
      WHISPER_LANGUAGE = cfg.language;
      VOSK_MODEL_PATH = "${voskModelPath}";
    };

    # Note: KDE shortcuts can be configured manually via System Settings
    # or by adding to home-manager configuration separately
  };
}