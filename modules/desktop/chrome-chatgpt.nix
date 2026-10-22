# Chrome policy for OpenAI ChatGPT extension
# Force-installs the official ChatGPT browser extension into all Chrome profiles
# (google-chrome-i3pm, google-chrome-codex-devtools, google-chrome-private, etc.)
#
# The extension (ID: hehggadaopoacecdllhhajmbjkdcmajg, OpenAI's official
# "ChatGPT" Chrome Web Store extension) provides sidebar integration, browser
# control / computer-use capabilities, and native messaging with Codex
# (com.openai.codexextension).
#
# Chrome reads /etc/opt/chrome/policies/managed/*.json on Linux but does NOT
# merge dictionary policies (e.g. ExtensionSettings) across files at the same
# source — the alphabetically-last file wins and silently drops the others.
# To avoid losing this entry, we contribute the ChatGPT extension to the policy
# file written by onepassword.nix via services.onepassword.chromeManagedExtensions.
{ lib, ... }:

let
  # OpenAI's official "ChatGPT" extension ID (from Chrome Web Store):
  # https://chromewebstore.google.com/detail/chatgpt/hehggadaopoacecdllhhajmbjkdcmajg
  chatgptExtensionId = "hehggadaopoacecdllhhajmbjkdcmajg";
in
{
  services.onepassword.chromeManagedExtensions.${chatgptExtensionId} = {
    installation_mode = "force_installed";
    update_url = "https://clients2.google.com/service/update2/crx";
    toolbar_pin = "force_pinned";
  };
}
