{ config, pkgs, ... }:

# Feature 034: Unified Application Launcher - Wrapper Scripts
#
# This module installs the unified launcher bundle and the terminal helpers it
# dispatches to. They must live in one package because the wrapper resolves its
# managed tmux helpers relative to its own script directory.

let
  # Launcher wrapper script (bash)
  # Feature 117: Socket path for user service daemon
  # User socket at XDG_RUNTIME_DIR with fallback to system socket
  daemonSocketPath = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock";

  wrapperScriptFile = builtins.toFile "app-launcher-wrapper" (
    builtins.replaceStrings
      [ "@DAEMON_SOCKET@" ]
      [ daemonSocketPath ]
      (builtins.readFile ../../scripts/app-launcher-wrapper.sh)
  );

  launcher-package = pkgs.runCommandLocal "app-launcher-bundle" { } (
    ''
      mkdir -p "$out/bin"

      install -m755 ${wrapperScriptFile} "$out/bin/app-launcher-wrapper"
      install -m755 ${../../scripts/project-terminal-launch.sh} "$out/bin/project-terminal-launch.sh"
      install -m755 ${../../scripts/devenv-terminal-launch.sh} "$out/bin/devenv-terminal-launch.sh"
      install -m755 ${../../scripts/managed-tmux-session.sh} "$out/bin/managed-tmux-session.sh"
    ''
  );

in
{
  home.packages = [
    launcher-package
  ];

  # Install wrapper script to standard location
  # This ensures it's accessible from desktop files
  home.file.".local/bin/app-launcher-wrapper.sh" = {
    source = "${launcher-package}/bin/app-launcher-wrapper";
    executable = true;
  };

  # Install terminal launch helpers for direct invocation and debugging.
  home.file.".local/bin/devenv-terminal-launch.sh" = {
    source = "${launcher-package}/bin/devenv-terminal-launch.sh";
    executable = true;
  };

  home.file.".local/bin/project-terminal-launch.sh" = {
    source = "${launcher-package}/bin/project-terminal-launch.sh";
    executable = true;
  };

  home.file.".local/bin/managed-tmux-session.sh" = {
    source = "${launcher-package}/bin/managed-tmux-session.sh";
    executable = true;
  };

  # Note: .local/state directory is created by other modules
}
