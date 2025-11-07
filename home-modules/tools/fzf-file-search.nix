{ config, lib, pkgs, ... }:

with lib;

let
  # FZF file search script with bat preview and nvim integration
  # Based on fzf README best practices: https://github.com/junegunn/fzf
  # Uses --bind 'enter:become(nvim {})' to open selected file
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

    # Launch in floating ghostty window with fzf
    # Uses fzf's built-in walker for fast file traversal
    # --bind 'enter:become(nvim {})' directly opens file in nvim (fzf README pattern)
    # Note: --title is used for Sway window rule matching (Ghostty's app_id is always com.mitchellh.ghostty)
    exec ${pkgs.ghostty}/bin/ghostty \
      --title="FZF File Search" \
      -e ${pkgs.fzf}/bin/fzf \
        --walker file,follow,hidden \
        --walker-skip .git,node_modules,target,.direnv,.cache,vendor,dist,build,.next,.venv,__pycache__,.pytest_cache,.mypy_cache \
        --scheme=path \
        --height=100% \
        --layout=reverse \
        --border=rounded \
        --info=inline \
        --preview '${pkgs.bat}/bin/bat --color=always --style=numbers,changes {}' \
        --preview-window=right:60%:wrap \
        --bind 'enter:become(${pkgs.ghostty}/bin/ghostty -e ${pkgs.neovim}/bin/nvim {})'
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
