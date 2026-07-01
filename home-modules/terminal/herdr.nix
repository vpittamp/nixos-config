{ pkgs, lib, inputs, ... }:

let
  scriptWrappers = import ../../shared/script-wrappers.nix { inherit pkgs lib; };
  clipboardSyncScript = "${scriptWrappers.clipboard-sync}/bin/clipboard-sync";
  clipcatFzfScript = "${scriptWrappers.clipcat-fzf}/bin/clipcat-fzf";
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  herdrFilePicker = pkgs.writeShellScriptBin "herdr-file-picker" ''
    set -euo pipefail

    file="$(${pkgs.fd}/bin/fd --type f --hidden --exclude .git . 2>/dev/null \
      | ${pkgs.fzf}/bin/fzf \
          --preview='${pkgs.bat}/bin/bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null || ${pkgs.coreutils}/bin/head -200 {}')"

    if [ -n "$file" ]; then
      printf "%s" "$file" | ${clipboardSyncScript}
      printf "Copied: %s\n" "$file"
      sleep 1
    fi
  '';
in
{
  home.activation.ensureOptionalHerdrIntegrations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/.copilot" ]; then
      run ${herdrPackage}/bin/herdr integration install copilot || true
    fi
    if [ -d "$HOME/.config/opencode" ]; then
      run ${herdrPackage}/bin/herdr integration install opencode || true
    fi
  '';

  xdg.configFile."herdr/config.toml" = {
    force = true;
    # Reload the running herdr server when this config changes, so a long-lived
    # server doesn't keep serving (and re-diagnosing) a stale in-memory config
    # after a switch — e.g. re-emitting the prefix+shift+h keybind warning even
    # though the fix is already on disk. No-op when no server is running.
    onChange = ''
      ${herdrPackage}/bin/herdr server reload-config >/dev/null 2>&1 || true
    '';
    text = ''
    # Managed by Home Manager. Edit home-modules/terminal/herdr.nix.
    onboarding = false

    [theme]
    name = "terminal"

    [terminal]
    default_shell = "${pkgs.bashInteractive}/bin/bash"
    shell_mode = "non_login"
    new_cwd = "follow"

    [keys]
    prefix = "backtick"

    help = "prefix+?"
    settings = "prefix+s"
    detach = "prefix+q"
    reload_config = "prefix+shift+r"
    open_notification_target = "prefix+o"

    workspace_picker = "prefix+w"
    goto = "prefix+g"
    new_workspace = "prefix+shift+n"
    new_worktree = "prefix+ctrl+g"
    rename_workspace = "prefix+shift+w"
    close_workspace = "prefix+alt+d"

    new_tab = "prefix+c"
    rename_tab = "prefix+shift+t"
    previous_tab = "prefix+p"
    next_tab = "prefix+n"
    switch_tab = "alt+1..9"
    close_tab = "prefix+shift+x"

    rename_pane = "prefix+shift+p"
    edit_scrollback = "prefix+e"
    focus_pane_left = "ctrl+h"
    focus_pane_down = "ctrl+j"
    focus_pane_up = "ctrl+k"
    focus_pane_right = "ctrl+l"
    cycle_pane_next = "prefix+tab"
    cycle_pane_previous = "prefix+shift+tab"
    last_pane = "prefix+backspace"
    split_vertical = "prefix+v"
    split_horizontal = "prefix+minus"
    close_pane = "prefix+x"
    zoom = "prefix+z"
    resize_mode = "prefix+r"
    toggle_sidebar = "prefix+b"

    navigate_pane_left = "h"
    navigate_pane_down = "j"
    navigate_pane_up = "k"
    navigate_pane_right = "l"

    # Unbind the built-in pane-swap actions. Their defaults are
    # prefix+shift+h / prefix+shift+l, and prefix+shift+h collides with the
    # btop launcher below — herdr resolves the clash by keeping swap_pane_left
    # and silently disabling the command (logged as "config diagnostic
    # prefix+shift+h: kept keys.swap_pane_left, disabled keys.command[1].key").
    # We don't use pane-swap (focus_pane/navigate_pane/cycle_pane cover pane
    # management), so unbind both to free the prefix+shift launcher row and
    # clear the warning. Bind them to real keys here if pane-swap is wanted.
    swap_pane_left = ""
    swap_pane_right = ""

    [[keys.command]]
    key = "prefix+shift+g"
    type = "pane"
    command = "${pkgs.lazygit}/bin/lazygit"

    [[keys.command]]
    key = "prefix+shift+h"
    type = "pane"
    command = "${pkgs.bash}/bin/bash -lc '${pkgs.btop}/bin/btop || ${pkgs.htop}/bin/htop || top'"

    [[keys.command]]
    key = "prefix+shift+d"
    type = "pane"
    command = "${pkgs.bash}/bin/bash -lc '${pkgs.lazydocker}/bin/lazydocker || docker ps -a'"

    [[keys.command]]
    key = "prefix+shift+f"
    type = "pane"
    command = "${herdrFilePicker}/bin/herdr-file-picker"

    [[keys.command]]
    key = "prefix+shift+q"
    type = "pane"
    command = "${clipcatFzfScript}"

    [ui]
    agent_panel_scope = "all"
    show_agent_labels_on_pane_borders = true
    # Capture normal mouse input in Herdr so wheel events scroll pane history
    # instead of being forwarded to agent TUIs. Codex treats forwarded wheel
    # events as prompt-history navigation, which makes review of long sessions
    # effectively impossible. Use Shift+mouse for the outer terminal's native
    # selection/context-menu behavior when needed.
    mouse_capture = true
    mouse_scroll_lines = 1
    prompt_new_tab_name = false
    accent = "cyan"

    [ui.toast]
    delivery = "system"
    delay_seconds = 1

    [ui.sound]
    enabled = false

    [session]
    resume_agents_on_restore = true

    [remote]
    manage_ssh_config = true

    [experimental]
    pane_history = true
    '';
  };
}
