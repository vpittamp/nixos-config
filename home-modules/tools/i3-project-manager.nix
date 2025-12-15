{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.i3pm;

  # Python package with i3pm and all dependencies
  i3pmPackage = pkgs.python3Packages.buildPythonApplication {
    pname = "i3-project-manager";
    version = "0.4.0";  # Feature 117: ai_sessions lifecycle tracking

    # Source is the tools directory containing both pyproject.toml and i3_project_manager/
    src = ./.;

    format = "pyproject";

    propagatedBuildInputs = with pkgs.python3Packages; [
      # Core TUI/CLI dependencies
      textual
      rich
      i3ipc
      argcomplete
      setuptools

      # Phase 7: Schema validation (T095)
      jsonschema

      # Layout management dependencies (Feature 022)
      psutil

      # Feature 025: Data validation (Pydantic models)
      pydantic

      # Phase 6: Window inspector dependencies
      # xdotool and xprop provided via buildInputs (system packages)
    ];

    # System dependencies for window inspection and Xvfb detection (T042, T098)
    buildInputs = with pkgs; [
      xdotool      # Window selection for inspector
      xorg.xprop   # Window property extraction
      xvfb-run     # Virtual framebuffer for app detection
    ];

    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    checkInputs = with pkgs.python3Packages; [
      pytest
      pytest-asyncio
      pytest-cov
      pytest-textual  # Phase 6: TUI testing
    ];

    # Skip tests during Nix build (Phase 2 - run tests manually for now)
    # TODO: Enable after setting up proper test data directory structure
    doCheck = false;

    meta = with lib; {
      description = "Unified CLI/TUI for i3 window manager project management";
      homepage = "https://github.com/vpittamp/nixos";
      license = licenses.mit;
      maintainers = [];
      platforms = platforms.linux;
    };
  };

in {
  options.programs.i3pm = {
    enable = mkEnableOption "i3 Project Manager (i3pm)";

    package = mkOption {
      type = types.package;
      default = i3pmPackage;
      defaultText = literalExpression "pkgs.i3-project-manager";
      description = "The i3pm package to use.";
    };

    enableBashIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable bash completion for i3pm.";
    };

    enableZshIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable zsh completion for i3pm.";
    };

    enableFishIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fish completion for i3pm.";
    };
  };

  config = mkIf cfg.enable {
    # Install i3pm package
    home.packages = [ cfg.package ];

    # Bash completion and aliases
    programs.bash.initExtra = mkIf cfg.enableBashIntegration ''
      # i3pm shell completion (only if argcomplete is available)
      if command -v register-python-argcomplete &> /dev/null; then
        eval "$(register-python-argcomplete i3pm)"
      fi

      # Backward compatibility aliases (replace old bash scripts)
      # Feature 072 fix: Close preview window before switching projects
      alias i3-project-switch='i3pm-workspace-mode cancel 2>/dev/null; i3pm switch'
      alias i3-project-current='i3pm current'
      alias i3-project-clear='i3pm clear'
      alias i3-project-list='i3pm list'
      alias i3-project-create='i3pm create'
      alias i3-project-show='i3pm show'
      alias i3-project-edit='i3pm edit'
      alias i3-project-delete='i3pm delete'

      # Short aliases
      # Feature 072 fix: Close preview window before switching projects
      alias pswitch='i3pm-workspace-mode cancel 2>/dev/null; i3pm switch'
      alias pcurrent='i3pm current'
      alias pclear='i3pm clear'
      alias plist='i3pm list'
    '';

    # Zsh completion and aliases
    programs.zsh.initExtra = mkIf cfg.enableZshIntegration ''
      # i3pm shell completion (only if argcomplete is available)
      if command -v register-python-argcomplete &> /dev/null; then
        autoload -U bashcompinit
        bashcompinit
        eval "$(register-python-argcomplete i3pm)"
      fi

      # Backward compatibility aliases
      # Feature 072 fix: Close preview window before switching projects
      alias i3-project-switch='i3pm-workspace-mode cancel 2>/dev/null; i3pm switch'
      alias i3-project-current='i3pm current'
      alias i3-project-clear='i3pm clear'
      alias i3-project-list='i3pm list'
      alias i3-project-create='i3pm create'
      alias i3-project-show='i3pm show'
      alias i3-project-edit='i3pm edit'
      alias i3-project-delete='i3pm delete'
      # Feature 072 fix: Close preview window before switching projects
      alias pswitch='i3pm-workspace-mode cancel 2>/dev/null; i3pm switch'
      alias pcurrent='i3pm current'
      alias pclear='i3pm clear'
      alias plist='i3pm list'
    '';

    # Fish completion and aliases
    programs.fish.interactiveShellInit = mkIf cfg.enableFishIntegration ''
      # i3pm shell completion
      register-python-argcomplete --shell fish i3pm | source

      # Backward compatibility aliases
      # Feature 072 fix: Close preview window before switching projects
      alias i3-project-switch='i3pm-workspace-mode cancel 2>/dev/null; i3pm switch'
      alias i3-project-current='i3pm current'
      alias i3-project-clear='i3pm clear'
      alias i3-project-list='i3pm list'
      alias i3-project-create='i3pm create'
      alias i3-project-show='i3pm show'
      alias i3-project-edit='i3pm edit'
      alias i3-project-delete='i3pm delete'
      # Feature 072 fix: Close preview window before switching projects
      alias pswitch='i3pm-workspace-mode cancel 2>/dev/null; i3pm switch'
      alias pcurrent='i3pm current'
      alias pclear='i3pm clear'
      alias plist='i3pm list'
    '';

    # Ensure daemon is available (dependency on i3-project-event-listener)
    # Note: The daemon is managed by systemd user service (Feature 015)
    # This module just installs the i3pm CLI/TUI that communicates with it

    # Create config directories if they don't exist
    home.activation.i3pmSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p ~/.config/i3/projects
      $DRY_RUN_CMD mkdir -p ~/.config/i3/layouts
      $DRY_RUN_CMD mkdir -p ~/.cache/i3pm

      # Create default app-classes.json if it doesn't exist
      if [ ! -f ~/.config/i3/app-classes.json ]; then
        $DRY_RUN_CMD cat > ~/.config/i3/app-classes.json << 'EOF'
{
  "scoped_classes": ["Ghostty", "Code", "neovide"],
  "global_classes": ["firefox", "Google-chrome", "mpv", "vlc"],
  "class_patterns": {
    "pwa-": "global",
    "terminal": "scoped",
    "editor": "scoped"
  }
}
EOF
      fi
    '';
  };
}
