{ config, pkgs, ... }:

# Feature 034: Unified Application Launcher - Wrapper Scripts
#
# This module:
# - Installs the launcher wrapper script
# - Installs the devenv-aware terminal launcher helper

let
  # Launcher wrapper script (bash)
  # Feature 117: Socket path for user service daemon
  # User socket at XDG_RUNTIME_DIR with fallback to system socket
  daemonSocketPath = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-project-daemon/ipc.sock";

  wrapper-script = pkgs.writeScriptBin "app-launcher-wrapper" (
    let
      scriptContent = builtins.readFile ../../scripts/app-launcher-wrapper.sh;
    in
    # Substitute @DAEMON_SOCKET@ placeholder with actual path
    builtins.replaceStrings
      [ "@DAEMON_SOCKET@" ]
      [ daemonSocketPath ]
      scriptContent
  );

  # Devenv-aware terminal launcher script
  devenv-terminal-launch-script = pkgs.writeScriptBin "devenv-terminal-launch" (
    builtins.readFile ../../scripts/devenv-terminal-launch.sh
  );

in
{
  home.packages = [
    wrapper-script
    devenv-terminal-launch-script
  ];

  # Install wrapper script to standard location
  # This ensures it's accessible from desktop files
  home.file.".local/bin/app-launcher-wrapper.sh" = {
    source = "${wrapper-script}/bin/app-launcher-wrapper";
    executable = true;
  };

  # Install devenv-aware terminal launcher
  home.file.".local/bin/devenv-terminal-launch.sh" = {
    source = "${devenv-terminal-launch-script}/bin/devenv-terminal-launch";
    executable = true;
  };

  # Note: .local/state directory is created by other modules
}
