"""Dry-run mode support for CLI commands.

T092: Dry-run mode implementation for mutation commands.
Shows what would change without applying changes.
"""

from typing import List, Dict, Any, Optional, Callable
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class DryRunChange:
    """Represents a single change that would be made.

    T092: Dry-run change tracking
    FR-125: Show what would change without applying

    Attributes:
        action: Type of action (create, update, delete, add, remove)
        target: What is being changed (file, class, pattern, etc.)
        details: Additional details about the change
        old_value: Previous value (for updates/deletes)
        new_value: New value (for creates/updates)
    """

    action: str
    target: str
    details: str = ""
    old_value: Optional[Any] = None
    new_value: Optional[Any] = None

    def __str__(self) -> str:
        """Format change as human-readable string."""
        if self.action == "create":
            return f"  [CREATE] {self.target}: {self.new_value}"
        elif self.action == "delete":
            return f"  [DELETE] {self.target}: {self.old_value}"
        elif self.action == "update":
            return f"  [UPDATE] {self.target}: {self.old_value} → {self.new_value}"
        elif self.action == "add":
            return f"  [ADD] {self.target}: {self.new_value}"
        elif self.action == "remove":
            return f"  [REMOVE] {self.target}: {self.old_value}"
        else:
            return f"  [{self.action.upper()}] {self.target}: {self.details}"

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON output."""
        result = {
            "action": self.action,
            "target": self.target,
        }
        if self.details:
            result["details"] = self.details
        if self.old_value is not None:
            result["old_value"] = str(self.old_value)
        if self.new_value is not None:
            result["new_value"] = str(self.new_value)
        return result


@dataclass
class DryRunResult:
    """Result of a dry-run operation.

    T092: Dry-run result with all changes

    Attributes:
        changes: List of changes that would be made
        success: Whether the operation would succeed
        error_message: Optional error message if operation would fail
        warnings: Optional warnings about the operation
    """

    changes: List[DryRunChange] = field(default_factory=list)
    success: bool = True
    error_message: Optional[str] = None
    warnings: List[str] = field(default_factory=list)

    def add_change(
        self,
        action: str,
        target: str,
        details: str = "",
        old_value: Optional[Any] = None,
        new_value: Optional[Any] = None,
    ) -> None:
        """Add a change to the result.

        Args:
            action: Type of action
            target: What is being changed
            details: Additional details
            old_value: Previous value
            new_value: New value
        """
        self.changes.append(
            DryRunChange(
                action=action,
                target=target,
                details=details,
                old_value=old_value,
                new_value=new_value,
            )
        )

    def add_warning(self, message: str) -> None:
        """Add a warning to the result.

        Args:
            message: Warning message
        """
        self.warnings.append(message)

    def set_error(self, message: str) -> None:
        """Set an error message.

        Args:
            message: Error message
        """
        self.success = False
        self.error_message = message

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON output."""
        return {
            "success": self.success,
            "changes": [c.to_dict() for c in self.changes],
            "error": self.error_message,
            "warnings": self.warnings,
        }

    def __str__(self) -> str:
        """Format result as human-readable string."""
        from .commands import Colors

        lines = []

        # Header
        lines.append(f"\n{Colors.BOLD}Dry-run mode: No changes will be applied{Colors.RESET}")
        lines.append(f"{Colors.GRAY}{'─' * 60}{Colors.RESET}\n")

        # Changes
        if self.changes:
            lines.append(f"{Colors.BOLD}Would make {len(self.changes)} change(s):{Colors.RESET}\n")
            for change in self.changes:
                lines.append(str(change))
        else:
            lines.append(f"{Colors.GRAY}No changes would be made{Colors.RESET}")

        # Warnings
        if self.warnings:
            lines.append(f"\n{Colors.YELLOW}{Colors.BOLD}Warnings:{Colors.RESET}")
            for warning in self.warnings:
                lines.append(f"  {Colors.YELLOW}⚠{Colors.RESET} {warning}")

        # Error
        if self.error_message:
            lines.append(f"\n{Colors.RED}{Colors.BOLD}Would fail:{Colors.RESET}")
            lines.append(f"  {Colors.RED}✗{Colors.RESET} {self.error_message}")

        lines.append("")  # Empty line at end
        return "\n".join(lines)


class DryRunContext:
    """Context manager for dry-run mode.

    T092: Dry-run context for tracking changes

    Usage:
        >>> with DryRunContext() as ctx:
        ...     ctx.add_change("add", "scoped_classes", new_value="Code")
        ...     ctx.add_change("update", "config_file", old_value="old", new_value="new")
        >>> print(ctx.result)
    """

    def __init__(self):
        """Initialize dry-run context."""
        self.result = DryRunResult()

    def __enter__(self) -> "DryRunContext":
        """Enter dry-run context."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Exit dry-run context."""
        if exc_type is not None:
            # An exception occurred, record it
            self.result.set_error(f"{exc_type.__name__}: {exc_val}")
        return False  # Don't suppress exceptions

    def add_change(
        self,
        action: str,
        target: str,
        details: str = "",
        old_value: Optional[Any] = None,
        new_value: Optional[Any] = None,
    ) -> None:
        """Add a change to the dry-run result."""
        self.result.add_change(action, target, details, old_value, new_value)

    def add_warning(self, message: str) -> None:
        """Add a warning to the dry-run result."""
        self.result.add_warning(message)

    def set_error(self, message: str) -> None:
        """Set an error message."""
        self.result.set_error(message)


def dry_run_create_project(
    name: str,
    directory: Path,
    display_name: str,
    icon: str,
    scoped_classes: List[str],
) -> DryRunResult:
    """Dry-run for project creation.

    Args:
        name: Project name
        directory: Project directory
        display_name: Display name
        icon: Project icon
        scoped_classes: Scoped window classes

    Returns:
        DryRunResult with changes that would be made
    """
    result = DryRunResult()

    # Check if project already exists
    config_file = Path.home() / ".config/i3/projects" / f"{name}.json"
    if config_file.exists():
        result.set_error(f"Project '{name}' already exists at {config_file}")
        return result

    # Check if directory exists
    if not directory.exists():
        result.set_error(f"Directory does not exist: {directory}")
        return result

    # Add changes
    result.add_change(
        "create",
        f"project '{name}'",
        details=f"Config file: {config_file}",
        new_value=f"{display_name} ({directory})",
    )

    result.add_change(
        "create",
        "configuration",
        details=f"Icon: {icon}, Scoped classes: {', '.join(scoped_classes)}",
    )

    return result


def dry_run_delete_project(
    name: str,
    project_exists: bool,
    config_file: Path,
    saved_layouts: List[str],
    delete_layouts: bool,
) -> DryRunResult:
    """Dry-run for project deletion.

    Args:
        name: Project name
        project_exists: Whether project exists
        config_file: Path to config file
        saved_layouts: List of saved layout files
        delete_layouts: Whether to delete layouts

    Returns:
        DryRunResult with changes that would be made
    """
    result = DryRunResult()

    if not project_exists:
        result.set_error(f"Project '{name}' not found")
        return result

    # Add changes
    result.add_change(
        "delete",
        f"project '{name}'",
        details=f"Config file: {config_file}",
        old_value=str(config_file),
    )

    if delete_layouts and saved_layouts:
        for layout in saved_layouts:
            result.add_change(
                "delete",
                "layout file",
                old_value=layout,
            )
        result.add_warning(f"Would delete {len(saved_layouts)} layout file(s)")

    return result


def dry_run_add_class(
    class_name: str,
    scope: str,
    already_classified: bool,
    current_scope: Optional[str] = None,
) -> DryRunResult:
    """Dry-run for adding a window class.

    Args:
        class_name: Window class name
        scope: Target scope (scoped or global)
        already_classified: Whether class is already classified
        current_scope: Current scope if already classified

    Returns:
        DryRunResult with changes that would be made
    """
    result = DryRunResult()

    if already_classified:
        if current_scope == scope:
            result.set_error(f"Class '{class_name}' already in {scope} list")
            return result
        else:
            result.add_change(
                "remove",
                f"{current_scope}_classes",
                old_value=class_name,
            )
            result.add_warning(f"Would move '{class_name}' from {current_scope} to {scope}")

    result.add_change(
        "add",
        f"{scope}_classes",
        new_value=class_name,
    )

    result.add_change(
        "update",
        "app-classes.json",
        details="Save configuration file",
    )

    return result


def dry_run_add_pattern(
    pattern: str,
    scope: str,
    priority: int,
    description: str,
    pattern_exists: bool,
) -> DryRunResult:
    """Dry-run for adding a pattern rule.

    Args:
        pattern: Pattern string
        scope: Target scope
        priority: Pattern priority
        description: Pattern description
        pattern_exists: Whether pattern already exists

    Returns:
        DryRunResult with changes that would be made
    """
    result = DryRunResult()

    if pattern_exists:
        result.set_error(f"Pattern '{pattern}' already exists")
        return result

    result.add_change(
        "add",
        "pattern rule",
        details=f"Pattern: {pattern}, Scope: {scope}, Priority: {priority}",
        new_value=f"{pattern} → {scope}",
    )

    if description:
        result.add_change(
            "add",
            "pattern description",
            new_value=description,
        )

    result.add_change(
        "update",
        "app-classes.json",
        details="Save configuration file",
    )

    return result


def dry_run_remove_pattern(
    pattern: str,
    pattern_exists: bool,
) -> DryRunResult:
    """Dry-run for removing a pattern rule.

    Args:
        pattern: Pattern string to remove
        pattern_exists: Whether pattern exists

    Returns:
        DryRunResult with changes that would be made
    """
    result = DryRunResult()

    if not pattern_exists:
        result.set_error(f"Pattern '{pattern}' not found")
        return result

    result.add_change(
        "remove",
        "pattern rule",
        old_value=pattern,
    )

    result.add_change(
        "update",
        "app-classes.json",
        details="Save configuration file",
    )

    return result
