{ config, pkgs, lib, inputs, ... }:

let
  # Darwin doesn't have osConfig from NixOS
  # Use fallback values for session configuration
  sessionConfig = {
    # Cursor size for macOS (HiDPI aware)
    XCURSOR_SIZE = "32";

    # UV (Python package manager) configuration for Darwin
    # Use system Python on macOS with nix-darwin
    UV_PYTHON_PREFERENCE = "only-system";
    UV_PYTHON = "${pkgs.python3}/bin/python3";

    # Note: SSH_AUTH_SOCK for 1Password is set in onepassword-env.nix
    # which handles both Linux and Darwin paths automatically
  };
in
{
  imports = [
    # Shell configurations (cross-platform)
    ../shell/bash.nix
    ../shell/starship.nix
    ../shell/colors.nix

    # Terminal configurations (cross-platform)
    ../terminal/tmux.nix
    ../terminal/sesh.nix
    ../terminal/iterm2.nix  # iTerm2 declarative profile (Darwin-only)

    # Editor configurations (cross-platform)
    ../editors/neovim.nix

    # Tool configurations (cross-platform compatible)
    ../tools/git.nix
    ../tools/ssh.nix
    ../tools/onepassword.nix
    ../tools/onepassword-env.nix
    ../tools/onepassword-plugins.nix
    # Note: onepassword-autostart.nix is Linux-specific (uses systemd)
    ../tools/bat.nix
    ../tools/direnv.nix
    ../tools/fzf.nix
    # Note: chromium.nix may have Linux-specific configs - excluded
    # Note: firefox.nix has xdg.mimeApps (Linux-only) - excluded
    ../tools/docker.nix # Docker with 1Password (works on macOS with Docker Desktop)
    ../tools/k9s.nix
    ../tools/yazi.nix
    ../tools/nix.nix

    # AI Assistant configurations (cross-platform)
    # Platform guards ensure only compatible MCP servers are enabled
    ../ai-assistants/claude-code.nix
    ../ai-assistants/codex.nix
    ../ai-assistants/gemini-cli.nix

    # VSCode with AI extensions
    ../tools/vscode.nix

    # Note: gitkraken.nix has xdg.desktopEntries (Linux-only) - excluded
    # Note: kubernetes-apps.nix has xdg.desktopEntries (Linux-only) - excluded

    # External modules (cross-platform)
    inputs.onepassword-shell-plugins.hmModules.default
  ];

  home.stateVersion = "25.05";
  home.enableNixpkgsReleaseCheck = false;

  home.packages =
    let
      # Import user packages (need to handle potential Linux-specific packages)
      userPackages = import ../../user/packages.nix { inherit pkgs lib; };
      packageConfig = import ../../shared/package-lists.nix { inherit pkgs lib; };
      basePackages = lib.filter (pkg: pkg.meta.available or true) (packageConfig.getProfile.user);
      darwinSpecificPackages = [
        pkgs._1password-cli  # 1Password CLI for macOS
      ];
    in
    basePackages ++ darwinSpecificPackages;

  # Yazi file manager
  modules.tools.yazi.enable = true;

  # Docker configuration (works with Docker Desktop on macOS)
  modules.tools.docker.enable = lib.mkDefault true;

  # VSCode profile configuration
  modules.tools.vscode.defaultProfile = lib.mkDefault "default";

  # iTerm2 declarative configuration (Darwin-only)
  programs.iterm2 = {
    enable = true;
    profileName = "NixOS Catppuccin";
    font = {
      name = "MesloLGS-NF-Regular";
      size = 14;
    };
    unlimitedScrollback = true;
    transparency = 0.0;
    blur = false;
  };

  programs.home-manager.enable = true;

  # Enable XDG base directories (macOS compatible, but skip Linux-only modules)
  # Note: xdg.mimeApps and xdg.desktopEntries are Linux-only
  xdg = {
    enable = true;
    # Don't configure mimeApps on Darwin - it's Linux-only
    # Don't use desktopEntries on Darwin - they're Linux-only
  };

  home.sessionVariables = sessionConfig;

  # Create stable bash symlink for use with chsh
  # This ensures we can set a persistent default shell that doesn't change with Nix store paths
  home.activation.createBashSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.local/bin"
    $DRY_RUN_CMD ln -sf "${pkgs.bashInteractive}/bin/bash" "$HOME/.local/bin/bash"

    # Check if already in /etc/shells
    if ! grep -q "^$HOME/.local/bin/bash$" /etc/shells 2>/dev/null; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📌 To set Nix bash 5.3 as your default shell, run:"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  sudo sh -c 'echo \"$HOME/.local/bin/bash\" >> /etc/shells'"
      echo "  chsh -s $HOME/.local/bin/bash"
      echo ""
      echo "Current shell: $(dscl . -read ~/ UserShell | awk '{print $2}')"
      echo "Nix bash version: ${pkgs.bashInteractive.version}"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
    fi
  '';

  # macOS-specific configurations
  # Note: macOS uses launchd instead of systemd, so services need to be configured differently
  # 1Password GUI and CLI auto-start should be handled by macOS login items
  # File associations are managed by macOS, not XDG on Darwin
}
