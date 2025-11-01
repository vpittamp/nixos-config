# Sway Configuration Contract: Workspace Mode

# This file demonstrates the expected Sway configuration for workspace mode navigation.
# It will be integrated into home-modules/desktop/sway/ as part of implementation.

{
  # Workspace Mode Definitions
  # These modes are defined in Sway config and trigger mode events that the daemon subscribes to

  modes = {
    # Goto Workspace Mode - Navigate to workspace by typing digits
    goto_workspace = ''
      # Digit bindings (0-9)
      bindsym 0 exec i3pm workspace-mode digit 0
      bindsym 1 exec i3pm workspace-mode digit 1
      bindsym 2 exec i3pm workspace-mode digit 2
      bindsym 3 exec i3pm workspace-mode digit 3
      bindsym 4 exec i3pm workspace-mode digit 4
      bindsym 5 exec i3pm workspace-mode digit 5
      bindsym 6 exec i3pm workspace-mode digit 6
      bindsym 7 exec i3pm workspace-mode digit 7
      bindsym 8 exec i3pm workspace-mode digit 8
      bindsym 9 exec i3pm workspace-mode digit 9

      # Execute workspace switch
      bindsym Return exec i3pm workspace-mode execute, mode default
      bindsym KP_Enter exec i3pm workspace-mode execute, mode default

      # Cancel mode
      bindsym Escape mode default
      bindsym Control+c mode default
      bindsym Control+g mode default

      # Backspace to remove last digit (optional future enhancement)
      # bindsym BackSpace exec i3pm workspace-mode backspace
    '';

    # Move Workspace Mode - Move focused window to workspace by typing digits
    move_workspace = ''
      # Digit bindings (0-9)
      bindsym 0 exec i3pm workspace-mode digit 0
      bindsym 1 exec i3pm workspace-mode digit 1
      bindsym 2 exec i3pm workspace-mode digit 2
      bindsym 3 exec i3pm workspace-mode digit 3
      bindsym 4 exec i3pm workspace-mode digit 4
      bindsym 5 exec i3pm workspace-mode digit 5
      bindsym 6 exec i3pm workspace-mode digit 6
      bindsym 7 exec i3pm workspace-mode digit 7
      bindsym 8 exec i3pm workspace-mode digit 8
      bindsym 9 exec i3pm workspace-mode digit 9

      # Execute window move + follow
      bindsym Return exec i3pm workspace-mode execute, mode default
      bindsym KP_Enter exec i3pm workspace-mode execute, mode default

      # Cancel mode
      bindsym Escape mode default
      bindsym Control+c mode default
      bindsym Control+g mode default
    '';
  };

  # Platform-Specific Mode Entry Keybindings
  # These are conditionally included based on hostname

  keybindings = {
    # M1 MacBook Pro - CapsLock activation (via keyd remap to F13)
    m1 = {
      # CapsLock (remapped to F13 by keyd) enters goto mode
      "bindcode 191" = "mode goto_workspace";  # F13 scancode
      "bindcode Shift+191" = "mode move_workspace";

      # Fallback: Mod+semicolon (works on all platforms)
      "bindsym $mod+semicolon" = "mode goto_workspace";
      "bindsym $mod+Shift+semicolon" = "mode move_workspace";
    };

    # Hetzner Cloud - Ctrl+0 activation (VNC compatible)
    hetzner = {
      "bindsym Control+0" = "mode goto_workspace";
      "bindsym Control+Shift+0" = "mode move_workspace";

      # Fallback: Mod+semicolon (works on all platforms)
      "bindsym $mod+semicolon" = "mode goto_workspace";
      "bindsym $mod+Shift+semicolon" = "mode move_workspace";
    };
  };

  # Sway Bar Configuration (for binding_mode_indicator)
  bar = {
    # Native Sway mode indicator (shows mode name with Pango markup)
    binding_mode_indicator = true;

    # Mode display text (Pango markup)
    mode_text = {
      goto_workspace = "<span foreground='#a6e3a1' weight='bold'>→ WS</span>";  # Catppuccin green
      move_workspace = "<span foreground='#89b4fa' weight='bold'>⇒ WS</span>";  # Catppuccin blue
    };

    # Colors for mode indicator
    colors = {
      binding_mode = {
        background = "#313244";  # Catppuccin surface0
        border = "#a6e3a1";      # Catppuccin green
        text = "#cdd6f4";        # Catppuccin text
      };
    };
  };
}

# NixOS Integration Pattern
# The above configuration will be declaratively generated via home-manager:

/*
{ config, lib, pkgs, ... }:

let
  isM1 = config.networking.hostName == "m1-mbp";
  isHetzner = config.networking.hostName == "hetzner";

  # Mode definitions (shared across platforms)
  gotoWorkspaceMode = ''
    mode "goto_workspace" {
      bindsym 0 exec i3pm workspace-mode digit 0
      bindsym 1 exec i3pm workspace-mode digit 1
      bindsym 2 exec i3pm workspace-mode digit 2
      bindsym 3 exec i3pm workspace-mode digit 3
      bindsym 4 exec i3pm workspace-mode digit 4
      bindsym 5 exec i3pm workspace-mode digit 5
      bindsym 6 exec i3pm workspace-mode digit 6
      bindsym 7 exec i3pm workspace-mode digit 7
      bindsym 8 exec i3pm workspace-mode digit 8
      bindsym 9 exec i3pm workspace-mode digit 9

      bindsym Return exec i3pm workspace-mode execute, mode "default"
      bindsym KP_Enter exec i3pm workspace-mode execute, mode "default"

      bindsym Escape mode "default"
      bindsym Control+c mode "default"
      bindsym Control+g mode "default"
    }
  '';

  moveWorkspaceMode = ''
    mode "move_workspace" {
      bindsym 0 exec i3pm workspace-mode digit 0
      bindsym 1 exec i3pm workspace-mode digit 1
      bindsym 2 exec i3pm workspace-mode digit 2
      bindsym 3 exec i3pm workspace-mode digit 3
      bindsym 4 exec i3pm workspace-mode digit 4
      bindsym 5 exec i3pm workspace-mode digit 5
      bindsym 6 exec i3pm workspace-mode digit 6
      bindsym 7 exec i3pm workspace-mode digit 7
      bindsym 8 exec i3pm workspace-mode digit 8
      bindsym 9 exec i3pm workspace-mode digit 9

      bindsym Return exec i3pm workspace-mode execute, mode "default"
      bindsym KP_Enter exec i3pm workspace-mode execute, mode "default"

      bindsym Escape mode "default"
      bindsym Control+c mode "default"
      bindsym Control+g mode "default"
    }
  '';

  # Platform-specific mode entry bindings
  m1ModeEntryBindings = ''
    # CapsLock (remapped to F13 by keyd)
    bindcode 191 mode "goto_workspace"
    bindcode Shift+191 mode "move_workspace"

    # Fallback
    bindsym $mod+semicolon mode "goto_workspace"
    bindsym $mod+Shift+semicolon mode "move_workspace"
  '';

  hetznerModeEntryBindings = ''
    # Ctrl+0 (VNC compatible)
    bindsym Control+0 mode "goto_workspace"
    bindsym Control+Shift+0 mode "move_workspace"

    # Fallback
    bindsym $mod+semicolon mode "goto_workspace"
    bindsym $mod+Shift+semicolon mode "move_workspace"
  '';

in {
  # Generate Sway config
  xdg.configFile."sway/config.d/workspace-modes.conf".text = ''
    # Workspace Mode Navigation (Feature 042)
    # Event-driven Python daemon integration

    ${gotoWorkspaceMode}
    ${moveWorkspaceMode}

    ${if isM1 then m1ModeEntryBindings else ""}
    ${if isHetzner then hetznerModeEntryBindings else ""}
  '';

  # Enable binding mode indicator in swaybar
  xdg.configFile."sway/config.d/bar-mode-indicator.conf".text = ''
    bar {
      # ... existing bar configuration ...

      # Enable native mode indicator
      binding_mode_indicator yes

      colors {
        binding_mode {
          background #313244
          border #a6e3a1
          text #cdd6f4
        }
      }
    }
  '';
}
*/

# Expected Sway Behavior
# When this configuration is active:

# 1. User presses CapsLock (M1) or Ctrl+0 (Hetzner)
#    → Sway enters "goto_workspace" mode
#    → Sway emits mode event (change="goto_workspace")
#    → Daemon on_mode handler called
#    → Daemon broadcasts workspace_mode event (mode_active=True)
#    → Status bar displays "WS: _"
#    → Swaybar shows binding_mode_indicator: "→ WS"

# 2. User types "2"
#    → Sway executes: i3pm workspace-mode digit 2
#    → CLI sends IPC: workspace_mode.digit {"digit": "2"}
#    → Daemon updates state: accumulated_digits = "2"
#    → Daemon broadcasts event (accumulated_digits="2")
#    → Status bar displays "WS: 2"

# 3. User types "3"
#    → Sway executes: i3pm workspace-mode digit 3
#    → CLI sends IPC: workspace_mode.digit {"digit": "3"}
#    → Daemon updates state: accumulated_digits = "23"
#    → Daemon broadcasts event (accumulated_digits="23")
#    → Status bar displays "WS: 23"

# 4. User presses Enter
#    → Sway executes: i3pm workspace-mode execute, mode "default"
#    → CLI sends IPC: workspace_mode.execute {}
#    → Daemon sends i3 commands: workspace number 23, focus output <output>
#    → Daemon resets state, broadcasts event (mode_active=False)
#    → Sway returns to default mode
#    → Swaybar hides binding_mode_indicator
#    → Status bar clears workspace mode display

# 5. Alternative: User presses Escape
#    → Sway executes: mode "default"
#    → Sway emits mode event (change="default")
#    → Daemon on_mode handler resets state
#    → Daemon broadcasts event (mode_active=False)
#    → Status bar clears workspace mode display

# Testing Contract Compliance

# Manual Test Script:
# 1. Enter mode: Press CapsLock (M1) or Ctrl+0 (Hetzner)
#    Expected: Mode indicator appears in swaybar
# 2. Type digits: Press "2", then "3"
#    Expected: Status bar shows "WS: 23"
# 3. Execute: Press Enter
#    Expected: Focus switches to workspace 23, mode exits
# 4. Verify: Run `swaymsg -t get_workspaces | jq '.[] | select(.focused)'`
#    Expected: num = 23

# Automated Test (pytest):
'''python
@pytest.mark.asyncio
async def test_sway_mode_integration():
    """Test Sway mode integration end-to-end."""
    # Trigger mode entry
    await sway_exec("mode goto_workspace")
    await asyncio.sleep(0.1)  # Wait for mode event

    # Verify daemon state
    state = await daemon_ipc_call("workspace_mode.state", {})
    assert state["active"] is True
    assert state["mode_type"] == "goto"

    # Simulate digit input
    await sway_exec("exec i3pm workspace-mode digit 2")
    await sway_exec("exec i3pm workspace-mode digit 3")
    await asyncio.sleep(0.1)

    # Verify accumulated state
    state = await daemon_ipc_call("workspace_mode.state", {})
    assert state["accumulated_digits"] == "23"

    # Execute switch
    await sway_exec("exec i3pm workspace-mode execute")
    await sway_exec("mode default")
    await asyncio.sleep(0.1)

    # Verify workspace switch
    workspaces = await sway_ipc_call("get_workspaces", {})
    focused = next(w for w in workspaces if w["focused"])
    assert focused["num"] == 23
'''
