# Speech-to-Text Module (Safe Version)
# Provides OpenAI Whisper and tools for speech recognition
# Removed problematic network operations and flatpak dependencies
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.speech-to-text;

  # Default KDE accelerator for toggling dictation
  defaultShortcut = "Meta+Alt+D";
  shortcutBinding = cfg.globalShortcut or defaultShortcut;

  # High-accuracy VOSK English model packaged via Nix (available for opt-in use)
  bundledVoskModel = pkgs.callPackage ../../pkgs/vosk-model-en-us-0.22-lgraph.nix {};

  defaultVoskModelPath = "/var/cache/vosk/model";

  effectiveVoskModelPath =
    if cfg.voskModelPath != null then cfg.voskModelPath else
    (if cfg.voskModelPackage != null then "${cfg.voskModelPackage}" else defaultVoskModelPath);

  # Package nerd-dictation from separate file (properly packaged from GitHub)
  nerdDictation = pkgs.callPackage ../../pkgs/nerd-dictation.nix {};

  # System tray indicator for speech-to-text status
  speechIndicator = pkgs.callPackage ../../pkgs/speech-to-text-indicator.nix {};

  # Toggle script for nerd-dictation (updated 2025-10-04 with timeout fix)
  # Note: PYTHONPATH and LD_LIBRARY_PATH are now set in the nerd-dictation package wrapper
  nerdDictationToggle = pkgs.writeScriptBin "nerd-dictation-toggle" ''
    #!${pkgs.bash}/bin/bash
    # Version: 2.0 - Fixed toggle detection and added timeout

    # Check if VOSK model is installed
    if [ ! -d "${effectiveVoskModelPath}" ]; then
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "VOSK model not found! Check services.speech-to-text settings" -i dialog-error
      echo "Error: VOSK model not found at ${effectiveVoskModelPath}"
      echo "Please adjust services.speech-to-text.voskModelPath or run: speech-model-setup"
      exit 1
    fi

    # Use the properly packaged nerd-dictation from Nix store
    NERD_DICTATION="${nerdDictation}/bin/nerd-dictation"

    # Check if nerd-dictation is running (match the wrapped process)
    if pgrep -f "\.nerd-dictation-wrapped begin" > /dev/null; then
      # Stop dictation (run with timeout to avoid indefinite hanging)
      ${pkgs.coreutils}/bin/timeout 10 "$NERD_DICTATION" end > /dev/null 2>&1 || true
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Dictation stopped" -i microphone-sensitivity-muted
    else
      # Start dictation with VOSK model (run in background)
      "$NERD_DICTATION" begin \
        --vosk-model-dir "${effectiveVoskModelPath}" \
        --continuous \
        --output SIMULATE_INPUT > /dev/null 2>&1 &
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
    echo "   Active model path: ${effectiveVoskModelPath}"
    echo ""

    if [ -d "${effectiveVoskModelPath}" ]; then
      echo "   Status: INSTALLED ✓"
      ${if cfg.voskModelPath != null then ''
        echo "   Source: ${cfg.voskModelPath}"
      '' else if cfg.voskModelPackage != null then ''
        echo "   Source: Bundled high-accuracy English model (vosk-model-en-us-0.22-lgraph)"
      '' else ''
        echo "   Source: Custom provisioning"
      ''}
    else
      echo "   Status: NOT FOUND"
      echo ""
      ${if cfg.voskModelPath != null then ''
        echo "   Populate ${cfg.voskModelPath} with a compatible VOSK model directory."
        ${optionalString (cfg.voskModelPackage != null) ''
        echo "   To copy the bundled model offline, run:"
        echo "     sudo mkdir -p ${cfg.voskModelPath}"
        echo "     sudo cp -a ${cfg.voskModelPackage}/. ${cfg.voskModelPath}/"
        ''}
      '' else if cfg.voskModelPackage != null then ''
        echo "   Bundled model missing from the Nix store. Rebuild with network access or switch to a local path."
      '' else ''
        echo "   Provide a model directory via services.speech-to-text.voskModelPath."
      ''}
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

    # Provide guidance if the VOSK model is still missing
    if [ ! -d "${effectiveVoskModelPath}" ]; then
      ${optionalString (cfg.voskModelPath != null && cfg.voskModelPackage != null) ''
      echo "Tip: you can copy the bundled model into ${cfg.voskModelPath} with:"
      echo "  sudo mkdir -p ${cfg.voskModelPath}"
      echo "  sudo cp -a ${cfg.voskModelPackage}/. ${cfg.voskModelPath}/"
      ''}
      echo ""
      echo "For other languages or updates, download a VOSK archive manually and extract it"
      echo "into the configured directory, then rerun this script to verify installation."
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
    echo "  Press ${shortcutBinding} to toggle dictation (using nerd-dictation)"
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

    globalShortcut = mkOption {
      type = types.str;
      default = defaultShortcut;
      example = "Meta+Alt+D";
      description = ''Default KDE shortcut to launch the dictation toggle script. Set alongside enableGlobalShortcut.'';
    };

    voskModelPackage = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = literalExpression "pkgs.callPackage ../../pkgs/vosk-model-en-us-0.22-lgraph.nix {}";
      description = ''Optional Nix-packaged VOSK model. Set this to pkgs.callPackage ../../pkgs/vosk-model-en-us-0.22-lgraph.nix {} to use the bundled high-accuracy English model without hitting the network at runtime.'';
    };

    voskModelPath = mkOption {
      type = types.nullOr types.str;
      default = defaultVoskModelPath;
      example = "/var/cache/vosk/model";
      description = "Filesystem directory containing a VOSK model. Leave at the default when staging models outside the Nix store. Set to null to rely solely on voskModelPackage.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.voskModelPath != null || cfg.voskModelPackage != null;
        message = "services.speech-to-text requires either voskModelPath or voskModelPackage to be set.";
      }
    ];

    # Install required packages
    environment.systemPackages = with pkgs; [
      # Core STT packages
      openai-whisper
      ffmpeg-full  # Required by Whisper

      # Python packages for speech processing
      (python3.withPackages (ps: with ps; [
        pyaudio
        soundfile
        numpy
        cffi
        requests
        tqdm
        srt
        websockets
        pip
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

      # Nerd-dictation and helper scripts
      whisperHelper
      whisperLive
      modelSetup  # Manual model download helper
    ] ++ [
      # Custom packages defined in let block
      nerdDictation  # Properly packaged from GitHub
      nerdDictationToggle
      speechIndicator  # System tray status indicator
    ] ++ (optional (cfg.voskModelPackage != null) cfg.voskModelPackage);

    # Create directory for models
    systemd.tmpfiles.rules = [
      "d /var/cache/whisper 0755 root root -"
      "d /var/cache/vosk 0755 root root -"
    ];

    system.activationScripts.installVoskModel = optionalString (cfg.voskModelPath != null && cfg.voskModelPackage != null) ''
      if [ ! -f "${cfg.voskModelPath}/conf/model.conf" ]; then
        echo "[speech-to-text] Installing VOSK model into ${cfg.voskModelPath}"
        rm -rf "${cfg.voskModelPath}"
        mkdir -p "${cfg.voskModelPath}"
        cp -a "${cfg.voskModelPackage}/." "${cfg.voskModelPath}/"
        chown -R root:root "${cfg.voskModelPath}"
      fi
    '';

    # No systemd services - everything is manual to avoid activation issues
    # The nerd-dictation-toggle script handles starting/stopping

    # XDG autostart for system tray indicator
    environment.etc =
      {
        "xdg/autostart/speech-to-text-indicator.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Speech-to-Text Indicator
          Comment=System tray indicator showing dictation status
          Exec=${speechIndicator}/bin/speech-to-text-indicator
          Icon=audio-input-microphone
          Terminal=false
          X-KDE-autostart-after=panel
          X-KDE-StartupNotify=false
        '';
      }
      // (mkIf cfg.enableGlobalShortcut {
        "xdg/kglobalshortcutsrc".text = ''
          [speech-to-text]
          toggle-dictation=${shortcutBinding},none,Toggle Speech Dictation
        '';
      });

    # Environment variables
    environment.sessionVariables = {
      WHISPER_MODEL = cfg.model;
      WHISPER_LANGUAGE = cfg.language;
      VOSK_MODEL_PATH = "${effectiveVoskModelPath}";
    };

    # Note: KDE shortcuts can be configured manually via System Settings
    # or by adding to home-manager configuration separately
  };
}
