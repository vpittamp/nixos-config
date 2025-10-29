"""
Configuration subsystem for Sway configuration management.

Modules:
- loader: Load and parse configuration files (TOML/JSON)
- validator: Validate configuration structure and semantics
- merger: Merge Nix base + runtime + project configurations
- rollback: Git-based version control and rollback
- reload_manager: Orchestrate configuration reload with two-phase commit
- file_watcher: Monitor configuration files for changes
"""

from .loader import ConfigLoader
from .validator import ConfigValidator
from .merger import ConfigMerger
from .rollback import RollbackManager
from .reload_manager import ReloadManager
from .file_watcher import FileWatcher

__all__ = [
    "ConfigLoader",
    "ConfigValidator",
    "ConfigMerger",
    "RollbackManager",
    "ReloadManager",
    "FileWatcher",
]
