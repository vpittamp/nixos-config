# Chrome policy for native Gemini and Generative AI features
#
# Enables Chrome's native generative AI policies, including:
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
