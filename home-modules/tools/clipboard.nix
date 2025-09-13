{ config, pkgs, lib, ... }:

{
  # Clipboard management module for seamless copy/paste across all environments
  # Supports: Wayland (wl-clipboard), X11 (xclip), tmux integration, and KDE Plasma clipboard history
  
  # Clipboard utilities are installed at system level in kde-plasma.nix
  # CopyQ, wl-clipboard, and xclip are all available system-wide

  # Create clipboard helper scripts
  home.file.".local/bin/clip-copy" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Universal clipboard copy script that detects the environment
      
      # For SSH sessions, try to detect the correct display
      if [ -n "$SSH_CONNECTION" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        # Check if we have X11 forwarding
        if [ -n "$DISPLAY" ]; then
          # Try to use the SSH-forwarded display
          export DISPLAY="$DISPLAY"
        else
          # No X11 forwarding, try to find local display
          if xauth list 2>/dev/null | grep -q "unix:"; then
            # Extract display number from xauth
            DISPLAY_NUM=$(xauth list | grep "unix:" | head -1 | cut -d: -f2 | cut -d' ' -f1)
            export DISPLAY=":$DISPLAY_NUM"
          fi
        fi
      fi
      
      # Check if we're in Wayland or X11
      if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        # Use wl-copy for Wayland
        wl-copy "$@"
      elif command -v xclip &> /dev/null; then
        # Use xclip for X11
        xclip -selection clipboard "$@" 2>/dev/null || {
          echo "Failed to access clipboard. Try using tmux clipboard or Klipper." >&2
          exit 1
        }
      elif command -v xsel &> /dev/null; then
        # Fallback to xsel
        xsel --clipboard --input "$@"
      else
        echo "No clipboard utility found!" >&2
        exit 1
      fi
    '';
  };

  home.file.".local/bin/clip-paste" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Universal clipboard paste script that detects the environment
      
      # For SSH sessions, try to detect the correct display
      if [ -n "$SSH_CONNECTION" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        # Check if we have X11 forwarding
        if [ -n "$DISPLAY" ]; then
          # Try to use the SSH-forwarded display
          export DISPLAY="$DISPLAY"
        else
          # No X11 forwarding, try to find local display
          if xauth list 2>/dev/null | grep -q "unix:"; then
            # Extract display number from xauth
            DISPLAY_NUM=$(xauth list | grep "unix:" | head -1 | cut -d: -f2 | cut -d' ' -f1)
            export DISPLAY=":$DISPLAY_NUM"
          fi
        fi
      fi
      
      if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        # Use wl-paste for Wayland
        wl-paste "$@"
      elif command -v xclip &> /dev/null; then
        # Use xclip for X11
        xclip -selection clipboard -o "$@" 2>/dev/null || {
          echo "Failed to access clipboard. Try using tmux clipboard or Klipper." >&2
          exit 1
        }
      elif command -v xsel &> /dev/null; then
        # Fallback to xsel
        xsel --clipboard --output "$@"
      else
        echo "No clipboard utility found!" >&2
        exit 1
      fi
    '';
  };

  # CopyQ configuration for advanced clipboard management (DISABLED - using Klipper)
  # home.file.".config/copyq/copyq.conf" = {
  #   text = ''
  #     [General]
  #     autostart=true
  #     check_clipboard=true
  #     check_selection=false
  #     clipboard_tab=&clipboard
  #     close_on_unfocus=true
  #     confirm_exit=false
  #     copy_clipboard=false
  #     copy_selection=false
  #     disable_tray=false
  #     edit_ctrl_return=true
  #     editor=nvim
  #     expire_tab=0
  #     hide_main_window=false
  #     hide_main_window_in_task_bar=false
  #     hide_tabs=false
  #     hide_toolbar=false
  #     hide_toolbar_labels=true
  #     item_popup_interval=0
  #     language=en
  #     max_items=500
  #     move=true
  #     notification_lines=0
  #     notification_position=3
  #     number_search=true
  #     open_windows_on_current_screen=true
  #     run_selection=true
  #     save_delay_ms_on_item_added=300000
  #     save_delay_ms_on_item_edited=1000
  #     save_delay_ms_on_item_modified=300000
  #     save_delay_ms_on_item_moved=1800000
  #     save_delay_ms_on_item_removed=600000
  #     save_filter_history=false
  #     save_on_app_deactivated=true
  #     show_advanced_command_settings=false
  #     show_simple_items=false
  #     show_tab_item_count=true
  #     style=
  #     tab_tree=false
  #     tabs=&clipboard
  #     text_tab_width=8
  #     text_wrap=true
  #     transparency=0
  #     transparency_focused=0
  #     tray_commands=true
  #     tray_images=true
  #     tray_item_paste=true
  #     tray_items=10
  #     tray_menu_open_on_left_click=false
  #     tray_tab=
  #     tray_tab_is_current=true
  #     vi=false
  #   '';
  # };

  # XDG autostart for CopyQ (DISABLED - using Klipper)
  # home.file.".config/autostart/copyq.desktop" = {
  #   text = ''
  #     [Desktop Entry]
  #     Name=CopyQ
  #     Comment=Advanced clipboard manager
  #     Exec=${pkgs.copyq}/bin/copyq
  #     Terminal=false
  #     Type=Application
  #     Icon=copyq
  #     Categories=Utility;
  #     StartupNotify=false
  #     X-GNOME-Autostart-enabled=true
  #     X-KDE-autostart-after=panel
  #   '';
  # };

  # Environment variables for clipboard
  home.sessionVariables = {
    # Ensure clipboard tools are in PATH
    PATH = "$HOME/.local/bin:$PATH";
    # Set Qt platform for X11 when not in Wayland
    QT_QPA_PLATFORM = lib.mkDefault "xcb";
  };

  # Add clipboard aliases to bash configuration
  programs.bash.shellAliases = {
    # Clipboard shortcuts
    "clip" = "clip-copy";
    
    # Klipper (KDE native clipboard) commands
    "cliph" = "qdbus org.kde.klipper /klipper org.kde.klipper.klipper.showKlipperPopupMenu";  # Show Klipper menu
    "clipc" = "qdbus org.kde.klipper /klipper org.kde.klipper.klipper.clearClipboardHistory"; # Clear history
    
    # CopyQ-specific aliases (DISABLED - using Klipper)
    # "cliph" = "copyq show";  # Show clipboard history
    # "clipc" = "copyq clear"; # Clear clipboard history
    # "clips" = "copyq search"; # Search clipboard history
    # "clipt" = "copyq tab";   # Switch clipboard tabs
    # "clipp" = "copyq paste"; # Paste from CopyQ
  };
}
