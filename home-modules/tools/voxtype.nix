# Voxtype - Push-to-talk speech-to-text configuration
# Uses evdev hotkey (KEY_COMPOSE = Scroll Lock without Fn on MX Keys).
# Output mode is "type" — injects text via wtype directly, no clipboard.
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
    model = "base.en"
    language = "en"

    [output]
    mode = "type"
    fallback_to_clipboard = true
  '';
}
