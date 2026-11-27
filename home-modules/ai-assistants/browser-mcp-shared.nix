{ config, lib, pkgs }:

let
  hasSwaySession =
    pkgs.stdenv.isLinux
    && lib.attrByPath [ "wayland" "windowManager" "sway" "enable" ] false config;
in
rec {
  enableBrowserMcpServers = hasSwaySession;

  chromeDevtoolsBrowserHost = "127.0.0.1";
  chromeDevtoolsBrowserPort = 39222;
  chromeDevtoolsBrowserUrl =
    "http://${chromeDevtoolsBrowserHost}:${toString chromeDevtoolsBrowserPort}";

  chromeDevtoolsMcpArgs = [
    "-y"
    "chrome-devtools-mcp@latest"
    "--categoryExperimentalWebmcp"
    "--browserUrl"
    chromeDevtoolsBrowserUrl
  ];

  # Attaches to the user's running, signed-in Chrome Beta instance once remote
  # debugging is enabled at chrome://inspect/#remote-debugging.
  chromeBetaWebmcpMcpArgs = [
    "-y"
    "chrome-devtools-mcp@latest"
    "--autoConnect"
    "--channel=beta"
    "--categoryExperimentalWebmcp"
    "--categoryExperimentalThirdParty"
  ];

  sharedBrowserProfilesRoot = "${config.xdg.dataHome}/mcp/browser-profiles";
  chromeDevtoolsProfileDir = "${sharedBrowserProfilesRoot}/chrome-devtools";

  codexPlaywrightProfileDir = "${config.xdg.dataHome}/codex/browser-profiles/playwright";

  assistantBrowserProfileDirs = [
    chromeDevtoolsProfileDir
    codexPlaywrightProfileDir
  ];

  legacyBrowserProfileDirs = [
    "/tmp/codex-chrome-about-blank"
    "/tmp/agent-browser-profile-"
  ];
}
