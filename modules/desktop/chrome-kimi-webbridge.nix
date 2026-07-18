# Chrome policy for Kimi WebBridge extension
# Force-installs the Kimi WebBridge extension into all Chrome profiles
# (google-chrome-i3pm, google-chrome-codex-devtools, google-chrome-private, etc.)
#
# The extension (ID: fldmhceldgbpfpkbgopacenieobmligc) auto-connects as a
# WebSocket client to the local Kimi WebBridge daemon at
# ws://127.0.0.1:10086/ws, letting local AI agents drive the user's real
# Chrome (navigate, snapshot, click, fill, screenshot, evaluate, ...).
# The daemon side runs as the `kimi-webbridge.service` systemd user service
# (home-manager side: home-modules/ai-assistants/kimi-webbridge.nix).
#
# Chrome reads /etc/opt/chrome/policies/managed/*.json on Linux but does NOT
# merge dictionary policies (e.g. ExtensionSettings) across files at the same
# source — the alphabetically-last file wins and silently drops the others.
# To avoid losing this entry, we contribute the Kimi WebBridge extension to
# the policy file written by onepassword.nix via
# services.onepassword.chromeManagedExtensions.
{ lib, ... }:

let
  # Kimi WebBridge extension ID (from Chrome Web Store)
  # Moonshot AI's official WebBridge extension
  kimiWebBridgeExtensionId = "fldmhceldgbpfpkbgopacenieobmligc";
in
{
  services.onepassword.chromeManagedExtensions.${kimiWebBridgeExtensionId} = {
    installation_mode = "force_installed";
    update_url = "https://clients2.google.com/service/update2/crx";
    toolbar_pin = "force_pinned";
  };
}
