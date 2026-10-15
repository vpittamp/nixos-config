# Chrome policy for Google's official WebMCP developer extension
# Force-installs the "Model Context Tool Inspector" extension (GoogleChromeLabs/webmcp-tools)
# recommended by Google's WebMCP developer documentation:
#   https://developer.chrome.com/docs/ai/webmcp
#   https://chromewebstore.google.com/detail/model-context-tool-inspec/gbpdfapgefenggkahomfgkhfehlcenpd
#
# Provides an interactive sidebar/popup to inspect registered imperative and
# declarative WebMCP tools (`navigator.modelContext`), test tool execution
# manually with JSON arguments, and test agentic tool calling via Gemini.
#
# Contributed via services.onepassword.chromeManagedExtensions so all managed
# Chrome extensions merge into a single ExtensionSettings policy dictionary.
{ lib, ... }:

let
  webmcpInspectorExtensionId = "gbpdfapgefenggkahomfgkhfehlcenpd";
in
{
  services.onepassword.chromeManagedExtensions.${webmcpInspectorExtensionId} = {
    installation_mode = "force_installed";
    update_url = "https://clients2.google.com/service/update2/crx";
    toolbar_pin = "force_pinned";
  };
}
