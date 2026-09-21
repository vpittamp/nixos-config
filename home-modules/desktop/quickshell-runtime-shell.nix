{ config, lib, ... }:

{
  imports = [
    ./quickshell-runtime-shell/default.nix
    ./jev-commands
  ];

  # The command bar is part of the shell, not a separate opt-in: the surface,
  # its keybindings and its `jevBin` all ship with the shell, and a shell whose
  # command bar cannot dispatch would be a dead key.
  programs.jev-commands.enable =
    lib.mkDefault config.programs.quickshell-runtime-shell.enable;

  # The house is on the tailnet, so any of these machines can drive it from the
  # same command bar that drives the desktop.
  programs.jev-commands.homeAssistant = {
    enable = lib.mkDefault config.programs.quickshell-runtime-shell.enable;
    url = lib.mkDefault "http://surface-pro.tail286401.ts.net:8123";
  };
}
