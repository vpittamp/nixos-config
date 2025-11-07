{ config, lib, pkgs, ... }:

with lib;

let
  # FZF file search script with bat preview and nvim integration
  # Based on fzf README best practices: https://github.com/junegunn/fzf
  # Opens selected file in nvim and closes search window
  fzf-file-search = pkgs.writeShellScriptBin "fzf-file-search" ''
    # Search directories: current project dir (if set), $HOME, /etc/nixos
    # I3PM_PROJECT_DIR is injected by app-launcher-wrapper.sh
    SEARCH_DIRS=()

    # Add I3PM_PROJECT_DIR if it exists and is a directory
    if [[ -n "''${I3PM_PROJECT_DIR:-}" ]] && [[ -d "$I3PM_PROJECT_DIR" ]]; then
      SEARCH_DIRS+=("$I3PM_PROJECT_DIR")
    else
      # Default to common locations
      SEARCH_DIRS+=("$HOME" "/etc/nixos")
    fi

    # Change to first search directory for relative paths
    cd "''${SEARCH_DIRS[0]}" || exit 1

    # Create wrapper script for fzf that handles file selection and terminal cleanup
    # This script runs inside Ghostty and closes the terminal after launching nvim
    FZF_WRAPPER=$(${pkgs.coreutils}/bin/mktemp)
    ${pkgs.coreutils}/bin/cat > "$FZF_WRAPPER" <<WRAPPER_EOF
#!/usr/bin/env bash
# Run fzf and capture selected file
SELECTED=\$(${pkgs.fzf}/bin/fzf \
  --walker file,follow,hidden \
  --walker-skip .git,node_modules,target,.direnv,.cache,vendor,dist,build,.next,.venv,__pycache__,.pytest_cache,.mypy_cache \
  --scheme=path \
  --height=100% \
  --layout=reverse \
  --border=rounded \
  --info=inline \
  --preview '${pkgs.bat}/bin/bat --color=always --style=numbers,changes {}' \
  --preview-window=right:60%:wrap)

# If file was selected, launch nvim in new window and close this terminal
if [[ -n "\$SELECTED" ]]; then
  ${pkgs.ghostty}/bin/ghostty -e ${pkgs.neovim}/bin/nvim "\$SELECTED" &
  exit 0
fi
WRAPPER_EOF

    ${pkgs.coreutils}/bin/chmod +x "$FZF_WRAPPER"

    # Launch Ghostty with wrapper script, then clean up temp file
    ${pkgs.ghostty}/bin/ghostty --title="FZF File Search" -e "$FZF_WRAPPER"
    ${pkgs.coreutils}/bin/rm -f "$FZF_WRAPPER"
  '';
in
{
  options = {
    modules.tools.fzf-file-search.enable = mkEnableOption "fzf file search with nvim integration";
  };

  config = mkIf config.modules.tools.fzf-file-search.enable {
    # Add script to user packages
    home.packages = [ fzf-file-search ];
  };
}
