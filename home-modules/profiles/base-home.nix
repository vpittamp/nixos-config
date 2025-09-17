{ config, pkgs, lib, inputs, osConfig, ... }:

let
  hostName = if osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else null;
  isM1 = hostName == "nixos-m1";
  sessionConfig = {
    GDK_DPI_SCALE = if isM1 then "0.5" else "1.0";
    QT_AUTO_SCREEN_SCALE_FACTOR = "0";
    QT_ENABLE_HIGHDPI_SCALING = "0";
    PLASMA_USE_QT_SCALING = "1";
    GDK_SCALE = if isM1 then "2" else "1";
    XCURSOR_SIZE = if isM1 then "48" else "28";
  };
in
{
  imports = [
    # Shell configurations
    ../shell/bash.nix
    ../shell/starship.nix
    ../shell/colors.nix

    # Terminal configurations
    ../terminal/tmux.nix
    ../terminal/sesh.nix

    # Editor configurations
    ../editors/neovim.nix

    # Tool configurations
    ../tools/git.nix
    ../tools/ssh.nix
    ../tools/onepassword.nix
    ../tools/onepassword-env.nix
    ../tools/onepassword-plugins.nix
    ../tools/onepassword-autostart.nix
    ../tools/bat.nix
    ../tools/direnv.nix
    ../tools/fzf.nix
    ../tools/chromium.nix
    ../tools/k9s.nix
    ../tools/yazi.nix
    ../tools/nix.nix
    ../tools/vscode.nix
    ../tools/gitkraken.nix
    ../tools/cluster-management.nix

    # AI Assistant configurations
    ../ai-assistants/claude-code.nix
    ../ai-assistants/codex.nix
    ../ai-assistants/gemini-cli.nix

    # External modules
    inputs.onepassword-shell-plugins.hmModules.default
  ];

  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;

  home.packages = let
    userPackages = import ../../user/packages.nix { inherit pkgs lib; };
    packageConfig = import ../../shared/package-lists.nix { inherit pkgs lib; };
  in
    packageConfig.getProfile.user ++ [ pkgs.papirus-icon-theme ];

  modules.tools.yazi.enable = true;

  programs.home-manager.enable = true;

  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
  };

  home.sessionVariables = sessionConfig;
}
