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

  sharedBrowserProfilesRoot = "${config.xdg.dataHome}/mcp/browser-profiles";
  chromeDevtoolsProfileDir = "${sharedBrowserProfilesRoot}/chrome-devtools";

  codexPlaywrightProfileDir = "${config.xdg.dataHome}/codex/browser-profiles/playwright";
  geminiPlaywrightProfileDir = "${config.xdg.dataHome}/gemini/browser-profiles/playwright";

  assistantBrowserProfileDirs = [
    chromeDevtoolsProfileDir
    codexPlaywrightProfileDir
    geminiPlaywrightProfileDir
  ];

  legacyBrowserProfileDirs = [
    "/tmp/codex-chrome-about-blank"
  ];
}
