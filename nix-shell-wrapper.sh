#!/usr/bin/env bash
# Wrapper for nix shell/develop to preserve terminal customization

# Save current environment
ORIG_PS1="$PS1"
ORIG_PATH="$PATH"
ORIG_STARSHIP_CONFIG="$STARSHIP_CONFIG"

# Function to restore terminal after nix shell
restore_terminal() {
    # Re-source bashrc to restore aliases and functions
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc" 2>/dev/null || true
    fi
    
    # Re-initialize terminal tools
    if command -v starship &> /dev/null; then
        eval "$(starship init bash)" 2>/dev/null || true
    fi
    
    if command -v direnv &> /dev/null; then
        eval "$(direnv hook bash)" 2>/dev/null || true
    fi
    
    if command -v zoxide &> /dev/null; then
        eval "$(zoxide init bash)" 2>/dev/null || true
    fi
    
    # Restore environment
    export STARSHIP_CONFIG="$ORIG_STARSHIP_CONFIG"
}

# Determine the command
if [ "$1" = "shell" ]; then
    shift
    echo "Entering nix shell with packages: $@"
    # Run nix shell with --impure to preserve more environment
    nix shell --impure "$@" --command bash -c "
        $(declare -f restore_terminal)
        restore_terminal
        exec bash
    "
elif [ "$1" = "develop" ]; then
    shift
    echo "Entering nix develop environment"
    # Run nix develop with --impure
    nix develop --impure "$@" --command bash -c "
        $(declare -f restore_terminal)
        restore_terminal
        exec bash
    "
else
    # Pass through to regular nix
    exec nix "$@"
fi