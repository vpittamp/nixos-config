"""
Lazygit Handler for Feature 109: Enhanced Worktree User Experience

Provides context-aware launching of lazygit for worktrees with automatic
view selection based on worktree state.

T003: Skeleton creation
T008: LazyGitContext model
T023: LazyGitContext.to_command_args()
T024: View selection rules
T026: Lazygit launch IPC method
"""

from __future__ import annotations

import logging
import subprocess
from enum import Enum
from typing import TYPE_CHECKING, List, Optional

from pydantic import BaseModel, Field

if TYPE_CHECKING:
    from ..worktree_utils import ParsedQualifiedName

logger = logging.getLogger(__name__)


class LazyGitView(str, Enum):
    """Available lazygit views/panels.

    Per contracts/lazygit-context.json.
    """
    STATUS = "status"
    BRANCH = "branch"
    LOG = "log"
    STASH = "stash"


class LazyGitContext(BaseModel):
    """Context for launching lazygit in a specific state.

    T008: Model per data-model.md specification.

    Attributes:
        working_directory: Absolute path to the worktree directory
        initial_view: Which lazygit panel to focus on launch
        filter_path: Optional path filter for commits (--filter argument)
    """
    working_directory: str = Field(
        ...,
        description="Absolute path to worktree directory",
        pattern="^/.*$"
    )
    initial_view: LazyGitView = Field(
        default=LazyGitView.STATUS,
        description="Which lazygit panel to focus on launch"
    )
    filter_path: Optional[str] = Field(
        default=None,
        description="Optional path filter for commits"
    )

    def to_command_args(self) -> List[str]:
        """Generate lazygit CLI arguments.

        T023: Per research.md, uses lazygit --path <dir> <view> pattern.

        Returns:
            List of command arguments ready for subprocess execution
        """
        args = ["lazygit", "--path", self.working_directory]
        if self.filter_path:
            args.extend(["--filter", self.filter_path])
        args.append(self.initial_view.value)
        return args

    def to_command_string(self) -> str:
        """Generate lazygit command string for shell execution.

        Returns:
            Space-separated command string
        """
        return " ".join(self.to_command_args())


class LazyGitLaunchReason(str, Enum):
    """Reason for launching lazygit - affects default view selection.

    Per contracts/lazygit-context.json view_selection_rules.
    """
    USER_ACTION = "user_action"
    DIRTY_INDICATOR = "dirty_indicator"
    SYNC_INDICATOR = "sync_indicator"
    CONFLICT_INDICATOR = "conflict_indicator"


def select_view_for_context(
    is_dirty: bool = False,
    is_behind: bool = False,
    has_conflicts: bool = False,
    reason: LazyGitLaunchReason = LazyGitLaunchReason.USER_ACTION
) -> LazyGitView:
    """Select appropriate lazygit view based on worktree context.

    T024: View selection rules per contracts/lazygit-context.json.

    Args:
        is_dirty: Worktree has uncommitted changes
        is_behind: Worktree is behind remote
        has_conflicts: Worktree has merge conflicts
        reason: Why lazygit is being launched

    Returns:
        Appropriate LazyGitView for the context
    """
    # Conflicts take priority - need to resolve in status view
    if has_conflicts or reason == LazyGitLaunchReason.CONFLICT_INDICATOR:
        logger.debug("[Feature 109] Selecting status view for conflicts")
        return LazyGitView.STATUS

    # Dirty state - show status to stage/commit
    if is_dirty or reason == LazyGitLaunchReason.DIRTY_INDICATOR:
        logger.debug("[Feature 109] Selecting status view for dirty worktree")
        return LazyGitView.STATUS

    # Behind remote - show branches to sync
    if is_behind or reason == LazyGitLaunchReason.SYNC_INDICATOR:
        logger.debug("[Feature 109] Selecting branch view for sync")
        return LazyGitView.BRANCH

    # Default: status view
    logger.debug("[Feature 109] Selecting default status view")
    return LazyGitView.STATUS


class LazyGitLauncher:
    """Service for launching lazygit with worktree context.

    T026: IPC method implementation.
    """

    def __init__(self, terminal: str = "ghostty"):
        """Initialize launcher with terminal preference.

        Args:
            terminal: Terminal emulator to use (default: ghostty per plan.md)
        """
        self.terminal = terminal

    def launch(self, context: LazyGitContext) -> dict:
        """Launch lazygit in a new terminal with the given context.

        Per contracts/lazygit-context.json: Always spawns new instance.

        Args:
            context: LazyGitContext with working_directory and initial_view

        Returns:
            Dict with success, pid, command, and optional error keys
        """
        command_args = context.to_command_args()
        command_str = context.to_command_string()

        logger.info(
            f"[Feature 109] Launching lazygit in {context.working_directory} "
            f"with view: {context.initial_view.value}"
        )

        try:
            # Build terminal command
            if self.terminal == "ghostty":
                full_cmd = [self.terminal, "-e", "bash", "-c", command_str]
            elif self.terminal == "alacritty":
                full_cmd = [self.terminal, "-e", "bash", "-c", command_str]
            elif self.terminal == "kitty":
                full_cmd = [self.terminal, "bash", "-c", command_str]
            else:
                # Generic fallback
                full_cmd = [self.terminal, "-e", "bash", "-c", command_str]

            # Launch process (detached)
            process = subprocess.Popen(
                full_cmd,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            return {
                "success": True,
                "pid": process.pid,
                "command": " ".join(full_cmd)
            }

        except (OSError, subprocess.SubprocessError) as e:
            logger.error(f"[Feature 109] Failed to launch lazygit: {e}")
            return {
                "success": False,
                "pid": None,
                "command": " ".join([self.terminal, "-e", *command_args]),
                "error": str(e)
            }

    def launch_for_worktree(
        self,
        worktree_path: str,
        is_dirty: bool = False,
        is_behind: bool = False,
        has_conflicts: bool = False,
        view_override: Optional[LazyGitView] = None
    ) -> dict:
        """Convenience method to launch lazygit for a worktree with auto view selection.

        Args:
            worktree_path: Absolute path to worktree directory
            is_dirty: Worktree has uncommitted changes
            is_behind: Worktree is behind remote
            has_conflicts: Worktree has merge conflicts
            view_override: Optional explicit view selection

        Returns:
            Dict with launch result (success, pid, command, error)
        """
        if view_override:
            view = view_override
        else:
            view = select_view_for_context(
                is_dirty=is_dirty,
                is_behind=is_behind,
                has_conflicts=has_conflicts
            )

        context = LazyGitContext(
            working_directory=worktree_path,
            initial_view=view
        )

        return self.launch(context)


# Module-level singleton for easy access
_launcher: Optional[LazyGitLauncher] = None


def get_launcher(terminal: str = "ghostty") -> LazyGitLauncher:
    """Get or create the lazygit launcher singleton.

    Args:
        terminal: Terminal emulator to use

    Returns:
        LazyGitLauncher instance
    """
    global _launcher
    if _launcher is None:
        _launcher = LazyGitLauncher(terminal=terminal)
    return _launcher
