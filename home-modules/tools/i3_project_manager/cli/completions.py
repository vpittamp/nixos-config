"""Shell completion support for i3pm CLI.

Provides dynamic completion for project names, layout names, and other arguments
using argcomplete library for both bash and zsh.
"""

import os
from pathlib import Path
from typing import List, Optional
import time

# Cache configuration
CACHE_DIR = Path.home() / ".cache/i3pm"
PROJECT_CACHE_FILE = CACHE_DIR / "project-list.txt"
CACHE_TTL = 60  # seconds


def _get_cached_projects() -> Optional[List[str]]:
    """Get cached project names if cache is fresh.

    Returns:
        List of project names if cache is valid, None otherwise
    """
    if not PROJECT_CACHE_FILE.exists():
        return None

    # Check cache age
    cache_age = time.time() - PROJECT_CACHE_FILE.stat().st_mtime
    if cache_age > CACHE_TTL:
        return None

    # Read cached project names
    try:
        with PROJECT_CACHE_FILE.open() as f:
            return [line.strip() for line in f if line.strip()]
    except Exception:
        return None


def _update_project_cache(project_names: List[str]) -> None:
    """Update the project name cache.

    Args:
        project_names: List of project names to cache
    """
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        with PROJECT_CACHE_FILE.open("w") as f:
            f.write("\n".join(project_names))
    except Exception:
        pass  # Fail silently if cache write fails


def complete_project_names(prefix: str, parsed_args, **kwargs) -> List[str]:
    """Completer for project names.

    Args:
        prefix: The prefix being completed
        parsed_args: Parsed argparse arguments
        **kwargs: Additional arguments from argcomplete

    Returns:
        List of matching project names
    """
    # Try to get from cache first
    projects = _get_cached_projects()

    if projects is None:
        # Load projects from disk
        from i3_project_manager.core.models import Project

        try:
            all_projects = Project.list_all()
            projects = [p.name for p in all_projects]

            # Update cache
            _update_project_cache(projects)
        except Exception:
            # If loading fails, return empty list
            return []

    # Filter by prefix
    if prefix:
        return [p for p in projects if p.startswith(prefix)]
    return projects


def complete_layout_names(prefix: str, parsed_args, **kwargs) -> List[str]:
    """Completer for layout names for a specific project.

    Args:
        prefix: The prefix being completed
        parsed_args: Parsed argparse arguments
        **kwargs: Additional arguments from argcomplete

    Returns:
        List of matching layout names
    """
    # Get project name from parsed args
    project_name = getattr(parsed_args, "project_name", None)
    if not project_name:
        return []

    # Get layout names for project
    layouts_dir = Path.home() / ".config/i3/layouts" / project_name
    if not layouts_dir.exists():
        return []

    try:
        layout_files = layouts_dir.glob("*.json")
        layout_names = [f.stem for f in layout_files]

        # Filter by prefix
        if prefix:
            return [name for name in layout_names if name.startswith(prefix)]
        return layout_names
    except Exception:
        return []


def generate_bash_completion() -> str:
    """Generate bash completion script.

    Returns:
        Bash completion script as string
    """
    return """# i3pm bash completion
# Add this to ~/.bashrc or /etc/bash_completion.d/i3pm

_i3pm_completion() {
    local IFS=$'
'
    COMPREPLY=( $(COMP_WORDS="${COMP_WORDS[*]}" \\
                   COMP_CWORD=$COMP_CWORD \\
                   _ARGCOMPLETE=1 \\
                   _ARGCOMPLETE_SHELL=bash \\
                   i3pm 8>&1 9>&2 2>/dev/null) )
}

complete -o nospace -o default -F _i3pm_completion i3pm
"""


def generate_zsh_completion() -> str:
    """Generate zsh completion script.

    Returns:
        Zsh completion script as string
    """
    return """#compdef i3pm
# i3pm zsh completion
# Add this to ~/.zshrc or a file in $fpath

_i3pm_completion() {
    local IFS=$'
'
    local reply
    _ARGCOMPLETE=1 _ARGCOMPLETE_SHELL=zsh i3pm "$@" 2>/dev/null | while IFS= read -r line; do
        reply+=("$line")
    done
    compadd -Q -a reply
}

compdef _i3pm_completion i3pm
"""


def install_completions(shell: str) -> None:
    """Install completion script for the specified shell.

    Args:
        shell: Shell type ("bash" or "zsh")
    """
    if shell == "bash":
        completion_script = generate_bash_completion()
        completion_file = Path.home() / ".bash_completion.d/i3pm"

        # Create directory if needed
        completion_file.parent.mkdir(parents=True, exist_ok=True)

        # Write completion script
        completion_file.write_text(completion_script)

        print(f"Bash completion installed to {completion_file}")
        print("Add this to your ~/.bashrc if not already present:")
        print("  source ~/.bash_completion.d/i3pm")

    elif shell == "zsh":
        completion_script = generate_zsh_completion()
        completion_file = Path.home() / ".zsh/completions/_i3pm"

        # Create directory if needed
        completion_file.parent.mkdir(parents=True, exist_ok=True)

        # Write completion script
        completion_file.write_text(completion_script)

        print(f"Zsh completion installed to {completion_file}")
        print("Add this to your ~/.zshrc if not already present:")
        print(f"  fpath=(~/.zsh/completions $fpath)")
        print("  autoload -Uz compinit && compinit")

    else:
        raise ValueError(f"Unsupported shell: {shell}")
