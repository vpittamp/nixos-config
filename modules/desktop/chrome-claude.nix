# Chrome policy for Claude-in-Chrome extension
# Force-installs the Claude Code browser extension into all Chrome profiles
# (google-chrome-i3pm, google-chrome-codex-devtools, google-chrome-private, etc.)
#
# The extension (ID: fcoeoabgfenejglbffodgkkbkcdhcgfn) connects Claude Code CLI
# to Chrome via native messaging, enabling browser automation tools like
# mcp__claude-in-chrome__navigate, tabs_context_mcp, computer, etc.
#
# This is a system-level policy that Chrome reads from
# /etc/opt/chrome/policies/managed/ on Linux.
{ lib, ... }:

let
  # Claude-in-Chrome extension ID (from Chrome Web Store)
  # This is Anthropic's official "Claude Code" browser extension
  claudeExtensionId = "fcoeoabgfenejglbffodgkkbkcdhcgfn";
in
{
  environment.etc."opt/chrome/policies/managed/claude-in-chrome.json" = {
    text = builtins.toJSON {
      # Force-install the Claude-in-Chrome extension from Chrome Web Store
      # Chrome merges ExtensionSettings dicts across policy files, so this
      # coexists with the 1Password extension in onepassword.nix
      ExtensionSettings = {
        "${claudeExtensionId}" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
          toolbar_pin = "force_pinned";
        };
      };

      # NativeMessagingAllowlist is a list-type policy that does NOT merge
      # across files. The allowlist is maintained in onepassword.nix alongside
      # 1Password hosts to ensure all native messaging hosts are permitted.
    };
    mode = "0644";
  };
}
