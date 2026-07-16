# Voxtype - toggle speech-to-text configuration
# Uses evdev hotkey (KEY_COMPOSE = ThinkPad Copilot key, remapped F23->Compose
# by keyd; see modules/services/keyd.nix). Output mode is "type" and still
# injects through wtype, but the wtype path is tapped so every dictated text run
# is recoverable from ~/.local/share/voxtype/transcripts/latest.txt and, after a
# short idle debounce, the Wayland clipboard / Elephant history.
#
# Triggering: the daemon runs in TOGGLE mode (`--toggle`), so every trigger
# behaves the same — press to start, press to stop:
#   • Copilot key (the daemon's evdev hotkey)
#   • Mod-less trackpad gesture / bar "Dictate" button / headset, which all call
#     `voxtype record toggle` via ~/.local/bin/dictation.
# This fixes the prior unreliability: the daemon was in push-to-talk mode, where
# an external `record toggle` fought the held-key state machine and recordings
# auto-stopped within ~1s. Toggle mode makes external toggles authoritative so
# recording holds until you stop it.
#
# Accuracy notes:
# - The default packaged binary is the Vulkan build, so whisper.cpp runs
#   GPU-accelerated on the Intel iGPU. That headroom lets us run
#   large-v3-turbo instead of a smaller/faster but less accurate model.
# - The model file itself is runtime data managed by voxtype under
#   ~/.local/share/voxtype/models; only the engine/model selection is
#   declarative here.
# - VAD (`--vad`) filters silence before transcription so a held toggle doesn't
#   feed silence/noise into the engine (fewer hallucinations / spurious words).
# - [text].replacements deterministically fixes domain terms whisper mis-hears.
{ pkgs, ... }:
let
  # Whisper model selection. Shared between the config.toml below and the
  # ExecStartPre bootstrap so the declared model and the auto-downloaded file
  # can never drift. voxtype stores it as ggml-<model>.bin under the models dir.
  whisperModel = "large-v3-turbo";

  # Model files are runtime data (not declaratively managed by Nix), so a fresh
  # machine or a wiped ~/.local/share has no model and the daemon would
  # crash-loop preloading it. This pre-start hook downloads any missing model
  # before ExecStart. It is best-effort: it always exits 0 so a transient
  # network failure never blocks the daemon, and ExecStart still surfaces a
  # clear "Model not found" error if the download genuinely failed.
  modelBootstrap = pkgs.writeShellScript "voxtype-model-bootstrap" ''
    set -u
    models_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models"
    voxtype=/run/current-system/sw/bin/voxtype

    if [ ! -f "$models_dir/ggml-${whisperModel}.bin" ]; then
      echo "voxtype: whisper model '${whisperModel}' missing, downloading..." >&2
      # `setup` also tries to rewrite the home-manager-managed (read-only)
      # config.toml and exits non-zero on that; the model file itself is still
      # saved, so we tolerate the failure.
      "$voxtype" setup --download --model ${whisperModel} --quiet || true
    fi

    if [ ! -f "$models_dir/ggml-silero-vad.bin" ]; then
      echo "voxtype: VAD model missing, downloading..." >&2
      "$voxtype" setup vad || true
    fi

    exit 0
  '';

  dictationSessionScript = pkgs.writeShellScriptBin "dictation-session" ''
    set -euo pipefail

    cmd="''${1:-}"
    runtime_base="''${XDG_RUNTIME_DIR:-/tmp}"
    state_dir="$runtime_base/voxtype"
    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
    transcript_dir="$data_home/voxtype/transcripts"
    current_file="$state_dir/transcript-current.txt"
    seq_file="$state_dir/transcript-seq"
    finalized_seq_file="$state_dir/transcript-finalized-seq"
    latest_file="$transcript_dir/latest.txt"
    history_file="$transcript_dir/history.jsonl"

    mkdir -p "$state_dir" "$transcript_dir"

    read_seq() {
      if [ -f "$seq_file" ]; then
        read -r seq < "$seq_file" || seq=0
      else
        seq=0
      fi
      case "$seq" in
        ""|*[!0-9]*) seq=0 ;;
      esac
      printf '%s' "$seq"
    }

    write_latest() {
      [ -f "$current_file" ] || : > "$current_file"
      ${pkgs.coreutils}/bin/cp "$current_file" "$latest_file"
    }

    finalize() {
      [ -s "$current_file" ] || exit 0

      seq="$(read_seq)"
      last_finalized=""
      if [ -f "$finalized_seq_file" ]; then
        read -r last_finalized < "$finalized_seq_file" || last_finalized=""
      fi
      if [ "$last_finalized" = "$seq" ]; then
        exit 0
      fi

      text="$(${pkgs.coreutils}/bin/cat "$current_file")"
      printf '%s' "$text" > "$latest_file"
      printf '%s\n' "$seq" > "$finalized_seq_file"

      if [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
        printf '%s' "$text" | ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain >/dev/null 2>&1 || true
      fi

      timestamp="$(${pkgs.coreutils}/bin/date --iso-8601=seconds)"
      ${pkgs.jq}/bin/jq -cn \
        --arg timestamp "$timestamp" \
        --arg text "$text" \
        '{timestamp: $timestamp, source: "voxtype", text: $text}' >> "$history_file" || true
    }

    case "$cmd" in
      start)
        : > "$current_file"
        printf '0\n' > "$seq_file"
        : > "$finalized_seq_file"
        ;;
      append)
        shift || true
        text="''${1:-}"
        [ -n "$text" ] || exit 0
        printf '%s' "$text" >> "$current_file"
        write_latest
        seq="$(read_seq)"
        seq=$((seq + 1))
        printf '%s\n' "$seq" > "$seq_file"
        ("$0" finalize-later "$seq" >/dev/null 2>&1 &)
        ;;
      finalize-later)
        expected="''${2:-}"
        ${pkgs.coreutils}/bin/sleep 2
        actual="$(read_seq)"
        [ "$actual" = "$expected" ] || exit 0
        finalize
        ;;
      finalize)
        finalize
        ;;
      *)
        echo "usage: dictation-session {start|append TEXT|finalize}" >&2
        exit 2
        ;;
    esac
  '';

  dictationWtypeTap = pkgs.writeShellScriptBin "wtype" ''
    set -euo pipefail

    text=""
    capture_next=0
    for arg in "$@"; do
      if [ "$capture_next" = 1 ]; then
        text="$arg"
        capture_next=0
        continue
      fi
      if [ "$arg" = "--" ]; then
        capture_next=1
      fi
    done

    if [ -n "$text" ]; then
      ${dictationSessionScript}/bin/dictation-session append "$text" || true
    fi

    exec ${pkgs.wtype}/bin/wtype "$@"
  '';
in
{
  # Daemon service (declarative — replaces the stale hand-installed unit). The
  # --toggle / --vad behaviour is set here via flags (CLI flags override config).
  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype voice-to-text daemon (toggle mode + VAD)";
      Documentation = "https://voxtype.io";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      # Download any missing whisper/VAD model before the daemon starts (see
      # modelBootstrap). Best-effort: always exits 0 so it can't block startup.
      ExecStartPre = "${modelBootstrap}";
      ExecStart = "/run/current-system/sw/bin/voxtype --toggle --vad daemon";
      Restart = "on-failure";
      RestartSec = 5;
      # First run may fetch a ~1.5 GB model in ExecStartPre; keep the start
      # timeout well above the default 90s so a slow download isn't killed.
      TimeoutStartSec = 1200;
      Environment = "XDG_RUNTIME_DIR=%t";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.configFile."voxtype/config.toml".text = ''
    engine = "whisper"
    state_file = "auto"

    [hotkey]
    key = "EVTEST_127"
    # Daemon is launched with --toggle (see systemd service above), which is
    # authoritative and keeps external triggers consistent.
    mode = "toggle"

    [audio]
    device = "default"
    sample_rate = 16000
    max_duration_secs = 120

    [audio.feedback]
    enabled = true

    [osd]
    enabled = false

    [whisper]
    model = "${whisperModel}"
    language = "en"

    [output]
    mode = "type"
    driver_order = ["wtype", "clipboard"]
    pre_recording_command = "${dictationSessionScript}/bin/dictation-session start"

    [text]
    # Say "period", "comma", "new line", etc. and get punctuation/newlines.
    spoken_punctuation = true
    # Whole-phrase fixups for terms whisper consistently garbles. Left side is
    # what whisper tends to emit; right side is the intended spelling.
    [text.replacements]
    "track pad" = "trackpad"
    "vox type" = "voxtype"
    "nix os" = "NixOS"
    "nixos" = "NixOS"
    "home manager" = "home-manager"
    "tail scale" = "Tailscale"
    "tailscale" = "Tailscale"
    "cube control" = "kubectl"
    "cube cuddle" = "kubectl"
    "cube ctl" = "kubectl"
    "kubernetes" = "Kubernetes"
    "argo cd" = "ArgoCD"
    "argocd" = "ArgoCD"
    "talos" = "Talos"
    "ryzen" = "Ryzen"
    "think pad" = "ThinkPad"
    "thinkpad" = "ThinkPad"
    "hetzner" = "Hetzner"
    "grafana" = "Grafana"
    "click house" = "ClickHouse"
    "pipe wire" = "PipeWire"
    "way land" = "Wayland"
    "quick shell" = "Quickshell"
    "t mux" = "tmux"
    "i 3 pm" = "i3pm"
    "i3 pm" = "i3pm"
  '';

  home.file.".local/bin/dictation-session" = {
    source = "${dictationSessionScript}/bin/dictation-session";
    executable = true;
  };

  home.file.".local/share/voxtype/bin/wtype" = {
    source = "${dictationWtypeTap}/bin/wtype";
    executable = true;
  };
}
