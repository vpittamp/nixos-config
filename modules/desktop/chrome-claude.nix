# Chrome policy for Claude-in-Chrome extension
# Force-installs the Claude Code browser extension into all Chrome profiles
# (google-chrome-i3pm, google-chrome-codex-devtools, google-chrome-private, etc.)
#
# The extension (ID: fcoeoabgfenejglbffodgkkbkcdhcgfn) connects Claude Code CLI
# to Chrome via native messaging, enabling browser automation tools like
# mcp__claude-in-chrome__navigate, tabs_context_mcp, computer, etc.
#
# Chrome reads /etc/opt/chrome/policies/managed/*.json on Linux but does NOT
# merge dictionary policies (e.g. ExtensionSettings) across files at the same
# source — the alphabetically-last file wins and silently drops the others.
# To avoid losing this entry, we contribute the Claude extension to the policy
# file written by onepassword.nix via services.onepassword.chromeManagedExtensions.
{ lib, ... }:

let
  # Claude-in-Chrome extension ID (from Chrome Web Store)
  # This is Anthropic's official "Claude Code" browser extension
  claudeExtensionId = "fcoeoabgfenejglbffodgkkbkcdhcgfn";
in
{
  services.onepassword.chromeManagedExtensions.${claudeExtensionId} = {
    installation_mode = "force_installed";
    update_url = "https://clients2.google.com/service/update2/crx";
    toolbar_pin = "force_pinned";
  };
}
