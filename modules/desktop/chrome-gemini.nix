# Chrome policy for native Gemini and Generative AI features
#
# Enables Chrome's native generative AI policies, including:
#   - GeminiSettings: Native "Gemini in Chrome" (Glic) sidebar / floating panel (0=Enabled, 1=Disabled)
#   - GeminiActOnWebSettings: Allow Gemini in Chrome to act on web pages (0=Allowed, 1=Blocked)
#   - GenAILocalFoundationalModelSettings: Allow downloading on-device Gemini Nano model (0=Allowed, 1=Blocked)
#   - GenAiDefaultSettings: Enable general generative AI features (0=Allowed, 1=Allowed without data sharing, 2=Disabled)
#   - HelpMeWriteSettings: Help Me Write feature in input fields
#   - TabOrganizerSettings: Automatic tab organization
#   - HistorySearchSettings: AI-powered search in browser history
#   - CreateThemesSettings: AI wallpaper and theme generator
#   - DevToolsGenAiSettings: DevTools Gemini AI console insights & assistance
{ lib, ... }:

{
  environment.etc."opt/chrome/policies/managed/chrome-gemini.json".text =
    builtins.toJSON {
      GeminiSettings = 0;
      GeminiActOnWebSettings = 0;
      GenAILocalFoundationalModelSettings = 0;
      GenAiDefaultSettings = 0;
      HelpMeWriteSettings = 0;
      TabOrganizerSettings = 0;
      HistorySearchSettings = 0;
      CreateThemesSettings = 0;
      DevToolsGenAiSettings = 0;
      EnableMediaRouter = true;
      ShowCastIconInToolbar = true;
      CastAllowAllIPs = true;
    };
}
