# Speech-to-Text Module
# Provides OpenAI Whisper, VOSK, and GUI tools for speech recognition
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.speech-to-text;

  # Declarative VOSK model - small English model for offline speech recognition
  # This model is lightweight (40MB) and works well for English dictation
  voskModel = pkgs.fetchzip {
    url = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip";
    sha256 = "1rl65n2maayggnzi811x6zingkd1ny2z7p0fvcbfaprbz5khz2h8";
    stripRoot = true;
  };

  # Note: Additional models can be downloaded through Speech Note GUI
  # Recommended Whisper models for comparison:
  # - Whisper tiny.en (39MB) - fastest, good for real-time
  # - Whisper base.en (74MB) - good balance of speed and accuracy
  # - Whisper small.en (244MB) - better accuracy, slower

  # Fixed Nerd Dictation wrapper script using declarative model
  nerdDictationWrapper = pkgs.writeScriptBin "nerd-dictation-toggle" ''
    #!${pkgs.bash}/bin/bash

    # Check if nerd-dictation is running
    if pgrep -f "nerd-dictation begin" > /dev/null; then
      # Stop dictation
      /usr/local/bin/nerd-dictation end
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Dictation stopped" -i microphone-sensitivity-muted
    else
      # Start dictation with VOSK using declarative model
      /usr/local/bin/nerd-dictation begin \
        --vosk-model-dir "${voskModel}" \
        --continuous \
        --output SIMULATE_INPUT &
      ${pkgs.libnotify}/bin/notify-send "Speech to Text" "Dictation started - Speak now!" -i audio-input-microphone
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

  # Configuration file for Speech Note
  speechNoteConfig = pkgs.writeText "speech-note-config.conf" ''
    [General]
    # Enable OpenAI Whisper as primary STT engine
    stt_engine=whisper

    # Model settings
    whisper_model=base
    whisper_lang=en

    # Use OpenAI API when available
    use_openai_api=true

    # System tray settings
    start_in_tray=true
    minimize_to_tray=true

    # Audio settings
    audio_input=default
    auto_punctuation=true
  '';

  # Wrapper script for Speech Note with 1Password integration
  speechNoteWrapper = pkgs.writeScriptBin "speech-note" ''
    #!${pkgs.bash}/bin/bash

    # Ensure config directory exists
    CONFIG_DIR="$HOME/.var/app/net.mkiol.SpeechNote/config/net.mkiol/dsnote"
    mkdir -p "$CONFIG_DIR"

    # Copy config if it doesn't exist
    if [ ! -f "$CONFIG_DIR/dsnote.conf" ]; then
      cp ${speechNoteConfig} "$CONFIG_DIR/dsnote.conf"
    fi

    # Check if 1Password CLI is available and signed in
    if command -v op &> /dev/null && op whoami &> /dev/null; then
      echo "Starting Speech Note with OpenAI API key from 1Password..."
      # Using item ID for service account compatibility
      exec op run \
        --env-file=<(echo "OPENAI_API_KEY=op://pb26ok6vdihb7udkl7uunp7kd4/credential") \
        -- flatpak run net.mkiol.SpeechNote --app-standalone "$@"
    else
      echo "Starting Speech Note without API key (1Password not available)"
      exec flatpak run net.mkiol.SpeechNote --app-standalone "$@"
    fi
  '';

  # Desktop entry for Speech Note
  speechNoteDesktop = pkgs.makeDesktopItem {
    name = "speech-note";
    desktopName = "Speech Note";
    comment = "Speech recognition with OpenAI integration";
    icon = "audio-input-microphone";
    exec = "${speechNoteWrapper}/bin/speech-note";
    categories = [ "Audio" "Utility" "Accessibility" ];
    startupNotify = true;
    terminal = false;
  };

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
        # Note: VOSK model is downloaded separately
      ]))
      xdotool      # For input simulation (X11)
      wtype        # Wayland input simulation (for KDE Plasma 6)

      # Required for notifications
      libnotify

      # Model download tools
      wget
      unzip

      # Helper scripts and applications
      nerdDictationWrapper
      whisperSetup
      speechNoteWrapper
      speechNoteDesktop

      # Audio tools
      sox          # Sound processing
      pavucontrol  # PulseAudio control for microphone setup
    ];

    # Note: Flatpak is enabled in kde-plasma.nix
    # We'll add an activation script to install Speech Note declaratively

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

    # Declaratively install Speech Note Flatpak application
    system.activationScripts.speechNoteFlatpak = ''
      # Ensure Flathub repository is added
      ${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

      # Check if Speech Note is installed
      if ! ${pkgs.flatpak}/bin/flatpak list --system | grep -q "net.mkiol.SpeechNote"; then
        echo "Installing Speech Note (GUI speech recognition app)..."
        ${pkgs.flatpak}/bin/flatpak install --system -y flathub net.mkiol.SpeechNote || true
      else
        echo "Speech Note is already installed"
      fi
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

    # Create systemd user service for Speech Note with OpenAI API key from 1Password
    systemd.user.services.speech-note = {
      description = "Speech Note - Speech Recognition System Tray Application";
      after = [ "graphical-session.target" "1password.service" ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        QT_QPA_PLATFORM = "xcb";  # Ensure Qt uses X11
        DISPLAY = ":0";
      };

      serviceConfig = {
        Type = "simple";
        # Use op run to inject the OpenAI API key from 1Password
        ExecStartPre = ''${pkgs.bash}/bin/bash -c "mkdir -p $HOME/.var/app/net.mkiol.SpeechNote/config/net.mkiol/dsnote && cp -n ${speechNoteConfig} $HOME/.var/app/net.mkiol.SpeechNote/config/net.mkiol/dsnote/dsnote.conf || true"'';
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c 'op run --env-file=<(echo "OPENAI_API_KEY=op://pb26ok6vdihb7udkl7uunp7kd4/credential") -- flatpak run net.mkiol.SpeechNote --app-standalone'
        '';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Environment variables
    environment.sessionVariables = {
      WHISPER_MODEL = cfg.model;
      WHISPER_LANGUAGE = cfg.language;
    };
  };
}