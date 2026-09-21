# The function catalog jev routes into.
#
# One entry per thing the desktop can be asked to do. An entry is a name, a
# description written for the router to match *meaning* against, an argv
# template, and the closed sets its arguments draw from. Nothing here is a
# string a model produced: every value that can reach a command is a key in an
# `options` attrset below, so a wrong answer picks the wrong one of our own
# commands and can never invent one.
#
# The option sets that would otherwise drift — installed applications, the
# theme set, the runtime-shell surfaces, the workspace numbers — are passed in
# from the same files sway and the shell already read, so the catalog cannot
# offer an app that is not installed or a theme that does not exist.
#
# Writing the questions: describe the *idea*, not the parameter. "Which
# resolution?" gives a sentence nothing to match against; "How far back should
# the window reach?" does. `stated` makes an argument optional — it is a second
# yes/no asking whether the command mentioned the argument at all, and a no
# leaves it out so the command's own default stands. That `default` is a
# *value*, not an option key — it goes into the argv untouched.
{ lib
, bins
, apps # [ { name; display_name; description; } ] — from the app registry
, themes # { <name> = { label; description; dark; }; } — from themes.nix
, surfaces # [ { id; description; } ] — runtime-shell surface ids
, workspaces # [ 1 2 3 … ] — the workspace numbers worth naming
}:

let
  # ---- shapes -----------------------------------------------------------
  # `value` defaults to the option key, which is what makes a catalog entry
  # short: the key is both what jev returns and what the command takes. It
  # diverges only where one word has to expand into several argv tokens.
  opt = description: { inherit description; };
  optv = value: description: { inherit description value; };

  choice = { question, options, stated ? null, default ? null }: {
    type = "choice";
    inherit question options stated default;
  };

  fn = { summary, description, argv, arguments ? { }, confirm ? false }: {
    inherit summary description argv arguments confirm;
  };

  # ---- shared option sets ----------------------------------------------
  directions = {
    left = opt "towards the left, or west";
    right = opt "towards the right, or east";
    up = opt "upwards, above, or north";
    down = opt "downwards, below, or south";
  };

  # Which screen, for the two "move to another output" actions. `next` is
  # sway's own word for the one after this, and it is the honest answer to
  # "the other screen" — a phrase that names no side, and which forcing into
  # left/right left hovering at a coin flip.
  outputDirections = directions // {
    next = opt "the other screen, the next one over, whichever it is — no side named";
  };

  appOptions = lib.listToAttrs (map
    (app: lib.nameValuePair app.name
      (opt ((app.display_name or app.name) + " — " + (app.description or ""))))
    apps);

  themeOptions = lib.mapAttrs
    (_: theme: opt "${theme.label}: ${theme.description} (${if theme.dark then "dark" else "light"})")
    themes;

  surfaceOptions = lib.listToAttrs
    (map (s: lib.nameValuePair s.id (opt s.description)) surfaces);

  workspaceOptions = lib.listToAttrs (map
    (n: lib.nameValuePair (toString n) (opt "workspace number ${toString n}"))
    workspaces);

  sway = bins.swaymsg;
in
{
  routeQuestion = ''
    The user typed one line into their desktop's command bar. Which of these
    actions were they asking for? Pick the action whose description matches
    what they want to happen, not the one that shares the most words with what
    they typed.
  '';

  functions = {
    # ---- window focus and movement -------------------------------------
    focus_window = fn {
      summary = "Move keyboard focus to a neighbouring window";
      description = ''
        Move the keyboard focus to the window next to the current one, in a
        direction the user names. The windows themselves do not move.
      '';
      argv = [ sway "focus" "%direction%" ];
      arguments.direction = choice {
        question = "Which neighbour should take the focus?";
        options = directions;
      };
    };

    move_window = fn {
      summary = "Move the focused window within its workspace";
      description = ''
        Push the focused window itself in a direction, rearranging the tiling
        layout around it. The focus stays on the window as it moves.
      '';
      argv = [ sway "move" "%direction%" ];
      arguments.direction = choice {
        question = "Which way should the window itself be pushed?";
        options = directions;
      };
    };

    resize_window = fn {
      summary = "Make the focused window wider, narrower, taller or shorter";
      description = ''
        Change the size of the focused window, taking the space from or giving
        it back to its neighbours.
      '';
      argv = [ sway "resize" "%action%" "%axis%" "%amount%" "px" ];
      arguments = {
        action = choice {
          question = "Should the window get bigger or smaller?";
          options = {
            grow = opt "make it larger, wider, taller, expand it";
            shrink = opt "make it smaller, narrower, shorter, reduce it";
          };
        };
        axis = choice {
          question = "Is the change side to side or top to bottom?";
          options = {
            width = opt "horizontally — wider or narrower";
            height = opt "vertically — taller or shorter";
          };
          stated = "Does the command say whether the size change is horizontal or vertical?";
          default = "width";
        };
        amount = choice {
          question = "How large a change did they ask for?";
          options = {
            "50" = opt "a nudge, a little, slightly";
            "100" = opt "an ordinary step, no size mentioned";
            "300" = opt "a lot, much bigger, a big jump";
          };
          stated = "Does the command say how much bigger or smaller, such as a little or a lot?";
          default = "100";
        };
      };
    };

    close_window = fn {
      summary = "Close the focused window";
      description = ''
        Close, quit or kill the window that currently has focus. Nothing else
        is affected.
      '';
      argv = [ sway "kill" ];
    };

    set_layout = fn {
      summary = "Change how the current container arranges its windows";
      description = ''
        Switch the arrangement of the windows in the current container between
        tabs, a stack, and side-by-side or over-under splits.
      '';
      argv = [ sway "layout" "%layout%" ];
      arguments.layout = choice {
        question = "How should the windows in this container be arranged?";
        options = {
          tabbed = opt "one at a time behind a row of tabs across the top";
          stacking = opt "one at a time behind a stack of titles down the side";
          splith = opt "all visible, side by side in a row";
          splitv = opt "all visible, stacked one above another in a column";
          "toggle split" = optv [ "toggle" "split" ] "flip between the two split directions, direction unspecified";
        };
      };
    };

    toggle_window_state = fn {
      summary = "Toggle fullscreen, floating or sticky on the focused window";
      description = ''
        Turn one of the focused window's states on or off: filling the whole
        screen, floating free of the tiling layout, or sticking to the screen
        across workspace changes.
      '';
      argv = [ sway "%state%" "toggle" ];
      arguments.state = choice {
        question = "Which of the window's states should be flipped?";
        options = {
          fullscreen = opt "filling the entire screen, maximised, full screen";
          floating = opt "floating loose above the tiled windows rather than tiled with them";
          sticky = opt "pinned so it follows along to every workspace";
        };
      };
    };

    scratchpad = fn {
      summary = "Stash the focused window away, or bring a stashed one back";
      description = ''
        Hide the focused window into the scratchpad so it is out of the way,
        or pull the next hidden window back out of it.
      '';
      argv = [ sway "%action%" ];
      arguments.action = choice {
        question = "Is the user putting a window away or getting one back?";
        options = {
          show = optv [ "scratchpad" "show" ] "bring back, show, retrieve a window that was stashed";
          stash = optv [ "move" "scratchpad" ] "hide, stash, put away the window that is in the way";
        };
      };
    };

    # ---- workspaces -----------------------------------------------------
    switch_workspace = fn {
      summary = "Go to a numbered workspace";
      description = ''
        Switch the display to a workspace the user names by number. Use this
        only when a specific number is named; a request to go to the next or
        previous one is a different action.
      '';
      argv = [ sway "workspace" "number" "%workspace%" ];
      arguments.workspace = choice {
        question = "Which numbered workspace did they name?";
        options = workspaceOptions;
      };
    };

    cycle_workspace = fn {
      summary = "Go to the next or previous workspace";
      description = ''
        Step to the workspace beside the current one without naming which one
        it is — forward, back, the next one, the one before.
      '';
      argv = [ sway "workspace" "%direction%" ];
      arguments.direction = choice {
        question = "Are they going forwards or backwards through the workspaces?";
        options = {
          next = opt "forward, the next one, the one after this";
          prev = opt "back, the previous one, the one before this";
        };
      };
    };

    move_window_to_workspace = fn {
      summary = "Send the focused window to a numbered workspace";
      description = ''
        Move the focused window onto another workspace, named by number. The
        window leaves the current workspace.
      '';
      argv = [ sway "move" "container" "to" "workspace" "number" "%workspace%" ];
      arguments.workspace = choice {
        question = "Which numbered workspace should the window end up on?";
        options = workspaceOptions;
      };
    };

    move_window_to_output = fn {
      summary = "Send the focused window to another monitor";
      description = ''
        Move the one focused window onto a different screen — the other
        monitor, the external display, the one on the left. Everything else
        stays where it is.
      '';
      argv = [ sway "move" "container" "to" "output" "%direction%" ];
      arguments.direction = choice {
        question = "Which screen should the window end up on, relative to this one?";
        options = outputDirections;
      };
    };

    move_workspace_to_output = fn {
      summary = "Move the whole workspace to another monitor";
      description = ''
        Shift *everything* on the current workspace onto a different screen,
        the whole set of windows at once. A request about one window moving
        screens is a different action.
      '';
      argv = [ sway "move" "workspace" "to" "output" "%direction%" ];
      arguments.direction = choice {
        question = "Which screen should the workspace land on, relative to this one?";
        options = outputDirections;
      };
    };

    # ---- applications ---------------------------------------------------
    launch_app = fn {
      summary = "Start or focus an application";
      description = ''
        Open a program — a terminal, an editor, a browser, a file manager, a
        git or Kubernetes tool, a password manager, a system and resource
        monitor that shows what is using the CPU, memory or disk. Use this
        when the user names a piece of software, or describes a job one of
        these programs does.
      '';
      argv = [ bins.i3pm "launch" "open" "%app%" ];
      arguments.app = choice {
        question = "Which program are they asking for?";
        options = appOptions;
      };
    };

    search_apps = fn {
      summary = "Open the app launcher already searching for what they typed";
      description = ''
        Open the launcher with the user's own words in its search box. This is
        the right action when they name something to open that is not one of
        the programs listed on the other actions — a web app, a dashboard, a
        site — or when they simply ask for the launcher or a way to search.
      '';
      argv = [ bins.runtimeShell "summon" "launcher" "{\"mode\":\"apps\",\"query\":\"%text:json%\"}" ];
    };

    find_file = fn {
      summary = "Search the filesystem for a file by name";
      description = ''
        Look for a file or a folder on disk. Use this when the user is after
        something stored, not a program to run.
      '';
      argv = [ bins.runtimeShell "summon" "launcher" "{\"mode\":\"files\",\"query\":\"%text:json%\"}" ];
    };

    # ---- shell surfaces -------------------------------------------------
    open_surface = fn {
      summary = "Open one of the shell's own panels or overlays";
      description = ''
        Show a part of the desktop shell itself. This is the way to reach
        settings, the notification centre, the keyboard cheat sheet, the
        window overview, the calendar and its reminders, the audio and
        Bluetooth controls, the monitor and display arrangement, the casting
        panel, the power menu, the AI subscription usage, and Tailscale — the
        VPN, its exit nodes and the machines on the tailnet.

        The router never sees the list of panels, only this description, so a
        request naming any of those things belongs here.
      '';
      argv = [ bins.runtimeShell "toggle" "%surface%" ];
      arguments.surface = choice {
        question = "Which part of the shell do they want in front of them?";
        options = surfaceOptions;
      };
    };

    show_panel_section = fn {
      summary = "Open the monitoring panel on a particular tab";
      description = ''
        Open the runtime monitoring panel showing one of its sections —
        windows, AI coding sessions, or system health.
      '';
      # One IPC function per tab rather than a section argument: those are the
      # three the shell's IpcHandler actually exposes.
      argv = [ bins.runtimeShell "call" "%section%" ];
      arguments.section = choice {
        question = "Which part of the monitoring panel are they asking about?";
        options = {
          showWindowsTab = opt "open windows and where they are";
          showSessionsTab = opt "AI coding agent sessions and what they are doing";
          showHealthTab = opt "whether the daemon and the rest of the runtime are healthy";
        };
      };
    };

    toggle_dock_mode = fn {
      summary = "Switch the panel between floating over windows and reserving space";
      description = ''
        Change whether the monitoring panel floats above the windows or docks
        so the windows resize around it.
      '';
      argv = [ bins.toggleDockMode ];
    };

    notifications = fn {
      summary = "Open, silence or clear notifications";
      description = ''
        Act on the notification centre: show it, turn do-not-disturb on or
        off, or clear everything that has piled up.
      '';
      argv = [ "%action%" ];
      arguments.action = choice {
        question = "What should happen to the notifications?";
        options = {
          show = optv [ bins.toggleNotifications ] "show or hide the notification centre and its history";
          dnd = optv [ bins.toggleDnd ] "silence them, stop interruptions, do not disturb, or let them through again";
          clear = optv [ bins.clearNotifications ] "dismiss them all, empty the list, get rid of them";
        };
      };
    };

    # ---- audio, brightness, media ---------------------------------------
    adjust_volume = fn {
      summary = "Change the speaker volume";
      description = ''
        Turn the sound coming out of the speakers or headphones up or down, or
        mute and unmute it. Use this when no particular level is named.
      '';
      argv = [ bins.wpctl "%action%" ];
      arguments.action = choice {
        question = "What should happen to the sound coming out?";
        options = {
          up = optv [ "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@" "5%+" ] "louder, turn it up, raise it";
          down = optv [ "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-" ] "quieter, turn it down, lower it";
          mute = optv [ "set-mute" "@DEFAULT_AUDIO_SINK@" "1" ] "silence it, mute, no sound at all";
          unmute = optv [ "set-mute" "@DEFAULT_AUDIO_SINK@" "0" ] "sound again, unmute, bring it back";
        };
      };
    };

    set_volume_level = fn {
      summary = "Set the speaker volume to a particular level";
      description = ''
        Put the output volume at a level the user names — half, a quarter, all
        the way up, a specific percentage.
      '';
      argv = [ bins.wpctl "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@" "%level%%" ];
      arguments.level = choice {
        question = "How loud do they want it, as a share of the maximum?";
        options = {
          "10" = opt "very quiet, barely audible, a tenth";
          "25" = opt "quiet, a quarter of the way up";
          "50" = opt "halfway, middling, medium";
          "75" = opt "loud, three quarters";
          "100" = opt "all the way up, maximum, full volume";
        };
      };
    };

    microphone = fn {
      summary = "Mute or unmute the microphone";
      description = ''
        Stop or resume the microphone picking up sound — being heard on a call
        rather than hearing anything.
      '';
      argv = [ bins.wpctl "set-mute" "@DEFAULT_AUDIO_SOURCE@" "%action%" ];
      arguments.action = choice {
        question = "Should the microphone stop being heard, or start again?";
        options = {
          "1" = opt "mute it, silence it, stop picking me up";
          "0" = opt "unmute it, turn it back on, let me be heard";
          toggle = opt "flip whichever way it currently is";
        };
      };
    };

    adjust_brightness = fn {
      summary = "Step the screen brightness up or down";
      description = ''
        Make the screen backlight brighter or dimmer by one step, without
        naming a level.
      '';
      argv = [ bins.brightnessKey "display" "%direction%" ];
      arguments.direction = choice {
        question = "Should the screen get brighter or dimmer?";
        options = {
          up = opt "brighter, lighter, turn it up";
          down = opt "dimmer, darker, turn it down";
        };
      };
    };

    set_brightness = fn {
      summary = "Set the screen brightness to a particular level";
      description = ''
        Put the screen backlight at a level the user names, rather than
        stepping it.
      '';
      argv = [ bins.setBrightness "%level%" ];
      arguments.level = choice {
        question = "How bright do they want the screen, as a share of the maximum?";
        options = {
          "5" = opt "as dark as it goes without turning off, for a dark room";
          "25" = opt "dim, a quarter";
          "50" = opt "halfway, medium";
          "75" = opt "bright, three quarters";
          "100" = opt "as bright as it goes, maximum, full";
        };
      };
    };

    media_control = fn {
      summary = "Control whatever is playing";
      description = ''
        Act on the music, video or podcast currently playing somewhere on the
        desktop — pause it, resume it, skip on, go back.
      '';
      argv = [ bins.playerctl "%action%" ];
      arguments.action = choice {
        question = "What should happen to what is playing?";
        options = {
          play-pause = opt "pause it, resume it, stop for a moment, start again";
          next = opt "skip forward, the next track, move on";
          previous = opt "go back, the last track, play that again";
          stop = opt "stop it entirely rather than pausing";
        };
      };
    };

    # ---- capture --------------------------------------------------------
    take_screenshot = fn {
      summary = "Take a screenshot";
      description = ''
        Capture a picture of what is on screen. It is saved and copied to the
        clipboard.
      '';
      argv = [ bins.capture "screenshot" "%area%" ];
      arguments.area = choice {
        question = "How much of the screen should the picture cover?";
        options = {
          region = opt "a part of it, chosen by dragging a box";
          output = opt "the whole screen, everything, the entire display";
          window = opt "just the one window";
        };
        stated = "Does the command say how much of the screen to capture — a region, a window, or the whole thing?";
        default = "region";
      };
    };

    toggle_screen_recording = fn {
      summary = "Start or stop recording the screen";
      description = ''
        Begin capturing a video of the screen, or end one that is already
        running.
      '';
      argv = [ bins.capture "record" "toggle" ];
    };

    extract_text_from_screen = fn {
      summary = "Read the text in part of the screen and copy it";
      description = ''
        Recognise the words shown on screen — in an image, a video, a window
        that will not let text be selected — and put them on the clipboard.
      '';
      argv = [ bins.capture "ocr" "%area%" ];
      arguments.area = choice {
        question = "Where should the text be read from?";
        options = {
          region = opt "a part of the screen, chosen by dragging a box";
          output = opt "the whole screen";
        };
        stated = "Does the command say whether to read a selected region or the whole screen?";
        default = "region";
      };
    };

    pick_screen_color = fn {
      summary = "Pick a colour off the screen";
      description = ''
        Sample the colour of a pixel anywhere on screen and copy its hex code.
      '';
      argv = [ bins.capture "color" ];
    };

    scan_qr_code = fn {
      summary = "Read a QR code on screen";
      description = ''
        Decode a QR code or barcode visible on screen and copy what it says.
      '';
      argv = [ bins.capture "qr" "region" ];
    };

    # ---- appearance -----------------------------------------------------
    set_theme = fn {
      summary = "Restyle the desktop with a named colour theme";
      description = ''
        Change the whole desktop's palette to a theme the user names. Use this
        only when they name one; asking merely for light or dark is a
        different action.
      '';
      argv = [ bins.runtimeTheme "set" "%theme%" ];
      arguments.theme = choice {
        question = "Which colour theme did they name?";
        options = themeOptions;
      };
    };

    toggle_theme_mode = fn {
      summary = "Flip between the light and dark theme";
      description = ''
        Switch the desktop's *colours* between the light and the dark palette
        without naming a particular theme — light mode, dark mode, go light,
        go dark. This is about which palette is in use, never about how much
        light the screen is emitting: a complaint about brightness is the
        backlight, not the theme.
      '';
      argv = [ bins.runtimeTheme "toggle" ];
    };

    set_text_size = fn {
      summary = "Make the shell's text and controls bigger or smaller";
      description = ''
        Change the size everything in the bars and panels is drawn at, for
        readability rather than for colour.
      '';
      argv = [ bins.runtimeTheme "text-size" "%size%" ];
      arguments.size = choice {
        question = "How large should the interface text be?";
        options = {
          "10" = opt "small, compact, fit more on screen";
          "12" = opt "the normal size, back to the default";
          "14" = opt "a bit larger, easier to read";
          "17" = opt "large";
          "20" = opt "as large as it goes, much bigger, hard to see otherwise";
        };
      };
    };

    toggle_night_light = fn {
      summary = "Warm the screen colours for night, or stop";
      description = ''
        Turn on or off the warmer, redder screen tint meant for the evening.
      '';
      argv = [ bins.nightlight "%state%" ];
      arguments.state = choice {
        question = "Should the warm night tint go on or off?";
        options = {
          on = opt "warmer, redder, easier on the eyes at night";
          off = opt "back to normal colours, stop the tint";
          toggle = opt "flip whichever way it is now";
        };
        stated = "Does the command say whether to turn the night tint on or off, rather than just flip it?";
        default = "toggle";
      };
    };

    toggle_touch_mode = fn {
      summary = "Scale the touched screens up for fingers, or back down";
      description = ''
        Make the controls on any screen with a touchscreen bigger so they can
        be hit with a fingertip, or return them to their pointer sizes.
      '';
      argv = [ bins.touchMode "%state%" ];
      arguments.state = choice {
        question = "Should the finger-sized scaling go on or off?";
        options = {
          on = opt "bigger, for touching, using it as a tablet";
          off = opt "back to normal, using a mouse again";
          toggle = opt "flip whichever way it is now";
        };
        stated = "Does the command say whether to turn touch scaling on or off, rather than just flip it?";
        default = "toggle";
      };
    };

    # ---- displays and casting -------------------------------------------
    cycle_display_layout = fn {
      summary = "Move to the next monitor arrangement";
      description = ''
        Switch between the saved ways the monitors are laid out — mirrored,
        extended, one screen only.
      '';
      argv = [ bins.cycleDisplayLayout ];
    };

    cast_screen = fn {
      summary = "Send the screen to a TV, or stop";
      description = ''
        Use a Chromecast or a smart TV as a screen: mirror what is on this
        one, use it as an extra display, stop casting, or see what is on the
        network.
      '';
      argv = [ bins.cast "%action%" ];
      arguments.action = choice {
        question = "What should happen with the TV?";
        options = {
          start = opt "mirror this screen onto the TV, show the same thing there";
          extend = opt "use the TV as an additional screen with its own space on it";
          stop = opt "stop casting, disconnect, put it away";
          list = opt "which receivers or TVs can be reached at all";
        };
      };
    };

    # ---- session and system ---------------------------------------------
    lock_screen = fn {
      summary = "Lock the session";
      description = ''
        Lock the screen so a password is needed to get back in, leaving
        everything running.
      '';
      argv = [ bins.lockSession ];
    };

    power_action = fn {
      summary = "Suspend, restart, shut down or log out";
      description = ''
        End or interrupt the session at the machine level. Every one of these
        closes what is running, so they are always confirmed first.
      '';
      confirm = true;
      argv = [ "%action%" ];
      arguments.action = choice {
        question = "How far do they want to go — sleep, out of the session, or off?";
        options = {
          suspend = optv [ bins.systemctl "suspend" ] "sleep, suspend, close it up for now and come back to it";
          hibernate = optv [ bins.systemctl "hibernate" ] "hibernate, save to disk and power off";
          reboot = optv [ bins.systemctl "reboot" ] "restart, reboot, boot it again";
          poweroff = optv [ bins.systemctl "poweroff" ] "shut down, power off, turn the machine off";
          logout = optv [ sway "exit" ] "log out, end the session, leave sway";
        };
      };
    };

    reload_sway = fn {
      summary = "Reload the window manager's configuration";
      description = ''
        Make sway re-read its configuration so edited keybindings, rules and
        appearance take effect.
      '';
      argv = [ sway "reload" ];
    };

    restart_shell = fn {
      summary = "Restart the desktop shell";
      description = ''
        Restart the bars, panels and notification server when they have got
        stuck or stopped drawing. Windows and applications are untouched.
      '';
      argv = [ bins.restartShell ];
    };

    set_reminder = fn {
      summary = "Set a timer that will notify them";
      description = ''
        Raise a notification after a stretch of time the user names — remind
        me in ten minutes, tell me in an hour.
      '';
      argv = [ bins.reminder "%minutes%" "%text%" ];
      arguments.minutes = choice {
        question = "How long from now should the reminder arrive?";
        options = {
          "1" = opt "a minute, right away, very shortly";
          "5" = opt "five minutes";
          "10" = opt "ten minutes";
          "15" = opt "a quarter of an hour, fifteen minutes";
          "20" = opt "twenty minutes";
          "30" = opt "half an hour, thirty minutes";
          "45" = opt "three quarters of an hour, forty-five minutes";
          "60" = opt "an hour";
          "90" = opt "an hour and a half";
          "120" = opt "two hours";
        };
      };
    };
  };
}
