# Voxtype - Push-to-talk speech-to-text configuration
# Uses evdev hotkey (KEY_COMPOSE = ThinkPad Copilot key, remapped F23->Compose
# by keyd; see modules/services/keyd.nix). Output mode is "type" — injects text
# via wtype directly, no clipboard.
#
# Accuracy notes:
# - whisper.cpp runs GPU-accelerated on the Intel iGPU (Vulkan); the daemon log
#   shows `whisper_backend_init_gpu: using Vulkan0 backend`. That headroom lets
#   us run large-v3-turbo (~4% WER) instead of base.en (~8% WER) at low latency.
# - The model file itself is a runtime download managed by voxtype
#   (`voxtype setup --download --model large-v3-turbo`), stored under
#   ~/.local/share/voxtype/models; only the selection is declarative here.
# - [text].replacements deterministically fixes domain terms whisper mis-hears.
{ ... }:
{
  xdg.configFile."voxtype/config.toml".text = ''
    [hotkey]
    key = "EVTEST_127"
    mode = "push_to_talk"

    [audio]
    device = "default"
    sample_rate = 16000
    max_duration_secs = 120

    [audio.feedback]
    enabled = true

    [whisper]
    model = "large-v3-turbo"
    language = "en"

    [output]
    mode = "type"
    fallback_to_clipboard = true

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
}
