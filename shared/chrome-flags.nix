# Shared Google Chrome and PWA Feature Flags Configuration
#
# Configures:
# 1. WebMCP (Web Model Context Protocol):
#    - DevTools WebMCP support (#devtools-webmcp-support, DevToolsWebMCPSupport)
#    - WebMCP testing API (#enable-webmcp-testing, WebMCPTesting, --enable-webmcp-testing)
#    - WebMCP declarative and form support (WebMCP, WebMCPDeclarativeFileInput, WebMCPFormAssociatedCustomElements)
#    - Top Chrome Touch UI Layout (#top-chrome-touch-ui, --top-chrome-touch-ui=enabled)
# 2. Desktop Progressive Web Apps (PWAs):
#    - Tabbed application mode (#enable-desktop-pwas-tab-strip, DesktopPWAsTabStrip)
#    - PWA tab strip settings (#enable-desktop-pwas-tab-strip-settings, DesktopPWAsTabStripSettings)
#    - PWA tab strip manifest customizations (#enable-desktop-pwas-tab-strip-customizations, DesktopPWAsTabStripCustomizations)
#    - Additional windowing controls (DesktopPWAsAdditionalWindowingControls, DesktopPWAsAdditionalWindowingControlsOnMove)
#    - Borderless & custom title (DesktopPWAsBorderless, DesktopPWAsAppTitle)
#    - Un-elided extensions menu for PWAs (disables DesktopPWAsElidedExtensionsMenu)
# 3. Native Gemini Nano AI features:
#    - OptimizationGuideModelDownloading, PromptAPIForGeminiNano, WriterAPIForGeminiNano, etc.
# 4. Wayland window decorations (preserves WaylandWindowDecorations on Sway).
{ lib }:

rec {
  # All features to enable via --enable-features=<comma-separated>
  # NOTE: Chromium only reads the *last* --enable-features switch on the command line.
  # All enabled features MUST be concatenated into a single comma-separated list.
  enabledFeatures = [
    # Wayland integration under Sway/Wayland
    "WaylandWindowDecorations"

    # Gemini Nano on-device AI
    "OptimizationGuideModelDownloading"
    "PromptAPIForGeminiNano"
    "WriterAPIForGeminiNano"
    "RewriterAPIForGeminiNano"
    "SummarizationAPIForGeminiNano"

    # Gemini in Chrome (Glic) native sidebar / panel component (chrome://glic).
    # Note: Do NOT force-enable GlicActor / GlicActorUi / GlicActorEnableScriptTools
    # or GlicTieredRolloutV2 on the command line: the first three are already
    # FEATURE_ENABLED_BY_DEFAULT on desktop Chrome and carry Finch FeatureParams
    # (which bare --enable-features entries reset to compiled defaults), and
    # GlicTieredRolloutV2 defaults its eligible-tiers param to "".
    "Glic"
    "GlicRollout"
    "GlicTieredRollout"
    "GlicToolbarHeightSidePanel"
    "GlicLiveMode"
    "GlicMultiInstance"
    "GlicZeroStateSuggestions"

    # WebMCP (Web Model Context Protocol)
    "WebMCP"
    "DeclarativeWebMCP"
    "WebMCPTesting"
    "DevToolsWebMCPSupport"
    "WebMCPDeclarativeFileInput"
    "WebMCPFormAssociatedCustomElements"

    # Prompt API Tool Calling (for client-side models using WebMCP)
    "AIPromptAPIToolUse"
    "AIPromptAPIStructuredOutput"
    "AIPromptAPIMultimodalInput"
    "AIPromptAPIForExtension"

    # Desktop PWAs
    "DesktopPWAsTabStrip"
    "DesktopPWAsTabStripSettings"
    "DesktopPWAsTabStripCustomizations"
    "DesktopPWAsAdditionalWindowingControls"
    "DesktopPWAsAdditionalWindowingControlsOnMove"
    "DesktopPWAsBorderless"
    "DesktopPWAsAppTitle"
  ];

  # Common command-line switches
  commonSwitches = [
    "--top-chrome-touch-ui=enabled"
    "--enable-webmcp-testing"
    "--optimization-guide-model-execution-override-command-line-flag"
    # Chrome 149's chrome://glic webview onBeforeRequest only allows
    # https://gemini.google.com and https://www.google.com by default
    # (kGlicAllowedOriginsOverride). After GlicClearCookiesOnFirstSync clears
    # the glic storage partition on startup, gemini.google.com/glic redirects
    # through accounts.google.com/ServiceLogin?osid=1 to mint an origin-bound
    # OSID cookie, which the webview aborts with ERR_BLOCKED_BY_CLIENT and then
    # times out to "Something went wrong". Upstream Chromium fixed this later in
    # guest_util.cc IsGuestOriginAllowed() by always allowing accounts.google.com.
    "--glic-webui-allowed-origins=https://gemini.google.com https://www.google.com https://accounts.google.com"
  ];

  # Features to disable for PWAs
  pwaDisabledFeatures = [
    "DesktopPWAsElidedExtensionsMenu"
  ];

  # Arguments for general Chrome instances (google-chrome, google-chrome-stable, google-chrome-i3pm, etc.)
  chromeArgs = [
    "--enable-features=${lib.concatStringsSep "," enabledFeatures}"
  ] ++ commonSwitches;

  # Arguments for PWA instances (launch-pwa-by-name)
  pwaArgs = [
    "--enable-features=${lib.concatStringsSep "," enabledFeatures}"
    "--disable-features=${lib.concatStringsSep "," pwaDisabledFeatures}"
  ] ++ commonSwitches;

  # Arguments for Codex / Assistant DevTools instances
  webmcpDevtoolsArgs = [
    "--enable-features=${lib.concatStringsSep "," [
      "WebMCP"
      "DeclarativeWebMCP"
      "WebMCPTesting"
      "DevToolsWebMCPSupport"
      "WebMCPDeclarativeFileInput"
      "WebMCPFormAssociatedCustomElements"
      "AIPromptAPIToolUse"
      "AIPromptAPIStructuredOutput"
      "AIPromptAPIMultimodalInput"
      "AIPromptAPIForExtension"
    ]}"
    "--enable-webmcp-testing"
  ];

  # Flags to populate in Chrome's Local State ("browser": { "enabled_labs_experiments": [...] })
  # This makes chrome://flags explicitly reflect the enabled state in the UI.
  labsExperiments = [
    "glic@1"
    "glic-toolbar-height-side-panel@1"
    "enable-webmcp-testing@1"
    "prompt-api-tool-use@1"
    "top-chrome-touch-ui@3"
    "top-chrome-touch-ui@1"
    "enable-desktop-pwas-tab-strip@1"
    "enable-desktop-pwas-tab-strip-settings@1"
    "enable-desktop-pwas-tab-strip-customizations@1"
    "enable-desktop-pwas-additional-windowing-controls@1"
    "enable-desktop-pwas-borderless@1"
    "enable-desktop-pwas-app-title@1"
  ];
}
