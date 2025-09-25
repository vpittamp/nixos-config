{ config, pkgs, lib, ... }:

{
  # Yakuake dropdown terminal
  # Disabled due to crash loop
  # home.packages = with pkgs; [
    # kdePackages.yakuake
  # ];

  # Konsole profile with improved settings
  home.file.".local/share/konsole/improved.profile" = {
    text = ''
      [Appearance]
      ColorScheme=BreezeDark
      Font=FiraCode Nerd Font,9,-1,5,50,0,0,0,0,0

      [Cursor Options]
      CursorShape=0
      UseCustomCursorColor=false

      [General]
      Command=/run/current-system/sw/bin/bash -l
      Environment=TERM=xterm-256color,KONSOLE_VERSION=1
      Name=Improved Selection
      Parent=FALLBACK/
      StartInCurrentSessionDir=false
      TerminalColumns=80
      TerminalRows=24
      TerminalMargin=1

      [Interaction Options]
      AutoCopySelectedText=true
      CopyTextAsHTML=false
      CtrlRequiredForDrag=true
      DropUrlsAsText=true
      EscapedLinksSchema=http;https;file
      MiddleClickPasteMode=0
      MouseWheelZoomEnabled=true
      OpenLinksByDirectClickEnabled=false
      PasteFromClipboardEnabled=true
      PasteFromSelectionEnabled=true
      TrimLeadingSpacesInSelectedText=false
      TrimTrailingSpacesInSelectedText=false
      TripleClickMode=0
      UnderlineFilesEnabled=true
      UnderlineLinksEnabled=true
      WordCharacters=:@-./_~?&=%+#

      [Keyboard]
      KeyBindings=default

      [Scrolling]
      HistoryMode=1
      HistorySize=10000
      ScrollBarPosition=2
      ScrollFullPage=false

      [Terminal Features]
      BellMode=0
      BidiRenderingEnabled=true
      BlinkingCursorEnabled=true
      BlinkingTextEnabled=true
      FlowControlEnabled=false
      PeekPrimaryKeySequence=
      ReverseUrlHints=false
      UrlHintsModifiers=0
      VerticalLine=false
      VerticalLineAtChar=80
    '';
  };

  # Set improved profile as the default for Konsole
  programs.plasma.configFile."konsolerc".General = {
    DefaultProfile = "Improved Selection.profile";
  };
}