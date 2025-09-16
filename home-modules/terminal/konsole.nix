{ config, pkgs, lib, ... }:

{
  # Yakuake dropdown terminal
  home.packages = with pkgs; [
    kdePackages.yakuake
  ];
  
  # Yakuake config is now managed declaratively via plasma-manager
  # (see home-modules/desktop/projects-config.nix). Avoid creating a
  # read-only symlink at ~/.config/yakuakerc that conflicts with
  # plasma-manager's writer.
  
  # Note: Autostart is configured in modules/desktop/kde-plasma.nix
  # Keybinding (F12) is set in the yakuakerc above
  
  
  # Konsole profile for better text selection
  home.file.".local/share/konsole/improved.profile" = {
    text = ''
      [Appearance]
      ColorScheme=BreezeDark
      Font=FiraCode Nerd Font,11,-1,5,50,0,0,0,0,0
      
      [Cursor Options]
      CursorShape=0
      UseCustomCursorColor=false
      
      [General]
      Command=/run/current-system/sw/bin/bash -l
      Name=Improved Selection
      Parent=FALLBACK/
      
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

  # Set this improved profile as the default for Konsole
  programs.plasma.configFile."konsolerc".General = {
    DefaultProfile = "Improved Selection.profile";
  };
}
