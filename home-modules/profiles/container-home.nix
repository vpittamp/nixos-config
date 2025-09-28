{ config, pkgs, lib, inputs, osConfig, ... }:

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

    # Tool configurations - using container-safe versions
    ../tools/git-container.nix  # Container-safe git config
    ../tools/ssh-container.nix  # Container-safe ssh config
    # ../tools/onepassword.nix  # Excluded for container
    # ../tools/onepassword-env.nix  # Excluded for container
    # ../tools/onepassword-plugins.nix  # Excluded for container
    # ../tools/onepassword-autostart.nix  # Excluded for container
    ../tools/bat.nix
    ../tools/direnv.nix
    ../tools/fzf.nix
    ../tools/k9s.nix
    ../tools/yazi.nix
    ../tools/nix.nix
    ../tools/vscode.nix
    ../tools/cluster-management.nix
    ../tools/konsole-profiles.nix

    # AI Assistant configurations
    ../ai-assistants/claude-code.nix
    ../ai-assistants/codex.nix
    ../ai-assistants/gemini-cli.nix

    # External modules (excluding 1Password)
    # inputs.onepassword-shell-plugins.hmModules.default  # Excluded for container
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

  # Enable XDG base directories and desktop entries
  xdg.enable = true;

  # Container-friendly session variables
  home.sessionVariables = {
    # Qt settings
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_ENABLE_HIGHDPI_SCALING = "1";

    # Cursor size
    XCURSOR_SIZE = "24";

    # Node.js settings for container development
    NODE_OPTIONS = "--max-old-space-size=16384";
    YARN_CACHE_FOLDER = "/home/code/.cache/yarn";
    npm_config_cache = "/home/code/.cache/npm";
  };

  # Container-specific configurations
  # Disable GUI applications that don't work in containers
  programs.chromium.enable = lib.mkForce false;
  programs.firefox.enable = lib.mkForce false;
  programs.gitkraken.enable = lib.mkForce false;
}